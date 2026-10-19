#!/usr/bin/env python3
"""Real prompt acceptance and cancelled intent at reused metadata addresses."""
import argparse
from pathlib import Path
import sys
import tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path)
p.add_argument('--wine')
p.add_argument('--negative-controls',action='store_true')
p.add_argument('--expect-refusal-failure',action='store_true')
a=p.parse_args()
if a.wine and not a.exe:p.error('--wine requires a prebuilt --exe')
if a.wine and a.negative_controls:p.error('prebuild Wine controls individually')
if a.expect_refusal_failure and not a.exe:p.error('--expect-refusal-failure requires --exe')
sys.path.insert(0,str(Path(__file__).resolve().parent/'faults'))
from ext_prompt_borrowers_build import build

def check(exe,negative=False):
    with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve())],timeout=30,output_bound=0,error_bound=4096)as e:
        out,err=e.finish()
        assert (e.process.returncode!=0 if negative else e.process.returncode==0) and not out and not err,(exe,e.process.returncode,out,err)

with tempfile.TemporaryDirectory(prefix='rhun-borrowers-')as tmp:
    folder=Path(tmp)
    check(a.exe or build(folder/'baseline'),a.expect_refusal_failure)
    if a.negative_controls:
        for mutation in ['skip-open', 'skip-close', 'skip-pure', 'skip-ext_init', 'skip-ext_load', 'skip-ext_slot_metadata_take', 'skip-ext_host_identity_take']:
            check(build(folder/mutation,mutation=mutation),True)
            print('rejected',mutation,flush=True)
print('ok Real prompt acceptance and cancelled intent at reused metadata addresses',flush=True)
