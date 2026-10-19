#!/usr/bin/env python3
"""Native keeper ownership, unknown-close quarantine and checked-unmap retry."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,case,index=0,disposition=0,windows=False,mutation=None):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    memory=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN kcf_real_alloc\n').replace('    SYS SYS_munmap\n','    call kcf_munmap\n')
    assert memory.count('call kcf_munmap')==1
    core=(ROOT/'src/app/taskproc.s').read_text().replace('kp_slots: .zero',' .globl kp_slots\nkp_slots: .zero',1)
    old='    mov r13, rax\n    xor esi, esi';assert core.count(old)==1
    core=core.replace(old,'    mov r13, rax\n    mov rdi, rbx\n    call kcf_prepare_hook\n    xor esi, esi',1)
    replacements={'src/mem.s':memory,'src/app/taskproc.s':core,
        'src/sys.s':(ROOT/'src/sys.s').read_text().replace('FN time_ms\n','FN kcf_real_time_ms\n',1),
        'src/app/extvalidatepath.s':(ROOT/'src/app/extvalidatepath.s').read_text().replace('FN ext_root_close\n','FN kcf_real_root_close\n',1),
        'src/app/exthostnative.s':(ROOT/'src/app/exthostnative.s').read_text().replace('FN ext_fd_close_checked\n','FN kcf_real_fd_close\n',1)}
    if case==8:
        replacements['src/app/taskcleanup.s']=(ROOT/'src/app/taskcleanup.s').read_text().replace('API DeleteProcThreadAttributeList','call kcf_DeleteAttr',1)
    if mutation=='lost':
        source=(ROOT/'src/app/taskposix.s').read_text();a=source.index('FN kp_backend_abort\n');z=source.index('FN kp_backend_recover\n',a)
        old='    cmp qword ptr [rdi + KX_native_state], KN_OWNED';assert source[a:z].count(old)==1
        replacements['src/app/taskposix.s']=source[:a]+source[a:z].replace(old,'    cmp qword ptr [rdi + KX_native_state], KN_LOST',1)+source[z:]
    elif mutation=='backoff':
        source=(ROOT/'src/app/taskproc.s').read_text();old='7:  add rax, rax';assert source.count(old)==1
        replacements['src/app/taskproc.s']=source.replace(old,'7:  mov eax, 16',1).replace('kp_slots: .zero',' .globl kp_slots\nkp_slots: .zero',1)
    elif mutation:
        cleanup=(ROOT/'src/app/taskcleanup.s').read_text()
        old='2:  bt qword ptr [r12], r13\n    jc .Lkco_unknown';assert cleanup.count(old)==1
        replacements['src/app/taskcleanup.s']=cleanup.replace(old,'2:',1)
    fixture=f'.equ KCF_CASE, {case}\n.equ KCF_INDEX, {index}\n.equ KCF_DISP, {disposition}\n'+(ROOT/'tests/faults/keeper_cleanup.s').read_text()
    return builder.build(folder,fixture,replacements,windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--quick',action='store_true');a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    cases=[(5,0,0),(9,34,0),(0,0,0),(1,4,0),(2,4,2),(3,4,1),(4,4,2),(6,4,2)]
    indices=[0,4,5,6,7,15,16,25] if a.quick else range(26)
    cases += [(8,30,0)] if windows else [(7,0,0)]
    cases += [(10,i,d)for i in indices for d in (0,1,2)]
    cases += [(10,i,0)for i in range(26,35)]
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-cleanup-')as temporary:
        for case,index,disposition in cases:
            label=f'{case}-{index}-{disposition}'
            exe=build((a.build_only or Path(temporary))/label,case,index,disposition,windows)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==0 and not r.stdout and not r.stderr,(label,r)
            print('ok keeper-cleanup/'+label,flush=True)
        exe=build((a.build_only or Path(temporary))/'negative-unknown',10,4,2,windows,True)
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,r
            print('ok keeper-cleanup/negative-control/unknown-retry',flush=True)
        exe=build((a.build_only or Path(temporary))/'negative-backoff',9,34,0,windows,'backoff')
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=10)
            assert r.returncode==73,r
            print('ok keeper-cleanup/negative-control/backoff-cap',flush=True)
        if not windows:
            exe=build((a.build_only or Path(temporary))/'negative-lost',7,0,0,False,'lost')
            if not a.build_only:
                r=subprocess.run([str(exe)],capture_output=True,timeout=10)
                assert r.returncode==-9,r
                print('ok keeper-cleanup/negative-control/lost-pid-signal',flush=True)
if __name__=='__main__':main()
