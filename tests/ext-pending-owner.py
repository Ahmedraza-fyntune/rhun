#!/usr/bin/env python3
"""Owned pending identity allocation, length, refcount and revision boundaries."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--wine');parser.add_argument('--exe',type=Path);parser.add_argument('--build-only',action='store_true');args=parser.parse_args()
    if args.build_only and not args.exe:parser.error('--build-only requires --exe')
    windows=bool(args.wine) or os.name=='nt' or bool(args.build_only and args.exe.suffix.lower()=='.exe')
    with tempfile.TemporaryDirectory(prefix='rhun-pending-owner-') as temporary:
        if args.exe and not args.build_only:exe=args.exe.resolve()
        else:
            spec=importlib.util.spec_from_file_location('pending_build',ROOT/'tests/faults/ext_store_build.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
            source=(ROOT/'src/app/extpending.s').read_text();assert source.count('call mem_alloc_try')==1;source=source.replace('call mem_alloc_try','call pno_alloc')
            source+='\nFN pno_set_revision_impl\n    mov [rip + pn_last_revision], rdi\n    ret\n'
            fixture=(ROOT/'tests/ext_pending_owner_test.s').read_text().replace('FN pno_set_revision\n    ret\n','FN pno_set_revision\n    jmp pno_set_revision_impl\n')
            exe=builder.build(Path(temporary),fixture,{'src/app/extpending.s':source},windows=windows)
        if args.build_only:args.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,args.exe);return
        result=subprocess.run(([args.wine,'Z:'+exe.as_posix()] if args.wine else [str(exe)]),cwd=ROOT,capture_output=True,timeout=30)
        assert result.returncode==0 and result.stdout==b'ok pending command ownership and failures\n' and not result.stderr,result
    print('ok pending identity ownership, input bounds, allocation refusal and revision exhaustion')
if __name__=='__main__':main()
