"""Build a V18 TF card package. No FPGA source or bitstream is generated."""
from pathlib import Path
import argparse, array, hashlib, json, os, shutil, struct, subprocess, sys, zlib

RATE=24000
PROBE_WORDS=1024
ARENA_WORDS=1482752
MAX_TOTAL_WORDS=ARENA_WORDS-2048
MAX_PAYLOAD_BYTES=(MAX_TOTAL_WORDS-PROBE_WORDS)*4
MAX_SECONDS=MAX_PAYLOAD_BYTES/RATE

def crc(data): return zlib.crc32(data)&0xffffffff
def sha(data): return hashlib.sha256(data).hexdigest()

def calibration_prefix():
    # Non-periodic pattern with distinctive burst boundaries; never sent to DAC.
    state=0x48584650
    result=bytearray()
    for _ in range(PROBE_WORDS):
        state^=(state<<13)&0xffffffff
        state^=state>>17
        state^=(state<<5)&0xffffffff
        state&=0xffffffff
        result.extend(struct.pack('<I',state))
    return bytes(result)

def find_ffmpeg():
    options=[]
    if os.environ.get('FFMPEG_EXE'): options.append(Path(os.environ['FFMPEG_EXE']))
    path=shutil.which('ffmpeg')
    if path: options.append(Path(path))
    try:
        import imageio_ffmpeg
        options.append(Path(imageio_ffmpeg.get_ffmpeg_exe()))
    except ImportError:
        pass
    here=Path(__file__).resolve().parent
    for parent in (here, *list(here.parents)[:3]):
        options.extend((parent/'tools').glob('ffmpeg*.exe'))
        options.extend((parent/'audio_diagnostics_20261012'/'deps'/'imageio_ffmpeg'/'binaries').glob('ffmpeg*.exe'))
    options.extend((Path('E:/FPGA/TD_6.2.1_SP1_178840_NL/competition/audio_diagnostics_20261012/deps/imageio_ffmpeg/binaries')).glob('ffmpeg*.exe'))
    for option in options:
        if option.is_file(): return str(option)
    raise ValueError('找不到 FFmpeg。请将 ffmpeg.exe 放入工具旁的 tools 文件夹，或设置 FFMPEG_EXE。')

def resolve_item(item, base):
    config={'path':item} if isinstance(item,str) else dict(item)
    path=Path(config['path']).expanduser()
    if not path.is_absolute(): path=base/path
    path=path.resolve()
    if not path.is_file(): raise ValueError('找不到素材：'+str(path))
    config['path']=str(path)
    return config,path

