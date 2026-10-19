#!/usr/bin/env python3
"""Bounded complete debt timer census with actual producer invalidation checks."""
import argparse,importlib.util,os,sys,tempfile,subprocess
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={n:190 for n in ('skip-insert','skip-retry','skip-consume','skip-wake','ignore-dirty','skip-last','unbounded','park-runnable','share-cursor','ignore-final-min','premature-ready')}
def build(folder,windows=False,mutation=None,scenario='standard'):
 sys.path.insert(0,str(ROOT/'tests/faults'));import ext_running_session_build as native
 spec=importlib.util.spec_from_file_location('debt_timer_remove',ROOT/'tests/runtime-remove.py');remove=importlib.util.module_from_spec(spec);spec.loader.exec_module(remove);previous=native.link
 def link(target,replacements,win):
  source=replacements['fixture.s']
  if scenario=='closed':
   start=source.index('    mov qword ptr [rip + rts_stage], 210\n');end=source.index('    mov qword ptr [rip + rts_stage], 213\n',start);source=source[:start]+source[end:]
  source='.equ DTS_TEST_CLOSED, '+str(int(scenario=='closed'))+'\n.equ DTS_INTERLEAVE, '+str(1 if scenario=='before'else 2 if scenario=='after'else 0)+'\n'+source
  old='.include "rhun.inc"';source=source.replace(old,old+'\n.include "app/extruntimeservice.inc"\n.include "app/extruntimedebtscan.inc"',1)
  old='    call rr_cases\n';assert source.count(old)==1;source=source.replace(old,'    call dts_choose_row\n'+old+'    call dts_cases\n',1)
  # A real LIVE row becomes DEBT through the normal accepted unregister API.
  old='    mov qword ptr [rip + rr_stage], 155\n';assert source.count(old)==1;source=source.replace(old,'    call dts_prepare_producer\n'+old,1)
  old='    call rr_checked_remove\n    test rax, rax';assert source.count(old)==1;source=source.replace(old,'    call rr_checked_remove\n    cmp qword ptr [rbx + RT_debtScanValid], 0\n    jne dts_fail\n    cmp qword ptr [rbx + RT_debtScanDirty], 1\n    jne dts_fail\n    call dts_finish_real\n    test rax, rax',1)
  # Every actual checked-drop attempt changes a row or its due; skipped visits do not.
  old='rr_checked_debt:\n    PROLOGUE\n    mov qword ptr [rip + rr_work_watch], 1\n    call rt_debt_step\n    mov qword ptr [rip + rr_work_watch], 0\n    EPILOGUE';assert source.count(old)==1
  source=source.replace(old,'''rr_checked_debt:
    PROLOGUE 64
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov rax, [rip + rr_drop_calls]
    mov [rsp + 24], rax
    call dts_prepare_producer
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov qword ptr [rip + rr_work_watch], 1
    call rt_debt_step
    mov qword ptr [rip + rr_work_watch], 0
    mov [rsp + 32], rax
    mov [rsp + 40], rdx
    mov [rsp + 48], rcx
    mov rax, [rip + rr_drop_calls]
    cmp rax, [rsp + 24]
    setne al
    movzx eax, al
    cmp [rbx + RT_debtScanDirty], rax
    jne dts_fail
.if DTS_INTERLEAVE == 0
    xor eax, 1
.else
    xor eax, eax
.endif
    cmp [rbx + RT_debtScanValid], rax
    jne dts_fail
    call dts_finish_real
    mov rax, [rsp + 32]
    mov rdx, [rsp + 40]
    mov rcx, [rsp + 48]
    EPILOGUE''',1)
  source=source.replace('    call rt_debt_wake\n','    call dts_wake\n')
  replacements['fixture.s']=source+'\n'+(ROOT/'tests/runtime_debt_timer_cases.inc').read_text()
  if mutation:
   path='src/app/'+('extruntimerow'if mutation=='skip-insert'else'extruntimedebt'if mutation in ('skip-retry','skip-consume','skip-wake')else'extruntimedebtscan')+'.s';text=replacements.get(path,(ROOT/path).read_text())
   invalid='    mov qword ptr [rbx + RT_debtScanValid], 0\n    mov qword ptr [rbx + RT_debtScanDirty], 1'
   if mutation=='skip-insert':old=invalid.replace('rbx','rdi');new='    nop\n    nop'
   elif mutation in ('skip-retry','skip-consume','skip-wake'):
    marker={'skip-retry':'3:  mov [r8 + RTR_debtBackoff], rax','skip-consume':'    mov qword ptr [r8 + RTR_state], RTR_FREE','skip-wake':'    mov qword ptr [r8 + RTR_debtDue], 0'}[mutation];old=marker+'\n'+invalid;new=marker+'\n    nop\n    nop'
   else:old,new={
    'ignore-final-min':('    mov rax, [rbx + RT_debtScanMin]','    xor eax, eax'),
    'premature-ready':('.Ldss_pending:\n    xor eax, eax','.Ldss_pending:\n    mov eax, 1'),
    'ignore-dirty':('    cmp qword ptr [rbx + RT_debtScanDirty], 0\n    je .Ldss_loop','    jmp .Ldss_loop'),
    'skip-last':('    cmp r14, RT_ROW_COUNT\n    jae .Ldss_finish','    cmp r14, RT_ROW_COUNT - 1\n    jae .Ldss_finish'),
    'unbounded':('    cmp r13, r12\n    jae .Ldss_pending','    cmp r13, RT_ROW_COUNT\n    jae .Ldss_pending'),
    'park-runnable':('    je .Ldss_loop\n    cmp qword ptr [rbx + RT_debtScanHasDue], 0','    mov edx, 0\n    cmp qword ptr [rbx + RT_debtScanHasDue], 0'),
    'share-cursor':('    mov [rbx + RT_debtScanCursor], rax','    mov [rbx + RT_debtScanCursor], rax\n    mov [rbx + RT_replyCursor], rax')
   }[mutation]
   assert text.count(old)==1,(mutation,text.count(old));replacements[path]=text.replace(old,new,1)
  return previous(target,replacements,win)
 native.link=link
 try:return remove.build(folder,windows,scenario='standard'if scenario in ('closed','before','after')else scenario)
 finally:native.link=previous

