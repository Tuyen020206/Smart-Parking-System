"""Audit saved actual/expected tables and the RTL hashes of the completed run."""
from pathlib import Path
import csv,hashlib,json,sys
from reference_model import HEX
ROOT=Path(__file__).resolve().parents[1]

def audit():
    meta=json.loads((ROOT/'results/metadata.json').read_text(encoding='utf-8'))
    assert meta['state']=='COMPLETE',meta
    for name,wanted in meta['rtl_sha256'].items():
        assert hashlib.sha256((ROOT/Path(name.replace('\\','/'))).read_bytes()).hexdigest()==wanted,('RTL changed',name)
    summary=list(csv.DictReader((ROOT/'results/summary.csv').open(encoding='utf-8-sig')))
    checked=0
    for test in summary:
        assert test['status']=='PASS'
        name=test['case'];directory=ROOT/'results/csv'/name
        if test['suite']=='engine':directory=ROOT/'results/csv'/f"n{test['slots']}_f{test['depth']}_{name}"
        expected=directory/('expected_milestones.csv' if test['suite']=='top' else 'expected.csv')
        actual=directory/('milestones.csv' if test['suite'] in ('top','gate') else 'actual.csv')
        exp=list(csv.DictReader(expected.open(encoding='utf-8-sig')));act=list(csv.DictReader(actual.open(encoding='utf-8-sig')))
        assert len(exp)==len(act),(name,'row count')
        for e,a in zip(exp,act):
            for k,v in e.items():
                if k in HEX and test['suite']=='engine':assert int(a[k],16)==int(v),(name,k)
                else:assert a[k]==v,(name,k,a[k],v)
                checked+=1
        # Integrated engine columns are hexadecimal on both saved sides.
        if test['suite']=='top':
            ex=list(csv.DictReader((directory/'expected.csv').open(encoding='utf-8-sig')))
            ac=list(csv.DictReader((directory/'actual.csv').open(encoding='utf-8-sig')))
            assert len(ex)==len(ac)==int(test['cycles']),(name,'integrated trace row count')
            for e,a in zip(ex,ac):
                for k,v in e.items():
                    base=16 if k in HEX else 10
                    assert int(a[k],base)==int(v,base),(name,k)
                    checked+=1
    assert len(summary)==meta['passed']
    print(f'AUDIT PASS: {len(summary)} runs, {checked} saved fields, matching RTL hashes')
    return meta,summary
if __name__=='__main__':audit()
