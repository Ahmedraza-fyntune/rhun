#!/usr/bin/env python3
"""Windows NUL reserves before opening, wide conversion failure returns its owned mapping."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,case):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    source=(ROOT/'src/win/taskproc.s').read_text().replace('kpw_open_null:\n','FN kcw_null\n',1).replace('    call kpw_open_null\n','    call kcw_null\n')
    source=source.replace('kpw_wide_owned:\n','FN kcw_wide\n',1).replace('    call kpw_wide_owned\n','    call kcw_wide\n')
    if case in(0,1):
        a=source.index('FN kcw_null\n');z=source.index('kpw_pipe_owned:\n',a)
        assert source[a:z].count('    API CreateFileW')==1
        source=source[:a]+source[a:z].replace('    API CreateFileW','    call kcw_create',1)+source[z:]
    if case==3:
        a=source.index('FN kcw_wide\n');z=source.index('kpw_wide:\n',a)
        block=source[a:z];needle='    API MultiByteToWideChar';assert block.count(needle)==2
        pos=block.rindex(needle);block=block[:pos]+block[pos:].replace(needle,'    call kcw_convert_fail',1)
        source=source[:a]+block+source[z:]
    fixture=f'.equ KCW_CASE,{case}\n'+(ROOT/'tests/faults/keeper_cleanup_win_producers.s').read_text()
    return builder.build(folder,fixture,{'src/win/taskproc.s':source,'src/win/rt.s':(ROOT/'src/win/rt.s').read_text().replace('FN win_fd_alloc\n','FN kcw_real_fd_alloc\n',1)},True)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    if not(a.wine or a.windows_build or os.name=='nt'):p.error('Windows-only fixture')
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-win-producer-')as folder:
        for case in range(4):
            exe=build((a.build_only or Path(folder))/str(case),case)
            if a.build_only:continue
            result=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert result.returncode==0 and not result.stdout and not result.stderr,(case,result)
            print('ok keeper-cleanup-win-producers/'+str(case),flush=True)
if __name__=='__main__':main()
