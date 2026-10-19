#!/usr/bin/env python3
"""Every native, EOF, terminal and diagnostic witness is mandatory for cleanup111."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,case,windows=False,negative=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    replacements={}
    if negative:
        source=(ROOT/'src/app/taskcleanup.s').read_text();a=source.index('FN kp_cleanup_terminal\n')
        old='    cmp qword ptr [rdi + KX_native_state], KN_REAPED\n    jne 1f';assert source[a:].count(old)==1
        replacements['src/app/taskcleanup.s']=source[:a]+source[a:].replace(old,'',1)
    fixture=f'.equ KCT_CASE, {case}\n'+(ROOT/'tests/faults/keeper_cleanup_terminal.s').read_text()
    return builder.build(folder,fixture,replacements,windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-terminal-')as folder:
        for case in range(15):
            exe=build((a.build_only or Path(folder))/str(case),case,windows)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==0 and not r.stdout and not r.stderr,(case,r)
            print('ok keeper-cleanup-terminal/'+str(case),flush=True)
        exe=build((a.build_only or Path(folder))/'negative-native',1,windows,True)
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,r
            print('ok keeper-cleanup-terminal/negative-control/lost-native',flush=True)
if __name__=='__main__':main()
