"""Reproduce MAX validation measurements with pinned physical CPU affinity.

Run: pixi run -e benchmark python tools/benchmark_threading.py
Artifacts go to ignored build/threading; summary statistics remain reproducible.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/threading'

def prepare():
    import treelite
    OUT.mkdir(parents=True, exist_ok=True)
    cases = []
    for family in ['xgboost_regression', 'sklearn_rf_multioutput_regression']:
        seed = treelite.Model.deserialize(ROOT / f'tests/fixtures/frameworks/{family}.tl')
        for trees in [64, 512, 1024, 2048, 3072, 4096, 4608, 6668, 8192]:
            model = treelite.Model.concatenate([seed] * (trees // seed.num_tree))
            path = OUT / f'{family}-{trees}.tl'
            model.serialize(path)
            nodes = sum(int(model.get_tree_accessor(i).get_field('num_nodes')[0]) for i in range(model.num_tree))
            cases.append(dict(name=path.stem, path=str(path), trees=model.num_tree, nodes=nodes))
    # Full binary trees with strongly unequal sizes and many one-node trees.
    from treelite.model_builder import ModelBuilder, Metadata, TreeAnnotation, PostProcessorFunc
    for name, sizes in [('leaves', [1]*4096), ('uneven', [255 if i % 16 == 0 else 1 for i in range(4096)]),
                        ('uneven-2048', [511 if i % 16 == 0 else 1 for i in range(2048)]),
                        ('uneven-3072', [511 if i % 16 == 0 else 1 for i in range(3072)]),
                        ('few-large', [1023]*128), ('dominant', [65535]+[1]*4095)]:
        builder = ModelBuilder(threshold_type='float32', leaf_output_type='float32',
            metadata=Metadata(num_feature=1, task_type='kRegressor', average_tree_output=False,
                              num_target=1, num_class=[1], leaf_vector_shape=(1,1)),
            tree_annotation=TreeAnnotation(num_tree=len(sizes), target_id=[0]*len(sizes), class_id=[0]*len(sizes)),
            postprocessor=PostProcessorFunc(name='identity'), base_scores=[0.0])
        for n in sizes:
            builder.start_tree()
            for i in range(n):
                builder.start_node(i)
                if 2*i+2 < n:
                    builder.numerical_test(feature_id=0, threshold=0.5, default_left=True, opname='<', left_child_key=2*i+1, right_child_key=2*i+2)
                else:
                    builder.leaf(1.0)
                builder.end_node()
            builder.end_tree()
        path = OUT / f'{name}.tl'
        builder.commit().serialize(path)
        cases.append(dict(name=name, path=str(path), trees=len(sizes), nodes=sum(sizes)))
    for case in cases:
        case['sha256'] = hashlib.sha256(Path(case['path']).read_bytes()).hexdigest()
    (OUT/'cases.json').write_text(json.dumps(cases, indent=2))
    return cases


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--reuse', action='store_true')
    parser.add_argument('--repeats', type=int, default=7)
    parser.add_argument('--cpus', default='0-7')
    args=parser.parse_args()
    if args.prepare_only:
        prepare()
        return
    if not args.reuse:
        # Keep Treelite's allocation high-water mark out of child RSS readings.
        import sys
        subprocess.run([sys.executable, str(Path(__file__).resolve()), '--prepare-only'], check=True)
    cases=json.loads((OUT/'cases.json').read_text())
    (OUT/'build-sources.json').write_text(json.dumps({
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in list((ROOT/'src/balsa').glob('*.mojo'))+[ROOT/'tools/threading_worker.mojo']}, indent=2))
    jobs=[]
    # Zero thresholds measure crossover; the imbalance guard still applies.
    for case in cases:
        for workers in [1,2,4,8]:
            jobs.append((case, workers, 0, 0, 1, 'validate'))
        for threshold in [2048,4096]:
            jobs.append((case, 4, threshold, 65536, 1, 'validate'))
    for case in cases:
        if case['name'].endswith(('-64','-4096','-6668')) or case['name'] in ['uneven','dominant','few-large']:
            for workers in [1,2,4,8]:
                for operation in ['encode','decode']:
                    jobs.append((case,workers,4096,65536,1,operation))
            for workers in [1,2,4,8]:
                for callers in [2,4]:
                    jobs.append((case,workers,4096,65536,callers,'validate'))
    jobs *= args.repeats
    random.Random(9241).shuffle(jobs)
    records=[]
    start=time.time()
    for j,(case,workers,trees,nodes,callers,op) in enumerate(jobs):
        loops=max(5,min(400,2_000_000//case['nodes']))
        cmd=['taskset','-c',args.cpus,
             str(OUT/'worker'),case['path'],str(workers),str(trees),str(nodes),str(loops),str(callers),op]
        with (OUT/'worker-output.txt').open('w+') as output:
            proc=subprocess.Popen(cmd,stdout=output,stderr=output,text=True)
            _,status,usage=os.wait4(proc.pid,0)
            proc.returncode=os.waitstatus_to_exitcode(status)
            output.seek(0)
            text=output.read()
            if proc.returncode:
                raise RuntimeError(f'{cmd}: {text}')
            cold,warm=map(float,text.split())
        records.append(dict(case=case['name'],workers=workers,min_trees=trees,min_nodes=nodes,
                            callers=callers,operation=op,loops=loops,cold_ns=cold,warm_ns=warm,
                            peak_rss_kib=usage.ru_maxrss))
        if j%50==0:
            print(f'{j}/{len(jobs)} {time.time()-start:.1f}s',flush=True)
            (OUT/'results.json').write_text(json.dumps(records,indent=2))
    (OUT/'results.json').write_text(json.dumps(records,indent=2))
    (OUT/'environment.json').write_text(json.dumps(dict(cpus=args.cpus,repeats=args.repeats,
        compiler=subprocess.check_output(['pixi','run','mojo','--version'],text=True),
        cpu=subprocess.check_output(['lscpu'],text=True),
        sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in list((ROOT/'src/balsa').glob('*.mojo'))+[Path(__file__), ROOT/'tools/threading_worker.mojo']},
        elapsed_s=time.time()-start),indent=2))

if __name__=='__main__': main()
