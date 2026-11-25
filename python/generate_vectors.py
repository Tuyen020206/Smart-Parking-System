from reference_model import Reference,LAYOUT,pack
import random

class Scenario:
    def __init__(self,name,slots=8,depth=8,dedup=16):
        self.name=name;self.ref=Reference(slots,depth,dedup);self.vectors=[];self.expected=[];self.seq=[0]*5;self.epoch=1
        self.step(rst=1)
    def step(self,**kw):
        x={key:0 for key,_ in LAYOUT};x.update(run_enable=1,epoch=self.epoch,event_ready=1,retire_epoch=self.epoch)
        x.update(kw);y=self.ref.step(x,len(self.vectors));self.vectors.append(x);self.expected.append(y);return y
    def command(self,port,op,slot=0,data=1,tag=1,eid=None,auto_retire=True,**kw):
        if eid is None:
            self.seq[port]+=1;eid=(port<<56)|(self.epoch<<32)|self.seq[port]
        for attempt in range(200):
            if auto_retire and len(self.ref.cache)>=self.ref.limit-1:self.checkpoint()
            y=self.step(**{f'v{port}':1,f'id{port}':eid,f'op{port}':op,f'slot{port}':slot,f'data{port}':data,f'tag{port}':tag},**kw)
            if y['ready']&(1<<port):return y
        raise AssertionError('command stalled: '+self.name)
    def checkpoint(self):
        for _ in range(self.ref.depth+2):self.step()
        for p,seq in list(self.ref.delivered.items()):self.step(retire_valid=1,retire_source=p,retire_seq=seq)
    def initialize(self):
        for slot in range(self.ref.slots):self.sensor(slot,True,False)
    def sensor(self,slot,known,occupied):
        for _ in range(100):
            y=self.step(sensor_valid=1,sensor_slot=slot,sensor_known=int(known),sensor_occupied=int(occupied),sensor_id=(254<<56)|(self.epoch<<32)|(len(self.vectors)+1))
            if y['sensor_ready']:return y
        raise AssertionError('sensor stalled')
    def alloc(self,port=0,op=0,tag=1,**kw):
        y=self.command(port,op,tag=tag,**kw);assert y['rsp_status']==0,y;return y['rsp_slot']
    def finish(self):
        for _ in range(self.ref.depth+2):self.step()

