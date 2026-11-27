"""Sample-level oracle, driven only by configured raw Echo widths."""
from collections import deque
from pathlib import Path
import csv,re
from run_tests import write_csv,selected

def expected(widths,expire_after=None):
    window=deque(maxlen=5);known=occ=median=confirm=last=echo=0;rows=[]
    for index,width in enumerate(widths):
        if index==expire_after:window.clear();known=confirm=0
        bad=not 50<=width<=3000
        if width>0 and width<=3000:echo=width
        if bad:window.clear();known=confirm=0
        else:
            window.append(width)
            if len(window)==5:
                median=sorted(window)[2]*343//2000
                cand=1 if median<=100 else 0 if median>=140 else occ
                can_confirm=known or median<=100 or median>=140
                if can_confirm:
                    if known and cand==occ:confirm=0
                    else:
                        confirm=confirm+1 if cand==last else 1;last=cand
                        if confirm>=3:known=1;occ=cand;confirm=0
                else:confirm=0
        rows.append(dict(index=index,width=width,echo_us=echo,sample_count=len(window),median_mm=median,
                         known=known,occupied=occ,led=6 if not known else 4 if occ else 2,timeout=int(bad)))
    return rows

def verify_sensor(tools,args,results):
    binary=None;binary_50=None
    cases={
      'S01_cold_free':[1200]*9,
      'S02_free_occupied':[1200]*8+[200]*9,
      'S03_outlier':[1200]*8+[200,1200,1200,1200,1200,2500,1200],
      'S04_hysteresis':[1200]*8+[700]*7+[200]*8+[700]*7+[900]*8,
      'S05_timeout_recovery':[1200]*8+[0]+[200]*8,
      'S06_stuck_high':[200]*8+[-1]+[1200]*8,
      'S07_invalid_short':[1200]*8+[20]+[1200]*8,
      'S08_no_echo_cold':[0,0]+[1200]*7,
      'S09_status_backpressure':[1200]*10,
      'S10_stale_backpressure':[1200]*10,
      'S11_clock_50mhz':[1200]*8+[200]*8,
      'S12_threshold_50mhz':[1200]*8+[584]*8+[700]*6+[817]*8}
    for name,widths in cases.items():
        if not selected(args,name):continue
        if binary is None:binary=tools.compile('tb_sensor','sensor')
        directory=args.out/'csv'/name;directory.mkdir(parents=True,exist_ok=True)
        inp=directory/'echo_widths.txt';out=directory/'actual.csv';inp.write_text('\n'.join(map(str,widths))+'\n')
        exp=expected(widths,7 if name=='S10_stale_backpressure' else None);write_csv(directory/'expected.csv',exp)
        plus=dict(INPUT=inp,OUTPUT=out)
        if name=='S04_hysteresis':plus['WAVE']=args.out/'vcd'/f'{name}.vcd'
        if name in ('S09_status_backpressure','S10_stale_backpressure'):
            hold=2 if name=='S10_stale_backpressure' else 1
            selected_binary=tools.compile('tb_sensor',f'sensor_backpressure_{hold}',dict(HOLD_STATUS=hold))
        elif name in ('S11_clock_50mhz','S12_threshold_50mhz'):
            if binary_50 is None:binary_50=tools.compile('tb_sensor','sensor_50mhz',dict(CLK_RATE=50000000))
            selected_binary=binary_50
        else:selected_binary=binary
        log=tools.simulate(selected_binary,name,plus)
        actual=[{k:int(v) for k,v in row.items()} for row in csv.DictReader(out.open())]
        assert actual==exp,(name,[(a,e) for a,e in zip(actual,exp) if a!=e][:3])
        cycles=int(re.search(r'cycles=(\d+)',log)[1])
        results.append(dict(suite='sensor',case=name,slots=1,depth=0,cycles=cycles,status='PASS',checks=len(exp)*9))
