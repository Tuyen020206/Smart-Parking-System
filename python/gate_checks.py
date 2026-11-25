"""Declarative expected milestones are independent of the gate implementation."""
import csv,re
from run_tests import write_csv

def verify_gate(tools,args,results):
    binary=tools.compile('tb_gate','gate')
    cases=[('G01_normal',[('granted',2,1,0,0),('passed',4,0,1,1),('closed',0,0,0,0)]),
           ('G02_denied',[('denied',0,0,0,0)]),
           ('G03_session_id',[('wrong_tag',1,0,0,0),('wrong_id',1,0,0,0),('correct',2,1,0,0)]),
           ('G04_backpressure_obstacle',[('stalled_passage',4,0,1,1),('obstacle',2,1,0,1),('delivered_once',0,0,0,0)]),
           ('G05_cancel',[('cancelled',4,0,1,0)]),
           ('G06_open_timeout',[('opening_timeout',5,0,0,0)]),
           ('G07_close_timeout',[('closing_timeout',5,0,0,1)]),
           ('G08_reset_active',[('reset_active',5,0,0,0)]),
           ('G09_simultaneous_cancel_pass',[('passage_wins',4,0,1,1)]),
           ('G10_authorization_timeout',[('authorization_timeout',5,0,0,0)])]
    for index,(name,marks) in enumerate(cases,1):
        directory=args.out/'csv'/name;directory.mkdir(parents=True,exist_ok=True)
        exp=[dict(zip(['milestone','state','open','close','pending'],row)) for row in [('recovered',0,0,0,0)]+marks]
        write_csv(directory/'expected.csv',exp)
        plus=dict(CASE=index,OUTPUT=directory/'actual.csv',MARKS=directory/'milestones.csv')
        if index==4:plus['WAVE']=args.out/'vcd'/f'{name}.vcd'
        log=tools.simulate(binary,name,plus)
        actual=[{k:v if k=='milestone' else int(v) for k,v in row.items()} for row in csv.DictReader((directory/'milestones.csv').open())]
        assert actual==exp,(name,actual,exp)
        rows=list(csv.DictReader((directory/'actual.csv').open()))
        assert all(not(int(r['blocked']) and int(r['close'])) for r in rows)
        results.append(dict(suite='gate',case=name,slots=0,depth=0,cycles=len(rows),status='PASS',checks=len(rows)+len(exp)*5))
