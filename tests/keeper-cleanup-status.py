#!/usr/bin/env python3
"""Broken status transport cannot reuse an earlier NO_TARGET or manufacture EOF."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,case,windows=False,negative=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    source=(ROOT/'src/app/taskproc.s').read_text().replace('kp_slots: .zero',' .globl kp_slots\nkp_slots: .zero',1)
    a=source.index('FN keeper_poll\n');z=source.index('.Lkp_poll_native:',a)
    needle='    SYS SYS_read';assert source[a:z].count(needle)==1
    source=source[:a]+source[a:z].replace(needle,'    call kcs_read',1)+source[z:]
    if negative:
        a=source.index('kp_parent_fail:\n');z=source.index('kp_status:\n',a)
        old='    mov qword ptr [rbx + KX_no_target], 0';assert source[a:z].count(old)==1
        source=source[:a]+source[a:z].replace(old,'',1)+source[z:]
    fixture=f'.equ KCS_CASE, {case}\n'+(ROOT/'tests/faults/keeper_cleanup_status.s').read_text()
    return builder.build(folder,fixture,{'src/app/taskproc.s':source},windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-status-')as folder:
        for case in range(5):
            exe=build((a.build_only or Path(folder))/str(case),case,windows)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==0 and not r.stdout and not r.stderr,(case,r)
            print('ok keeper-cleanup-status/'+str(case),flush=True)
        exe=build((a.build_only or Path(folder))/'negative-stale',1,windows,True)
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,r
            print('ok keeper-cleanup-status/negative-control/stale-no-target',flush=True)
if __name__=='__main__':main()