def audio_payload(config,path):
    suffix=path.suffix.lower()
    if suffix in ('.ulw','.fpa'):
        if config.get('start',0) or config.get('duration'):
            raise ValueError('ULW/FPA 直接复用原数据；需要截取时请选择原始 MP3/WAV。')
        if path.stat().st_size>MAX_PAYLOAD_BYTES+4608:
            raise ValueError(f'{path.name} 超过本版单曲容量，最长约 {MAX_SECONDS:.2f} 秒。')
        data=path.read_bytes()
        if suffix=='.fpa':
            if len(data)<512+4096+512 or data[:8]!=b'HXAU0001' or crc(data[:508])!=struct.unpack_from('<I',data,508)[0]:
                raise ValueError('FPA 文件头无效：'+path.name)
            words,full,probe,rate,probe_words,payload_bytes=struct.unpack_from('<6I',data,8)
            stored=data[512:]
            if rate!=RATE or probe_words!=PROBE_WORDS or len(stored)!=words*4 or crc(stored)!=full or crc(stored[:4096])!=probe or len(stored[4096:])!=payload_bytes:
                raise ValueError('FPA 内容或校验不匹配：'+path.name)
            data=stored[4096:]
        if not data: raise ValueError('音频文件为空：'+path.name)
        method='existing mu-law payload preserved'
    else:
        start=float(config.get('start',0))
        duration=config.get('duration')
        gain=float(config.get('gain',0.65))
        if start<0 or not 0<gain<=1: raise ValueError('截取起点须非负，增益须大于 0 且不超过 1。')
        if duration is not None and not 0<float(duration)<=MAX_SECONDS:
            raise ValueError(f'截取时长须为 0～{MAX_SECONDS:.2f} 秒。')
        # Decode at most limit+1 seconds, then reject overflow instead of silently truncating.
        cmd=[find_ffmpeg(),'-v','error','-nostdin']
        if start: cmd+=['-ss',str(start)]
        cmd+=['-i',str(path),'-t',str(float(duration) if duration is not None else MAX_SECONDS+1),
              '-vn','-ac','1','-ar',str(RATE),'-f','s16le','pipe:1']
        run=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        if run.returncode: raise ValueError('音频转换失败：'+run.stderr.decode('utf-8',errors='replace')[-2000:])
        if not run.stdout: raise ValueError('音频没有可解码的数据：'+path.name)
        if len(run.stdout)//2>MAX_PAYLOAD_BYTES:
            raise ValueError(f'{path.name} 超过单曲 {MAX_SECONDS:.2f} 秒，请在工具中设置截取范围。不会自动截断。')
        samples=array.array('h');samples.frombytes(run.stdout)
        if sys.byteorder!='little': samples.byteswap()
        # Same 0.65 gain and 100 ms end ramps as the existing preparation workflow.
        ramp=min(2400,len(samples)//2)
        for i in range(len(samples)):
            factor=gain
            if ramp>1:
                if i<ramp: factor*=i/(ramp-1)
                if i>=len(samples)-ramp: factor*=(len(samples)-1-i)/(ramp-1)
            samples[i]=round(samples[i]*factor)
        if sys.byteorder!='little': samples.byteswap()
        try:
            import audioop
        except ImportError as e:
            raise ValueError('此转换工具需要带 audioop 的 Python 3.11/3.12；请用随工程的启动脚本。') from e
        data=audioop.lin2ulaw(samples.tobytes(),2)
        method='24kHz mono G.711 mu-law, gain='+str(gain)+', 100ms ramps'
    # Minimum 128 payload words satisfies the player's FIFO start watermark.
    padded=max(512,(len(data)+127)//128*128)
    if padded>MAX_PAYLOAD_BYTES: raise ValueError('音频补齐后超过可用内存容量。')
    return data+b'\xff'*(padded-len(data)),method

def pack_image(path,dest):
    from PIL import Image,ImageOps
    if path.suffix.lower()=='.bmp':
        with path.open('rb') as f: header=f.read(54)
        if len(header)==54 and header[:2]==b'BM':
            width,height=struct.unpack_from('<ii',header,18)
            bpp=struct.unpack_from('<H',header,28)[0]
            compression=struct.unpack_from('<I',header,30)[0]
            if 0<width<=2048 and 0<abs(height)<=2048 and bpp==24 and compression==0:
                shutil.copy2(path,dest)
                return {'width':width,'height':abs(height),'conversion':'existing RGB24 BMP preserved'}
    with Image.open(path) as original:
        image=ImageOps.exif_transpose(original).convert('RGBA')
        source_size=image.size
        image.thumbnail((2048,2048),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',image.size,(0,16,64,255))
        image=Image.alpha_composite(canvas,image).convert('RGB')
        image.save(dest,format='BMP')
        return {'width':image.width,'height':image.height,'source_size':source_size,
                'conversion':'RGB24 BMP; transparency on #001040; max dimension 2048'}

def build_package(config,output,base=None,progress=print):
    base=Path(base or '.').resolve()
    images=config.get('images',[]);music=config.get('music',[])
    if not 1<=len(images)<=8 or not 1<=len(music)<=8:
        raise ValueError('请选择 1～8 张图片和 1～8 首歌曲。')
    output=Path(output).resolve()
    if output.exists(): raise ValueError('输出目录已存在，请选择新的文件夹，避免覆盖旧素材。')
    sources_images=[resolve_item(x,base) for x in images]
    sources_music=[resolve_item(x,base) for x in music]
    output.mkdir(parents=True)
    try:
        records={'format':'HXPL0001','images':[],'music':[],'sample_rate':RATE,'max_seconds':MAX_SECONDS}
        for i,(item,path) in enumerate(sources_images,1):
            progress(f'图片 {i}/{len(images)}：{path.name}')
            name=f'PIC000{i}.BMP';details=pack_image(path,output/name)
            records['images'].append({'file':name,'source':str(path),**details})
        prefix=calibration_prefix();probe_crc=crc(prefix)
        catalog=bytearray(512);catalog[:8]=b'HXPL0001'
        catalog[8]=len(images);catalog[9]=len(music)
        struct.pack_into('<III',catalog,12,RATE,512,PROBE_WORDS)
        for i,(item,path) in enumerate(sources_music,1):
            progress(f'歌曲 {i}/{len(music)}：{path.name}')
            payload,method=audio_payload(item,path)
            stored=prefix+payload;words=len(stored)//4;full=crc(stored)
            header=bytearray(512);header[:8]=b'HXAU0001'
            struct.pack_into('<6I',header,8,words,full,probe_crc,RATE,PROBE_WORDS,len(payload))
            struct.pack_into('<I',header,508,crc(header[:508]))
            name=f'MUSIC0{i}.FPA'
            (output/name).write_bytes(header+stored)
            struct.pack_into('<8I',catalog,32+(i-1)*32,words,full,probe_crc,RATE,len(payload),1,i,0)
            records['music'].append({'file':name,'source':str(path),'seconds':len(payload)/RATE,
                'stored_words':words,'payload_bytes':len(payload),'full_crc32':f'{full:08x}',
                'probe_crc32':f'{probe_crc:08x}','payload_sha256':sha(payload),'conversion':method})
        struct.pack_into('<I',catalog,508,crc(catalog[:508]))
        # Commit the catalog last. A partial failed package has no usable catalog.
        (output/'PLAYLST.BIN').write_bytes(catalog)
        (output/'MEDIA_INFO.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
        reusable={'images':[x['file'] for x in records['images']], 'music':[x['file'] for x in records['music']]}
        (output/'素材清单.json').write_text(json.dumps(reusable,ensure_ascii=False,indent=2),encoding='utf-8')
        (output/'复制说明.txt').write_text('将 PLAYLST.BIN、全部 PIC000*.BMP 和 MUSIC0*.FPA 一起复制到 TF 卡根目录。\n'
            '不要把文件夹本身复制进去。请在开发板断电时换卡；重新下载同一个 V18 位流即可读取新清单，无需重新编译。\n'
            '旧 .ULW 文件会被 V18 忽略，可以保留用于 V17 回滚。\n',encoding='utf-8')
        progress('素材包已生成：'+str(output))
        return records
    except Exception:
        # Keep the directory for diagnosis, with no completion marker/catalog.
        catalog_path=output/'PLAYLST.BIN'
        if catalog_path.is_file(): catalog_path.unlink()
        (output/'生成未完成.txt').write_text('此目录生成失败，请勿复制到卡。修正错误后选择新输出目录重新生成。',encoding='utf-8')
        raise

if __name__=='__main__':
    parser=argparse.ArgumentParser(description='生成 V18 素材包，不修改 FPGA 工程')
    parser.add_argument('--config',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    config=json.loads(args.config.read_text(encoding='utf-8-sig'))
    build_package(config,args.output,args.config.resolve().parent)
