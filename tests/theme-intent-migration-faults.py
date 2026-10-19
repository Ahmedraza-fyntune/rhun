#!/usr/bin/env python3
"""Allocation refusal and native failed-unmap preserve TCM owners, quota and exact retries."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,name,win,negative=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_intent_migration_test.s').read_text();replacements={}
 mark=(ROOT/'src/app/themeintentmigration.s').read_text().split('FN theme_intent_migration_mark_committed\n',1)[1]
 assert not any(line.strip().startswith(('call ','SYS ','API '))for line in mark.splitlines()),'publication mark must contain no calls'
 fixture+='''\n.bss\n.p2align 3\ntcmf_armed: .zero 8\ntcmf_count: .zero 8\ntcmf_fired: .zero 8\ntcmf_now: .zero 8\ntcmf_last: .zero 8\ntcmf_delay: .zero 8\ntcmf_calls: .zero 8\ntcmf_plan: .zero 8\ntcmf_publish: .zero 8\n.text\n'''
 old='    call theme_intent_migration_prepare\n';assert fixture.count(old)==1
 fixture=fixture.replace(old,'    mov qword ptr [rip + tcmf_armed], 1\n'+old+'    mov [rip + tcmf_plan], rax\n    mov qword ptr [rip + tcmf_armed], 0\n',1)
 alloc=(ROOT/'src/app/themecapturemem.s').read_text()
 if name.startswith(('alloc','reserve')):
  n=int(name[-1]);symbol='tc_alloc_try'if name.startswith('alloc')else'tc_charge_reserve'
  alloc=alloc.replace('FN '+symbol+'\n','FN tcmf_real_fault\n',1)
  fixture+='FN '+symbol+'\n    cmp qword ptr [rip + tcmf_publish], 0\n    jne tcmt_fail\n    cmp qword ptr [rip + tcmf_armed], 0\n    je tcmf_real_fault\n    inc qword ptr [rip + tcmf_count]\n    cmp qword ptr [rip + tcmf_count], '+str(n)+'\n    jne tcmf_real_fault\n'+('    xor eax, eax\n'if symbol=='tc_alloc_try'else'    mov rax, -12\n')+'    ret\n'
  old='''.Ltcmt_prepared:
    test r14, r14
    jz tcmt_fail
    or rdx, rcx
    jnz tcmt_fail
''';assert fixture.count(old)==1
  if name=='alloc1':
   new='''.Ltcmt_prepared:
    test r14, r14
    jnz tcmt_fail
    cmp rdx, -12
    jne tcmt_fail
    test rcx, rcx
    jnz tcmt_fail
    cmp qword ptr [rip + g_theme_intent_migration], 0
    jne tcmt_fail
    cmp qword ptr [r12 + TI_refs], 1
    jne tcmt_fail
    mov rdi, r12
    call theme_intent_release
    cmp rdx, 1
    jne tcmt_fail
    jmp .Ltcmt_old_cleanup
'''
  else:
   new='''.Ltcmt_prepared:
    test r14, r14
    jz tcmt_fail
    cmp rdx, -12
    jne tcmt_fail
    test rcx, rcx
    jnz tcmt_fail
    cmp qword ptr [r14 + TCM_state], TCM_RETIRING
    jne tcmt_fail
    cmp qword ptr [r14 + TCM_primary], -12
    jne tcmt_fail
    jmp .Ltcmt_release
'''
  fixture=fixture.replace(old,new,1)
 else:
  # Actual failed SYS_munmap boundary or unexpected retained Small plan self-free.
  alloc=alloc.replace('FN tc_free\n','FN tcmf_real_free\n',1)
  fixture=fixture.replace('    PROLOGUE 400\n','    PROLOGUE 512\n',1).replace('    cmp qword ptr [rsp + 352], 1100\n','    cmp qword ptr [rsp + 352], 12000\n',1)
  fixture+='''FN tc_free
    cmp qword ptr [rip + tcmf_publish], 0
    jne tcmt_fail
    inc qword ptr [rip + tcmf_calls]
'''
  if name=='self':
   fixture+='''    cmp rdi, [rip + tcmf_plan]
    jne tcmf_real_free
    cmp qword ptr [rip + tcmf_fired], 10
    jae tcmf_real_free
    PROLOGUE
    call tcmf_retry
    mov rax, -5
    xor edx, edx
    EPILOGUE
'''
  else:fixture+='    jmp tcmf_real_free\n'
  memory=(ROOT/'src/mem.s').read_text();old='    SYS SYS_munmap\n';assert memory.count(old)==1
  if name=='large':
   replacements['src/mem.s']=memory.replace(old,'    call tcmf_unmap\n',1)
   fixture+='''FN tcmf_unmap
    lea rax, [rdi + 16]
    cmp rax, [rip + tcmt_fault_target]
    jne 1f
    cmp qword ptr [rip + tcmf_fired], 10
    jae 1f
    cmp qword ptr [rdi + 8], 70000
    jne tcmt_fail
    cmp qword ptr [rdi], 73728
    jne tcmt_fail
    PROLOGUE
    call tcmf_retry
    mov rax, -5
    EPILOGUE
1:  SYS SYS_munmap
    ret
'''
  due='''    cmp qword ptr [rip + tcmf_fired], 0
    je 90f
    mov rax, [rip + tcmf_last]
    add rax, [rip + tcmf_delay]
    cmp [rip + tcmf_now], rax
    jb tcmt_fail
90:
'''
  fixture=fixture.replace('    cmp qword ptr [rip + tcmf_fired], 10\n',due+'    cmp qword ptr [rip + tcmf_fired], 10\n',1)
  fixture+='''tcmf_retry:
    mov rax, [rip + tcmf_fired]
    test rax, rax
    jz 1f
    mov rax, [rip + tcmf_last]
    add rax, [rip + tcmf_delay]
    cmp [rip + tcmf_now], rax
    jb tcmt_fail
1:  mov rax, [rip + tcmf_now]
    mov [rip + tcmf_last], rax
    mov rax, [rip + tcmf_delay]
    test rax, rax
    jnz 2f
    mov eax, 8
2:  add rax, rax
    cmp rax, 1000
    jbe 3f
    mov eax, 1000
3:  mov [rip + tcmf_delay], rax
    inc qword ptr [rip + tcmf_fired]
    ret
'''
  mask=264 if name=='large' else 256
  target=8 if name=='large' else 256
  status=f'''    mov rdi, r14
    lea rsi, [rsp + 128]
    call theme_intent_migration_status
    test rax, rax
    jnz tcmt_fail
    cmp qword ptr [rsp + 128], TCM_COMMITTED
    je 80f
    cmp qword ptr [rsp + 128], TCM_RETIRING
    jne tcmt_fail
80: cmp qword ptr [rsp + 128 + 40], 1
    jne tcmt_fail
    cmp qword ptr [rsp + 128 + 48], 0
    jne tcmt_fail
    mov rax, [rsp + 128 + 32]
    test rax, 256
    jz tcmt_fail
    cmp rax, 511
    ja tcmt_fail
    xor ecx, ecx
    cmp qword ptr [rip + tcmf_fired], 0
    je 81f
    mov rcx, -5
81: cmp [rsp + 128 + 8], rcx
    jne tcmt_fail
    xor ecx, ecx
    test rax, {target}
    jz 82f
    mov rcx, [rip + tcmf_delay]
82: cmp [rsp + 128 + 24], rcx
    jne tcmt_fail
    cmp rax, {mask}
    jne 83f
    cmp qword ptr [rip + tcmf_fired], 0
    je 83f
    mov rcx, [rip + tcmf_last]
    add rcx, [rip + tcmf_delay]
    cmp [rsp + 128 + 16], rcx
    jne tcmt_fail
    jmp 84f
83: cmp qword ptr [rsp + 128 + 16], 0
    jne tcmt_fail
84: mov qword ptr [rsp + 384], 0
    mov rax, [rsp + 352]
    cmp rax, [rsp + 128 + 16]
    jge 85f
    mov qword ptr [rsp + 384], 1
85: mov rax, [rip + tcmf_fired]
    mov [rsp + 392], rax
    mov rdi, r14
    mov rsi, [rsp + 352]
'''
  needle='    call theme_intent_migration_release\n';assert fixture.count(needle)==1
  fixture=fixture.replace(needle,status+'''    mov [rip + tcmf_now], rsi
    mov qword ptr [rip + tcmf_calls], 0
    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 368], rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 376], rax
'''+needle+'''    cmp rcx, 1
    ja tcmt_fail
    cmp qword ptr [rip + tcmf_calls], 1
    ja tcmt_fail
    cmp qword ptr [rsp + 384], 0
    je 24f
    cmp rcx, 1
    jne tcmt_fail
    test rdx, rdx
    jnz tcmt_fail
    cmp qword ptr [rip + tcmf_calls], 0
    jne tcmt_fail
24: cmp qword ptr [rip + tcmf_fired], 0
    je 21f
    cmp rax, -5
    jne tcmt_fail
    test rdx, rdx
    jnz 22f
    cmp [rip + g_theme_intent_migration], r14
    jne tcmt_fail
    mov r8, [rip + tcmf_fired]
    cmp r8, [rsp + 392]
    jne 25f
    cmp qword ptr [rsp + 384], 1
    jne 22f
25: mov rax, [rip + g_theme_capture_charge]
    cmp rax, [rsp + 368]
    jne tcmt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 376]
    jne tcmt_fail
22: xor eax, eax
21:
''',1)
  # Poison every allocator/native action reachable from ownership mark.
  for symbol in ['tc_alloc_try','tc_charge_reserve']:
   alloc=alloc.replace('FN '+symbol+'\n','FN '+symbol+'\n    cmp qword ptr [rip + tcmf_publish], 0\n    jne tcmt_fail\n',1)
  fixture=fixture.replace('    call theme_intent_migration_mark_committed\n','    mov qword ptr [rip + tcmf_publish], 1\n    call theme_intent_migration_mark_committed\n    mov qword ptr [rip + tcmf_publish], 0\n',1)
  fixture=fixture.replace('    cmp qword ptr [rip + g_theme_capture_charge], 0\n','    cmp qword ptr [rip + tcmf_fired], 10\n    jne tcmt_fail\n    cmp qword ptr [rip + g_theme_capture_charge], 0\n',1)
 replacements['src/app/themecapturemem.s']=alloc
 # Counter symbols are intentionally visible only to the independently replaced modules.
 fixture+='\n.globl tcmf_publish, tcmf_calls, tcmt_fail\n'
 if negative:
  core=(ROOT/'src/app/themeintentmigrationrelease.s').read_text()
  if negative=='consumed':
   old='    test r15, r15\n    jz .Ltcmr_retained\n';new='    nop\n'
  elif negative=='reason':
   old='.Ltcmr_backoff:\n    mov rax, [rbx + TCM_cleanup]\n    xor edx, edx\n    mov ecx, 1\n';new=old.replace('    mov ecx, 1\n','    xor ecx, ecx\n')
  elif negative=='status':
   old='2:  mov [rsi + 16], r9\n';new='2:  mov qword ptr [rsi + 16], 0\n'
  else:
   old='    cmp rax, 1000\n    jbe 2f\n    mov eax, 1000\n';new=old.replace('1000','1024')
  assert core.count(old)==1,(negative,core.count(old));replacements['src/app/themeintentmigrationrelease.s']=core.replace(old,new,1)
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';cases=[('alloc'+str(n),False)for n in range(1,5)]+[('reserve'+str(n),False)for n in range(1,4)]+[('large',False),('self',False)]+[('large',n)for n in('consumed','reason','status','cap')]
 if a.build_only:
  for name,negative in cases:build(a.build_only/(name+('-'+str(negative)+'-negative'if negative else'')),name,True,negative)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-migration-fault-')as td:
  for name,negative in cases:
   key=name+('-'+str(negative)+'-negative'if negative else'');exe=a.exe_root/key/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/key,name,win,negative)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),'1'if name in('large','self')else'0'],capture_output=True,timeout=15)
   assert r.returncode==(73 if negative else 0)and not r.stdout and not r.stderr,(key,r)
   print('ok theme-intent/migration-fault/'+key,flush=True)
if __name__=='__main__':main()
