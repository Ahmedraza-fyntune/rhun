#!/usr/bin/env python3
"""Bounded owned command rows against the actual legacy binding implementation."""
import argparse,importlib.util,os,subprocess,tempfile,shutil,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False,collisions=False,mutation=None,addon=None,extra_replacements=None,mem_unmap_hook=None):
 collisions=collisions or mutation=="hash-only"
 spec=importlib.util.spec_from_file_location('build_cg',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 keys=(ROOT/'src/app/keys.s').read_text()+'\n.text\nFN cgbt_bindings\n    lea rax, [rip + bindings]\n    ret\n'
 if windows:keys=re.sub(r'(?m)^(\s*\.(?:pushsection|section)) \.rodata(\.\w+)?[^\n]*',lambda m:m[1]+' .rdata'+('$'+m[2][1:] if m[2] else '')+',"dr"',keys)
 mem=(ROOT/'src/mem.s').read_text();old='FN mem_alloc_try\n';assert mem.count(old)==1;mem=mem.replace(old,'FN mem_alloc_try\n    jmp cgbt_alloc\nFN cgbt_real_alloc\n',1)
 if mem_unmap_hook:
  old='    SYS SYS_munmap';assert mem.count(old)==1;mem=mem.replace(old,'    call '+mem_unmap_hook,1)
 fixture=(ROOT/'tests/faults/command_generation_build.s').read_text()+(ROOT/'tests/faults/command_generation_limits.inc').read_text()+(ROOT/'tests/faults/command_generation_build_limits.inc').read_text()+(ROOT/'tests/faults/command_generation_retire.inc').read_text()
 if addon:
  assert fixture.count('FN main\n')==1;fixture=fixture.replace('FN main\n','FN original_cg_build_main\n')+'\n'+addon
 replacements={'src/app/keys.s':keys,'src/mem.s':mem,'src/app/ext.s':(ROOT/'src/app/ext.s').read_text()+'\n.text\nFN cgbt_ext_tmp\n    lea rax, [rip + tmp]\n    ret\n'}
 source=(ROOT/'src/app/commandgeneration.s').read_text()
 for old,new in [('ext_prepare_release_deferred','cgbt_drop_ep'),('ext_runtime_release_deferred','cgbt_drop_ro'),('ext_prepare_retire_handoff_ledger','cgbt_ledger')]:
  marker='call '+old+'\n';assert source.count(marker)==1;source=source.replace(marker,'call '+new+'\n')
 if mutation=='retire-clear':
  old='    cmp rdx, 1\n    jne .Lcgd_blocked';assert source.count(old)==1;source=source.replace(old,'    cmp rdx, 1\n    nop')
 replacements['src/app/commandgeneration.s']=source
 if mutation in ['stale-ready','stale-final']:
  step=(ROOT/'src/app/commandgenerationstep.s').read_text();body,tail=step.split('FN command_generation_check',1);old='    call cg_context\n';assert body.count(old)==2
  if mutation=='stale-ready':body=body.replace(old,'    cmp qword ptr [rbx + PO_ready], 1\n    je .Lcgstep_ready\n'+old,1)
  else:
   a,z=body.rsplit(old,1);body=a+'    xor eax, eax\n'+z
  replacements['src/app/commandgenerationstep.s']=body+'FN command_generation_check'+tail
 if collisions:
  sha=(ROOT/'src/sha256.s').read_text();assert sha.count('FN sha256_final\n')==1;sha=sha.replace('FN sha256_final\n','FN cgbt_real_sha_final\n');replacements['src/sha256.s']=sha
  bindings=(ROOT/'src/app/commandgenerationbindings.s').read_text();assert bindings.count('FN cg_binding_hash\n')==1;bindings=bindings.replace('FN cg_binding_hash\n','FN cgbt_real_binding_hash\n');replacements['src/app/commandgenerationbindings.s']=bindings
  fixture='.equ CGBT_COLLISIONS, 1\n'+fixture+'''\n.bss
.p2align 3
cgbt_forced_hash_calls: .quad 0
cgbt_forced_binding_calls: .quad 0
.text
FN sha256_final
    PROLOGUE
    mov rbx, rsi
    call cgbt_real_sha_final
    test eax, eax
    jz 1f
    inc qword ptr [rip + cgbt_forced_hash_calls]
    mov qword ptr [rbx], 0
    mov qword ptr [rbx + 8], 0
    mov qword ptr [rbx + 16], 0
    mov qword ptr [rbx + 24], 0
1:  EPILOGUE
FN cg_binding_hash
    cmp qword ptr [rip + cgbt_heavy_bindings], 0
    jne cgbt_real_binding_hash
    inc qword ptr [rip + cgbt_forced_binding_calls]
    mov eax, CG_BINDING_MAP_CAP - 1
    ret
'''
 # Count actual variable source reads in compiled CG code, including both equality operands.
 for name in ['commandgenerationbuild','commandgenerationbindings','commandgenerationuser']:
  relative='src/app/'+name+'.s';source=replacements.get(relative,(ROOT/relative).read_text())
  if mutation=='hash-only' and name=='commandgenerationbuild':
   assert source.count('call memeq\n')==2;source=source.replace('call memeq\n','mov eax, 1\n')
  if mutation=='default-precedence' and name=='commandgenerationbindings':
   old='    cmp qword ptr [rbx + CG_wordmode], 1\n    je .Lcgbd_bind_next';assert source.count(old)==1;source=source.replace(old,'    cmp qword ptr [rbx + CG_wordmode], 1\n    nop')
  if name=='commandgenerationbuild':
   marker='FN cg_build_one\n';assert source.count(marker)==1;source=source.replace(marker,marker+'    inc qword ptr [rip + cgbt_dispatch_calls]\n')
  source=source.replace('    lea rax, [rip + g_commands]','    lea rax, [rip + g_commands]\n    cmp qword ptr [rip + cgbt_builtin_override], 0\n    je 991f\n    mov rax, [rip + cgbt_builtin_override]\n991:')
  for function in ['memcpy','memeq','sha256_update','keys_combo_step']:
   source=source.replace('call '+function+'\n','call cgbt_observed_'+function+'\n')
  for marker in ['    cmp byte ptr [r12 + r13], 0','    movzx eax, byte ptr [r12 + r13]','    movzx eax, byte ptr [r12 + r14]','    cmp al, [r13 + r14]']:
   source=source.replace(marker,'    inc qword ptr [rip + cgbt_source_bytes]\n'+marker)
  if name=='commandgenerationuser':
   marker='    mov qword ptr [rbx + CG_phase], CG_READY\n';assert source.count(marker)==1;source=source.replace(marker,marker+'    call cgbt_finish_hook\n')
  replacements[relative]=source
 fixture=fixture.replace('call command_generation_step\n','call cgbt_observed_step\n')
 fixture+='\n.bss\n.p2align 3\n.globl cgbt_source_bytes\ncgbt_source_bytes: .quad 0\n.globl cgbt_dispatch_calls\ncgbt_dispatch_calls: .quad 0\ncgbt_finish_stale: .quad 0\n.text\nFN cgbt_observed_memcpy\n    cmp rdx, 4096\n    ja cgbt_fail\n    add [rip + cgbt_source_bytes], rdx\n    jmp memcpy\nFN cgbt_observed_memeq\n    cmp rdx, 4096\n    ja cgbt_fail\n    add [rip + cgbt_source_bytes], rdx\n    add [rip + cgbt_source_bytes], rdx\n    jmp memeq\nFN cgbt_observed_sha256_update\n    cmp rdx, 4096\n    ja cgbt_fail\n    add [rip + cgbt_source_bytes], rdx\n    jmp sha256_update\nFN cgbt_observed_keys_combo_step\n    PROLOGUE\n    call keys_combo_step\n    cmp rdx, 4096\n    ja cgbt_fail\n    cmp rcx, 1\n    ja cgbt_fail\n    add [rip + cgbt_source_bytes], rdx\n    EPILOGUE\nFN cgbt_observed_step\n    PROLOGUE\n    mov r14, rdx\n    mov qword ptr [rip + cgbt_source_bytes], 0\n    mov qword ptr [rip + cgbt_dispatch_calls], 0\n    call command_generation_step\n    mov r12, rax\n    mov r13, rdx\n    cmp [rip + cgbt_dispatch_calls], rdx\n    jne cgbt_fail\n    cmp rdx, r14\n    ja cgbt_fail\n    mov rax, rdx\n    shl rax, 12\n    cmp [rip + cgbt_source_bytes], rax\n    ja cgbt_fail\n    mov rax, r12\n    mov rdx, r13\n    EPILOGUE\nFN cgbt_finish_hook\n    cmp qword ptr [rip + cgbt_finish_stale], 0\n    je 1f\n    inc qword ptr [rip + cgbt_context]\n    mov qword ptr [rip + cgbt_finish_stale], 0\n1:  ret\n'
 if extra_replacements:
  assert not(replacements.keys() & extra_replacements.keys()),"test override would discard existing source observers"
  replacements.update(extra_replacements)
 return m.build(folder,fixture,replacements,windows=windows)
MUTATIONS={'stale-ready':89,'stale-final':90,'hash-only':88,'retire-clear':104,'default-precedence':83}
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--collisions',action='store_true');p.add_argument('--mutation',choices=list(MUTATIONS));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('--negative-controls builds baseline and controls')
 windows=bool(a.wine)or os.name=='nt'or bool(a.build_only and a.exe and a.exe.suffix=='.exe')
 def check(exe,mutation=None):
  result=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe)]),capture_output=True,timeout=40)
  if mutation:
   assert result.returncode==MUTATIONS[mutation] and not result.stdout and not result.stderr,(mutation,result)
   print('ok command generation negative control '+mutation,flush=True)
  else:
   assert result.returncode==0 and result.stdout==b'ok bounded command rows, exact routing and legacy binding oracle\n'and not result.stderr,result
   print('ok bounded command rows, exact routing and legacy binding oracle',flush=True)
 with tempfile.TemporaryDirectory(prefix='rhun-cg-build-')as d:
  folder=Path(d)
  if a.negative_controls:
   check(build(folder/'normal',windows))
   check(build(folder/'collisions',windows,True))
   for mutation in MUTATIONS:check(build(folder/mutation,windows,False,mutation),mutation)
  else:
   exe=a.exe if a.exe and not a.build_only else build(folder,windows,a.collisions,a.mutation)
   if a.build_only:
    assert a.exe;shutil.copy2(exe,a.exe);return
   check(exe,a.mutation)
if __name__=='__main__':main()
