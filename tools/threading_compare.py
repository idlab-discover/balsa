"""Compare the saved pre-change worker with the current worker on the existing corpus.

Build benchmarking/balsa_worker.mojo against the old/new sources as
build/threading/baseline and build/threading/parallel before running.
"""
import json
import random
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'build/threading'

def main():
    cases=json.loads((ROOT/'benchmarking/corpus/manifest.json').read_text())
    jobs=[(c,op,b) for c in cases for op in ['validate','encode','decode']
          for b in ['baseline','parallel']]*9
    random.Random(411).shuffle(jobs)
    rows=[]
    for case,op,binary in jobs:
        loops=max(10,min(1000,2_000_000//case['nodes']))
        result=subprocess.check_output(['taskset','-c','0-7',str(OUT/binary),
            case['path'],op,str(loops)],text=True)
        rows.append(dict(case=case['name'],operation=op,binary=binary,
                         ns=float(result.split()[0])*1e9/loops))
    (OUT/'baseline-comparison.json').write_text(json.dumps(rows,indent=2)+'\n')
    for case in cases:
        print(case['name'])
        for op in ['validate','encode','decode']:
            values=[statistics.median(r['ns'] for r in rows if r['case']==case['name']
                    and r['operation']==op and r['binary']==b) for b in ['baseline','parallel']]
            print(op,*(round(v/1000,2) for v in values),'speedup',round(values[0]/values[1],3))

if __name__=='__main__': main()