def engine_scenarios(slots=8,depth=8,dedup=16,random_cycles=600):
    ss=[]
    def new(name):
        s=Scenario(name,slots,depth,dedup);ss.append(s);return s
    s=new('E01_reset_unknown');assert s.command(0,0)['rsp_status']==1
    s=new('E02_normal');s.initialize();slot=s.alloc();s.command(0,1,slot);s.sensor(slot,1,1);s.sensor(slot,1,0)
    s.command(3,11,slot,tag=55);s.command(3,3,slot,tag=55);assert s.ref.n==s.ref.r==0
    s=new('E03_full');s.initialize()
    for i in range(slots):s.alloc(i%3,tag=i+1)
    assert s.command(0,0,tag=200)['rsp_status']==1
    s=new('E04_three_gates_last');s.sensor(0,1,0)
    ids=[(p<<56)|(1<<32)|1 for p in range(3)]
    pending={0,1,2};accepted=[]
    while pending:
        kw={}
        for p in pending:kw.update({f'v{p}':1,f'id{p}':ids[p],f'op{p}':0,f'data{p}':1,f'tag{p}':1})
        y=s.step(**kw)
        if y['rsp_valid']:pending.remove(y['rsp_source']);accepted.append(y['rsp_status'])
    assert accepted.count(0)==1 and s.ref.r==1
    s=new('E05_round_robin');pending={p:1 for p in range(3)};grants=[]
    for _ in range(12):
        kw={}
        for p,q in pending.items():kw.update({f'v{p}':1,f'id{p}':(p<<56)|(1<<32)|q,f'op{p}':15})
        y=s.step(**kw);p=y['rsp_source'];grants.append(p);pending[p]+=1
    assert grants==[0,1,2]*4
    s=new('E06_cancel');s.initialize();slot=s.alloc();assert s.command(0,2,slot,data=0)['rsp_status']==9
    s.command(0,2,slot);assert s.ref.r==0
    s=new('E07_slot_vs_vehicle');s.initialize();slot=s.alloc();s.command(0,1,slot);s.sensor(slot,1,1)
    assert s.command(3,11,slot)['rsp_status']==3
    s.sensor(slot,1,0);assert s.ref.n==1
    s=new('E08_unknown_maintenance');s.initialize();s.sensor(0,0,0);s.command(4,10,1,data=1)
    y=s.command(0,0);assert y['rsp_slot'] not in (0,1) or y['rsp_status']!=0
    s=new('E09_duplicate');s.initialize();slot=s.alloc();eid=(1<<32)|s.seq[0]
    before=s.ref.r;s.command(0,0,eid=eid);assert s.ref.r==before and s.ref.hits==1
    s=new('E10_conflict');s.initialize();s.alloc();eid=(1<<32)|s.seq[0]
    assert s.command(0,0,data=0,eid=eid)['rsp_status']==4 and s.ref.r==1
    s=new('E11_checkpoint_stale');s.initialize();s.alloc();eid=(1<<32)|s.seq[0];s.checkpoint()
    assert s.command(0,0,eid=eid)['rsp_status']==5 and s.ref.r==1
    s=new('E12_dedup_full');s.initialize()
    for i in range(dedup):s.command(4,15,tag=i,auto_retire=False)
    held=dict(v4=1,id4=(4<<56)|(1<<32)|(dedup+1),op4=15)
    y=s.step(**held);assert not y['ready']
    # Keep the same request asserted while checkpoint frees capacity.
    for _ in range(depth+5):
        y=s.step(**held,retire_valid=1,retire_source=4,retire_seq=dedup)
        if y['ready']:break
    assert y['rsp_valid'] and len(s.ref.cache)==1
    s=new('E13_fifo_full');s.initialize();s.finish()
    for i in range(depth):s.command(i%3,15,tag=i,event_ready=0)
    y=s.step(v0=1,id0=(1<<32)|200,op0=15,event_ready=0);assert not y['ready']
    y=s.step(v0=1,id0=(1<<32)|200,op0=15,event_ready=1);assert y['ready']==1 and y['fifo_count']==depth
    s=new('E14_wrap');s.initialize()
    for i in range(depth*4):s.command(4,15,tag=i)
    s=new('E15_booking');s.initialize();s.command(4,4,data=2);slot=s.alloc(1,5,tag=9)
    assert s.ref.d==1 and s.ref.r==1;s.command(1,1,slot,tag=9);s.command(4,12,data=1);assert s.ref.d==0 and s.ref.n==1
    s=new('E16_offline_quota');s.initialize();s.command(4,6,data=1);s.command(4,8,data=0)
    slot=s.alloc(2,7,tag=8);s.command(2,1,slot,tag=8)
    assert s.ref.q==0 and s.ref.n==1 and s.command(1,7)['rsp_status']==1
    assert s.command(0,0)['rsp_status']==1
    s.command(4,8,data=1);s.command(0,0);assert s.ref.n==1
    s=new('E17_quota_replay');s.initialize();s.command(4,6,data=2);eid=(4<<56)|(1<<32)|s.seq[4]
    s.command(4,6,data=2,eid=eid);assert s.ref.q==2
    s=new('E18_capacity_reduction');s.initialize();s.alloc();s.command(4,9,data=0)
    assert s.ref.r==1 and s.expected[-1]['overcommitted']==1
    assert s.command(1,0)['rsp_status']==1
    s=new('E19_epoch_wrap');s.initialize();s.command(0,15,eid=(1<<32)|0xffffffff)
    assert s.command(0,15,eid=(1<<32))['rsp_status']==5
    assert s.command(1,0,eid=(1<<56)|(2<<32)|1)['rsp_status']==6
    s=new('E20_source_owner');s.initialize();slot=s.alloc(0,tag=77)
    assert s.command(1,1,slot,tag=77)['rsp_status']==3
    assert s.command(0,1,slot,tag=78)['rsp_status']==3
    assert s.command(4,8,eid=(3<<56)|(1<<32)|1)['rsp_status']==7
    s=new('E21_checkpoint_not_delivered');s.initialize();s.finish();s.command(4,15,event_ready=0)
    y=s.step(retire_valid=1,retire_source=4,retire_seq=1,event_ready=0);assert y['retire_ok']==0
    s=new('E22_reset_pending');s.initialize();s.alloc();s.step(rst=1,run_enable=0);s.epoch=2
    y=s.command(0,0,eid=(1<<32)|100,run_enable=0);assert y['rsp_status']==6 and not s.ref.v
    s=new('E23_sensor_command_priority');
    y=s.step(sensor_valid=1,sensor_slot=0,sensor_known=1,sensor_occupied=0,v0=1,id0=(1<<32)|1,op0=0,data0=1)
    assert y['ready']==0 and y['sensor_ready']==1
    y=s.step(v0=1,id0=(1<<32)|1,op0=0,data0=1);assert y['ready']==1
    s=new('E24_run_disabled');s.initialize();assert s.command(0,0,run_enable=0)['rsp_status']==10
    s=new('E25_random');s.initialize();rng=random.Random(20261125+slots+depth);pending=[None]*5;sequence=[0]*5
    for step in range(random_cycles):
        kw=dict(event_ready=int(rng.random()<.75))
        # Retire through a separate channel; never drop a stalled valid request.
        for port in range(5):
            if s.ref.delivered.get(port) is not None and any((key>>56)==port for key in s.ref.cache):
                kw.update(retire_valid=1,retire_source=port,retire_seq=s.ref.delivered[port]);break
        for port in range(5):
            if pending[port] is None and rng.random()<.45:
                sequence[port]+=1
                op=rng.choice([0,1,2,5,7,15]) if port<3 else rng.choice([3,11,15]) if port==3 else rng.choice([4,6,8,9,10,12,15])
                pending[port]=dict(eid=(port<<56)|(1<<32)|sequence[port],op=op,slot=rng.randrange(slots+2),data=rng.randrange(3),tag=rng.randrange(1,5))
            if pending[port]:
                c=pending[port];kw.update({f'v{port}':1,f'id{port}':c['eid'],f'op{port}':c['op'],f'slot{port}':c['slot'],f'data{port}':c['data'],f'tag{port}':c['tag']})
        y=s.step(**kw)
        for port in range(5):
            if y['ready']&(1<<port):pending[port]=None
    for _ in range(40):
        if not any(pending):break
        kw=dict(event_ready=1)
        for port in range(5):
            if port in s.ref.delivered and any((key>>56)==port for key in s.ref.cache):
                kw.update(retire_valid=1,retire_source=port,retire_seq=s.ref.delivered[port]);break
        for port,c in enumerate(pending):
            if c:kw.update({f'v{port}':1,f'id{port}':c['eid'],f'op{port}':c['op'],f'slot{port}':c['slot'],f'data{port}':c['data'],f'tag{port}':c['tag']})
        y=s.step(**kw)
        for port in range(5):
            if y['ready']&(1<<port):pending[port]=None
    assert not any(pending),'Random test must drain held requests'
    for s in ss:s.finish()
    return ss
