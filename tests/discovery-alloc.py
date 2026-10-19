#!/usr/bin/env python3
"""Real charged construction and common-retirement fixture."""
import argparse
import importlib.util
import os
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);p.add_argument('--negative-controls',action='store_true');p.add_argument('--controls-dir',type=Path);a=p.parse_args()
if a.exe:exe=a.exe.resolve()
else:
    spec=importlib.util.spec_from_file_location('da_builder',ROOT/'tests/faults/discovery_alloc_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    exe=module.build(ROOT/'build/discovery-alloc-native',windows=os.name=='nt')
for mode in range(10):
    command=([a.wine]if a.wine else[])+[str(exe),str(mode)]
    with FixtureExchange(command,timeout=15,output_bound=1024,error_bound=4096)as exchange:
        out,err=exchange.finish()
        if exchange.process.returncode or out or err:
            raise AssertionError(f'mode{mode}:exit{exchange.process.returncode},stdout={out!r},stderr={err!r}')
    print(f'mode{mode}: PASS',flush=True)

if a.negative_controls or a.controls_dir:
    if 'module' not in globals():
        spec=importlib.util.spec_from_file_location('da_builder',ROOT/'tests/faults/discovery_alloc_build.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    controls=[('extra-commit',0),('extra-release',1),('prep-transfer',2),('member-link',2),('owner-deferred',2),('ep-default',2),('setting-publish',6),('binding-reset',2),('gp-move',2),('retained-charge',3),('quarantine-retry',5),('copy-prefix',0),('copy-state',6),('prep-cap',9),('minimum-deadline',8)]
    for name,mode in controls:
        if a.controls_dir:controlled=a.controls_dir/name/('discovery-alloc.exe'if a.wine or os.name=='nt'else'discovery-alloc')
        else:controlled=module.build(ROOT/'build/discovery-alloc-controls'/name,windows=os.name=='nt',mutation=name)
        command=([a.wine]if a.wine else[])+[str(controlled),str(mode)]
        with FixtureExchange(command,timeout=15,output_bound=1024,error_bound=4096)as exchange:
            out,err=exchange.finish()
            if exchange.process.returncode!=73 or out or err:
                raise AssertionError(f'{name}:exit{exchange.process.returncode},stdout={out!r},stderr={err!r}')
        print(f'control {name}: PASS',flush=True)
