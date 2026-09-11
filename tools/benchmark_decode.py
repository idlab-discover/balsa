"""Reproduce serial/default Balsa versus native Treelite codec measurements.

Run from the repo: pixi run -e benchmark python tools/benchmark_decode.py
Use --profile for additional perf, Callgrind, and allocator-call diagnostics.
Timings never use instrumented executables or preloaded allocation hooks.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, text=True, **kwargs)


def prepare(out):
    import treelite
    assert treelite.__version__ == '4.6.1'
    cases=[]
    for source in sorted((ROOT/'tests/fixtures/frameworks').glob('*.tl')):
        model=treelite.Model.deserialize(source)
        scales=[1,16,1667] if source.stem in ['xgboost_regression','sklearn_rf_multioutput_regression'] else [1]
        for scale in scales:
            expanded=model if scale==1 else treelite.Model.concatenate([model]*scale)
            name=source.stem+(f'_x{scale}' if scale!=1 else '')
            path=out/f'{name}.tl'
            expanded.serialize(path)
            cases.append(dict(name=name,path=str(path),trees=expanded.num_tree,
                nodes=sum(int(expanded.get_tree_accessor(i).get_field('num_nodes')[0]) for i in range(expanded.num_tree)),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    (out/'cases.json').write_text(json.dumps(cases,indent=2)+'\n')


def build(out, revision):
    commit=run(['git','rev-parse','--verify',revision+'^{commit}'],capture_output=True).stdout.strip()
    archive=subprocess.check_output(['git','archive',commit,'src'],cwd=ROOT)
    baseline=out/commit
    baseline.mkdir(exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(baseline,filter='data')
    for name,source in [('baseline',baseline/'src'),('current',ROOT/'src')]:
        run(['pixi','run','mojo','build','-O3','-g1','-I',str(source),
             'tools/decode_worker.mojo','-o',str(out/name)])
    library=run([sys.executable,'-c','from treelite.core import _LIB; print(_LIB._name)'],capture_output=True).stdout.strip()
    lib=Path(library).resolve()
    run(['g++','-O3','-g','tools/treelite_codec_worker.cpp',str(lib),f'-Wl,-rpath,{lib.parent}','-o',str(out/'native')])
    info=dict(baseline_commit=commit,current_commit=run(['git','rev-parse','HEAD'],capture_output=True).stdout.strip(),
              compiler=run(['pixi','run','mojo','--version'],capture_output=True).stdout.strip(),
              library=str(lib),library_sha256=hashlib.sha256(lib.read_bytes()).hexdigest(),
              sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in list((ROOT/'src/balsa').glob('*.mojo'))+list((ROOT/'tools').glob('*decode*')) if p.is_file()})
    info['binaries']={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in ['baseline','current','native']}
    (out/'build.json').write_text(json.dumps(info,indent=2)+'\n')


def command(out,case,engine,operation,loops,cpus):
    prefix=['taskset','-c',cpus]
    if engine=='native':
        return prefix+[str(out/'native'),case['path'],operation,str(loops)]
    binary='baseline' if engine=='baseline-serial' else 'current'
    workers=4 if engine=='current-default' else 1
    return prefix+[str(out/binary),case['path'],str(workers),'4096','65536',str(loops),'1',operation]


def measure(out,cases,args):
    configurations=[]
    for case in cases:
        for operation in ['decode','encode','validate']:
            for engine in ['baseline-serial','current-serial','current-default','native']:
                if engine=='native' and operation=='validate': continue
                probe=run(command(out,case,engine,operation,1,args.cpus),capture_output=True).stdout.split()
                ns=float(probe[0])*1e9 if engine=='native' else float(probe[1])
                loops=max(1,min(10000,int(80_000_000/ns)))
                configurations.append((case,engine,operation,loops))
    jobs=configurations*args.repeats
    random.Random(6183).shuffle(jobs)
    records=[]
    started=time.time()
    for index,(case,engine,operation,loops) in enumerate(jobs):
        result=run(command(out,case,engine,operation,loops,args.cpus),capture_output=True).stdout.split()
        ns=float(result[0])*1e9/loops if engine=='native' else float(result[1])
        if engine=='native':
            expected=loops*(Path(case['path']).stat().st_size if operation=='encode' else 1)
            assert int(result[1])==expected
        records.append(dict(case=case['name'],engine=engine,operation=operation,loops=loops,ns=ns))
        if index%50==0:
            print(f'{index}/{len(jobs)} {time.time()-started:.1f}s',flush=True)
            (out/'timings.json').write_text(json.dumps(records,indent=2)+'\n')
    (out/'timings.json').write_text(json.dumps(records,indent=2)+'\n')
    summary=[]
    for case,engine,operation,_ in configurations:
        values=[r['ns'] for r in records if r['case']==case['name'] and r['engine']==engine and r['operation']==operation]
        summary.append(dict(case=case['name'],engine=engine,operation=operation,
                            median_ns=statistics.median(values),min_ns=min(values),max_ns=max(values)))
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    (out/'environment.json').write_text(json.dumps(dict(cpus=args.cpus,repeats=args.repeats,
        elapsed_s=time.time()-started,cpu=run(['lscpu'],capture_output=True).stdout),indent=2)+'\n')


def profile(out,cases):
    info=json.loads((out/'build.json').read_text())
    lib=Path(info['library'])
    run(['gcc','-O2','-c','tools/decode_callgrind.c','-o',str(out/'client.o')])
    worker=(ROOT/'tools/decode_worker.mojo').read_text().replace('from std.sys import argv','from std.ffi import external_call\nfrom std.sys import argv')
    worker=worker.replace('    var start = perf_counter_ns()', '    external_call["profile_begin", NoneType]()\n    var start = perf_counter_ns()')
    worker=worker.replace('    var elapsed = perf_counter_ns() - start','    var elapsed = perf_counter_ns() - start\n    external_call["profile_end", NoneType]()')
    (out/'profile_worker.mojo').write_text(worker)
    medium=next(c for c in cases if c['name']=='xgboost_regression_x16')
    large=next(c for c in cases if c['name']=='xgboost_regression_x1667')
    for name,source in [('baseline',out/info['baseline_commit']/'src'),('current',ROOT/'src')]:
        run(['pixi','run','mojo','build','-O3','-g1','-I',str(source),str(out/'profile_worker.mojo'),
             '-Xlinker',str(out/'client.o'),'-o',str(out/f'{name}-profile')])
    run(['g++','-O3','-g','-DPROFILE_CLIENT','tools/treelite_codec_worker.cpp',str(out/'client.o'),
         str(lib),f'-Wl,-rpath,{lib.parent}','-o',str(out/'native-profile')])
    for engine in ['baseline-serial','current-serial','native']:
        name={'baseline-serial':'baseline','current-serial':'current','native':'native'}[engine]
        measured=command(out,large,engine,'decode',300,'0')[3:]
        run(['perf','record','-q','-e','cycles:u','-F','997','--call-graph','dwarf,16384',
             '-o',str(out/f'{name}.perf'),'--','taskset','-c','0',*measured],capture_output=True)
        instrumented=command(out,medium,engine,'decode',100,'0')[3:]
        instrumented[0]=str(out/f'{name}-profile')
        result=run(['valgrind','--tool=callgrind','--instr-atstart=no',
             f'--callgrind-out-file={out/name}.callgrind',*instrumented],capture_output=True)
        (out/f'{name}-callgrind.log').write_text(result.stdout+result.stderr)
    run(['gcc','-O2','-shared','-fPIC','tools/decode_allocations.c','-ldl','-o',str(out/'allocations.so')])
    records=[]
    for case in cases:
        if case['name'] not in ['xgboost_regression','xgboost_regression_x1667','sklearn_rf_multioutput_regression_x1667']: continue
        for engine in ['baseline-serial','current-serial','native']:
            values=[]
            for loops in [1,11,21]:
                result=run(command(out,case,engine,'decode',loops,'0'),capture_output=True,
                           env={**os.environ,'LD_PRELOAD':str(out/'allocations.so')})
                values.append(json.loads(next(line[6:] for line in result.stderr.splitlines() if line.startswith('ALLOC '))))
            deltas=[{key:(values[i+1][key]-values[i][key])/10 for key in values[0]} for i in range(2)]
            records.append(dict(case=case['name'],engine=engine,process_counts=values,per_decode=deltas))
    (out/'allocations.json').write_text(json.dumps(records,indent=2)+'\n')
    profile_sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in [ROOT/'tools/decode_allocations.c', ROOT/'tools/decode_callgrind.c',
                               ROOT/'tools/decode_worker.mojo', ROOT/'tools/treelite_codec_worker.cpp']}
    (out/'profile-build.json').write_text(json.dumps(dict(sources=profile_sources,
        valgrind=run(['valgrind','--version'],capture_output=True).stdout.strip(),
        perf=run(['perf','--version'],capture_output=True).stdout.strip()),indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',default='06ee661')
    parser.add_argument('--output',type=Path,default=ROOT/'build/decode-profile')
    parser.add_argument('--repeats',type=int,default=7)
    parser.add_argument('--cpus',default='0-7')
    parser.add_argument('--reuse',action='store_true')
    parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--profile',action='store_true')
    args=parser.parse_args()
    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=True)
    if args.prepare_only:
        prepare(out)
        return
    if not args.reuse:
        run([sys.executable,str(Path(__file__).resolve()),'--prepare-only','--output',str(out)])
        build(out,args.baseline)
    cases=json.loads((out/'cases.json').read_text())
    measure(out,cases,args)
    if args.profile: profile(out,cases)


if __name__=='__main__': main()
