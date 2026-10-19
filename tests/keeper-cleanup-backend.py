#!/usr/bin/env python3
"""Windows actual launch scratch gets one failed unmap pass and remains charged until due retry."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,negative=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    fixture=(ROOT/'tests/task_keeper_test.s').read_text().replace('.include "rhun.inc"','.include "win.inc"',1).replace('    mov rdi, [rip + tkp_stage]\n    call sys_exit','    mov edi, 73\n    call sys_exit',1)
    old='    call keeper_prepare\n    test rax, rax';assert fixture.count(old)==1
    fixture=fixture.replace(old,'''    mov rax, [rip + g_mem_live]
    mov [rip + kcb_base], rax
    mov qword ptr [rip + kcb_now], 1000
    call keeper_prepare
    jmp kcb_parent
    test rax, rax''',1)
    fixture=f'.equ KCB_MODE, {mode}\n'+fixture+'\n'+(ROOT/'tests/faults/keeper_cleanup_backend.s').read_text()
    source=(ROOT/'src/win/taskproc.s').read_text();old='FN kp_backend_prepare\n';assert source.count(old)==1
    source=source.replace(old,old+'    call kcb_capture\n',1)
    if mode in(1,3):
        a=source.index('kpw_spawn:\n');z=source.index('.section .rdata',a);block=source[a:z]
        old='    API CreateProcessW\n';assert block.count(old)==1
        block=block.replace(old,'    mov rax, -13\n    jmp .Lkpw_spawn_fail\n',1);source=source[:a]+block+source[z:]
    memory=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN kcb_real_alloc\n',1).replace('    SYS SYS_munmap\n','    call kcb_munmap\n',1)
    core=(ROOT/'src/app/taskproc.s').read_text()
    if negative:
        old='    mov qword ptr [rbx + KX_cleanup_skip_once], 1'
        assert core.count(old)==1
        core=core.replace(old,'',1)
    return builder.build(folder,fixture,{'src/app/taskproc.s':core,'src/win/taskproc.s':source,'src/mem.s':memory,
        'src/sys.s':(ROOT/'src/sys.s').read_text().replace('FN time_ms\n','FN kcb_real_time_ms\n',1)},True)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    if not(a.wine or a.windows_build or os.name=='nt'):p.error('Windows backend fixture requires --wine, --windows-build or native Windows')
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-backend-')as folder:
        for mode in(0,1,3):
            exe=build((a.build_only or Path(folder))/str(mode),mode)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
            assert r.returncode==0 and r.stdout+r.stderr==b'ok independent task keeper\n',(mode,r)
            print('ok keeper-cleanup-backend/'+str(mode),flush=True)
        exe=build((a.build_only or Path(folder))/'negative-operation-skip',3,True)
        if not a.build_only:
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
            assert r.returncode==73,r
            print('ok keeper-cleanup-backend/negative-control/operation-skip',flush=True)
if __name__=='__main__':main()
