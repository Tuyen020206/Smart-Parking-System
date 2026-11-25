"""Run real RTL simulations and independent Python scoreboards. Python >=3.10.
Run from project root: python python/run_tests.py --iverilog PATH --vvp PATH
"""
from pathlib import Path
import argparse,csv,json,os,shutil,subprocess,sys,time,hashlib
from generate_vectors import engine_scenarios
from reference_model import HEX,pack
ROOT=Path(__file__).resolve().parents[1]
def write_csv(path,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not rows:return
    with path.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
class Tools:
    def __init__(self,args):
        self.iv=str(args.iverilog or shutil.which('iverilog') or '')
        self.vvp=str(args.vvp or shutil.which('vvp') or '')
        if not self.iv or not self.vvp:raise RuntimeError('Need Icarus iverilog and vvp. No RTL PASS is generated without tools.')
        self.args=args;self.env=os.environ.copy();self.env['PATH']=str(Path(self.iv).resolve().parent)+os.pathsep+self.env.get('PATH','')
        scratch=args.out/'build'/'tmp';scratch.mkdir(parents=True,exist_ok=True)
        self.env.update(TMP=str(scratch),TEMP=str(scratch),TMPDIR=str(scratch))
        self.attempts=[];self.logs=args.out/'logs';self.logs.mkdir(parents=True,exist_ok=True)
        r=subprocess.run([self.iv,'-V'],capture_output=True,text=True,errors='replace',env=self.env)
        (self.logs/'tool-version.txt').write_text(r.stdout+r.stderr,encoding='utf-8')
    def compile(self,top,name,params=None):
        target=self.args.out/'build'/f'{name}.vvp';target.parent.mkdir(parents=True,exist_ok=True)
        src=sorted((ROOT/'rtl').rglob('*.v'))+[ROOT/'tb'/f'{top}.v']
        # Keep actionable warnings without verbose array-sensitivity listings.
        cmd=[self.iv,'-g2012','-Wimplicit','-Wportbind','-I',str(ROOT/'tb'),'-s',top,'-o',str(target)]
        for k,v in (params or {}).items():cmd.append(f'-P{top}.{k}={v}')
        cmd.extend(map(str,src));logs=['COMMAND '+json.dumps(cmd)]
        for attempt in range(1,self.args.compile_attempts+1):
            r=subprocess.run(cmd,capture_output=True,text=True,errors='replace',env=self.env)
            self.attempts.append(dict(build=name,attempt=attempt,exit=r.returncode))
            logs.append(f'ATTEMPT {attempt}; EXIT {r.returncode}\n'+r.stdout+r.stderr)
            if r.returncode==0:break
            if r.returncode not in (3221225477,-1073741819):break
        (self.logs/f'compile_{name}.log').write_text('\n'.join(logs),encoding='utf-8')
        if r.returncode:raise RuntimeError('Compile failed '+name+'; see logs. Exit '+str(r.returncode))
        return target
    def simulate(self,binary,name,plusargs):
        command=[self.vvp,str(binary),*[f'+{k}={v}' for k,v in plusargs.items()]]
        r=subprocess.run(command,capture_output=True,text=True,errors='replace',env=self.env,timeout=180)
        (self.logs/f'run_{name}.log').write_text('COMMAND '+json.dumps(command)+'\nEXIT '+str(r.returncode)+'\n'+r.stdout+r.stderr,encoding='utf-8')
        if r.returncode:raise RuntimeError('RTL runtime failure '+name+'\n'+r.stdout+r.stderr)
        return r.stdout
def verify_engine(tools,args,results):
    for size in args.sizes:
        for depth in args.depths:
            binary=tools.compile('tb_memory',f'engine_{size}_{depth}',dict(SLOTS=size,FIFO_DEPTH=depth,DEDUP=args.dedup))
            cases=engine_scenarios(size,depth,args.dedup,args.random_cycles)
            for case in cases:
                name=f'n{size}_f{depth}_{case.name}';directory=args.out/'csv'/name;directory.mkdir(parents=True,exist_ok=True)
                inp=directory/'vectors.txt';out=directory/'actual.csv'
                inp.write_text(''.join(f'{pack(x)} {i}\n' for i,x in enumerate(case.vectors)),encoding='ascii')
                write_csv(directory/'expected.csv',case.expected)
                plus=dict(INPUT=inp,OUTPUT=out)
                if size==8 and depth==8 and case.name in ('E02_normal','E04_three_gates_last','E13_fifo_full','E16_offline_quota','E10_conflict'):
                    plus['WAVE']=args.out/'vcd'/f'{name}.vcd';(args.out/'vcd').mkdir(exist_ok=True)
                tools.simulate(binary,name,plus)
                with out.open() as f:actual=list(csv.DictReader(f))
                assert len(actual)==len(case.expected),(name,len(actual),len(case.expected))
                diffs=[]
                for i,(a,e) in enumerate(zip(actual,case.expected)):
                    for field,value in e.items():
                        try:observed=int(a[field],16 if field in HEX else 10)
                        except ValueError:observed=a[field]
                        if observed!=value:diffs.append(dict(cycle=i,field=field,expected=value,actual=observed))
                if diffs:
                    write_csv(directory/'mismatches.csv',diffs)
                    raise AssertionError(name+' '+str(diffs[:5]))
                results.append(dict(suite='engine',case=case.name,slots=size,depth=depth,cycles=len(actual),status='PASS',checks=len(actual)*len(case.expected[0])))
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--iverilog',type=Path);p.add_argument('--vvp',type=Path);p.add_argument('--out',type=Path,default=ROOT/'results')
    p.add_argument('--sizes',nargs='+',type=int,default=[8,33,128]);p.add_argument('--depths',nargs='+',type=int,default=[8,3])
    p.add_argument('--dedup',type=int,default=16);p.add_argument('--random-cycles',type=int,default=600)
    p.add_argument('--compile-attempts',type=int,default=1);p.add_argument('--suite',choices=['engine','sensor','gate','top','all'],default='all')
    a=p.parse_args();a.out=a.out.resolve();a.out.mkdir(parents=True,exist_ok=True)
    for child in ('csv','vcd','logs'):(a.out/child).mkdir(parents=True,exist_ok=True)
    if min(a.sizes)<3 or max(a.sizes)>255 or min(a.depths)<1 or a.dedup<max(a.depths)+3:p.error('sizes 3..255, depth>=1, dedup>=max(depth)+3')
    metadata=a.out/'metadata.json';metadata.write_text('{"state":"RUNNING","passed":0}',encoding='utf-8')
    results=[];started=time.time()
    try:
        tools=Tools(a)
        if a.suite in ('engine','all'):verify_engine(tools,a,results)
        # Additional suites are installed below and use the same strict tool contract.
        if a.suite in ('sensor','all'):
            from sensor_checks import verify_sensor
            verify_sensor(tools,a,results)
        if a.suite in ('gate','all'):
            from gate_checks import verify_gate
            verify_gate(tools,a,results)
        if a.suite in ('top','all'):
            from top_checks import verify_top
            verify_top(tools,a,results)
        write_csv(a.out/'summary.csv',results)
        hashes={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT/'rtl').rglob('*.v')}
        data=dict(state='COMPLETE',passed=len(results),failed=0,cycles=sum(r['cycles'] for r in results),checks=sum(r['checks'] for r in results),
                  suite=a.suite,sizes=a.sizes,depths=a.depths,dedup=a.dedup,random_cycles=a.random_cycles,seed='20261125+slots+depth',
                  compile_attempts=tools.attempts,rtl_sha256=hashes,wall_seconds=round(time.time()-started,3),
                  python_version=sys.version,simulator=tools.iv,invocation=sys.argv,
                  physical_fpga=False,synthesis=False,CPU_isa_emulated=False)
        metadata.write_text(json.dumps(data,indent=2,ensure_ascii=False),encoding='utf-8')
        print(json.dumps({k:v for k,v in data.items() if k not in ('compile_attempts','rtl_sha256')},ensure_ascii=False))
    except Exception as exc:
        write_csv(a.out/'summary.csv',results)
        metadata.write_text(json.dumps(dict(state='ERROR',passed=len(results),error=str(exc)),indent=2),encoding='utf-8')
        print(str(exc),file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