def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--scenario',choices=['standard','diagnostic','closed','before','after']);p.add_argument('--mutation',choices=CODES);p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.exe and a.build_only:p.error('exe and build-only are exclusive')
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('Wine needs exact exe and owned drive')
 if a.negative_controls and(a.exe or a.scenario or a.mutation):p.error('controls build their exact variants')
 if a.mutation and a.scenario not in (None,'standard'):p.error('mutants use standard producer scenario')
 variants=[(a.scenario or 'standard',a.mutation)]if a.exe or a.scenario or a.mutation else[(n,None)for n in ('standard','diagnostic','closed','before','after')]
 if a.negative_controls:variants.extend(('standard',m)for m in CODES)
 drive=a.wine_drive_root.resolve()if a.wine else None
 with tempfile.TemporaryDirectory(prefix='rhun-debt-timer-',dir=drive)as tmp:
  for scenario,mutation in variants:
   label=mutation or scenario;exe=a.exe or build((a.build_only or Path(tmp)/'bin')/label,os.name=='nt'or bool(a.wine)or a.windows_build,mutation,scenario)
   if a.build_only:print('built debt timer',label,exe,flush=True);continue
   arg='C:/'+Path(tmp).relative_to(drive).as_posix()if drive else str(Path(tmp).resolve())
   try:
    with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),arg],timeout=90,output_bound=0,error_bound=4096)as e:
     out,err=e.finish();assert(e.process.returncode,out,err)==(CODES.get(mutation,0),b'',b''),(label,e.process.returncode,out,err)
   except (TimeoutError, subprocess.TimeoutExpired):
    sys.stdout.buffer.write(bytes(e.buffer));sys.stdout.buffer.flush()
    sys.stderr.buffer.write(bytes(e.errors));sys.stderr.buffer.flush()
    raise
   print('ok bounded complete debt timer',label,flush=True)
if __name__=='__main__':main()
