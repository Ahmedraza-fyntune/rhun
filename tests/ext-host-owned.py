#!/usr/bin/env python3
"""Bounded private host identity, metadata transfer, and endpoint ownership checks."""
import argparse
import os
from pathlib import Path
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--dir',type=Path,required=True)
p.add_argument('--fault-exe',type=Path)
p.add_argument('--wine')
a=p.parse_args()
suffix='.exe'if a.wine or os.name=='nt'else''
executables=[a.dir/('ext_host_identity_test'+suffix),a.dir/('ext_host_owned_test'+suffix)]
if a.fault_exe:executables.append(a.fault_exe)
for executable in executables:
    with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=0,error_bound=4096)as e:
        out,err=e.finish()
        assert e.process.returncode==0 and not out and not err,(executable,e.process.returncode,out,err)
print('ok private host identity, metadata transfer and checked endpoint ownership',flush=True)
