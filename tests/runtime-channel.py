#!/usr/bin/env python3
"""Retained typed reply-channel authority, independent of action revocation."""
import argparse,importlib.util,os,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CODES={'skip-bound':243,'skip-keeper':237,'timestamp-dead':228,'action-gate':222,'unknown-write':229,'wrong-count':244,'raw-error-dead':248,'byte-quota':246,'missing-nonblock':249}
def build(folder,windows=False,long=False,mutation=None):
 sys.path.insert(0,str(ROOT/'tests/faults'))
 import ext_running_session_build as native
 previous=native.link
 def link(target,replacements,win):
  text=replacements['fixture.s'];marker='    mov qword ptr [rip + rts_stage], 210\n';assert text.count(marker)==1
  text=text.replace(marker,'    call rch_cases\n'+marker,1)+'\n'+(ROOT/'tests/runtime_channel_cases.inc').read_text()
  replacements['fixture.s']=text+'\n'+(ROOT/'tests/runtime_channel_transport_cases.inc').read_text()
  for path in ['src/app/extenqueue.s','src/app/extflush.s']:
   source=(ROOT/path).read_text()
   if path.endswith('extenqueue.s'):
    assert source.count('call mem_alloc_try')==1;source=source.replace('call mem_alloc_try','call rch_alloc')
   else:
    assert source.count('SYS SYS_write')==1 and source.count('SYS SYS_fcntl')==1
    source=source.replace('SYS SYS_write','call rch_write').replace('SYS SYS_fcntl','call rch_fcntl').replace('call time_ms','call rch_time')
   source=source.replace('call watch_set_events','call rch_watch');replacements[path]=source
  if mutation:
   path='src/app/extflush.s'if mutation in ['raw-error-dead','byte-quota','missing-nonblock']else'src/app/extruntimechannel.s'
   source=replacements.get(path,(ROOT/path).read_text())
   old,new={
    'skip-bound':('1:  test qword ptr [r14 + RTS_flags], RTSF_CHANNEL_BOUND\n    jz .Lrch_stale','1:  nop'),
    'skip-keeper':('    cmp [r15 + EXT_keeper], rax\n    jne .Lrch_stale','    nop'),
    'timestamp-dead':('    cmp qword ptr [r15 + EXT_in_closed_at], 0\n    jne .Lrch_pending','    cmp qword ptr [r15 + EXT_in_closed_at], 0\n    jne .Lrch_closed'),
    'action-gate':('    xor eax, eax\n    mov rdx, r15','    mov rdi, r15\n    call ext_can_act\n    test eax, eax\n    jz .Lrch_stale\n    xor eax, eax\n    mov rdx, r15'),
    'unknown-write':('    cmp dword ptr [r15 + EXT_host_cleanup_mask], 0\n    jne .Lrch_pending','    nop'),
    'wrong-count':('    cmp qword ptr [rbx + RT_stableExtCount], RT_SLOT_COUNT\n    jne .Lrch_stale','    nop'),
    'raw-error-dead':('    mov r14, rax\n    test r14, r14','    mov r14, -32\n    test r14, r14'),
    'byte-quota':('    mov r12, rcx','    mov r12d, 65536'),
    'missing-nonblock':('    test eax, O_NONBLOCK\n    jz .Lef_nonblock','    test eax, O_NONBLOCK\n    nop'),
   }[mutation]
   assert source.count(old)==1,(mutation,source.count(old));replacements[path]=source.replace(old,new,1)
  return previous(target,replacements,win)
 native.link=link
 try:
  spec=importlib.util.spec_from_file_location('channel_session',ROOT/'tests/runtime-service-session.py');session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)
  return session.build(folder,windows,long=long)
 finally:native.link=previous

def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.wine and(not a.exe or not a.wine_drive_root):p.error('--wine requires exact --exe and --wine-drive-root')
 if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
 if a.negative_controls and(a.exe or a.mutation):p.error('negative controls build their own unambiguous variants')
 windows=os.name=='nt'or a.windows_build or bool(a.wine);drive=a.wine_drive_root.resolve()if a.wine else None
 variants=[('baseline',False,None),('maximum',True,None)]
 if a.mutation:variants=[(a.mutation,False,a.mutation)]
 elif a.negative_controls:variants.extend((m,False,m)for m in CODES)
 if a.exe:variants=[('prebuilt',False,a.mutation)]
 with tempfile.TemporaryDirectory(prefix='rhun-runtime-channel-',dir=drive)as tmp:
  for label,long,mutation in variants:
   exe=a.exe or build((a.build_only or Path(tmp)/'bin')/label,windows,long,mutation)
   if a.build_only:print('built',label,exe,flush=True);continue
   native='C:/'+Path(tmp).relative_to(drive).as_posix()if drive else str(Path(tmp).resolve())
   with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native],timeout=45,output_bound=0,error_bound=4096)as f:
    out,err=f.finish();assert f.process.returncode==CODES.get(mutation,0) and not out and not err,(label,f.process.returncode,out,err)
   print('ok retained runtime channel',label,flush=True)
if __name__=='__main__':main()
