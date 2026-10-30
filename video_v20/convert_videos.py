"""Convert local MP4s to the V20 160x90 indexed-video stream; originals untouched."""
from pathlib import Path
import argparse, hashlib, json, math, shutil, struct, subprocess, tempfile, zlib
from PIL import Image

WIDTH, HEIGHT, FPS, RATE = 160, 90, 15, 24000
SAMPLES = RATE // FPS
PAYLOAD = 256 * 3 + WIDTH * HEIGHT + SAMPLES
PACKET = ((32 + PAYLOAD + 511) // 512) * 512

def ffmpeg_path():
    if shutil.which('ffmpeg'):
        return shutil.which('ffmpeg')
    root = Path(__file__).resolve().parent
    candidates = [root / 'tools/ffmpeg.exe', root.parent / 'audio_diagnostics_20261012/deps/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe', Path('C:/Users/ASUS/Desktop/ds/competition_work/audio_diagnostics_20261012/deps/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe')]
    for p in candidates:
        if p.is_file(): return str(p)
    raise RuntimeError('FFmpeg not found; put ffmpeg.exe in tools/')
def read_exact(pipe, size):
    chunks = bytearray()
    while len(chunks) < size:
        block = pipe.read(size-len(chunks))
        if not block: break
        chunks.extend(block)
    return bytes(chunks)

def convert(source, destination, ff, seconds=None):
    source = Path(source).resolve()
    metadata = subprocess.run([ff, '-hide_banner', '-i', str(source)], capture_output=True).stderr.decode('utf-8', errors='replace')
    duration_args = ['-t',str(seconds)] if seconds else []
    audio_run = subprocess.run([ff,'-v','error','-i',str(source),*duration_args,'-map','0:a:0','-vn','-ac','1','-ar',str(RATE),'-c:a','pcm_mulaw','-f','mulaw','pipe:1'], capture_output=True)
    if audio_run.returncode: raise RuntimeError(audio_run.stderr.decode('utf-8', errors='replace'))
    audio = audio_run.stdout
    if not audio: raise RuntimeError('The input has no decodable audio')
    video_cmd = [ff,'-v','error','-i',str(source),*duration_args,'-map','0:v:0','-an','-vf',f'fps={FPS},scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease:flags=lanczos,pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1','-pix_fmt','rgb24','-f','rawvideo','pipe:1']
    temporary = destination.with_suffix('.tmp')
    frames = 0
    with tempfile.TemporaryFile() as errors:
        proc = subprocess.Popen(video_cmd, stdout=subprocess.PIPE, stderr=errors)
        try:
            with temporary.open('wb') as out:
                out.write(bytes(512))
                while True:
                    raw = read_exact(proc.stdout, WIDTH*HEIGHT*3)
                    if not raw: break
                    if len(raw) != WIDTH*HEIGHT*3: raise RuntimeError('Truncated decoded video frame')
                    rgb = Image.frombytes('RGB',(WIDTH,HEIGHT),raw)
                    indexed = rgb.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
                    palette = bytes(indexed.getpalette()[:768]).ljust(768,b'\0')
                    soundtrack = audio[frames*SAMPLES:(frames+1)*SAMPLES].ljust(SAMPLES,b'\xff')
                    payload = palette + indexed.tobytes() + soundtrack
                    frame_head = struct.pack('<4sIII',b'FRM1',frames,zlib.crc32(payload)&0xffffffff,len(payload)).ljust(32,b'\0')
                    out.write(frame_head + payload + bytes(PACKET-32-len(payload)))
                    if frames in (0, 450):
                        indexed.convert('RGB').resize((640,360),Image.Resampling.NEAREST).save(destination.with_name(destination.stem+f'_preview_{frames:04d}.png'))
                    frames += 1
                    if frames % 300 == 0: print(f'{destination.name}: {frames} frames',flush=True)
                result = proc.wait()
                if result:
                    errors.seek(0)
                    raise RuntimeError(errors.read().decode('utf-8',errors='replace'))
                if not 0 < frames <= 60000: raise RuntimeError('Video frame count outside supported range')
                header = bytearray(512)
                struct.pack_into('<8sHHHHIIIIII',header,0,b'HXVD0001',WIDTH,HEIGHT,FPS,1,frames,RATE,SAMPLES,PACKET,WIDTH*HEIGHT,frames*SAMPLES)
                struct.pack_into('<I',header,508,zlib.crc32(header[:508])&0xffffffff)
                out.seek(0);out.write(header)
            temporary.replace(destination)
        except BaseException:
            proc.kill();proc.wait()
            raise
        finally:
            proc.stdout.close()
    return {'input':str(source),'output':destination.name,'frames':frames,'fps':FPS,'seconds':frames/FPS,'width':WIDTH,'height':HEIGHT,'encoding':'per-frame RGB888 palette + 8-bit indices','audio':'24 kHz mono mu-law','bytes':destination.stat().st_size,'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),'original_metadata':metadata}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--input-dir',type=Path,default=Path('D:/软件/Download'))
    parser.add_argument('--out',type=Path,default=Path(__file__).resolve().parent/'TF_CARD')
    parser.add_argument('--seconds',type=float,default=None)
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    sources=sorted(args.input_dir.glob('*.mp4'),key=lambda p:p.name)
    if len(sources)!=2: raise RuntimeError('This two-video experiment expects exactly two MP4 inputs')
    records=[]
    for i,source in enumerate(sources,1):
        destination=args.out/f'VIDEO0{i}.FPV'
        if destination.exists(): raise FileExistsError(f'Not overwriting existing media: {destination}')
        records.append(convert(source,destination,ffmpeg_path(),args.seconds))
    manifest={'format':'HXVD0001','packet_bytes':PACKET,'data_bytes_per_second':PACKET*FPS,'videos':records}
    (args.out/'VIDEO_INFO.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(manifest,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__': main()
