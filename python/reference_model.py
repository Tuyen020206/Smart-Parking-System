"""Independent set/dictionary reference for arbitration, capacity, replay and FIFO.
This model does not call RTL or use its outputs to create expected values.
"""
from collections import deque

HEX={'ready','event_data_pre','rsp_id','occupied','valid','reserved','maintenance','admitted','exit_pending','commit_id'}
LAYOUT=[('rst',1),('run_enable',1),('epoch',24)]
for port in range(5):
    LAYOUT += [(f'v{port}',1),(f'id{port}',64),(f'op{port}',4),(f'slot{port}',16),(f'data{port}',16),(f'tag{port}',16)]
LAYOUT += [('sensor_valid',1),('sensor_slot',16),('sensor_known',1),('sensor_occupied',1),('sensor_id',64),('event_ready',1),
           ('retire_valid',1),('retire_source',8),('retire_epoch',24),('retire_seq',32)]
assert sum(n for _,n in LAYOUT)==760
def pack(x):
    result=0
    for name,width in LAYOUT:
        assert 0<=x[name]<(1<<width),(name,x[name]);result=(result<<width)|x[name]
    return f'{result:0190x}'
def bitmap(items):return sum(1<<i for i in items)
def event_record(eid,op,status,slot,tag,data,counts,flags=0):
    result=eid
    for value,width in [(op,8),(status,8),(slot,16),(tag,16),(data,16),*[(v,16) for v in counts],(flags,8),(0,40)]:
        result=(result<<width)|value
    return result

