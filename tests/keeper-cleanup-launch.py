#!/usr/bin/env python3
"""A real fork/CreateProcess success remains owned when subsequent scratch cleanup fails."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,disposition,windows=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    fixture=(ROOT/'tests/task_keeper_test.s').read_text()
    old='    call keeper_prepare\n    test rax, rax';assert fixture.count(old)==1
    fixture=fixture.replace(old,'''    call keeper_prepare
    cmp rdx, -13
    jne .Ltkp_fail
    cmp rcx, -13
    jne .Ltkp_fail
    test rax, rax''',1)
    old='    mov [rip + tkp_handle], rax\n';assert fixture.count(old)==1
    fixture=fixture.replace(old,old+'''    mov rdi, rax
    call kp_find
    test rax, rax
    jz .Ltkp_fail
    cmp qword ptr [rax + KX_native_state], KN_OWNED
    jne .Ltkp_fail
    cmp qword ptr [rax + KX_sent], 0
    jne .Ltkp_fail
    mov r13, rax
    mov qword ptr [rip + kcp_observe], 1
    mov rdi, r13
    call kp_backend_poll
    cmp qword ptr [r13 + KX_native_state], KN_OWNED
    jne .Ltkp_fail
    cmp dword ptr [r13 + KX_reaped], 0
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    test rax, rax
    jns .Ltkp_fail
    cmp rdx, KCP_BUSY_DISP
    jne .Ltkp_fail
    mov qword ptr [rip + kcp_observe], 0
''',1)
    a=fixture.index('    test eax, KP_FAILED\n',fixture.index('.Ltkp_loop:'));z=fixture.index('1:  mov qword ptr [rip + tkp_stage], 3\n',a)
    fixture=fixture[:a]+'''    test eax, KP_STARTED
    jnz .Ltkp_fail
'''+fixture[z:]
    # Failed pre-INIT service intentionally reports a drain failure instead of fabricating EOF.
    fixture=fixture.replace('''    test rax, rax
    js .Ltkp_fail
    jz 11f
    add [rip + tkp_used], rax''','''    test rax, rax
    js 11f
    jz 11f
    add [rip + tkp_used], rax''',1)
    a=fixture.index('    test r8d, r8d\n',fixture.index('.Ltkp_complete:'));z=fixture.index('    lea rdi, [rip + tkp_ok]\n',a)
    finish='''    cmp r8d, -13
    jne .Ltkp_fail
    test eax, KP_FAILED
    jz .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call kp_find
    test rax, rax
    jz .Ltkp_fail
    cmp qword ptr [rax + KX_native_state], KN_REAPED
    jne .Ltkp_fail
    cmp qword ptr [rax + KX_sent], 0
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -13
    jne .Ltkp_fail
    cmp rdx, KCP_DISP
    jne .Ltkp_fail
    cmp qword ptr [rip + tkp_used], 0
    jne .Ltkp_fail
    cmp qword ptr [rip + kcp_faults], 1
    jne .Ltkp_fail
'''
    if disposition==0:
        finish+='''    mov rdi, [rip + tkp_handle]
    mov esi, 7
    call keeper_retry_known
    test rax, rax
    jnz .Ltkp_fail
    cmp rdx, 1
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -13
    jne .Ltkp_fail
    cmp rdx, 1
    jne .Ltkp_fail
'''
    fixture=fixture[:a]+finish+fixture[z:]
    fault=(ROOT/'tests/faults/keeper_cleanup_launch.s').read_text();fault=fault[fault.index('.bss'): ]
    if windows:fixture=fixture.replace('.include \"rhun.inc\"','.include \"win.inc\"',1)
    fixture=f'.equ KCP_DISP, {disposition}\n.equ KCP_BUSY_DISP, {2 if disposition==2 else 0}\n'+fixture+'\n'+fault
    relative='src/win/taskproc.s'if windows else'src/app/taskposix.s';source=(ROOT/relative).read_text()
    old='FN kp_backend_prepare\n';assert source.count(old)==1
    source=source.replace(old,old+'    call kcp_capture\n',1)
    a=source.index('FN kp_backend_poll\n');z=source.index('FN kp_backend_abort\n',a)
    needle='    API WaitForSingleObject'if windows else'    SYS SYS_wait4'
    assert source[a:z].count(needle)==1
    source=source[:a]+source[a:z].replace(needle,'    call kcp_wait',1)+source[z:]

    return builder.build(folder,fixture,{relative:source,'src/app/exthostnative.s':(ROOT/'src/app/exthostnative.s').read_text().replace('FN ext_fd_close_checked\n','FN kcp_real_fd_close\n',1)},windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-launch-')as folder:
        for disposition in(0,1,2):
            exe=build((a.build_only or Path(folder))/str(disposition),disposition,windows)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
            assert r.returncode==0 and r.stdout+r.stderr==b'ok independent task keeper\n',(disposition,r)
            print('ok keeper-cleanup-launch/'+str(disposition),flush=True)
if __name__=='__main__':main()
