"""Small local asset manager. Produces a new folder; never writes a card directly."""
from pathlib import Path
import datetime,json,queue,threading,traceback
import tkinter as tk
from tkinter import ttk,filedialog,messagebox,simpledialog
from media_pack import build_package,MAX_SECONDS

class App:
    def __init__(self,root):
        self.root=root;self.items={'images':[],'music':[]};self.boxes={};self.busy=False;self.events=queue.Queue()
        root.title('FPGA 素材管理 · V18');root.geometry('940x650');root.minsize(820,580)
        shell=ttk.Frame(root,padding=14);shell.pack(fill='both',expand=True)
        ttk.Label(shell,text='增减素材、调整顺序，无需重新编译 FPGA',font=('Microsoft YaHei UI',14,'bold')).pack(anchor='w')
        ttk.Label(shell,text='每组 1～8 个；歌曲最长约 4 分 6 秒。生成后把素材包中的文件复制到 TF 卡根目录。').pack(anchor='w',pady=(5,12))
        toolbar=ttk.Frame(shell);toolbar.pack(fill='x',pady=(0,8))
        ttk.Button(toolbar,text='打开清单',command=self.load_config).pack(side='left')
        ttk.Button(toolbar,text='保存清单',command=self.save_config).pack(side='left',padx=8)
        panes=ttk.Frame(shell);panes.pack(fill='both',expand=True)
        for kind,label in (('images','图片 · 从上到下为播放顺序'),('music','歌曲 · 从上到下为播放顺序')):
            pane=ttk.LabelFrame(panes,text=label,padding=8);pane.pack(side='left',fill='both',expand=True,padx=(0,8))
            box=tk.Listbox(pane,exportselection=False,font=('Microsoft YaHei UI',10),width=39)
            box.pack(fill='both',expand=True);self.boxes[kind]=box
            bar=ttk.Frame(pane);bar.pack(fill='x',pady=8)
            ttk.Button(bar,text='添加',command=lambda k=kind:self.add(k)).pack(side='left')
            ttk.Button(bar,text='移除',command=lambda k=kind:self.remove(k)).pack(side='left',padx=3)
            ttk.Button(bar,text='上移',command=lambda k=kind:self.move(k,-1)).pack(side='left',padx=3)
            ttk.Button(bar,text='下移',command=lambda k=kind:self.move(k,1)).pack(side='left')
            if kind=='music':
                ttk.Button(pane,text='设置所选歌曲的截取范围',command=self.clip).pack(anchor='w')
            else:
                ttk.Label(pane,text='支持 JPG / PNG / BMP；透明区域填充深蓝色。').pack(anchor='w')
        ttk.Label(shell,text='普通音频支持 MP3 / WAV / FLAC 等；已有 FPA / ULW 可复用原音频数据。').pack(anchor='w',pady=8)
        self.status=tk.StringVar(value='先添加素材，或打开工程中的“素材清单.json”。')
        ttk.Label(shell,textvariable=self.status,wraplength=890).pack(anchor='w')
        self.progress=ttk.Progressbar(shell,mode='indeterminate');self.progress.pack(fill='x',pady=8)
        self.generate=ttk.Button(shell,text='生成新的素材包…',command=self.build);self.generate.pack(anchor='e')
        default=Path(__file__).resolve().parent/'素材清单.json'
        if default.exists():
            try:self.read_config(default)
            except Exception:pass
        root.after(150,self.poll)
    def refresh(self,kind,select=None):
        box=self.boxes[kind];box.delete(0,'end')
        for i,item in enumerate(self.items[kind],1):
            text=f'{i}. {Path(item["path"]).name}'
            if item.get('start',0) or item.get('duration'):
                text+=f'  [{item.get("start",0):g}s 起 / {item.get("duration",0):g}s]'
            box.insert('end',text)
        if select is not None and 0<=select<len(self.items[kind]):box.selection_set(select);box.see(select)
    def selected(self,kind):
        selection=self.boxes[kind].curselection()
        return selection[0] if selection else None
    def add(self,kind):
        if self.busy:return
        types=[('图片','*.jpg *.jpeg *.png *.bmp *.webp')] if kind=='images' else [('音频','*.mp3 *.wav *.flac *.m4a *.ogg *.ulw *.fpa')]
        files=filedialog.askopenfilenames(title='添加图片' if kind=='images' else '添加歌曲',filetypes=types+[('全部文件','*.*')])
        if len(self.items[kind])+len(files)>8:
            messagebox.showerror('数量超出','每组最多 8 个，请先移除不需要的条目。');return
        self.items[kind].extend({'path':str(Path(p).resolve())} for p in files);self.refresh(kind)
    def remove(self,kind):
        if self.busy:return
        i=self.selected(kind)
        if i is not None:del self.items[kind][i];self.refresh(kind,min(i,len(self.items[kind])-1))
    def move(self,kind,delta):
        if self.busy:return
        i=self.selected(kind)
        if i is None or not 0<=i+delta<len(self.items[kind]):return
        self.items[kind][i],self.items[kind][i+delta]=self.items[kind][i+delta],self.items[kind][i]
        self.refresh(kind,i+delta)
    def clip(self):
        if self.busy:return
        i=self.selected('music')
        if i is None:return
        item=self.items['music'][i]
        if Path(item['path']).suffix.lower() in ('.ulw','.fpa'):
            messagebox.showinfo('复用已有音频','这类文件会保留现有音频数据。若要截取，请添加原始 MP3 或 WAV。');return
        start=simpledialog.askfloat('截取起点','从第几秒开始？',initialvalue=item.get('start',0),minvalue=0)
        if start is None:return
        duration=simpledialog.askfloat('截取时长',f'播放多少秒？0 表示完整剩余部分；上限 {MAX_SECONDS:.2f} 秒。',initialvalue=item.get('duration',0),minvalue=0,maxvalue=MAX_SECONDS)
        if duration is None:return
        item['start']=start
        if duration:item['duration']=duration
        else:item.pop('duration',None)
        self.refresh('music',i)
    def read_config(self,path):
        path=Path(path).resolve();data=json.loads(path.read_text(encoding='utf-8-sig'));new={}
        for kind in ('images','music'):
            entries=data.get(kind,[])
            if not isinstance(entries,list) or len(entries)>8:raise ValueError('每组清单最多 8 个条目。')
            new[kind]=[]
            for entry in entries:
                item={'path':entry} if isinstance(entry,str) else dict(entry)
                source=Path(item['path'])
                if not source.is_absolute():source=path.parent/source
                item['path']=str(source.resolve());new[kind].append(item)
        self.items=new
        for kind in self.items:self.refresh(kind)
        self.status.set('已打开：'+str(path))
    def load_config(self):
        if self.busy:return
        name=filedialog.askopenfilename(title='打开素材清单',filetypes=[('素材清单','*.json')])
        if name:
            try:self.read_config(name)
            except Exception as e:messagebox.showerror('无法打开',str(e))
    def save_config(self):
        if self.busy:return
        name=filedialog.asksaveasfilename(title='保存素材清单',defaultextension='.json',initialfile='素材清单.json',filetypes=[('JSON','*.json')])
        if name:
            try:Path(name).write_text(json.dumps(self.items,ensure_ascii=False,indent=2),encoding='utf-8');self.status.set('已保存清单：'+name)
            except Exception as e:messagebox.showerror('保存失败',str(e))
    def build(self):
        if self.busy:return
        if not all(1<=len(self.items[k])<=8 for k in self.items):
            messagebox.showinfo('素材未选齐','请至少选择 1 张图片和 1 首歌曲。');return
        parent=filedialog.askdirectory(title='选择保存位置（将在其中新建素材包文件夹）')
        if not parent:return
        target=Path(parent)/('TF_CARD_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
        config=json.loads(json.dumps(self.items));self.busy=True;self.generate.config(state='disabled');self.progress.start(15)
        def worker():
            try:
                build_package(config,target,progress=lambda msg:self.events.put(('progress',msg)))
                self.events.put(('done',str(target)))
            except Exception as e:self.events.put(('error',str(e)))
        threading.Thread(target=worker,daemon=True).start()
    def poll(self):
        try:
            while True:
                kind,msg=self.events.get_nowait();self.status.set(msg)
                if kind in ('done','error'):
                    self.busy=False;self.progress.stop();self.generate.config(state='normal')
                    if kind=='done':messagebox.showinfo('素材包已生成',msg+'\n\n将其中的 PLAYLST.BIN、全部 BMP 和 FPA 文件复制到 TF 卡根目录，再重新下载同一个 V18 位流。')
                    else:messagebox.showerror('生成失败',msg)
        except queue.Empty:pass
        self.root.after(150,self.poll)

if __name__=='__main__':
    root=tk.Tk()
    try:App(root);root.mainloop()
    except Exception as e:messagebox.showerror('启动失败',str(e)+'\n'+traceback.format_exc()[-1200:])
