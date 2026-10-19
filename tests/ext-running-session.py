#!/usr/bin/env python3
"""Bind accepted ownership once, then check immutable running tuples without byte scans."""
import argparse
from pathlib import Path
import sys,tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path)
p.add_argument('--negative-controls',action='store_true')
p.add_argument('--expect-failure',action='store_true')
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
p.add_argument('--build-only',type=Path)
p.add_argument('--windows-build',action='store_true')
a=p.parse_args()
if a.wine and(not a.exe or not a.wine_drive_root):p.error('--wine requires --exe and --wine-drive-root')
if a.expect_failure and not a.exe:p.error('--expect-failure requires --exe')
sys.path.insert(0,str(Path(__file__).resolve().parent/'faults'))
from ext_running_session_build import MUTATIONS,build
windows=a.windows_build or bool(a.wine)
drive=a.wine_drive_root.resolve()if a.wine else None
with tempfile.TemporaryDirectory(prefix='rhun-running-session-',dir=drive)as tmp:
    variants=[('baseline',None,False),('maximum',None,True)]
    if a.negative_controls:variants.extend((m,m,False)for m in MUTATIONS)
    if a.exe:variants=[('prebuilt',None,False)]
    for label,mutation,long in variants:
        exe=a.exe or build((a.build_only or Path(tmp)/'bin')/label,windows,mutation,long)
        if a.build_only:print('built',label,exe,flush=True);continue
        native='C:/'+Path(tmp).relative_to(drive).as_posix()if drive else str(Path(tmp).resolve())
        with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native],timeout=30,output_bound=0,error_bound=4096)as f:
            out,err=f.finish()
            expected=f.process.returncode!=0 if mutation or a.expect_failure else f.process.returncode==0
            assert expected and not out and not err,(label,f.process.returncode,out,err)
        print('ok running session',label,flush=True)
