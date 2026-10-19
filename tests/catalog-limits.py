#!/usr/bin/env python3
"""Empty registry and exact input admission bounds."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/faults'))
from ext_retire_build import bounded_tool

def build(folder,windows=False,replacements=None,fixture=None):
    spec=importlib.util.spec_from_file_location('catalog_limits_link',ROOT/'tests/faults/ext_store_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.subprocess=SimpleNamespace(run=lambda command,**kwargs:bounded_tool(command))
    return module.build(folder,fixture if fixture is not None else(ROOT/'tests/catalog_limits_test.s').read_text(),replacements or{},windows=windows)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--exe',type=Path);p.add_argument('--build-only',type=Path)
    p.add_argument('--windows',action='store_true');p.add_argument('--wine')
    a=p.parse_args()
    if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
    windows=a.windows or bool(a.wine)or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-catalog-limits-')as temporary:
        executable=a.exe or build(Path(temporary),windows=windows)
        if a.build_only:
            a.build_only.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(executable,a.build_only);shutil.copymode(executable,a.build_only);return
        with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=0,error_bound=4096)as exchange:
            out,err=exchange.finish()
            assert exchange.process.returncode==0 and not out and not err,(exchange.process.returncode,out,err)
    print('ok empty registry,128 input refs, typed refusal and terminal cache',flush=True)
if __name__=='__main__':main()
