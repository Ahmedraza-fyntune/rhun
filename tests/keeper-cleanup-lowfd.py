#!/usr/bin/env python3
"""Eight actual keeper lifetimes reuse exact FD/allocation census under limit32."""
import importlib.util, resource, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    source=(ROOT/'tests/task_keeper_test.s').read_text()
    old='    mov qword ptr [rip + tkp_stage], 1\n';assert source.count(old)==1
    source=source.replace(old,'''    call kcl_census
    mov [rip + kcl_basefds], rax
    mov rax, [rip + g_mem_live]
    mov [rip + kcl_basemem], rax
.Lkcl_again:
    mov qword ptr [rip + tkp_started], 0
    mov qword ptr [rip + tkp_eof], 0
    mov qword ptr [rip + tkp_used], 0
'''+old,1)
    old='    lea rdi, [rip + tkp_ok]\n';assert source.count(old)==1
    source=source.replace(old,'''    call kcl_census
    cmp rax, [rip + kcl_basefds]
    jne .Ltkp_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + kcl_basemem]
    jne .Ltkp_fail
    inc qword ptr [rip + kcl_round]
    cmp qword ptr [rip + kcl_round], 8
    jb .Lkcl_again
'''+old,1)
    source+='''
.bss
kcl_basefds: .quad 0
kcl_basemem: .quad 0
kcl_round: .quad 0
.text
kcl_census:
    PROLOGUE
    xor r12d, r12d
    xor r13d, r13d
1:  mov rdi, r12
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    cmp rax, -9
    je 2f
    test rax, rax
    js .Ltkp_fail
    bts r13, r12
2:  inc r12
    cmp r12, 32
    jb 1b
    mov rax, r13
    EPILOGUE
'''
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-lowfd-')as folder:
        exe=builder.build(Path(folder),source,{})
        def limit():resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))
        result=subprocess.run([str(exe)],capture_output=True,timeout=60,preexec_fn=limit)
        assert result.returncode==0 and result.stdout+result.stderr==b'ok independent task keeper\n',result
        print('ok keeper-cleanup-lowfd/8-lifetimes-exact-census',flush=True)
if __name__=='__main__':main()
