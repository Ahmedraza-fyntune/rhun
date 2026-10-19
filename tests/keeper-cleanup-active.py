#!/usr/bin/env python3
"""Unknown output/control owners after INIT quarantine, never signal the live collector or read reused FD."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    fixture=(ROOT/'tests/task_keeper_test.s').read_text().replace('printf keeper"','printf keeper;sleep 5"',1)
    fixture=fixture.replace('    mov rdi, [rip + tkp_stage]\n    call sys_exit','    mov edi, 73\n    call sys_exit',1)
    old='    test eax, KP_FAILED\n    jnz .Ltkp_fail';assert fixture.count(old)==1;fixture=fixture.replace(old,'',1)
    old='1:  mov qword ptr [rip + tkp_stage], 3\n';assert old in fixture
    fixture=fixture.replace(old,old+'''    test dword ptr [rip + tkp_flags], KP_STARTED
    jz 90f
    cmp qword ptr [rip + kpo_calls], 0
    jne 90f
    mov rdi, [rip + tkp_handle]
    call kp_find
    mov [rip + kpo_owner], rax
    mov rbx, rax
    mov rax, [rbx + KPO_OFFSET]
    mov [rip + kpo_target], rax
.ifdef WINDOWS
    mov rdi, rax
    call win_fd
    mov rsi, rax
    lea rdi, [rip + kpo_record]
    mov edx, FD_SIZE
    call memcpy
.endif
    mov rdi, rbx
    mov esi, KPO_FIELD
    call kp_close_field
    cmp rax, -13
    jne .Ltkp_fail
    cmp rdx, 2
    jne .Ltkp_fail
    mov rax, [rip + kpo_target]
    cmp [rbx + KPO_OFFSET], rax
    jne .Ltkp_fail
.ifndef WINDOWS
    lea rdi, [rip + kpo_null]
    mov esi, O_RDONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js .Ltkp_fail
    mov r12, rax
    cmp rax, [rip + kpo_target]
    je 91f
    mov rdi, rax
    mov rsi, [rip + kpo_target]
    SYS SYS_dup2
    test rax, rax
    js .Ltkp_fail
    mov rdi, r12
    call kpo_real_close
91:
.endif
    mov rdi, rbx
    call kp_backend_abort
    cmp qword ptr [rip + kpo_signals], 0
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_stop
90:
''',1)
    fixture=fixture.replace('''    test rax, rax
    js .Ltkp_fail
    jz 11f
    add [rip + tkp_used], rax''','''    test rax, rax
    js 11f
    jz 11f
    add [rip + tkp_used], rax''',1)
    old='    cmp qword ptr [rip + tkp_eof], 0\n    jne .Ltkp_complete';assert old in fixture;fixture=fixture.replace(old,'    jmp .Ltkp_complete',1)
    a=fixture.index('    test r8d, r8d\n',fixture.index('.Ltkp_complete:'));z=fixture.index('    lea rdi, [rip + tkp_ok]\n',a)
    fixture=fixture[:a]+'''    cmp r8d, -13
    jne .Ltkp_fail
    cmp qword ptr [rip + kpo_calls], 1
    jne .Ltkp_fail
    cmp qword ptr [rip + kpo_reads], 0
    jne .Ltkp_fail
    cmp qword ptr [rip + kpo_signals], 0
    jne .Ltkp_fail
    mov rbx, [rip + kpo_owner]
    cmp qword ptr [rbx + KX_native_state], KN_REAPED
    jne .Ltkp_fail
    cmp qword ptr [rbx + KX_lifetime_ready], 1
    jne .Ltkp_fail
    mov rax, [rip + kpo_target]
    cmp [rbx + KPO_OFFSET], rax
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    call keeper_close_checked
    cmp rax, -13
    jne .Ltkp_fail
    cmp rdx, 2
    jne .Ltkp_fail
    mov rdi, [rip + tkp_handle]
    mov esi, KPO_FIELD
    call keeper_retry_known
    cmp rax, -22
    jne .Ltkp_fail
.ifdef WINDOWS
    mov rdi, [rip + kpo_target]
    call win_fd
    test rax, rax
    jz .Ltkp_fail
    mov rdi, rax
    lea rsi, [rip + kpo_record]
    mov edx, FD_SIZE
    call memeq
    test eax, eax
    jz .Ltkp_fail
.else
    mov rdi, [rip + kpo_target]
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js .Ltkp_fail
    mov rdi, [rip + kpo_target]
    call kpo_real_close
    mov rdi, [rbx + KX_target]
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    jne .Ltkp_fail
    mov rdi, [rbx + KX_target]
    neg rdi
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    jne .Ltkp_fail
.endif
'''+fixture[z:]
    if windows:
        fixture=fixture.replace('.include "rhun.inc"','.include "win.inc"',1)
        old='    cmp rax, 6\n    jne 7f\n    xor eax, eax';assert old in fixture
        fixture=fixture.replace(old,'    cmp rax, 6\n    jne 7f\n    mov ecx, 5000\n    call kpo_pause\n    xor eax, eax',1)
    fault=(ROOT/'tests/faults/keeper_cleanup_active.s').read_text()
    fixture=f'.equ KPO_FIELD,{2 if mode==0 else 0}\n.equ KPO_OFFSET,{"KX_output"if mode==0 else"KX_control"}\n'+fixture+'\n'+fault
    core=(ROOT/'src/app/taskproc.s').read_text();a=core.index('FN keeper_read\n');z=core.index('kp_parent_fail:\n',a)
    assert core[a:z].count('    SYS SYS_read')==1
    core=core[:a]+core[a:z].replace('    SYS SYS_read','    call kpo_read',1)+core[z:]
    relative='src/win/taskproc.s'if windows else'src/app/taskposix.s';source=(ROOT/relative).read_text();a=source.index('FN kp_backend_abort\n');z=source.index('FN kp_backend_recover\n',a)
    needle='    API TerminateProcess'if windows else'    SYS SYS_kill';assert source[a:z].count(needle)==1
    source=source[:a]+source[a:z].replace(needle,'    call kpo_signal',1)+source[z:]
    return builder.build(folder,fixture,{'src/app/taskproc.s':core,relative:source,'src/app/exthostnative.s':(ROOT/'src/app/exthostnative.s').read_text().replace('FN ext_fd_close_checked\n','FN kpo_real_close\n',1)},windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-active-')as folder:
        for mode in(0,1):
            exe=build((a.build_only or Path(folder))/str(mode),mode,windows)
            if a.build_only:continue
            r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
            assert r.returncode==0 and r.stdout+r.stderr==b'ok independent task keeper\n',(mode,r)
            print('ok keeper-cleanup-active/'+str(mode),flush=True)
if __name__=='__main__':main()
