#!/usr/bin/env python3
"""Actual owned registry grammar/theme composition and independent lifetime."""
import argparse
import contextlib
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

@contextlib.contextmanager
def lease_folder(wine):
    if not wine:
        yield str(ROOT)
        return
    drive=(Path(os.environ.get('WINEPREFIX',str(Path.home()/'.wine'))))/'drive_c'
    drive=drive.expanduser().resolve()
    if not drive.is_dir():
        raise AssertionError('Initialize the private Wine prefix before the registry lease fixture')
    # Wine maps Z: through Unix symlinks. The rooted no-follow proof uses an owned C: directory.
    with tempfile.TemporaryDirectory(prefix='rhun-registry-lease-',dir=drive)as folder:
        yield 'C:/'+Path(folder).relative_to(drive).as_posix()

def build(folder,windows=False,replacements=None,fixture=None):
    spec=importlib.util.spec_from_file_location('catalog_merge_link',ROOT/'tests/faults/ext_store_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.subprocess=SimpleNamespace(run=lambda command,**kwargs:bounded_tool(command))
    return module.build(folder,fixture if fixture is not None else(ROOT/'tests/catalog_merge_test.s').read_text(),replacements or{},windows=windows)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--exe',type=Path);p.add_argument('--build-only',type=Path)
    p.add_argument('--windows',action='store_true');p.add_argument('--wine')
    a=p.parse_args()
    if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
    windows=a.windows or bool(a.wine)or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-catalog-merge-')as temporary, lease_folder(a.wine if not a.build_only else None)as lease:
        executable=a.exe or build(Path(temporary),windows=windows)
        if a.build_only:
            a.build_only.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(executable,a.build_only);shutil.copymode(executable,a.build_only);return
        with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve()),lease],timeout=30,output_bound=0,error_bound=4096)as exchange:
            out,err=exchange.finish()
            assert exchange.process.returncode==0 and not out and not err,(exchange.process.returncode,out,err)
    print('ok registry exact names/paths, original ordinals, independent supplier/GP lifetime',flush=True)
if __name__=='__main__':main()
