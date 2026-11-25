"""Replay the real event stream into a durable JSONL host journal.
This is a trace-driven host demonstration, not a live UART transport.
ACK checks use only journal entries fsync'ed BEFORE the retirement cycle.
"""
import csv,json,os
from pathlib import Path
from top_checks import unpack
from run_tests import write_csv
ROOT=Path(__file__).resolve().parents[1]

def decode(word):
    shifts=dict(id=(192,64),op=(184,8),status=(176,8),slot=(160,16),tag=(144,16),data=(128,16),
                c=(112,16),n=(96,16),r=(80,16),d=(64,16),q=(48,16),flags=(40,8))
    result={k:(word>>s)&((1<<w)-1) for k,(s,w) in shifts.items()}
    result.update(source=result['id']>>56,epoch=(result['id']>>32)&0xffffff,sequence=result['id']&0xffffffff)
    result['id']=f"{result['id']:016x}";return result

def main():
    destination=ROOT/'results/journals';destination.mkdir(parents=True,exist_ok=True);summary=[]
    cases=[p for p in (ROOT/'results/csv').iterdir() if p.name.startswith('T') or p.name in
           ('n8_f8_E11_checkpoint_stale','n8_f8_E12_dedup_full','n8_f8_E17_quota_replay','n8_f8_E25_random')]
    for directory in sorted(cases):
        durable={};seen={};records=acks=denied=0
        actual=list(csv.DictReader((directory/'actual.csv').open(encoding='utf-8-sig')))
        vectors=None
        if (directory/'vectors.txt').exists():vectors=[unpack(int(line.split()[0],16)) for line in (directory/'vectors.txt').read_text().splitlines()]
        with (destination/(directory.name+'.jsonl')).open('w',encoding='utf-8') as file:
            for index,a in enumerate(actual):
                x=vectors[index] if vectors else unpack(int(a['input_vector'],16))
                if x['retire_valid']:
                    key=(x['retire_source'],x['retire_epoch'])
                    safe=key in durable and x['retire_seq']<=durable[key]
                    if int(a['retire_ok']):assert safe,(directory.name,'ACK before journal');acks+=1
                    else:denied+=1
                if int(a['event_valid_pre']) and x['event_ready']:
                    word=int(a['event_data_pre'],16);record=decode(word);eid=record['id']
                    if eid in seen:assert seen[eid]==word,('journal ID conflict',eid)
                    else:
                        file.write(json.dumps(dict(cycle=int(a['cycle']),**record),ensure_ascii=False)+'\n')
                        file.flush();os.fsync(file.fileno());seen[eid]=word;records+=1
                    if record['source']<5:
                        key=(record['source'],record['epoch']);durable[key]=max(durable.get(key,0),record['sequence'])
        summary.append(dict(trace=directory.name,journal_records=records,accepted_retirements=acks,
                            rejected_retirements=denied,ack_after_fsync='PASS'))
    write_csv(ROOT/'results/host_journal_summary.csv',summary)
    print(f'Host journal replay PASS: {len(summary)} traces; ACK never precedes fsync.')
if __name__=='__main__':main()
