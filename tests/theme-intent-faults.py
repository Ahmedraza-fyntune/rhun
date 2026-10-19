#!/usr/bin/env python3
"""Intent constructors retain failed checked cleanup and expose no incomplete semantics."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,win,negative=False):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_intent_test.s').read_text();mem=(ROOT/'src/app/themecapturemem.s').read_text();replacements={}
 if mode==0:
  mem=mem.replace('FN tc_alloc_try\n','FN tif_real_alloc\n',1)
  fixture+='\n.text\nFN tc_alloc_try\n    xor eax, eax\n    ret\n'
 else:
  mem=mem.replace('FN tc_free\n','FN tif_real_free\n',1)
  fixture+='\n.bss\n.p2align 3\ntif_frees: .zero 8\n.text\nFN tc_free\n    inc qword ptr [rip + tif_frees]\n    cmp qword ptr [rip + tif_frees], 1\n    jne tif_real_free\n    mov rax, -5\n    xor edx, edx\n    ret\n'
  checks='''    cmp qword ptr [rsp + 304], -36
    jne tit_fail
    cmp qword ptr [rsp + 312], -5
    jne tit_fail
    test r14, r14
    jz tit_fail
    cmp qword ptr [r14 + TI_state], TI_RETIRING
    jne tit_fail
    cmp qword ptr [r14 + TI_refs], 1
    jne tit_fail
    cmp qword ptr [r14 + TI_primary], -36
    jne tit_fail
    cmp dword ptr [r14 + TI_cleanup], -5
    jne tit_fail
    mov rdi, r14
    lea rsi, [rsp + 128]
    call theme_intent_view
    cmp rax, -16
    jne tit_fail
    mov rdi, r14
    call theme_intent_guard
    test rax, rax
    jnz tit_fail
    cmp rdx, -16
    jne tit_fail
    mov rdi, r14
    call theme_intent_retain
    test rax, rax
    jnz tit_fail
    cmp rdx, -16
    jne tit_fail
'''
  fixture=fixture.replace('.Ltit_emit:\n','.Ltit_emit:\n'+checks,1)
  old='    call theme_intent_release\n    test rax, rax\n    jnz tit_fail\n    cmp rdx, 1\n';assert fixture.count(old)==2
  # Final release only. The earlier retained-reference test is not entered in this fault mode.
  pos=fixture.rindex(old);fixture=fixture[:pos]+fixture[pos:].replace(old,'    call theme_intent_release\n    cmp rax, -5\n    jne tit_fail\n    cmp rdx, 1\n',1)
 if negative:
  core=(ROOT/'src/app/themeintent.s').read_text();old='    test rdx, rdx\n    jnz 6f\n';assert core.count(old)==1
  replacements['src/app/themeintent.s']=core.replace(old,'    jmp 6f\n',1)
 replacements['src/app/themecapturemem.s']=mem
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for mode,negative,name in((0,False,'oom'),(1,False,'retained'),(1,True,'negative')):build(a.build_only/name,mode,True,negative)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-intent-fault-')as td:
  for mode,negative,name in((0,False,'oom'),(1,False,'retained'),(1,True,'negative')):
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,mode,win,negative)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),'7'if mode else'0','x'*4096 if mode else'normal','dark','light'],capture_output=True,timeout=10)
   if negative:assert r.returncode==73 and not r.stdout and not r.stderr,(name,r)
   else:
    assert r.returncode==0 and not r.stderr and len(r.stdout)==24,(name,r)
    assert struct.unpack('<qqQ',r.stdout)==((-36,-5,32768)if mode else(-12,0,0)),(name,r)
   print('ok theme-intent/constructor-'+name,flush=True)
if __name__=='__main__':main()
