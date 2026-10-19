#!/usr/bin/env python3
"""Twelve same-process construction failures preserve capacity and retained child owners."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,win,negative=False):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture='.equ TCJO_MODE, '+str(mode)+'\n'+(ROOT/'tests/faults/theme_capture_job_owner.s').read_text();replacements={}
 for path,names in {'src/app/themecapturemem.s':{'tc_alloc_try':'tcjo_real_alloc','tc_free':'tcjo_real_free','tc_charge_reserve':'tcjo_real_reserve'},'src/app/extsettingsnative.s':{'theme_capture_native_start':'tcjo_real_native_start'}}.items():
  core=(ROOT/path).read_text()
  for name,new in names.items():
   old='FN '+name+'\n';assert core.count(old)==1;core=core.replace(old,'FN '+new+'\n',1)
  replacements[path]=core
 if negative:
  core=(ROOT/'src/app/themecapturejob.s').read_text();old='    mov qword ptr [rbx + TCJ_fallback_request], 0\n';assert core.count(old)==1
  # Pretend a retained fallback request was consumed.
  needle='    call tc_request_dispose\n    mov r13, rdx\n';assert core.count(needle)==1
  replacements['src/app/themecapturejob.s']=core.replace(needle,'    call tc_request_dispose\n    mov r13d, 1\n',1)
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 cases=[(n,False,str(n))for n in (1,2,3,4,6,7,8,9)]+[(2,True,'negative')]
 if a.build_only:
  for mode,negative,name in cases:build(a.build_only/name,mode,True,negative)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-job-owners-')as td:
  for mode,negative,name in cases:
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,mode,win,negative)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=20)
   assert r.returncode==(73 if negative else 0)and not r.stdout and not r.stderr,(name,r)
   print('ok theme-capture-job/repeated-constructor-owner/'+name,flush=True)
if __name__=='__main__':main()
