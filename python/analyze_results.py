"""Derive cycle/occupancy metrics and explicit logical storage estimates."""
from pathlib import Path
import csv,json,math
from compare_results import audit,ROOT
from reference_model import HEX
from top_checks import unpack
from run_tests import write_csv

def rows(path):return list(csv.DictReader(path.open(encoding='utf-8-sig')))
def analyze():
    meta,summary=audit();assert meta['suite']=='all','Run the complete suite before regenerating analysis';metrics=[]
    for test in summary:
        if test['suite'] not in ('engine','top'):continue
        name=test['case'];directory=ROOT/'results/csv'/name
        if test['suite']=='engine':directory=ROOT/'results/csv'/f"n{test['slots']}_f{test['depth']}_{name}"
        actual=rows(directory/'actual.csv');starts={};latencies=[];accepted=0;stalled=0
        if test['suite']=='engine':
            from reference_model import LAYOUT
            vectors=[unpack(int(line.split()[0],16)) for line in (directory/'vectors.txt').read_text().splitlines()]
        else:vectors=[unpack(int(r['input_vector'],16)) for r in actual]
        for a,x in zip(actual,vectors):
            cycle=int(a['cycle']);ready=int(a['ready'],16)
            for p in range(5):
                if x[f'v{p}']:
                    key=(p,x[f'id{p}']);starts.setdefault(key,cycle)
                    if ready&(1<<p):accepted+=1;latencies.append(cycle-starts.pop(key)+1)
                    else:stalled+=1
        metrics.append(dict(suite=test['suite'],case=name,slots=test['slots'],depth=test['depth'],cycles=len(actual),
          accepted=accepted,stalled_source_cycles=stalled,request_to_rsp_min=min(latencies,default=0),
          request_to_rsp_max=max(latencies,default=0),request_to_rsp_mean=round(sum(latencies)/max(1,len(latencies)),3),
          fifo_peak=max(int(a['fifo_count']) for a in actual),dedup_peak=max(int(a['dedup_used']) for a in actual),
          dedup_hits=max(int(a['dedup_hits']) for a in actual)))
    write_csv(ROOT/'results/metrics.csv',metrics)
    storage=[]
    # Declared functional storage, not technology-mapped utilization.
    for slots in [8,33,128]:
        for dedup in [16,32]:
            depth=8;pw=max(1,(depth-1).bit_length());cw=depth.bit_length();dcw=dedup.bit_length()
            parts=dict(bitmap_bits=6*slots,owner_bits=48*slots,sensor_bits=272*slots,gate_bits=256*4,
                       central_bits=275,dedup_entry_bits=145*dedup,source_history_bits=66*5,
                       memory_control_bits=96+dcw+1,fifo_payload_bits=256*depth,fifo_control_bits=2*pw+cw,
                       top_sync_bits=2*6*4,top_sequence_bits=32)
            storage.append(dict(slots=slots,dedup=dedup,**parts,estimated_total_bits=sum(parts.values()),
                                byte_flags_baseline_bits=6*8*slots,bitmap_saving_percent=87.5))
    write_csv(ROOT/'results/storage.csv',storage)
    # Same input/output trace: byte-flag baseline and shift-queue baseline.
    baseline=[]
    for name in ['n8_f8_E13_fifo_full','n33_f3_E14_wrap','n128_f8_E25_random']:
        actual=rows(ROOT/'results/csv'/name/'actual.csv');previous=0;ring_writes=shift_writes=0
        for a in actual:
            flags=[int(a[k],16) for k in ['occupied','valid','reserved','maintenance','admitted','exit_pending']]
            size=int(name.split('_')[0][1:]);byte_flags=[[int(bool(mask&(1<<i))) for i in range(size)] for mask in flags]
            assert all(sum(v<<i for i,v in enumerate(arr))==mask for arr,mask in zip(byte_flags,flags))
            inp=unpack(int((ROOT/'results/csv'/name/'vectors.txt').read_text().splitlines()[int(a['cycle'])].split()[0],16))
            count=int(a['fifo_count']);pop=int(a['event_valid_pre']) and inp['event_ready']
            push=count-previous+int(bool(pop))
            if inp['rst']:previous=0;continue
            assert push in (0,1)
            ring_writes+=push;shift_writes+=push+max(0,previous-1)*int(bool(pop));previous=count
        baseline.append(dict(trace=name,cycles=len(actual),same_flags_and_fifo_stream='PASS (oracle)',
                             ring_payload_word_writes=ring_writes,shift_baseline_word_writes=shift_writes,
                             event_bits=256,assumption='shift on every pop; ring writes only on push'))
    write_csv(ROOT/'results/baseline.csv',baseline)
    (ROOT/'results/analysis.json').write_text(json.dumps(dict(passed=meta['passed'],cycles=meta['cycles'],checks=meta['checks'],
          metrics=metrics,storage=storage,baseline=baseline),indent=2),encoding='utf-8')
    print('Analysis complete. Memory is a declared-state estimate; no synthesis claim.')
if __name__=='__main__':analyze()
