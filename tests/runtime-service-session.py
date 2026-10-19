#!/usr/bin/env python3
"""Real retained EA/HI session capture, accepted handshake, immediate revocation and reset."""
import argparse,os,sys,tempfile
from pathlib import Path
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
MUTATIONS={'skip-hi-overflow':202,'skip-ea-overflow':203,'skip-barrier':206,'skip-grant':208,'skip-revoke':212,'skip-reset':215}
def build(folder,windows=False,mutation=None,long=False,scenario=0):
    sys.path.insert(0,str(ROOT/'tests/faults'))
    import ext_running_session_build as b
    real_link=b.link
    def link(target,replacements,win):
        source=replacements['fixture.s']
        marker='    jmp ext_activation_host_running_bind_check\n'
        assert source.count(marker)==1
        replacements['fixture.s']=source.replace(marker,'    jmp rts_bind_hook\n',1)+'\n.equ RTS_TEST_SCENARIO, '+str(scenario)+'\n'+(ROOT/'tests/runtime_service_session_cases.inc').read_text()
        for path,symbol,real in [('src/app/extactivation.s','ext_activation_owner_release','rts_real_ea_release'),('src/app/exthostidentity.s','ext_host_identity_release','rts_real_hi_release')]:
            text=(ROOT/path).read_text();marker='FN '+symbol+'\n';assert text.count(marker)==1;replacements[path]=text.replace(marker,'FN '+real+'\n',1)
        for name in ('extruntimeservice','extruntimesession','extruntimespan','extruntimepromptrevoke'):
            path='src/app/'+name+'.s';replacements[path]=(ROOT/path).read_text()
        if mutation:
            text=(ROOT/'src/app/extruntimesession.s').read_text()
            old,new={
                'skip-hi-overflow':('    cmp qword ptr [rax + PO_refs], -1\n    je .Lrsb_overflow','    nop'),
                'skip-ea-overflow':('    cmp qword ptr [r13 + PO_refs], -1\n    je .Lrsb_overflow','    nop'),
                'skip-barrier':('    cmp qword ptr [rbx + RT_barrierState], 0\n    jne .Lrsb_busy','    nop'),
                'skip-grant':('    cmp [r14 + RTS_grantSession], r13\n    jne .Lrsc_stale','    nop'),
                'skip-revoke':('    mov qword ptr [r15 + RTS_grantSession], 0','    nop'),
                'skip-reset':('    or rax, [r13 + EXT_wq + SB_len]','    nop'),
            }[mutation]
            assert text.count(old)==1,(mutation,text.count(old));replacements['src/app/extruntimesession.s']=text.replace(old,new,1)
        return real_link(target,replacements,win)
    b.link=link
    try:return b.build(folder,windows,long=long)
    finally:b.link=real_link

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--negative-controls',action='store_true');p.add_argument('--exe',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--mutation',choices=MUTATIONS);p.add_argument('--scenario',type=int,choices=range(3),default=0);a=p.parse_args()
    if a.wine and(not a.exe or not a.wine_drive_root):p.error('--wine requires exact --exe and --wine-drive-root')
    if a.exe and a.build_only:p.error('--exe and --build-only are exclusive')
    windows=os.name=='nt'or a.windows_build or bool(a.wine)
    drive=a.wine_drive_root.resolve()if a.wine else None
    variants=[('baseline',None,False,0),('maximum',None,True,0),('refused-drops',None,False,1),('consumed-diagnostic',None,False,2)]
    if a.mutation:variants=[(a.mutation,a.mutation,False,a.scenario)]
    elif a.negative_controls:variants.extend((m,m,False,0)for m in MUTATIONS)
    if a.exe:variants=[('prebuilt',a.mutation,False,a.scenario)]
    with tempfile.TemporaryDirectory(prefix='rhun-runtime-session-',dir=drive)as tmp:
        for label,mutation,long,scenario in variants:
            exe=a.exe or build((a.build_only or Path(tmp)/'bin')/label,windows,mutation,long,scenario)
            if a.build_only:print('built',label,exe,flush=True);continue
            native='C:/'+Path(tmp).relative_to(drive).as_posix()if drive else str(Path(tmp).resolve())
            with FixtureExchange(([a.wine]if a.wine else[])+[str(exe.resolve()),native],timeout=30,output_bound=0,error_bound=4096)as f:
                out,err=f.finish();expected=MUTATIONS[mutation]if mutation else 0
                assert f.process.returncode==expected and not out and not err,(label,f.process.returncode,out,err)
            print('ok runtime session',label,flush=True)
if __name__=='__main__':main()
