#!/usr/bin/env python3
"""Verify actual fresh-EO constructor drop preconditions and consumed ownership."""
import argparse,importlib.util,os,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False,mutation=None):
 spec=importlib.util.spec_from_file_location('eo_audit_build',ROOT/'tests/faults/ext_activation_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 return m.build(folder,windows,audit=True,mutation=mutation)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--mutation',choices=['missing-drop']);p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('Wine requires exact exe and drive root')
 if a.exe and a.build_only:p.error('exe and build-only are exclusive')
 if a.negative_controls and(a.exe or a.mutation):p.error('negative controls build exact separate variants')
 variants=[a.mutation]if a.mutation else[None,'missing-drop']if a.negative_controls else[None]
 drive=a.wine_drive_root.resolve()if a.wine else None
 with tempfile.TemporaryDirectory(prefix='rhun-ea-eo-audit-',dir=drive)as tmp:
  for mutation in variants:
   exe=a.exe or build((a.build_only or Path(tmp)/'bin')/(mutation or'baseline'),os.name=='nt'or a.windows_build or bool(a.wine),mutation)
   if a.build_only:print('built fresh EO audit',exe,flush=True);continue
   native='C:/'+Path(tmp).relative_to(drive).as_posix()if drive else str(Path(tmp).resolve())
   for mode in range(1,8):
    with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native,str(mode)],timeout=30,output_bound=0,error_bound=4096)as f:
     out,err=f.finish();expected=91 if mutation and mode!=1 else 0
     assert(f.process.returncode,out,err)==(expected,b'',b''),(mutation,mode,f.process.returncode,out,err)
    print('ok fresh EO audit',mutation or'baseline',mode,flush=True)
if __name__=='__main__':main()
