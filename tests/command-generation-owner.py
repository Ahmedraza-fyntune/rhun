#!/usr/bin/env python3
"""Caller-owned command-generation construction and checked two-owner retirement."""
import argparse, importlib.util, os, re, shutil, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={"hidden-drop":120,"wrong-kind":122,"skip-extent":122,"skip-header":122,"early-charge":124,"custom-fallback":123}
def build(folder,windows=False,mutation=None):
 spec=importlib.util.spec_from_file_location('cg_owner_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 paths=['src/app/commandgeneration.s','src/app/commandgenerationowner.s'];rep={p:(ROOT/p).read_text()for p in paths}
 new=rep[paths[1]]
 assert 'call ext_prepare_owner_create' not in new and 'call ext_prepare_owner_release' not in new
 for p in paths:
  assert rep[p].count('call ext_prepare_retire_mark_custom_po')==1
  rep[p]=rep[p].replace('call ext_prepare_retire_mark_custom_po','call cgo_mark' if p==paths[1] else 'call cgt_mark')
 def change(path,old,new):
  assert rep[path].count(old)==1,(path,old);rep[path]=rep[path].replace(old,new,1)
 if mutation=='hidden-drop':change(paths[1],'    mov r13, rax\n','    mov r13, rax\n    mov rdi, rbx\n    call ext_prepare_owner_release_deferred\n')
 if mutation=='wrong-kind':change(paths[1],'    mov r8, [r13 - RD_PO_BACK + RD_kind]','    mov r8d, 4')
 if mutation=='skip-extent':change(paths[1],'    cmp qword ptr [r8 - 8], CG_SIZE + RD_PO_BACK\n    jne .Lcgor_bad','    cmp qword ptr [r8 - 8], CG_SIZE + RD_PO_BACK\n    nop')
 if mutation=='skip-header':change(paths[1],'3:  cmp qword ptr [rbx + rcx], 0','3:  cmp rax, rax')
 change(paths[1],'    call ext_prepare_retire_release_custom_po','    call cgo_custom_drop')
 if mutation=='custom-fallback':change(paths[1],'    call cgo_custom_drop\n    EPILOGUE','    call cgo_custom_drop\n    test rdx, rdx\n    jnz 991f\n    mov rdi, rbx\n    call prep_owned_dispose\n991:    EPILOGUE')
 if mutation=='early-charge':
  path='src/app/extprepareretirestep.s';rep[path]=(ROOT/path).read_text();change(path,'1:  call prep_cleanup_free\n    test rax, rax\n    js .Lrone_known_error','1:  call prep_cleanup_free\n    test rax, rax\n    nop')
 mem=(ROOT/'src/mem.s').read_text();assert mem.count('FN mem_alloc_try\n')==1
 rep['src/mem.s']=mem.replace('FN mem_alloc_try\n','FN mem_alloc_try\n    jmp cgt_alloc\nFN cgt_real_alloc\n',1)
 fixture='.equ CGT_INSTRUMENTED, 1\n'+(ROOT/'tests/command_generation_input_test.s').read_text()+'\n'+(ROOT/'tests/faults/command_generation_input_faults.inc').read_text()+'\n'+(ROOT/'tests/command_generation_owner_cases.inc').read_text()
 fixture+='''
FN cgo_custom_drop
    cmp qword ptr [rip + cgo_custom_refuse], 0
    je ext_prepare_retire_release_custom_po
    mov qword ptr [rip + cgo_custom_refuse], 0
    mov rax, -5
    xor edx, edx
    ret
FN cgo_mark
    cmp qword ptr [rip + cgt_fail_mark], 2
    jne cgt_mark
    PROLOGUE
    call ext_prepare_retire_mark_custom_po
    mov rax, -5
    EPILOGUE
'''
 old='    mov [rip + cgt_charge], rax\n';assert fixture.count(old)==1;fixture=fixture.replace(old,old+'    call cgo_test_cases\n',1)
 if windows:
  sys=(ROOT/'src/win/sys.s').read_text();assert sys.count('API VirtualFree')==1;rep['src/win/sys.s']=sys.replace('API VirtualFree','call cgo_virtual_free')
  fixture+='''
FN cgo_virtual_free
    cmp qword ptr [rip + cgo_unmap_armed], 1
    jne 2f
    cmp rcx, [rip + cgo_unmap_target]
    jne 2f
    mov qword ptr [rip + cgo_unmap_armed], 0
    inc qword ptr [rip + cgo_unmap_hits]
    sub rsp, 40
    mov ecx, 31
    call [rip + __imp_SetLastError]
    add rsp, 40
    xor eax, eax
    ret
2:  jmp [rip + __imp_VirtualFree]
'''
 else:
  mem=rep['src/mem.s'];assert mem.count('SYS SYS_munmap')==1;rep['src/mem.s']=mem.replace('SYS SYS_munmap','call cgo_native_unmap')
  fixture+='''
FN cgo_native_unmap
    cmp qword ptr [rip + cgo_unmap_armed], 1
    jne 2f
    cmp rdi, [rip + cgo_unmap_target]
    jne 2f
    mov qword ptr [rip + cgo_unmap_armed], 0
    inc qword ptr [rip + cgo_unmap_hits]
    mov rax, -5
    ret
2:  SYS SYS_munmap
    ret
'''
 # This builder normalizes only the unsuffixed read-only section. Never collapse suffixes.
 assert not any(re.search(r'(?m)^\s*\.section \.rodata\.',s)for s in [fixture,*rep.values()])
 return b.build(folder,fixture,rep,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and(a.exe or a.build_only or a.mutation):p.error('controls require fresh baseline and mutation builds')
 windows=bool(a.wine)or os.name=='nt'or bool(a.build_only and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-cg-owner-')as d:
  def check(exe,mutation):
   r=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe.resolve())]),capture_output=True,timeout=60)
   if mutation:assert r.returncode==CODES[mutation]and not r.stdout and not r.stderr,(mutation,r)
   else:assert r.returncode==0 and r.stdout==b'ok command generation owned inputs and deferred suppliers\n'and not r.stderr,r
   print('ok CG caller-owner '+(mutation or 'baseline'),flush=True)
  if a.negative_controls:
   check(build(Path(d)/'baseline',windows),None)
   for mutation in CODES:check(build(Path(d)/mutation,windows,mutation),mutation)
  else:
   exe=a.exe if a.exe and not a.build_only else build(Path(d),windows,a.mutation)
   if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);return
   check(exe,a.mutation)
 print('ok caller-owned CG constructor, tagged partial ownership, supplier retirement and native retention',flush=True)
if __name__=='__main__':main()
