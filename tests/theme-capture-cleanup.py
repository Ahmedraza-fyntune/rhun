#!/usr/bin/env python3
"""Retain exact native mapping ownership and theme charge through failed release."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False,negative=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 mem=(ROOT/'src/mem.s').read_text().replace('    SYS SYS_munmap\n','    call tcc_munmap\n')
 replacements={'src/mem.s':mem}
 if negative:
  tc=(ROOT/'src/app/themecapturemem.s').read_text();old='    test rdx, rdx\n    jz 3f\n    sub [rip + g_theme_capture_charge], r12';assert tc.count(old)==1
  replacements['src/app/themecapturemem.s']=tc.replace(old,'    sub [rip + g_theme_capture_charge], r12\n    test rdx, rdx\n    jz 3f',1)
 return b.build(folder,'.equ TCC_MODE, %d\n'%mode+(ROOT/'tests/faults/theme_cleanup.s').read_text(),replacements,windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=bool(a.wine)or a.windows_build or os.name=='nt'
 with tempfile.TemporaryDirectory(prefix='rhun-theme-cleanup-')as d:
  for mode,negative in[(0,False),(1,False),(0,True)]:
   key=str(mode)+('-negative'if negative else'');exe=build((a.build_only or Path(d))/key,mode,windows,negative)
   if a.build_only:continue
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
   assert r.returncode==(73 if negative else 0)and not r.stdout and not r.stderr,(mode,negative,r)
   print('ok theme-cleanup/retained-mapping-charge/'+key,flush=True)
if __name__=='__main__':main()
