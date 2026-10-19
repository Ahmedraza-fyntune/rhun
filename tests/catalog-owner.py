#!/usr/bin/env python3
"""Real kind7 typed ownership, zero-ref callbacks and partial cancellation."""
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

def build(folder,windows=False,replacements=None):
    spec=importlib.util.spec_from_file_location('catalog_link',ROOT/'tests/faults/ext_store_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.subprocess=SimpleNamespace(run=lambda command,**kwargs:bounded_tool(command))
    return module.build(folder,(ROOT/'tests/catalog_owner_test.s').read_text(),replacements or{},windows=windows)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',type=Path)
    parser.add_argument('--build-only',type=Path)
    parser.add_argument('--windows',action='store_true')
    parser.add_argument('--wine')
    args=parser.parse_args()
    if args.exe and args.build_only:parser.error('--exe and --build-only are exclusive')
    windows=args.windows or bool(args.wine) or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-catalog-owner-')as temporary:
        executable=args.exe or build(Path(temporary),windows=windows)
        if args.build_only:
            args.build_only.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(executable,args.build_only);shutil.copymode(executable,args.build_only)
            return
        command=([args.wine]if args.wine else[])+[str(executable.resolve())]
        with FixtureExchange(command,timeout=30,output_bound=0,error_bound=4096)as exchange:
            out,err=exchange.finish()
            assert exchange.process.returncode==0 and not out and not err,(exchange.process.returncode,out,err)
    print('ok catalog typed owners, initial EO transfer and bounded cancellation',flush=True)
if __name__=='__main__':main()
