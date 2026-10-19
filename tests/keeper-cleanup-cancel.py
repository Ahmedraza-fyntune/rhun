#!/usr/bin/env python3
"""A consumed-negative control close cannot strand a valid collected no-target terminal."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False,negative=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    fixture=(ROOT/'tests/task_keeper_test.s').read_text().replace('    mov rdi, [rip + tkp_stage]\n    call sys_exit','    mov edi, 73\n    call sys_exit',1)
    old='    mov [rip + tkp_handle], rax\n';assert fixture.count(old)==1
    fixture=fixture.replace(old,old+'''    mov rdi, rax
    call kp_find
    mov [rip + kcx_owner], rax
    mov rdi, [rip + tkp_handle]
    call keeper_stop
    cmp rax, -13
    jne .Ltkp_fail
''',1)
    a=fixture.index('    test eax, KP_FAILED\n',fixture.index('.Ltkp_loop:'));z=fixture.index('1:  mov qword ptr [rip + tkp_stage], 3\n',a)
    fixture=fixture[:a]+'''    test eax, KP_STARTED
    jnz .Ltkp_fail
'''+fixture[z:]
    a=fixture.index('    test r8d, r8d\n',fixture.index('.Ltkp_complete:'));z=fixture.index('    lea rdi, [rip + tkp_ok]\n',a)
    fixture=fixture[:a]+'''    test eax, KP_FAILED
    jz .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call kp_find
    test rax, rax
    jz .Ltkp_fail
    cmp qword ptr [rax + KX_cleanup], -13
    jne .Ltkp_fail
    cmp qword ptr [rax + KX_native_state], KN_REAPED
    jne .Ltkp_fail
    cmp dword ptr [rax + KX_helper_exit], 0
    jne .Ltkp_fail
    cmp qword ptr [rax + KX_status_eof], 1
    jne .Ltkp_fail
    cmp qword ptr [rax + KX_lifetime_ready], 1
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -13
    jne .Ltkp_fail
    cmp rdx, 1
    jne .Ltkp_fail
    cmp qword ptr [rip + tkp_used], 0
    jne .Ltkp_fail
    cmp qword ptr [rip + kcx_calls], 1
    jne .Ltkp_fail
    cmp qword ptr [rip + kcx_checked], 1
    jne .Ltkp_fail
'''+fixture[z:]
    fixture+='''
.bss
kcx_owner: .quad 0
kcx_calls: .quad 0
kcx_checked: .quad 0
.text
FN kcx_read
    mov rax, [rip + kcx_owner]
    test dword ptr [rax + KX_wireflags], KP_DONE
    jz 1f
    cmp qword ptr [rip + kcx_checked], 0
    jne 1f
    cmp qword ptr [rax + KX_native_state], KN_REAPED
    jne 2f
    cmp qword ptr [rax + KX_protocol_bad], 0
    jne .Ltkp_fail
    cmp qword ptr [rax + KX_lifetime_ready], 0
    jne .Ltkp_fail
    inc qword ptr [rip + kcx_checked]
1:  SYS SYS_read
    ret
2:  mov rax, -11
    ret

FN ext_fd_close_checked
    PROLOGUE
    mov rbx, rdi
    mov rax, [rip + kcx_owner]
    test rax, rax
    jz 1f
    cmp rbx, [rax + KX_control]
    jne 1f
    cmp qword ptr [rip + kcx_calls], 0
    jne 1f
    inc qword ptr [rip + kcx_calls]
    call kcx_real_close
    test rax, rax
    jnz .Ltkp_fail
    cmp rdx, 1
    jne .Ltkp_fail
    mov rax, -13
    mov edx, 1
    EPILOGUE
1:  mov rdi, rbx
    call kcx_real_close
    EPILOGUE
'''
    if windows:fixture=fixture.replace('.include "rhun.inc"','.include "win.inc"',1)
    core=(ROOT/'src/app/taskproc.s').read_text();a=core.index('FN keeper_poll\n');z=core.index('.Lkp_poll_native:',a)
    assert core[a:z].count('    SYS SYS_read')==1
    core=core[:a]+core[a:z].replace('    SYS SYS_read','    call kcx_read',1)+core[z:]
    if negative:
        old='    cmp qword ptr [rbx + KX_status_failed], 0\n    je .Lkp_poll_result'
        assert core.count(old)==1
        core=core.replace(old,'',1)
    return builder.build(folder,fixture,{'src/app/taskproc.s':core,'src/app/exthostnative.s':(ROOT/'src/app/exthostnative.s').read_text().replace('FN ext_fd_close_checked\n','FN kcx_real_close\n',1)},windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-cancel-')as folder:
        exe=build((a.build_only or Path(folder))/'positive',windows)
        if a.build_only:
            build(a.build_only/'negative-eager-recovery',windows,True)
            return
        r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
        assert r.returncode==0 and r.stdout+r.stderr==b'ok independent task keeper\n',r
        print('ok keeper-cleanup-cancel/consumed-negative-control',flush=True)
        exe=build((a.build_only or Path(folder))/'negative-eager-recovery',windows,True)
        r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
        assert r.returncode==73,r
        print('ok keeper-cleanup-cancel/negative-control/eager-recovery',flush=True)
if __name__=='__main__':main()
