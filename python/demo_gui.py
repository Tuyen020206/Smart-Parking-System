"""Basic Tkinter viewer. All displayed state is read from verified actual CSV.
Run RTL creates a new simulation; Play only replays existing output by events.
"""
import argparse,math,os,shutil,subprocess,sys,threading
from pathlib import Path
import tkinter as tk
from tkinter import ttk,messagebox
from demo import ROOT,DEMOS,STATES,load_demo,keyframes

class Viewer:
    def __init__(self,root,args):
        self.root=root;self.args=args;self.run=None;self.frames=[];self.index=0;self.playing=False;self.running=False
        root.title('Smart Parking RTL - Verified Trace Replay');root.geometry('1120x790')
        root.configure(bg='white');style=ttk.Style();style.configure('.',font=('Arial',11))
        self.title=ttk.Label(root,text='VERIFIED RTL TRACE REPLAY - NOT LIVE FPGA',font=('Arial',16,'bold'));self.title.pack(pady=12)
        bar=ttk.Frame(root);bar.pack(fill='x',padx=20)
        self.scenario=tk.StringVar(value=args.name);ttk.Combobox(bar,textvariable=self.scenario,values=list(DEMOS),state='readonly',width=18).pack(side='left')
        ttk.Button(bar,text='Load verified output',command=self.load).pack(side='left',padx=6)
        ttk.Button(bar,text='Run RTL then load',command=self.execute).pack(side='left',padx=6)
        ttk.Button(bar,text='Play / Pause',command=self.toggle).pack(side='left',padx=6)
        ttk.Button(bar,text='Next event',command=self.advance).pack(side='left',padx=6)
        self.info=ttk.Label(root,text='No trace loaded');self.info.pack(pady=10)
        self.canvas=tk.Canvas(root,width=1060,height=380,bg='white',highlightthickness=1,highlightbackground='#aaa');self.canvas.pack(padx=20)
        self.scale=tk.Scale(root,from_=0,to=1,orient='horizontal',command=self.seek,label='Event index (clock cycles may jump)',length=1050);self.scale.pack()
        self.event=ttk.Label(root,text='',font=('Consolas',11));self.event.pack(pady=5)
        self.log=tk.Text(root,height=8,font=('Consolas',10),wrap='word');self.log.pack(fill='both',expand=True,padx=20,pady=10)
        self.load(initial=True)
    def load(self,initial=False,results=None):
        try:
            self.run=load_demo(self.scenario.get(),results or self.args.results)
            if self.run['suite']!='top':raise ValueError('The graphical parking layout supports top scenarios; use CLI for unit tests')
            self.frames=keyframes(self.run['rows']);self.index=0
            if initial and self.args.at=='occupied':
                wanted=next((i for i,r in enumerate(self.run['rows']) if int(r['occupied'],16)),0)
                self.index=next((k for k,i in enumerate(self.frames) if i>=wanted),0)
            self.scale.config(to=max(0,len(self.frames)-1));self.scale.set(self.index);self.draw()
            self.log.insert('end',f"Loaded PASS {self.run['case']}: {self.run['summary']['cycles']} cycles\n")
        except Exception as error:
            if not initial:messagebox.showerror('No verified trace',str(error))
            self.info.config(text='Load a COMPLETE verified trace, or run RTL. '+str(error))
    def draw(self):
        if not self.run:return
        r=self.run['rows'][self.frames[self.index]];c=self.canvas;c.delete('all')
        self.info.config(text=f"{self.run['case']}   cycle={r['cycle']}   C={r['c']} N={r['n']} R={r['r']} D={r['d']} Q={r['q']}   FIFO={r['fifo_count']}   dedup_hit={r['dedup_hits']}")
        masks={k:int(r[k],16) for k in ['valid','occupied','reserved','maintenance','admitted']}
        for i in range(8):
            x=40+(i%4)*255;y=35+(i//4)*120
            state='UNKNOWN' if not masks['valid']>>i&1 else 'MAINT' if masks['maintenance']>>i&1 else 'OCCUPIED' if masks['occupied']>>i&1 else 'RESERVED' if (masks['reserved']|masks['admitted'])>>i&1 else 'FREE'
            color={'UNKNOWN':'#ddd','MAINT':'#fff0bb','RESERVED':'#fff0bb','OCCUPIED':'#f4cccc','FREE':'#d9ead3'}[state]
            c.create_rectangle(x,y,x+215,y+90,fill=color,outline='#333');c.create_text(x+108,y+27,text=f'SLOT {i}',font=('Arial',13,'bold'));c.create_text(x+108,y+60,text=state,font=('Arial',12))
        states=int(r['states'],16);positions=int(r.get('barrier_pos','0'),16)
        for g in range(4):
            x=65+g*255;y=285;st=(states>>(g*3))&7
            c.create_text(x+65,y-20,text=f"{'IN' if g<3 else 'OUT'} {g}: {STATES[st] if st<6 else '?'}",font=('Arial',11))
            auto=int(self.run['case'][1:3])>=9
            pos=(positions>>(g*8))&255;angle=min(12,pos)/12*math.pi/2 if auto else 0
            c.create_rectangle(x,y,x+12,y+45,fill='#bbb');c.create_line(x+6,y,x+6+90*math.cos(angle),y-60*math.sin(angle),width=5,fill='#333')
            c.create_text(x+70,y+45,text=f'model position {pos}/12' if auto else 'manual limit stimulus',font=('Arial',10))
        self.event.config(text=f"rsp={r['rsp_valid']} op={r['rsp_op']} src={r['rsp_source']} status={r['rsp_status']}  ready=0x{r['ready']} pending=0x{r['pending']} blocked_sync=0x{r['blocked_sync']}")
    def seek(self,value):
        if self.run:self.index=min(int(float(value)),len(self.frames)-1);self.draw()
    def advance(self):
        if self.run:self.index=min(self.index+1,len(self.frames)-1);self.scale.set(self.index)
    def toggle(self):
        self.playing=not self.playing
        if self.playing:self.animate()
    def animate(self):
        if not self.playing or not self.run:return
        if self.index>=len(self.frames)-1:self.playing=False;return
        self.advance();self.root.after(180,self.animate)
    def execute(self):
        if self.running:return
        self.running=True
        self.playing=False;name=self.scenario.get();destination=ROOT/'results/demos'/name
        cmd=[sys.executable,str(ROOT/'python/demo.py'),'run',name,'--compile-attempts',str(self.args.compile_attempts)]
        for flag,value in [('--iverilog',self.args.iverilog),('--vvp',self.args.vvp)]:
            if value:cmd.extend([flag,str(value)])
        def worker():
            try:
                creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0) if os.name=='nt' else 0
                proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',creationflags=creationflags)
                for line in proc.stdout:self.root.after(0,lambda s=line:self.log.insert('end',s))
                status=proc.wait()
                if status:raise RuntimeError('RTL simulation failed; inspect the log')
                self.root.after(0,lambda:self.load(results=destination))
            except Exception as error:self.root.after(0,lambda msg=str(error):messagebox.showerror('Run failed',msg))
            finally:self.root.after(0,lambda:setattr(self,'running',False))
        self.log.insert('end','RUNNING REAL RTL '+name+'\n');threading.Thread(target=worker,daemon=True).start()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--name',default='entry',choices=DEMOS);p.add_argument('--results',type=Path)
    p.add_argument('--at',choices=['start','occupied'],default='start');p.add_argument('--iverilog');p.add_argument('--vvp');p.add_argument('--compile-attempts',type=int,default=1)
    args=p.parse_args();root=tk.Tk();Viewer(root,args);root.mainloop()
if __name__=='__main__':main()
