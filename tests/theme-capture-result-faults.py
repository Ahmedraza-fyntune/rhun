#!/usr/bin/env python3
"""Failed result wire disposal retains all prior borrows and the capacity reservation."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,win,negative=False):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_result_test.s').read_text();needle='''    mov rdi, r12
    call theme_capture_result_release
    test rax, rax
    jnz tcsrt_fail
    cmp rdx, 1
    jne tcsrt_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
'''
 assert fixture.count(needle)==1
 replacement='''    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 272], rax
    mov rdi, r12
    call theme_capture_result_release
    cmp rax, -5
    jne tcsrt_fail
    test rdx, rdx
    jnz tcsrt_fail
    cmp qword ptr [r12 + TCS_refs], 1
    jne tcsrt_fail
    cmp qword ptr [r12 + TCS_state], TCS_RETIRING
    jne tcsrt_fail
    cmp qword ptr [r12 + TCS_cleanup], -5
    jne tcsrt_fail
    cmp qword ptr [rip + g_theme_capture_results], 1
    jne tcsrt_fail
    mov rax, [rip + g_theme_capture_charge]
    cmp rax, [rsp + 272]
    jne tcsrt_fail
    mov rdi, [rsp + 80 + TCV_bytes]
    lea rsi, [rip + tcsrt_raw]
    mov edx, 4
    call memeq
    test eax, eax
    jz tcsrt_fail
    mov rdi, r12
    call theme_capture_result_release
    cmp rax, -5
    jne tcsrt_fail
    cmp rdx, 1
    jne tcsrt_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
'''
 fixture=fixture.replace(needle,replacement,1)
 fixture+='''\n.bss\n.p2align 3\ntcsrf_failed: .zero 8\n.text\nFN tc_free\n    cmp rdi, [rip + tcsrt_wire_target]\n    jne tcsrf_real_free\n    cmp qword ptr [rip + tcsrf_failed], 0\n    jne tcsrf_real_free\n    mov qword ptr [rip + tcsrf_failed], 1\n    mov rax, -5\n    xor edx, edx\n    ret\n'''
 mem=(ROOT/'src/app/themecapturemem.s').read_text().replace('FN tc_free\n','FN tcsrf_real_free\n',1)
 replacements={'src/app/themecapturemem.s':mem}
 if negative:
  core=(ROOT/'src/app/themecaptureresult.s').read_text();old='5:  test rdx, rdx\n    jz .Ltcsf_retained';assert core.count(old)==1
  replacements['src/app/themecaptureresult.s']=core.replace(old,'5:  test rdx, rdx\n    nop',1)
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for negative,name in((False,'retained'),(True,'negative')):build(a.build_only/name,True,negative)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-result-fault-')as td:
  for negative,name in((False,'retained'),(True,'negative')):
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,win,negative)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
   assert r.returncode==(73 if negative else 0)and not r.stdout and not r.stderr,(name,r)
   print('ok theme-capture-result/wire-'+name,flush=True)
if __name__=='__main__':main()
