"""Summarize randomized per-process timing batches (ns -> us)."""
import json
from pathlib import Path
import statistics
from collections import defaultdict

root = Path(__file__).resolve().parents[1]
groups = defaultdict(list)
for row in json.loads((root/'build/threading/results.json').read_text()):
    key = tuple(row[k] for k in ['case','operation','callers','min_trees','min_nodes','workers'])
    groups[key].append(row)
summary=[]
for key,rows in sorted(groups.items()):
    entry=dict(zip(['case','operation','callers','min_trees','min_nodes','workers'],key))
    entry['batches']=len(rows)
    for field in ['warm_ns','cold_ns','peak_rss_kib']:
        values=[r[field] for r in rows]
        entry[field]={'median':statistics.median(values),'min':min(values),'max':max(values)}
    summary.append(entry)
(root/'build/threading/summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for entry in summary:
    if entry['operation']=='validate' and entry['callers']==1 and entry['min_trees']==0:
        print(entry['case'],entry['workers'],round(entry['warm_ns']['median']/1000,1),round(entry['cold_ns']['median']/1000,1))

# Independent bootstrap of process-batch medians; no independence is claimed
# for the individual calls inside a timed batch.
import random
comparison_path=root/'build/threading/baseline-comparison.json'
if comparison_path.exists():
    comparison=json.loads(comparison_path.read_text())
    rng=random.Random(42)
    comparisons=[]
    for name in sorted({r['case'] for r in comparison}):
        for op in ['validate','encode','decode']:
            old,new=[[r['ns'] for r in comparison if r['case']==name and
                      r['operation']==op and r['binary']==binary]
                     for binary in ['baseline','parallel']]
            ratios=sorted(statistics.median(rng.choices(old,k=len(old)))/
                          statistics.median(rng.choices(new,k=len(new)))
                          for _ in range(5000))
            comparisons.append(dict(case=name,operation=op,
                baseline_ns=statistics.median(old),parallel_ns=statistics.median(new),
                speedup=statistics.median(old)/statistics.median(new),
                bootstrap_95=[ratios[125],ratios[4875]]))
    (root/'build/threading/comparison-summary.json').write_text(json.dumps(comparisons,indent=2)+'\n')
