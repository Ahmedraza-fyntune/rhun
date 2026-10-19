#!/usr/bin/env python3
"""Owned runtime removal and independently scheduled physical row cleanup."""
import argparse,importlib.util,os,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={'skip-revoke':155,'alias-global-neighbors':157,'consume-refused-drop':158,'ignore-retry-due':158,'spin-max-clock':159,'wrong-session-wake':159,'ignore-feature':152,'ignore-barrier':156,'ignore-selected':156,'skip-mutation':155,'skip-alias-proof':156,'skip-epoch-close':164,'wrap-mutation':164,'unbounded-revoke':163,'skip-credited-revoke':163,'rewrite-frozen-end':165,'skip-debt-reciprocal':166,'allocate-in-remove':170,'native-stop-in-remove':171,'global-lookup':174,'reuse-debt-row':174,'early-duplicate-match':182,'shareclock':163}
SCENARIOS={m:('full'if m in ('global-lookup','reuse-debt-row')else 'saturation'if m in ('skip-epoch-close','wrap-mutation','skip-credited-revoke')else 'capacity'if m in ('unbounded-revoke','skip-debt-reciprocal','early-duplicate-match','shareclock')else 'ended'if m=='rewrite-frozen-end'else 'standard')for m in CODES}
def build(folder,windows=False,mutation=None,scenario=None):
 scenario=scenario or SCENARIOS.get(mutation,'standard')
 if mutation and scenario!=SCENARIOS[mutation]:raise ValueError(('mutation scenario',mutation,scenario))
 sys.path.insert(0,str(ROOT/'tests/faults'));import ext_running_session_build as native
 s=importlib.util.spec_from_file_location('remove_ticket_base',ROOT/'tests/runtime-ticket.py');ticket=importlib.util.module_from_spec(s);s.loader.exec_module(ticket)
 previous=native.link
 def link(target,replacements,win):
  source=replacements['fixture.s'];marker='    call tt_cases\n';assert source.count(marker)==1
  source=source.replace(marker,marker+'    call rr_cases\n'+('    call rr_many_cases\n'if scenario in ('capacity','saturation')else '    call rr_full_cases\n'if scenario=='full'else''),1)
  if scenario in ('capacity','saturation','ended','full'):
   start=source.index('    mov qword ptr [rip + rts_stage], 210\n');end=source.index('    mov qword ptr [rip + rts_stage], 213\n',start);source=source[:start]+source[end:]
  if scenario=='diagnostic':
   marker='.equ RTS_TEST_SCENARIO, 0';assert source.count(marker)==1;source=source.replace(marker,'.equ RTS_TEST_SCENARIO, 2',1)
  source+='\n.equ RR_TEST_ENDED, '+str(int(scenario=='ended'))+'\n.equ RR_TEST_SATURATION, '+str(int(scenario=='saturation'))+'\n.equ RR_TEST_DIAG, '+str(int(scenario=='diagnostic'))+'\n.equ RR_TEST_QUIESCING, '+str(int(scenario=='quiescing'))+'\n.equ RR_TEST_LARGE, '+str(int(scenario=='large'))+'\n'
  replacements['fixture.s']=source+(ROOT/'tests/runtime_remove_cases.inc').read_text()+('\n'+(ROOT/'tests/runtime_remove_capacity_cases.inc').read_text()if scenario in ('capacity','saturation','full')else'')+('\n'+(ROOT/'tests/runtime_remove_full_cases.inc').read_text()if scenario=='full'else'')
  marker='FN mem_alloc_try\n';text=replacements['fixture.s'];assert text.count(marker)==1;replacements['fixture.s']=text.replace(marker,marker+'    cmp qword ptr [rip + rr_work_watch], 0\n    je 992f\n    mov qword ptr [rip + rr_stage], 170\n    jmp rr_fail\n992:\n',1)
  path='src/app/ext.s';text=replacements.get(path,(ROOT/path).read_text());marker='FN ext_stop\n';assert text.count(marker)==1;replacements[path]=text.replace(marker,'FN rr_real_ext_stop\n',1)
  path='src/app/extruntime.s';text=(ROOT/path).read_text();old='FN ext_runtime_release_deferred\n';assert text.count(old)==1;replacements[path]=text.replace(old,'FN rr_real_ro_release\n',1)
  if mutation:
   file,old,new={
    'early-duplicate-match':('extruntimeremove','    mov [rsp + 24], rax\n.Lrm_next:','    mov [rsp + 24], rax\n    cmp qword ptr [r14 + RTS_nlive], 64\n    jne .Lrm_next\n    mov rax, [r14 + RTS_nlive]\n    mov [rsp + 32], rax\n    jmp .Lrm_scanned\n.Lrm_next:'),
    'shareclock':('extruntimerevoke','1:  mov [rbx + RT_revokeCursor], rax','1:  mov [rbx + RT_revokeCursor], rax\n    mov [rbx + RT_replyCursor], rax'),
    'global-lookup':('extruntimeremove','    mov rax, [r14 + RTS_liveHead]','    mov rax, [rbx + RT_liveHead]'),
    'reuse-debt-row':('extruntimerow','    mov qword ptr [r10 + RTR_state], RTR_DEBT','    mov qword ptr [r10 + RTR_state], RTR_DEBT\n    cmp qword ptr [rdi + RT_nlive], 64\n    jbe 991f\n    mov [rdi + RT_freeHead], rsi\n991:'),
    'skip-revoke':('extruntimerow','    mov qword ptr [rax + RO_live], 0','    nop'),
    'alias-global-neighbors':('extruntimerow','    cmp rcx, rdx\n    je .Lruc_bad','    nop'),
    'consume-refused-drop':('extruntimedebt','    cmp rdx, 1\n    je .Lrds_consumed','    jmp .Lrds_consumed'),
    'ignore-retry-due':('extruntimedebt','    cmp rax, r12\n    ja .Lrds_due','    nop'),
    'spin-max-clock':('extruntimedebt','4:  mov qword ptr [r8 + RTR_debtDue], -1','4:  mov [r8 + RTR_debtDue], r12'),
    'wrong-session-wake':('extruntimedebt','    cmp [r8 + RTR_session], r13\n    jne .Lrdw_bad','    nop'),
    'ignore-feature':('extruntimeremove','    jz .Lrm_unsupported','    nop'),
    'ignore-barrier':('extruntimeremove','    cmp qword ptr [rbx + RT_barrierState], RTB_QUIESCING\n    ja .Lrm_busy','    nop'),
    'ignore-selected':('extruntimeremove','    cmp rax, r13\n    je .Lrm_busy','    nop'),
    'skip-mutation':('extruntimeremove','    inc qword ptr [rbx + RT_mutation]','    nop'),
    'skip-alias-proof':('extruntimeremove','    call rt_admit_source_check','    xor eax, eax'),
    'skip-epoch-close':('extruntimeremove','    call rt_table_revoke_all_pure','    nop'),
    'wrap-mutation':('extruntimeremove','    je .Lrm_saturated','    nop'),
    'unbounded-revoke':('extruntimerevoke','    cmp r14, r13','    cmp r14, 128'),
    'skip-credited-revoke':('extruntimerevoke','    cmp qword ptr [r8 + RTS_state], RTS_DRAINING\n    jne .Lrrv_loop','    cmp qword ptr [r8 + RTS_state], RTS_DRAINING\n    jne .Lrrv_loop\n    test qword ptr [r8 + RTS_flags], RTSF_OP_CREDIT\n    jnz .Lrrv_loop'),
    'rewrite-frozen-end':('extruntimesession','    mov qword ptr [r15 + RTS_grantSession], 0','    mov qword ptr [r15 + RTS_grantSession], 0\n    mov byte ptr [r15 + RTS_reply], 120'),
    'skip-debt-reciprocal':('extruntimedebt','    cmp [r8 + RTR_prev], r12\n    jne .Lrdc_bad','    nop'),
    'allocate-in-remove':('extruntimeremove','    mov qword ptr [r14 + RTS_opKind], RTQ_UNREGISTER','    mov qword ptr [r14 + RTS_opKind], RTQ_UNREGISTER\n    mov edi, 16\n    call mem_alloc_try'),
    'native-stop-in-remove':('extruntimeremove','    mov qword ptr [r14 + RTS_opKind], RTQ_UNREGISTER','    mov qword ptr [r14 + RTS_opKind], RTQ_UNREGISTER\n    mov rdi, [rbx + RT_stableExtBase]\n    call ext_stop'),
   }[mutation]
   path='src/app/'+file+'.s';text=(ROOT/path).read_text();assert text.count(old)==1,(mutation,old);replacements[path]=text.replace(old,new,1)
  return previous(target,replacements,win)
 native.link=link
 try:return ticket.build(folder,windows)
 finally:native.link=previous

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--mutation',choices=CODES);p.add_argument('--negative-controls',action='store_true');p.add_argument('--scenario',choices=['standard','diagnostic','quiescing','large','capacity','saturation','ended','full']);a=p.parse_args()
 if a.exe and a.build_only:p.error('exe and build-only are exclusive')
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('Wine requires exact prebuilt and owned drive root')
 if a.negative_controls and(a.exe or a.mutation or a.scenario):p.error('controls build their exact variants')
 drive=a.wine_drive_root.resolve()if a.wine else None
 with tempfile.TemporaryDirectory(prefix='rhun-runtime-remove-',dir=drive)as temporary:
  variants=[(a.scenario or SCENARIOS.get(a.mutation,'standard'),a.mutation)]if a.exe or a.mutation or a.scenario else[(name,None)for name in ['standard','diagnostic','quiescing','large','capacity','saturation','ended','full']]
  if a.negative_controls:variants.extend((SCENARIOS[m],m)for m in CODES)
  for scenario,mutation in variants:
   label=mutation or scenario;exe=a.exe or build((a.build_only or Path(temporary)/'bin')/label,os.name=='nt'or a.windows_build or bool(a.wine),mutation,scenario)
   if a.build_only:print('built runtime removal',label,exe,flush=True);continue
   native='C:/'+Path(temporary).relative_to(drive).as_posix()if drive else str(Path(temporary).resolve())
   with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native],timeout=90,output_bound=0,error_bound=4096)as f:
    out,err=f.finish();assert(f.process.returncode,out,err)==(CODES.get(mutation,0),b'',b''),(label,f.process.returncode,out,err)
   print('ok owned runtime removal and row retirement',label,flush=True)
if __name__=='__main__':main()
