#!/usr/bin/env python3
"""Actual granted session, owned registration bytes and role2 deferred supplier lifetime."""
import argparse,importlib.util,os,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
MUTATIONS={'skip-key':228,'skip-title':228,'skip-keys':228,'skip-ea':226,'lose-orphan':226,'skip-extent':230,'active-retire-guard':229}
def build(folder,windows=False,maximum=False,fault=0,mutation=None):
    sys.path.insert(0,str(ROOT/'tests/faults'))
    import ext_running_session_build as original
    spec=importlib.util.spec_from_file_location('session_for_ticket',ROOT/'tests/runtime-service-session.py');session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)
    real_link=original.link
    def link(target,replacements,win):
        source=replacements['fixture.s'];marker='    mov qword ptr [rip + rts_stage], 210\n';assert source.count(marker)==1
        source=source.replace(marker,'    call tt_cases\n'+marker,1)
        replacements['fixture.s']=source+'\n.equ TT_TEST_MAX, '+str(int(maximum))+'\n.equ TT_TEST_FAULT, '+str(fault)+'\n'+(ROOT/'tests/runtime_ticket_cases.inc').read_text()
        for name in ('extruntimeticket','extruntimeticketcheck'):
            path='src/app/'+name+'.s';replacements[path]=(ROOT/path).read_text()
        for path,symbol,new in [('src/mem.s','mem_alloc_try','tt_real_alloc'),('src/app/extprepareretirecustom.s','ext_prepare_retire_mark_custom_po','tt_real_mark'),('src/app/extprepareretirecustom.s','ext_prepare_retire_register_kind','tt_real_register'),('src/app/extprepareretirequeue.s','ext_prepare_owner_release_deferred','tt_real_eo_drop')]:
            text=replacements.get(path,(ROOT/path).read_text());old='FN '+symbol+'\n';assert text.count(old)==1,(path,symbol);replacements[path]=text.replace(old,'FN '+new+'\n',1)
        marker='    SYS SYS_munmap';assert replacements['src/mem.s'].count(marker)==1;replacements['src/mem.s']=replacements['src/mem.s'].replace(marker,'    call tt_unmap',1)
        if mutation:
            text=replacements['src/app/extruntimeticket.s']
            if mutation in ('skip-key','skip-title','skip-keys'):
                index={'skip-key':0,'skip-title':1,'skip-keys':2}[mutation];marker='    call memcpy\n';assert text.count(marker)==3;parts=text.split(marker);text=marker.join(parts[:index+1])+'    nop\n'+marker.join(parts[index+1:])
            elif mutation=='skip-ea':
                marker='    inc qword ptr [r15 + PO_refs]\n';assert text.count(marker)==1;text=text.replace(marker,'    nop\n',1)
            elif mutation=='lose-orphan':
                marker='    cmp rdx, 1\n    jne 3f\n    mov qword ptr [r13 + RTC_orphanEO], 0';assert text.count(marker)==1;text=text.replace(marker,marker.replace('    jne 3f\n',''),1)
            elif mutation=='skip-extent':
                marker='    cmp [rdi + RTT_fixedBytes], rcx\n    jne 9f';assert text.count(marker)==1;text=text.replace(marker,'    nop',1)
            elif mutation=='active-retire-guard':
                marker='    call rt_ticket_extent_check\n    test eax, eax\n    jz .Ltt_retire_bad';assert text.count(marker)==1;text=text.replace(marker,marker.replace('rt_ticket_extent_check','rt_ticket_is_owned'),1)
            replacements['src/app/extruntimeticket.s']=text
        return real_link(target,replacements,win)
    original.link=link
    try:return session.build(folder,windows,long=maximum)
    finally:original.link=real_link

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--negative-controls',action='store_true');p.add_argument('--fault',type=int,choices=range(9),default=0);p.add_argument('--mutation',choices=MUTATIONS);a=p.parse_args()
    if a.wine and(not a.exe or not a.wine_drive_root):p.error('--wine requires exact prebuilt --exe and --wine-drive-root')
    if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
    if a.fault and a.negative_controls and not a.exe:p.error('--fault and --negative-controls are exclusive')
    drive=a.wine_drive_root.resolve()if a.wine else None
    variants=[('small',False,0,None),('maximum',True,0,None)]+[('fault-'+str(n),n==8,n,None)for n in range(1,9)]
    if a.mutation:variants=[(a.mutation,a.mutation in ('skip-title','skip-keys'),4 if a.mutation=='lose-orphan'else 0,a.mutation)]
    elif a.fault:variants=[('fault-'+str(a.fault),a.fault==8,a.fault,None)]
    elif a.negative_controls:variants.extend((m,m in ('skip-title','skip-keys'),4 if m=='lose-orphan'else 0,m)for m in MUTATIONS)
    if a.exe:variants=[('prebuilt',False,a.fault,a.mutation)]
    with tempfile.TemporaryDirectory(prefix='rhun-runtime-ticket-',dir=drive)as temporary:
        for label,maximum,fault,mutation in variants:
            exe=a.exe or build((a.build_only or Path(temporary)/'bin')/label,os.name=='nt'or a.windows_build or bool(a.wine),maximum,fault,mutation)
            if a.build_only:print('built ticket',label,exe,flush=True);continue
            native='C:/'+Path(temporary).relative_to(drive).as_posix()if drive else str(Path(temporary).resolve())
            with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native],timeout=30,output_bound=0,error_bound=4096)as f:
                out,err=f.finish();expected=MUTATIONS[mutation]if mutation else 0;assert f.process.returncode==expected and not out and not err,(label,f.process.returncode,out,err)
            print('ok runtime ticket',label,flush=True)
if __name__=='__main__':main()
