#!/usr/bin/env python3
"""Candidate work is pure and the harness detects forbidden calls or lost work bounds."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MUTATIONS={
 'lookup':('    mov rbx, rdi\n    mov qword ptr [rbx + TCL_bytes], 0','    call theme_find\n    mov rbx, rdi\n    mov qword ptr [rbx + TCL_bytes], 0'),
 'allocation':('    mov rbx, rdi\n    mov qword ptr [rbx + TCL_bytes], 0','    call tc_alloc_try\n    mov rbx, rdi\n    mov qword ptr [rbx + TCL_bytes], 0'),
 'source-IO':('    mov rbx, rdi\n    mov qword ptr [rbx + TCL_bytes], 0','    call tc_file_capture\n    mov rbx, rdi\n    mov qword ptr [rbx + TCL_bytes], 0'),
 'unit-size':('    mov r14d, 4096','    mov r14d, 65536'),
 'query-charge':('    inc qword ptr [rbx + TCL_bytes]\n    test eax, eax\n    jz .Ltcls_invalid_row\n    mov [rbx + TCL_held], rax','    nop\n    test eax, eax\n    jz .Ltcls_invalid_row\n    mov [rbx + TCL_held], rax'),
 'skip-first-self':('    mov rax, -2\n1:  mov [rbx + TCL_result], rax','    jmp .Ltcls_next\n1:  mov [rbx + TCL_result], rax'),
 'stale':('    cmp [rbx + TCL_epoch], rsi\n    jne .Ltcls_stale','    cmp [rbx + TCL_epoch], rsi\n    nop'),
}
def build(folder,win,mutation=None):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_candidate_test.s').read_text();needle='    mov [rsp + 312], r13\n';assert needle in fixture
 fixture=fixture.replace(needle,needle+'    mov qword ptr [rip + tclp_armed], 1\n',1)
 fixture+='\n.bss\n.p2align 3\ntclp_armed: .zero 8\n.text\n'
 replacements={};symbols={'src/sys.s':['file_read_all'],'src/mem.s':['mem_alloc','mem_alloc_try'],'src/proc.s':['proc_cwd'],'src/app/extvalidatepath.s':['ext_root_open'],'src/app/theme.s':['theme_find'],'src/app/themecapturemem.s':['tc_alloc_try'],'src/app/themecaptureio.s':['tc_file_capture'],'src/app/omarchy.s':['omarchy_target']}
 for path,names in symbols.items():
  source=(ROOT/path).read_text()
  for name in names:
   old='FN '+name+'\n';assert source.count(old)==1;source=source.replace(old,'FN tclp_real_'+name+'\n',1)
   fixture+='FN '+name+'\n    cmp qword ptr [rip + tclp_armed], 0\n    je tclp_real_'+name+'\n    mov edi, 73\n    call sys_exit\n'
  replacements[path]=source
 core=(ROOT/'src/app/themecapturecandidate.s').read_text();assert '\n    SYS 'not in core and '\n    API 'not in core
 if mutation:
  old,new=MUTATIONS[mutation];assert core.count(old)==1;core=core.replace(old,new,1)
  if mutation=='stale':
   # Keep stale fixture sources valid so the oracle detects an incorrect result, not a crash.
   fixture=fixture.replace('    mov qword ptr [rsp + 32 + TCL_query], 1\n','').replace('    mov qword ptr [rsp + 32 + TCL_current], 1\n','')
 replacements['src/app/themecapturecandidate.s']=core
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for name in ['baseline',*MUTATIONS]:build(a.build_only/name,True,None if name=='baseline'else name)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-tc-candidate-purity-')as td:
  for name in ['baseline',*MUTATIONS]:
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,win,None if name=='baseline'else name)
   command=[os.sys.executable,str(ROOT/'tests/theme-capture-candidate.py'),'--exe',str(exe)]+(['--wine',a.wine]if a.wine else[])
   r=subprocess.run(command,capture_output=True,timeout=60)
   if name=='baseline':assert r.returncode==0 and not r.stderr and b'ok theme-capture-candidate/'in r.stdout,(name,r)
   else:assert r.returncode==1 and b'AssertionError'in r.stderr,(name,r)
   print('ok theme-capture-candidate/'+('pure-baseline'if name=='baseline'else'mutation-'+name),flush=True)
if __name__=='__main__':main()