class Reference:
    def __init__(self,slots,depth=8,dedup=16):self.slots=slots;self.depth=depth;self.limit=dedup;self.reset()
    def reset(self):
        self.c=self.slots;self.n=self.r=self.d=self.q=0;self.online=1;self.rr=0
        self.o=set();self.v=set();self.res=set();self.maint=set();self.inside=set();self.exits={};self.owner={}
        self.queue=deque();self.cache={};self.high={};self.delivered={};self.hits=self.conflicts=self.stale=0
        self.rsp=dict(rsp_id=0,rsp_op=0,rsp_source=0,rsp_status=0,rsp_slot=65535,rsp_tag=0)
        self.commit_op=0;self.commit_id=0
    def counts(self):return (self.c,self.n,self.r,self.d,self.q)
    def available(self):return max(0,self.c-self.n-self.r-self.d-self.q)
    def step(self,x,cycle):
        rst=x['rst']
        # Keep the selection logic explicit for readability and independence.
        selected=None
        for k in range(5):
            p=(self.rr+k)%5
            if x[f'v{p}']:selected=p;break
        fifo_space=len(self.queue)<self.depth or bool(x['event_ready'])
        sensor_ready=int(not rst and fifo_space)
        y=dict(cycle=cycle,ready=0,sensor_ready=sensor_ready,event_valid_pre=int(bool(self.queue) and not rst),
               event_data_pre=self.queue[0] if self.queue else 0)
        duplicate=False;early=0;cached=None;eid=op=slot=data=tag=0;status=0;chosen_slot=0
        if selected is not None:
            eid=x[f'id{selected}'];op=x[f'op{selected}'];slot=x[f'slot{selected}'];data=x[f'data{selected}'];tag=x[f'tag{selected}']
            payload=(op,slot,data,tag);src=eid>>56;ep=(eid>>32)&0xffffff;seq=eid&0xffffffff
            if src!=selected:early=7
            elif ep!=x['epoch']:early=6
            elif eid in self.cache:
                old_payload,old_status,old_slot=self.cache[eid]
                if old_payload!=payload:early=4
                else:duplicate=True;cached=(old_status,old_slot)
            elif selected in self.high and seq<=self.high[selected]:early=5
            ready=not rst and not x['sensor_valid'] and (duplicate or early or (len(self.cache)<self.limit and fifo_space))
            if ready:y['ready']=1<<selected
        fire=bool(y['ready']);sensor_fire=bool(x['sensor_valid'] and sensor_ready)
        retire_ok=0;commit=False
        if rst:self.reset()
        else:
            # Retirement is validated against previously delivered data, not the same edge's pop.
            rs=x['retire_source'];rq=x['retire_seq']
            if x['retire_valid'] and rs in self.delivered and x['retire_epoch']==x['epoch'] and rq<=self.delivered[rs]:
                retire_ok=1
                retire_ids=[key for key in self.cache if key>>56==rs and (key>>32)&0xffffff==x['epoch'] and (key&0xffffffff)<=rq]
            else:retire_ids=[]
            if self.queue and x['event_ready']:
                ev=self.queue.popleft();source=ev>>248;sequence=(ev>>192)&0xffffffff
                if source<5:self.delivered[source]=max(self.delivered.get(source,0),sequence)
            for key in retire_ids:self.cache.pop(key)
            if sensor_fire:
                s=x['sensor_slot'];known=x['sensor_known'];occ=x['sensor_occupied']
                if s<self.slots:
                    if known:self.v.add(s)
                    else:self.v.discard(s)
                    if known:
                        if occ:self.o.add(s)
                        else:self.o.discard(s)
                        if occ and s in self.inside:self.res.discard(s)
                self.queue.append(event_record(x['sensor_id'],128,0,s,0,0,self.counts(),known*2+occ))
            elif fire:
                self.rr=(selected+1)%5;chosen_slot=slot
                if early:
                    status=early
                    if early==4:self.conflicts+=1
                    if early==5:self.stale+=1
                elif duplicate:
                    status,chosen_slot=cached;self.hits+=1
                else:
                    # Slot eligibility/ownership is evaluated before capacity/authorization.
                    free=sorted(self.v-self.o-self.res-self.maint-self.inside)
                    if op in (0,5,7):
                        chosen_slot=free[0] if free else 65535
                        if not free:status=1
                    elif op in (1,2):
                        if slot>=self.slots:status=2
                        elif slot not in self.res or slot in self.inside or self.owner.get(slot)!=(selected,tag):status=3
                    elif op==3:
                        if slot>=self.slots:status=2
                        elif slot not in self.inside or slot in self.o or self.exits.get(slot)!=(selected,tag):status=3
                    elif op==10:
                        if slot>=self.slots:status=2
                    elif op==11:
                        if slot>=self.slots:status=2
                        elif slot not in self.inside or slot in self.o or slot in self.exits:status=3
                    elif op not in (4,6,8,9,12):status=8
                    if not status:
                        total=self.n+self.r+self.d+self.q
                        if op in (0,5,7):
                            if selected>=3 or not(data&1):status=9
                            elif not x['run_enable']:status=10
                            elif op==0 and (not self.online or total>=self.c):status=1
                            elif op==5 and (not self.online or self.d==0):status=1
                            elif op==7 and (self.online or self.q==0):status=1
                        elif op in (1,2):
                            if selected>=3 or not(data&1):status=9
                            elif self.r==0:status=1
                        elif op==3:
                            if selected!=3 or not(data&1):status=9
                            elif self.n==0:status=1
                        elif op in (4,6):
                            if selected!=4:status=9
                            elif not data or total+data>self.c or not self.online:status=1
                        elif op in (8,9,10,12):
                            if selected!=4:status=9
                            elif op==9 and data>self.slots:status=1
                            elif op==12 and (data==0 or data>self.d):status=1
                        elif op==11:
                            if selected!=3 or not(data&1):status=9
                            elif not x['run_enable']:status=10
                    if status==0:
                        commit=True
                        if op in (0,5,7):
                            self.res.add(chosen_slot);self.owner[chosen_slot]=(selected,tag);self.r+=1
                            if op==5:self.d-=1
                            if op==7:self.q-=1
                        elif op==1:
                            self.r-=1;self.n+=1;self.inside.add(slot)
                            if slot in self.o:self.res.discard(slot)
                        elif op==2:self.res.discard(slot);self.r-=1
                        elif op==3:
                            self.inside.discard(slot);self.res.discard(slot);self.exits.pop(slot);self.n-=1
                        elif op==4:self.d+=data
                        elif op==6:self.q+=data
                        elif op==8:self.online=data&1
                        elif op==9:self.c=data
                        elif op==10:
                            if data&1:self.maint.add(slot)
                            else:self.maint.discard(slot)
                        elif op==11:self.exits[slot]=(selected,tag)
                        elif op==12:self.d-=data
                        self.commit_op=op;self.commit_id=eid
                    self.cache[eid]=(payload,status,chosen_slot);self.high[selected]=seq
                    self.queue.append(event_record(eid,op,status,chosen_slot,tag,data,self.counts()))
                self.rsp=dict(rsp_id=eid,rsp_op=op,rsp_source=selected,rsp_status=status,rsp_slot=chosen_slot,rsp_tag=tag)
        assert self.n==len(self.inside) and self.r==len(self.res-self.inside)
        assert min(self.n,self.r,self.d,self.q)>=0 and len(self.queue)<=self.depth and len(self.cache)<=self.limit
        y.update(self.rsp)
        y.update(rsp_valid=int(fire and not rst),c=self.c,n=self.n,r=self.r,d=self.d,q=self.q,available=self.available(),
                 online=self.online,overcommitted=int(self.n+self.r+self.d+self.q>self.c),
                 occupied=bitmap(self.o),valid=bitmap(self.v),reserved=bitmap(self.res),maintenance=bitmap(self.maint),
                 admitted=bitmap(self.inside),exit_pending=bitmap(self.exits),fifo_count=len(self.queue),dedup_used=len(self.cache),
                 dedup_hits=self.hits,conflicts=self.conflicts,stale_count=self.stale,retire_ok=retire_ok,
                 commit_valid=int(commit),commit_op=self.commit_op,commit_id=self.commit_id)
        return y
