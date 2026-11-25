"""Reconstruct every real engine handshake in the integrated top and check it.
Expected engine results come from Python sets/dicts, not from Verilog results.
The milestone list additionally verifies the complete physical Echo/gate route.
"""
import csv
from reference_model import Reference,LAYOUT,HEX
from run_tests import write_csv

def unpack(value):
    result={}
    for name,width in reversed(LAYOUT):result[name]=value&((1<<width)-1);value>>=width
    assert not value
    return result

def verify_top(tools,args,results):
    binary=tools.compile('tb_parking_top','top')
    # Each tuple: milestone,C,N,R,D,Q,O_bitmap,valid_bitmap,reserved_bitmap.
    cases=[('T01_entry_park_exit',[('entered',8,1,0,0,0,0,255,1),('parked',8,1,0,0,0,1,255,0),
                                   ('left_slot',8,1,0,0,0,0,255,0),('exited',8,0,0,0,0,0,255,0)]),
           ('T02_last_slot',[('one_grant',1,0,1,0,0,0,255,1)]),
           ('T03_obstacle_fifo',[('fifo_stalled',8,0,1,0,0,0,255,1),('obstacle',8,0,1,0,0,0,255,1),
                                  ('event_recovered',8,1,0,0,0,0,255,1)]),
           ('T04_offline',[('offline_entered',8,1,0,0,0,0,255,1),('quota_empty',8,1,0,0,0,0,255,1),
                             ('reconnected',8,1,0,0,0,0,255,1)]),
           ('T05_booking',[('booked_entered',8,1,0,1,0,0,255,1),('booking_cancelled',8,1,0,0,0,0,255,1)]),
           ('T06_near_passages',[('three_entered',8,3,0,0,0,0,255,7)]),
           ('T07_reset_session',[('before_reset',8,0,1,0,0,0,255,1),('reset_locked',8,0,0,0,0,0,0,0,0)]),
           ('T08_invalid_ticket',[('ticket_denied',8,0,0,0,0,0,255,0)])]
    for index,(name,marks) in enumerate(cases,1):
        directory=args.out/'csv'/name;directory.mkdir(parents=True,exist_ok=True)
        exp=[dict(zip(['milestone','c','n','r','d','q','occupied','valid','reserved'],row)) for row in [('ready',8,0,0,0,0,0,255,0)]+marks]
        write_csv(directory/'expected_milestones.csv',exp)
        tools.simulate(binary,name,dict(CASE=index,OUTPUT=directory/'actual.csv',MARKS=directory/'milestones.csv',WAVE=args.out/'vcd'/f'{name}.vcd'))
        actual=[{k:v if k=='milestone' else int(v) for k,v in row.items()} for row in csv.DictReader((directory/'milestones.csv').open())]
        assert actual==exp,(name,actual,exp)
        ref=Reference(8,8,32);checks=0;expected_rows=[];cycles=0
        with (directory/'actual.csv').open() as file:
            for row in csv.DictReader(file):
                cycle=int(row['cycle']);x=unpack(int(row['input_vector'],16));e=ref.step(x,cycle)
                for field,wanted in e.items():
                    observed=int(row[field],16 if field in HEX else 10)
                    assert observed==wanted,(name,cycle,field,observed,wanted)
                    checks+=1
                assert not(int(row['close'],16)&int(row['blocked_sync'],16)),(name,'interlock',cycle)
                expected_rows.append({k:(f'{v:x}' if k in HEX else v) for k,v in e.items()})
                cycles+=1
        write_csv(directory/'expected.csv',expected_rows)
        results.append(dict(suite='top',case=name,slots=8,depth=8,cycles=cycles,status='PASS',checks=checks+len(exp)*9))
