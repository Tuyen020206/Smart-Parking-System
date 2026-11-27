"""Run a selected real RTL scenario, or replay an already-verified actual CSV.
Examples: python python/demo.py list
          python python/demo.py run entry --iverilog PATH --vvp PATH
          python python/demo.py show entry --results results
"""
from pathlib import Path
import argparse,csv,hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
DEMOS={
 'entry':('top','T09_auto_entry_exit','Automatic barrier: entry, parking and exit'),
 'last-slot':('top','T02_last_slot','Three entrances compete for one remaining space'),
 'obstacle':('top','T10_auto_obstacle','FIFO full, obstacle, reopen, reclose, exactly one ENTER'),
 'cancel':('top','T13_cancel_obstacle','Cancel ACK waits until the barrier region is clear'),
 'jam-open':('top','T11_opening_jam','Jammed opening limit: FAULT and retained reservation'),
 'jam-close':('top','T12_closing_jam','Jammed closing limit: FAULT without inventing an exit'),
 'offline':('top','T04_offline','Quota replay, offline consumption, exhaustion and reconnect'),
 'booking':('top','T05_booking','D to R to N and cancellation of remaining booking'),
 'parallel':('top','T06_near_passages','Three nearly simultaneous passage events'),
 'reset':('top','T07_reset_session','Reset active session and lock operation'),
 'invalid-ticket':('top','T08_invalid_ticket','Reject unverified permission'),
 'fifo':('engine','E13_fifo_full','Full + pop + push without overwrite'),
 'replay':('engine','E09_duplicate','Same ID and payload: one business effect'),
 'conflict':('engine','E10_conflict','Same ID with different payload: CONFLICT'),
 'checkpoint':('engine','E12_dedup_full','Full CAM waits for checkpoint without dropping valid'),
 'echo':('sensor','S04_hysteresis','Median and two distance thresholds'),
 'echo-stale':('sensor','S10_stale_backpressure','Expired snapshot followed immediately by UNKNOWN'),
 'echo-50mhz':('sensor','S11_clock_50mhz','Measure Echo correctly with a 50 MHz clock'),
 'auth-timeout':('gate','G13_stalled_auth_timeout','Keep an unaccepted request valid after timeout')}
STATES=['IDLE','WAIT_AUTH','OPENING','WAIT_PASS','CLOSING','FAULT']
def read_rows(path):return list(csv.DictReader(path.open(encoding='utf-8-sig')))
def load_demo(name,results=None):
    suite,case,description=DEMOS[name]
    directory=Path(results).resolve() if results else ROOT/'results/demos'/name
    if not (directory/'metadata.json').exists() and results is None:directory=ROOT/'results'
    meta=json.loads((directory/'metadata.json').read_text(encoding='utf-8'))
    if meta['state']!='COMPLETE':raise ValueError('The requested run is not COMPLETE; no replay of stale PASS data')
    for filename,sha in meta['rtl_sha256'].items():
        path=ROOT/filename.replace('\\','/')
        if hashlib.sha256(path.read_bytes()).hexdigest()!=sha:raise ValueError('RTL changed since this trace was verified: '+filename)
    matches=[r for r in read_rows(directory/'summary.csv') if r['case']==case and (suite!='engine' or r['slots']=='8' and r['depth']=='8')]
    if len(matches)!=1:raise ValueError('Scenario missing from this result set; run it first: '+name)
    match=matches[0];folder=directory/'csv'/(f'n8_f8_{case}' if suite=='engine' else case)
    rows=read_rows(folder/'actual.csv')
    if len(rows)!=int(match['cycles']) and suite!='sensor':raise ValueError('Actual CSV row count does not match summary')
    milestones=read_rows(folder/'milestones.csv') if (folder/'milestones.csv').exists() else []
    return dict(name=name,suite=suite,case=case,description=description,root=directory,folder=folder,rows=rows,
                milestones=milestones,summary=match,meta=meta)
def keyframes(rows):
    fields=['states','open','close','pending','c','n','r','d','q','occupied','valid','reserved','maintenance',
            'fifo_count','dedup_hits','raw_blocked','barrier_pos','state','known','median_mm','sample_count']
    indices=[];last=None
    for i,r in enumerate(rows):
        key=tuple(r.get(f,'') for f in fields)
        if key!=last or r.get('rsp_valid')=='1':indices.append(i);last=key
    if rows and (not indices or indices[-1]!=len(rows)-1):indices.append(len(rows)-1)
    return indices
def show(run):
    print('REPLAY OF VERIFIED RTL OUTPUT (not live FPGA)')
    print(run['case']+' | '+run['description'])
    print('PASS; cycles='+run['summary']['cycles']+'; checks='+run['summary']['checks'])
    for m in run['milestones']:print('MILESTONE '+' '.join(k+'='+v for k,v in m.items()))
    fields=['cycle','index','state','states','open','close','pending','c','n','r','d','q','occupied','reserved','fifo_count','dedup_hits','width','echo_us','median_mm','known']
    frames=keyframes(run['rows']);print('KEY EVENTS (cycle numbers may jump):')
    for i in frames[-35:]:
        row=run['rows'][i];print(' '.join(f+'='+row[f] for f in fields if f in row))
    print('ACTUAL '+str(run['folder']/'actual.csv'))
    print('VCD '+str(run['root']/'vcd'/(('n8_f8_' if run['suite']=='engine' else '')+run['case']+'.vcd')))
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['list','run','show'])
    p.add_argument('name',nargs='?',choices=DEMOS);p.add_argument('--results',type=Path)
    p.add_argument('--iverilog',type=Path);p.add_argument('--vvp',type=Path);p.add_argument('--compile-attempts',type=int,default=1)
    a=p.parse_args()
    if a.action=='list':
        for name,(suite,case,description) in DEMOS.items():print(f'{name:16} {case:30} {description}')
        return 0
    if not a.name:p.error('Choose a scenario; see list')
    try:
        result_dir=a.results or ROOT/'results/demos'/a.name
        if a.action=='run':
            suite,case,_=DEMOS[a.name]
            cmd=[sys.executable,str(ROOT/'python/run_tests.py'),'--suite',suite,'--case',case,'--sizes','8','--depths','8',
                 '--compile-attempts',str(a.compile_attempts),'--out',str(result_dir)]
            for flag,value in [('--iverilog',a.iverilog),('--vvp',a.vvp)]:
                if value:cmd.extend([flag,str(value)])
            result_dir.mkdir(parents=True,exist_ok=True)
            print('RUNNING REAL RTL: '+case,flush=True)
            with (result_dir/'console.log').open('w',encoding='utf-8') as log:
                proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
                for line in proc.stdout:log.write(line);log.flush();print(line,end='',flush=True)
                status=proc.wait()
            if status:return status
            show(load_demo(a.name,result_dir))
        else:show(load_demo(a.name,a.results))
        return 0
    except (OSError,ValueError,KeyError) as error:print('ERROR: '+str(error),file=sys.stderr);return 1
if __name__=='__main__':sys.exit(main())
