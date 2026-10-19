#!/usr/bin/env python3
"""Owned frozen response transfer and checked operation cleanup on retained EA/HI."""
import argparse,importlib.util,os,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={'early-id':183,'ignore-consumed':190,'ignore-cleanup-due':191,'skip-phase':193,'skip-role':193,'no-park':187,'copy-budget':198,'allocation-slice':200,'compaction-slice':199,'missing-timeout':201,'wake-deadline':186,'lose-unmap-charge':202,'fixed-start':203,'reject-committed':205,'copy-accepted-debit':206,'oom-retry':207}
SCENARIOS={'early-id':0,'no-park':0,'wake-deadline':0,'ignore-consumed':1,'ignore-cleanup-due':1,'skip-phase':1,'skip-role':1,'copy-budget':2,'allocation-slice':2,'compaction-slice':2,'missing-timeout':2,'lose-unmap-charge':3,'fixed-start':4,'reject-committed':5,'copy-accepted-debit':4,'oom-retry':2}
def build(folder,windows=False,scenario=0,mutation=None):
 sys.path.insert(0,str(ROOT/'tests/faults'));import ext_running_session_build as native
 real=native.link
 def link(target,replacements,win):
  text=replacements['fixture.s'];old='    call ra_cases\n';assert text.count(old)==1
  text=text.replace(old,'    call rpl_cases\n',1)
  old='    cmp qword ptr [rip + af_status + 24], 0\n';assert text.count(old)==1; text=text.replace(old,'    mov rdx, [rip + rpl_expected_diag]\n    cmp [rip + af_status + 24], rdx\n',1)
  old='    cmp qword ptr [rip + tt_report + 24], 0\n';assert text.count(old)==1; text=text.replace(old,'    mov rdx, [rip + rpl_expected_diag]\n    cmp [rip + tt_report + 24], rdx\n')
  replacements['fixture.s']=text+'\n.equ RPL_SCENARIO, '+str(scenario)+'\n'+(ROOT/'tests/runtime_reply_cases.inc').read_text()+'\n'+(ROOT/'tests/runtime_reply_fair_cases.inc').read_text()
  path='src/app/extruntimeadmit.s';text=replacements[path];assert text.count('call time_ms')==1;replacements[path]=text.replace('call time_ms','call rpl_clock')
  path='src/app/extenqueue.s';text=(ROOT/path).read_text();assert text.count('call watch_set_events')==1;replacements[path]=text.replace('call watch_set_events','call rpl_watch',1).replace('call memcpy','call rpl_copy').replace('call mem_alloc_try','call rpl_queue_alloc')
  path='src/app/extqueuecompact.s';text=(ROOT/path).read_text();assert text.count('call memmove')==1;replacements[path]=text.replace('call memmove','call rpl_move')
  path='src/app/extruntimeoperation.s';text=(ROOT/path).read_text();assert text.count('call rt_ticket_release')==1 and text.count('call ext_prepare_owner_release_deferred')==1
  replacements[path]=text.replace('call rt_ticket_release','call rpl_ticket_drop').replace('call ext_prepare_owner_release_deferred','call rpl_eo_drop')
  if mutation:
   name='extruntimeoperation'if mutation in ['ignore-consumed','ignore-cleanup-due','skip-phase','skip-role','reject-committed']else'extruntimereplystate'if mutation in ['no-park','wake-deadline']else'extprepareretirealloc'if mutation=='lose-unmap-charge'else'extruntimereply'
   path='src/app/'+name+'.s';text=replacements.get(path,(ROOT/path).read_text())
   old,new={
    'reject-committed':('    cmp qword ptr [r12 + RTT_phase], RTT_COMMITTED\n    jne .Lrot_bad','    jmp .Lrot_bad'),
    'copy-accepted-debit':('    sub [rsp + 24], rax\n    mov qword ptr [r15 + RTS_delivery], RTDEL_QUEUED','    nop\n    mov qword ptr [r15 + RTS_delivery], RTDEL_QUEUED'),
    'oom-retry':('.Lrr_failed:\n    cmp rax, -32','.Lrr_failed:\n    cmp rax, -12\n    jne 99f\n    call .Lrr_enqueue\n99: cmp rax, -32'),
    'early-id':('    call .Lrr_channel\n','    mov qword ptr [r15 + RTS_replyID], 0\n    call .Lrr_channel\n'),
    'ignore-consumed':('    cmp rdx, 1\n    jne .Lroc_refused','    cmp rdx, 1\n    nop'),
    'ignore-cleanup-due':('    cmp rax, r12\n    ja .Lroc_loop','    cmp rax, r12\n    nop'),
    'skip-phase':('cmp qword ptr [r12 + RTT_phase], RTT_TERMINAL_ERROR\n    jne .Lrot_bad','nop'),
    'skip-role':('    call rt_operation_ticket_check','    xor eax, eax'),
    'no-park':('    mov qword ptr [rdi + RTS_retryDue], RTR_PARKED','    mov rax, 0x7fffffffffffffff\n    mov [rdi + RTS_retryDue], rax'),
    'copy-budget':('    sub rax, [r15 + RTS_replyLen]','    nop'),
    'allocation-slice':('    test rcx, rcx\n    jz 2f\n    mov qword ptr [rsp + 64], 1','    test rcx, rcx\n    jz 2f\n    nop'),
    'compaction-slice':('    mov [rsp + 48], rdx\n    mov qword ptr [rsp + 64], 1','    mov [rsp + 48], rdx\n    nop'),
    'missing-timeout':('    mov rcx, rax\n    mov rdx, [rsp]','    xor ecx, ecx\n    mov rdx, [rsp]'),
    'fixed-start':('    mov r14, [rbx + RT_replyCursor]','    mov r14d, 17'),
    'lose-unmap-charge':('    inc qword ptr [rip + g_mem_live]','    nop'),
    'wake-deadline':('    mov qword ptr [r14 + RTS_backoff], 0','    mov qword ptr [r14 + RTS_backoff], 0\n    mov qword ptr [r14 + RTS_stallDeadline], 0')
   }[mutation]
   count=text.count(old);assert count==(2 if mutation=='early-id'else 1),(mutation,count);replacements[path]=text.replace(old,new,1)
  return real(target,replacements,win)
 native.link=link
 try:
  spec=importlib.util.spec_from_file_location('reply_admission',ROOT/'tests/runtime-admission.py');a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
  return a.build(folder,windows)
 finally:native.link=real

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--scenario',type=int,choices=range(6));p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('Wine requires exact exe and owned drive root')
 if a.exe and a.build_only:p.error('exe and build-only are exclusive')
 if a.negative_controls and(a.exe or a.mutation or a.scenario is not None):p.error('controls build all unambiguous variants')
 if a.mutation and a.scenario is not None and a.scenario!=SCENARIOS[a.mutation]:p.error('mutation requires its documented scenario')
 variants=[(str(i),i,None)for i in range(6)]
 if a.mutation:variants=[(a.mutation,SCENARIOS[a.mutation],a.mutation)]
 elif a.scenario is not None:variants=[(str(a.scenario),a.scenario,None)]
 elif a.negative_controls:variants.extend((m,SCENARIOS[m],m)for m in CODES)
 if a.exe:variants=[('prebuilt',a.scenario if a.scenario is not None else SCENARIOS.get(a.mutation,0),a.mutation)]
 drive=a.wine_drive_root.resolve()if a.wine else None
 with tempfile.TemporaryDirectory(prefix='rhun-runtime-reply-',dir=drive)as tmp:
  for label,scenario,mutation in variants:
   exe=a.exe or build((a.build_only or Path(tmp)/'bin')/label,os.name=='nt'or a.windows_build or bool(a.wine),scenario,mutation)
   if a.build_only:print('built runtime reply',label,exe,flush=True);continue
   arg='C:/'+Path(tmp).relative_to(drive).as_posix()if drive else str(Path(tmp).resolve())
   with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),arg],timeout=45,output_bound=0,error_bound=4096)as f:
    out,err=f.finish();assert(f.process.returncode,out,err)==(CODES.get(mutation,0),b'',b''),(label,f.process.returncode,out,err)
   print('ok runtime reply',label,flush=True)
if __name__=='__main__':main()
