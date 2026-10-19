#!/usr/bin/env python3
"""Startup allocation refusal and sealed API refusal leave no new owned memory or lazy IO."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,win,negative=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_startup_test.s').read_text();replacements={}
 if not negative:
  memory=(ROOT/'src/mem.s').read_text();old='FN mem_alloc_try\n';assert memory.count(old)==1;replacements['src/mem.s']=memory.replace(old,'FN tcsf_real_alloc\n',1)
  needle='    mov rdi, [rax + 8]\n    call theme_capture_path_snapshot\n';assert fixture.count(needle)==1
  fixture=fixture.replace(needle,'    mov rdi, [rax + 8]\n    mov qword ptr [rip + tcsf_armed], 1\n    call theme_capture_path_snapshot\n    mov qword ptr [rip + tcsf_armed], 0\n',1)
  fixture+='\n.bss\n.p2align 3\ntcsf_armed: .zero 8\n.text\nFN mem_alloc_try\n    cmp qword ptr [rip + tcsf_armed], 0\n    je tcsf_real_alloc\n    xor eax, eax\n    ret\n'
 else:
  core=(ROOT/'src/app/themecapturestartup.s').read_text();old='FN theme_capture_path_snapshot\n    cmp qword ptr [rip + tc_start_state], 1\n    jne .Ltcs_path_busy\n';assert core.count(old)==1
  replacements['src/app/themecapturestartup.s']=core.replace(old,'FN theme_capture_path_snapshot\n',1)
  # Poison the underlying bounded scan so bypassing the admission fails deterministically.
  source=(ROOT/'src/app/extvalidatepath.s').read_text();old='FN ext_root_length\n';assert source.count(old)==1
  replacements['src/app/extvalidatepath.s']=source.replace(old,'FN tcsf_real_length\n',1)
  fixture+='\n.text\nFN ext_root_length\n    cmp rdi, 1\n    je tcst_fail\n    jmp tcsf_real_length\n'
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for negative,name in((False,'oom'),(True,'negative')):build(a.build_only/name,True,negative)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-startup-fault-')as td:
  for negative,name in((False,'oom'),(True,'negative')):
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,win,negative)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),'relative.theme'],capture_output=True,timeout=10)
   if negative:assert r.returncode==73 and not r.stdout and not r.stderr,(name,r)
   else:assert r.returncode==0 and r.stdout==struct.pack('<qQ',-12,0)and not r.stderr,(name,r)
   print('ok theme-capture/startup-'+name,flush=True)
if __name__=='__main__':main()
