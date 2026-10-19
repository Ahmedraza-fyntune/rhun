#!/usr/bin/env python3
"""Raw allocation preserves header/census/free while ordinary allocation stays zeroed."""
import argparse
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from fixture_exchange import FixtureExchange
SPEC=importlib.util.spec_from_file_location('mem_uninit_build',ROOT/'tests/faults/mem_uninit_build.py')
BUILD=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(BUILD)
MUTATIONS={'raw-clears':0,'zero-skips':0,'raw-census':0,'ordinary-entry-skips':0,'raw-bump-clears':6,'raw-large-clears':7,'raw-callee':4}

def run(exe,mode,runner=(),negative=False):
    with FixtureExchange([*runner,str(exe),str(mode)],timeout=30,output_bound=512,error_bound=1024)as exchange:
        out,err=exchange.finish();code=exchange.process.returncode
    if negative:assert code==73 and out==err==b'',(exe,mode,code,out,err)
    elif mode==5:assert code==1 and out==b'' and err==b'rhun: out of memory\n',(exe,mode,code,out,err)
    else:assert code==0 and out==b'' and err==b'ok mem-uninit\n',(exe,mode,code,out,err)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--runtime-root',type=Path)
    p.add_argument('--controls-dir',type=Path);p.add_argument('--negative-controls',action='store_true')
    p.add_argument('--build-windows-only',action='store_true');p.add_argument('--out',type=Path)
    a=p.parse_args()
    if a.build_windows_only:
        assert a.out
        BUILD.build(a.out,True,a.runtime_root)
        if a.negative_controls:
            for mutation in MUTATIONS:BUILD.build(a.out/mutation,True,a.runtime_root,mutation)
        return
    runner=[a.wine]if a.wine else[]
    with tempfile.TemporaryDirectory(prefix='rhun-mem-uninit-')as temp:
        folder=Path(temp)
        exe=a.exe.resolve()if a.exe else BUILD.build(folder,windows=os.name=='nt',runtime_root=a.runtime_root)
        for mode in range(8):
            run(exe,mode,runner);print('ok mem-uninit/'+str(mode),flush=True)
        if a.negative_controls or a.controls_dir:
            for mutation in MUTATIONS:
                control=(a.controls_dir/mutation/'mem-uninit.exe').resolve()if a.controls_dir else BUILD.build(folder/mutation,windows=os.name=='nt',runtime_root=a.runtime_root,mutation=mutation)
                run(control,MUTATIONS[mutation],runner,True);print('ok mem-uninit rejects '+mutation,flush=True)
if __name__=='__main__':main()
