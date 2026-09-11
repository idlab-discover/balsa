"""Summarize decode benchmark medians and bootstrap process-batch uncertainty."""
import argparse
import json
from pathlib import Path
import random
import statistics

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory',type=Path)
args=parser.parse_args()
rows=json.loads((args.directory/'timings.json').read_text())
cases=sorted({r['case'] for r in rows})
rng=random.Random(9041)
summary=[]
for case in cases:
    for operation in ['decode','encode','validate']:
        groups={engine:[r['ns'] for r in rows if r['case']==case and r['operation']==operation and r['engine']==engine]
                for engine in ['baseline-serial','current-serial','current-default','native']}
        groups={key:value for key,value in groups.items() if value}
        medians={key:statistics.median(value) for key,value in groups.items()}
        intervals={}
        for numerator,denominator in [('baseline-serial','current-serial'),('current-serial','native'),('current-default','native')]:
            if numerator not in groups or denominator not in groups:continue
            a,b=groups[numerator],groups[denominator]
            samples=sorted(statistics.median(rng.choices(a,k=len(a)))/statistics.median(rng.choices(b,k=len(b))) for _ in range(5000))
            intervals[numerator+'/'+denominator]=[samples[125],samples[4875]]
        entry=dict(case=case,operation=operation,median_ns=medians,ratio_bootstrap95=intervals)
        summary.append(entry)
        print(case,operation,{key:round(value/1000,2) for key,value in medians.items()})
(args.directory/'analysis.json').write_text(json.dumps(summary,indent=2)+'\n')
