#!/usr/bin/env python3
"""Bounded checked keeper consumer, raw drain, and shutdown ownership checks."""
import argparse
import importlib.util
from pathlib import Path
import tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--fault-exe',type=Path)
p.add_argument('--wine')
a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='rhun-keeper-host-')as folder:
    executable=a.fault_exe
    if executable is None:
        root=Path(__file__).resolve().parents[1]
        spec=importlib.util.spec_from_file_location('keeper_host_build',root/'tests/faults/ext_keeper_host_build.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        import os
        executable=module.build(Path(folder),bool(a.wine)or os.name=='nt')
    with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=0,error_bound=4096)as e:
        out,err=e.finish()
        assert e.process.returncode==0 and not out and not err,(e.process.returncode,out,err)
print('ok checked keeper collection, bounded raw drain, true EOF and shutdown ownership',flush=True)
