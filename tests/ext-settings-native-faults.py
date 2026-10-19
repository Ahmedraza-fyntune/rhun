#!/usr/bin/env python3
"""Deterministic capsule construction, pending-I/O and mandatory cleanup failures."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False,mutation=None):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    core=(ROOT/'src/app/extsettingsnative.s').read_text().replace('FN ext_settings_native_free\n','FN ecnf_real_free\n')
    if mutation=='pending':
        old='    cmp qword ptr [rbx + ECN_operation], 0\n    jne .Lecn_free_busy';assert core.count(old)==1;core=core.replace(old,'',1)
    memory=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN ecnf_real_alloc\n')
    relative='src/win/extstorejob.s' if windows else 'src/app/extstorejobposix.s'
    source=(ROOT/relative).read_text().replace('FN ext_store_job_native_close\n','FN ecnf_real_close\n')
    replacements={'src/app/extsettingsnative.s':core,'src/mem.s':memory}
    if windows:
        for name in ['CreatePipe','CreateProcessW','WaitForSingleObject','GetExitCodeProcess','UpdateProcThreadAttribute']:source=source.replace('API '+name,'call ecnf_'+name)
        if mode in (6,15):
            a=source.index('FN ext_store_job_native_free');b=source.index('FN ecnf_real_close',a);source=source[:a]+source[a:b].replace('API CloseHandle','call ecnf_parent_close')+source[b:]
        native=(ROOT/'src/win/extsettingsnative.s').read_text().replace('FN ext_settings_native_write_poll\n','FN ecnf_real_write_poll\n')
        for name in ['CreateFileW','WriteFile','CancelIoEx','GetOverlappedResult','CreateNamedPipeW','CreateEventW']:native=native.replace('API '+name,'call ecnf_'+name)
        if mutation=='observation':
            old='    cmp dword ptr [rbx + ECN_overlapped], 0\n    jge .Lecnw_poll_observation';assert native.count(old)==1;native=native.replace(old,'',1)
        if mutation=='debt':
            old='    mov rax, [rbx + ECN_offset]\n    mov [rbx + ECN_length], rax\n    cmp qword ptr [rbx + ECN_debt], 0\n    jne 2f\n    mov qword ptr [rbx + ECN_length], 0\n    mov qword ptr [rbx + ECN_offset], 0\n2:'
            assert native.count(old)==1;native=native.replace(old,'    mov qword ptr [rbx + ECN_length], 0\n    mov qword ptr [rbx + ECN_offset], 0\n    mov qword ptr [rbx + ECN_debt], 0\n2:',1)
        replacements['src/win/extsettingsnative.s']=native
        security=(ROOT/'src/app/extchoicessecurity.s').read_text().replace('API LocalFree','call ecnf_LocalFree').replace('API OpenProcessToken','call ecnf_OpenProcessToken')
        replacements['src/app/extchoicessecurity.s']=security
    else:
        for name in ['pipe2','fcntl','fork','wait4']:source=source.replace('SYS SYS_'+name,'call ecnf_'+('pipe' if name=='pipe2' else 'wait' if name=='wait4' else name))
        if mode in (6,15):
            a=source.index('FN ext_store_job_native_free');b=source.index('FN ecnf_real_close',a);source=source[:a]+source[a:b].replace('SYS SYS_close','call ecnf_parent_close')+source[b:]
    if not windows:
        replacements['src/app/extsettingsnativeposix.s']=(ROOT/'src/app/extsettingsnativeposix.s').read_text().replace('FN ext_settings_native_write_poll\n','FN ecnf_real_write_poll\n').replace('SYS SYS_write','call ecnf_write')
    if mutation=='workspace':
        old='    mov rdi, [rbx + ESJ_work]\n    call prep_cleanup_free\n'
        assert source.count(old)==1
        source=source.replace(old,'    xor edi, edi\n    call prep_cleanup_free\n',1)
    replacements[relative]=source
    fixture=(ROOT/'tests/ext_settings_native_test.s').read_text()
    old='    call ext_settings_native_start\n    test rax, rax';assert fixture.count(old)==1
    if mode==0:fixture=fixture.replace(old,'    mov qword ptr [rsp], 0\n'+old,1)
    fixture=fixture.replace(old,'    call ext_settings_native_start\n    jmp ecnf_parent\n    test rax, rax',1)
    expected={0:-22,1:-12,2:-12,3:-13 if windows else -24,4:-13 if windows else -5,5:-13 if windows else -11,6:-5,10:-13,11:-13,15:-13 if windows else -5,16:-12,17:-12,18:-12,19:-5,20:-13,21:-13,22:-13,23:-13}.get(mode,0)
    cleanup={9:-16,10:-13,11:-5,12:-5,22:-13,23:-13,24:-5}.get(mode,0)
    parent='''
.text
ecnf_parent:
    cmp rdx, %d
    jne ecnt_fail
    mov r12, rax
    cmp rcx, %d
    jne ecnt_fail
    mov qword ptr [rsp + 288], 0
    mov qword ptr [rsp + 296], 0
    mov qword ptr [rsp + 304], 0
    call time_ms
    add rax, 10000
    mov [rsp + 312], rax
'''%(expected,(-9 if windows else -16) if mode==15 else -13 if mode in (10,22,23) else 0)
    if mode<=5 or 15<=mode<=21:
        parent+='    test r12, r12\n    jnz ecnt_fail\n    jmp ecnf_finish\n'
    else:
        parent+='    test r12, r12\n    jz ecnt_fail\n'
        if mode in (12,13,24):
            parent+='''    mov edi, 65536
    call mem_alloc_try
    test rax, rax
    jz ecnt_fail
    mov [rsp + 288], rax
    mov rdi, r12
    mov rsi, rax
    mov edx, 65536
    call ext_settings_native_write_begin
    cmp rax, 1
    jne ecnt_fail
    mov rdi, r12
    mov esi, 65536
    call ext_settings_native_write_poll
    test rax, rax
    jnz ecnt_fail
    cmp qword ptr [rip + ecnf_write_fired], 1
    jne ecnt_fail
'''
        if mode==13:
            parent+='''    mov rdi, r12
    mov esi, 17
    call ext_settings_native_write_poll
    test rax, rax
    jnz ecnt_fail
    cmp rdx, 17
    jne ecnt_fail
    add [rsp + 296], rdx
'''
        if mode==24:
            parent+='    mov rdi, r12\n    mov esi, 17\n    call ext_settings_native_write_poll\n    cmp rax, -9\n    jne ecnt_fail\n    test rdx, rdx\n    jnz ecnt_fail\n'
        parent+='''    mov rdi, r12
    call ext_settings_native_close_input
    mov rdi, r12
    call ext_settings_native_kill
    test rax, rax
    jnz ecnt_fail
ecnf_loop:
    call time_ms
    cmp rax, [rsp + 312]
    jae ecnt_fail
    mov rdi, r12
    mov esi, 17
    call ext_settings_native_write_poll
    cmp rdx, 17
    ja ecnt_fail
    add [rsp + 296], rdx
    mov r14, rdx
    mov rdi, r12
    call ext_settings_native_poll
    cmp rax, ESJ_REAPED
    jne 9f
    cmp rdx, 255
    ja ecnt_fail
9:  test rcx, rcx
    jns 1f
    cmp rax, %d
    jne ecnt_fail
    inc qword ptr [rsp + 304]
1:  mov rdi, r12
    call ext_settings_native_free
    test rdx, rdx
    jnz ecnf_consumed
    cmp rax, -16
    jne ecnt_fail
    test rcx, rcx
    jnz ecnt_fail
    test r14, r14
    jnz ecnf_loop
    call ext_store_job_retire_wait
    jmp ecnf_loop
ecnf_consumed:
    test rcx, rcx
    jnz ecnt_fail
    cmp rax, %d
    jne ecnt_fail
'''%((3 if mode==14 else 1),cleanup)
        if mode in (7,8,14):parent+='    cmp qword ptr [rsp + 304], 1\n    jne ecnt_fail\n'
        if mode==12:parent+='    cmp qword ptr [rip + ecnf_collected_busy], 0\n    je ecnt_fail\n    cmp qword ptr [rip + ecnf_observed], 0\n    je ecnt_fail\n'
        if mode in (13,24):parent+='    cmp qword ptr [rsp + 296], 65536\n    jne ecnt_fail\n'
    if windows and mode in(10,22,23):
        old='    cmp rax, -16\n    jne ecnt_fail\n    test rcx, rcx\n    jnz ecnt_fail\n    test r14, r14'
        new='    cmp rax, -16\n    je 72f\n    cmp rax, -13\n    jne ecnt_fail\n    cmp rcx, 1\n    jne ecnt_fail\n    cmp qword ptr [r12 + ECN_event], -1\n    jne ecnt_fail\n    jmp 71f\n72: test rcx, rcx\n    jnz ecnt_fail\n71: test r14, r14'
        assert parent.count(old)==1
        parent=parent.replace(old,new,1)
    if mode==25:parent=parent.replace('9:  test rcx, rcx','    cmp rdx, 255\n    jne ecnt_fail\n9:  test rcx, rcx',1)
    parent+='''ecnf_finish:
    mov rdi, [rsp + 288]
    call mem_free
    mov rdi, [rsp + 176]
    call ecnt_foreign_close
    cmp [rip + g_mem_live], r15
    jne ecnt_fail
    call ecnt_census
    cmp rax, [rsp + 168]
    jne ecnt_fail
    xor eax, eax
    EPILOGUE
'''
    fixture+='\n.equ ECNF_MODE, %d\n'%mode+parent+(ROOT/'tests/faults/ext_settings_native.s').read_text()
    return builder.build(folder,fixture,replacements,windows=windows)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--windows-build',action='store_true');parser.add_argument('--build-only',type=Path);parser.add_argument('--wine');args=parser.parse_args()
    windows=args.windows_build or bool(args.wine) or os.name=='nt'
    modes=[0,*range(1,10),14,15] if not windows else list(range(0,14))+list(range(15,26))
    if not windows:modes.remove(8)
    foreign=None;options={}
    if not windows:
        import resource
        foreign=os.open(__file__,os.O_RDONLY);os.dup2(foreign,150,inheritable=True);os.close(foreign)
        options={'pass_fds':(150,),'preexec_fn':lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))}
    try:
        with tempfile.TemporaryDirectory(prefix='rhun-settings-native-fault-') as temp:
            folder=Path(temp)
            for mode in modes:
                exe=build((args.build_only or folder)/str(mode),mode,windows)
                if args.build_only:continue
                r=subprocess.run(([args.wine] if args.wine else [])+[str(exe),'2'],capture_output=True,timeout=20,**options)
                assert r.returncode==0 and not r.stdout and not r.stderr,(mode,r)
                print('ok ext-settings-native/fault/'+str(mode),flush=True)
            controls=[(3,'workspace')] if not windows else [(12,'pending'),(13,'debt'),(24,'observation')]
            for mode,mutation in controls:
                exe=build((args.build_only or folder)/('negative-'+mutation),mode,windows,mutation)
                if args.build_only:continue
                r=subprocess.run(([args.wine] if args.wine else [])+[str(exe),'2'],capture_output=True,timeout=20,**options)
                assert r.returncode==73,(mutation,r)
                print('ok ext-settings-native/negative-control/'+mutation,flush=True)
    finally:
        if not windows:os.close(150)
if __name__=='__main__':main()
