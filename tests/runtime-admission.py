#!/usr/bin/env python3
"""Real granted session, operation credit, FIFO reservation and checked cancellation."""
import argparse,importlib.util,os,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={'late-credit':241,'skip-reservation':242,'cancel-without-check':243,'lose-orphan':244,'duplicate-no-stop':245,'rewrite-frozen':246,'extra-validation':250,'wrong-oom':244,'skip-ext-alias':248,'skip-ea-alias':248,'skip-hi-alias':248,'skip-eo-alias':248,'skip-fifo-shift':249}
def build(folder,windows=False,fault=0,mutation=None):
 sys.path.insert(0,str(ROOT/'tests/faults'));import ext_running_session_build as original
 spec=importlib.util.spec_from_file_location('ticket_for_admission',ROOT/'tests/runtime-ticket.py');ticket=importlib.util.module_from_spec(spec);spec.loader.exec_module(ticket)
 real_link=original.link
 def link(target,replacements,win):
  source=replacements['fixture.s'];marker='    call tt_cases\n';assert source.count(marker)==1
  source=source.replace(marker,marker+'    call ra_cases\n',1)
  marker='FN mem_alloc_try\n';assert source.count(marker)==1
  source=source.replace(marker,marker+'    cmp qword ptr [rip + ra_credit_watch], 0\n    je 991f\n    mov rax, [rip + rts_table]\n    mov rax, [rax + RT_slots + 17 * RT_SLOT_SIZE + RTS_flags]\n    and eax, RTSF_OP_CREDIT | RTSF_ID_IN_USE\n    cmp eax, RTSF_OP_CREDIT | RTSF_ID_IN_USE\n    jne ra_alloc_fail\n991:\n',1)
  replacements['fixture.s']=source+'\n.equ RA_TEST_FAULT, '+str(fault)+'\n'+(ROOT/'tests/runtime_admission_cases.inc').read_text()+'\n'+(ROOT/'tests/runtime_admission_fifo_cases.inc').read_text()
  for name in ('extruntimeadmit','extruntimecredit','extruntimeterminal'):
   path='src/app/'+name+'.s';replacements[path]=(ROOT/path).read_text()
  path='src/app/extruntimeticketcheck.s';text=replacements[path];old='FN rt_ticket_request_check\n';assert text.count(old)==1;replacements[path]=text.replace(old,old+'    inc qword ptr [rip + ra_validation_count]\n',1)
  if mutation:
   path='src/app/'+('extruntimecredit'if mutation=='duplicate-no-stop'else'extruntimeterminal'if mutation=='rewrite-frozen'else'extruntimeadmit')+'.s';text=replacements[path]
   if mutation=='skip-eo-alias':
    path='src/app/extruntimespan.s';text=(ROOT/path).read_text();head,tail=text.split('FN rt_output_disjoint_po\n',1);pos=tail.rfind('    call rt_spans_disjoint\n');assert pos>=0;tail=tail[:pos]+tail[pos:].replace('    call rt_spans_disjoint\n','    xor eax, eax\n',1);replacements[path]=head+'FN rt_output_disjoint_po\n'+tail
   elif mutation.startswith('skip-')and mutation.endswith('-alias'):
    path='src/app/extruntimeadmit.s';text=replacements[path];head,tail=text.split('FN rt_admit_span_check\n',1)
    if mutation=='skip-ext-alias':
     old='    call rt_spans_disjoint\n';assert tail.count(old)==1;tail=tail.replace(old,'    xor eax, eax\n',1)
    else:
     old='    call rt_output_disjoint_po\n';parts=tail.split(old);assert len(parts)==4;index=1 if mutation=='skip-ea-alias'else 2;tail=old.join(parts[:index+1])+'    xor eax, eax\n'+old.join(parts[index+1:])
    replacements[path]=head+'FN rt_admit_span_check\n'+tail
   else:
    old,new={
     'late-credit':('    call rt_credit_begin\n','    xor eax, eax\n    mov edx, 1\n'),
     'skip-reservation':('    inc qword ptr [r14 + RTS_nreserved]\n','    nop\n'),
     'cancel-without-check':('    call rt_reply_freeze_check\n','    xor eax, eax\n'),
     'lose-orphan':('    mov [r14 + RTS_orphanEO], rax\n','    mov qword ptr [r14 + RTS_orphanEO], 0\n'),
     'duplicate-no-stop':('    call rt_session_end\n','    nop\n'),
     'rewrite-frozen':('    jnz .Lrf_already\n','    nop\n'),
     'extra-validation':('    call rt_ticket_create_checked\n','    call rt_ticket_create\n'),
     'skip-fifo-shift':('    mov [r11 + r8*8], rax\n','    nop\n'),
     'wrong-oom':('    mov r15d, RTRSP_OOM\n','    mov r15d, RTRSP_BUSY\n')}[mutation]
    assert text.count(old)==1,(mutation,text.count(old));replacements[path]=text.replace(old,new,1)
  return real_link(target,replacements,win)
 original.link=link
 try:return ticket.build(folder,windows)
 finally:original.link=real_link

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--fault',type=int,choices=range(8),default=0);p.add_argument('--mutation',choices=CODES);p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('Wine requires exact prebuilt exe and owned drive root')
 variants=[('baseline',0,None)]+[('fault-'+str(i),i,None)for i in range(1,8)]
 if a.mutation:variants=[(a.mutation,4 if a.mutation=='lose-orphan'else 1 if a.mutation=='wrong-oom'else 0,a.mutation)]
 elif a.fault:variants=[('fault-'+str(a.fault),a.fault,None)]
 elif a.negative_controls:variants.extend((m,4 if m=='lose-orphan'else 1 if m=='wrong-oom'else 0,m)for m in CODES)
 if a.exe:variants=[('prebuilt',a.fault,a.mutation)]
 drive=a.wine_drive_root.resolve()if a.wine else None
 with tempfile.TemporaryDirectory(prefix='rhun-runtime-admission-',dir=drive)as temporary:
  for label,fault,mutation in variants:
   exe=a.exe or build((a.build_only or Path(temporary)/'bin')/label,os.name=='nt'or a.windows_build or bool(a.wine),fault,mutation)
   if a.build_only:print('built admission',label,exe,flush=True);continue
   native='C:/'+Path(temporary).relative_to(drive).as_posix()if drive else str(Path(temporary).resolve())
   with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native],timeout=30,output_bound=0,error_bound=4096)as f:
    out,err=f.finish();expected=CODES[mutation]if mutation else 0
    assert(f.process.returncode,out,err)==(expected,b'',b''),(label,f.process.returncode,out,err)
   print('ok runtime admission',label,flush=True)
if __name__=='__main__':main()
