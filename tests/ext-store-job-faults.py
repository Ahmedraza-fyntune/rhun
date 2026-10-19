#!/usr/bin/env python3
"""Private exact-inventory helper transport fault gates."""
import argparse
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False,mutation=None):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    relative='src/win/extstorejob.s' if windows else 'src/app/extstorejobposix.s'
    source=(ROOT/relative).read_text().replace('FN ext_store_job_native_read\n','FN esjf_real_read\n')
    if windows:
        source=source.replace('API WaitForSingleObject','call esjf_wait_win')
        if mutation=='inherit':source=source.replace('mov dword ptr [rsp + 96], 112','mov dword ptr [rsp + 96], 104').replace('0x8080400','0x8000400')
    else:
        source=source.replace('SYS SYS_wait4','call esjf_wait')
        a=source.index('esjp_remap:');b=source.index('FN ext_store_job_native_spawn',a)
        source=source[:a]+source[a:b].replace('SYS SYS_fcntl','call esjf_fcntl')+source[b:]
        source=source.replace('SYS SYS_execve','call esjf_exec')
        if mutation=='inherit':source=source.replace('call kp_closefrom','xor eax, eax')
    if mode==16:
        a=source.index('FN ext_store_job_native_free');b=source.index('FN ext_store_job_native_close',a)
        source=source[:a]+source[a:b].replace('API CloseHandle' if windows else 'SYS SYS_close','call esjf_parent_close')+source[b:]
    if mode==17:source=source.replace('API GetExitCodeProcess','call esjf_exitcode_win')
    core=(ROOT/'src/app/extstorejob.s').read_text()
    if mode in (0,14):
        core=core.replace('FN ext_store_job_step\n    PROLOGUE 32','FN ext_store_job_step\n    PROLOGUE 32\n    call esjf_step_reset')
        if mutation=='budget':core=core.replace('cmp r15, 8','cmp r15, 1024')
    if mode==12 and mutation=='cancel':
        old='    mov rax, [rbx + ESJ_cancel]\n    test rax, rax\n    jz 27f'
        assert core.count(old)==1
        core=core.replace(old,'    jmp 27f\n    mov rax, [rbx + ESJ_cancel]\n    test rax, rax\n    jz 27f')
    if mode==13:source=source.replace('FN ext_store_job_native_spawn\n','FN esjf_real_spawn\n')
    if mode==7:
        a=core.index('FN ext_store_job_free');core=core[:a]+core[a:].replace('call ext_root_close','call esjf_close',1)
    if mode==9:core=core.replace('call mem_alloc_try','call esjf_alloc',1)
    fixture=(ROOT/'tests/ext_store_job_test.s').read_text()
    if mode==7:
        old='    call ext_store_job_free\n    test rax, rax\n    jnz esjt_fail\n    cmp rdx, 1'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,'    call ext_store_job_free\n    cmp rax, -16\n    jne esjt_fail\n    cmp rdx, 1',1)
        old='    cmp rdx, 1\n    jne esjt_fail\n    mov rdi, [r12 + ESG_root]'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,'    cmp rdx, 1\n    jne esjt_fail\n    mov rdi, rsp\n    call esjf_restart\n    test rax, rax\n    jnz esjt_fail\n    mov rdi, [r12 + ESG_root]',1)
    if mode==14:
        fixture=fixture.replace('96:\n    inc qword ptr [rsp + 192]', '96: \n    test rax, rax\n    jnz 991f\n    mov rdi, r13\n    call ext_store_job_cancel\n991: inc qword ptr [rsp + 192]',1)
    if mode==12:
        fixture=fixture.replace('    call time_ms\n    mov [rsp + ESJR_now], rax','    lea rax, [rip + esjf_cancel]\n    mov [rsp + ESJR_cancel], rax\n    call time_ms\n    mov [rsp + ESJR_now], rax',1)
    if mode==16:
        old='    call ext_store_job_start\n    test rax, rax'
        assert old in fixture
        fixture=fixture.replace(old,'    call ext_store_job_start\n    cmp rdx, -5\n    jne esjt_fail\n    test rcx, rcx\n    jnz esjt_fail\n    test rax, rax',1)
    if mode in(17,20):
        old='    call ext_store_job_free\n    test rax, rax\n    jnz esjt_fail\n    cmp rdx, 1'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,'    mov rbx, [r13 + ESJ_secondary]\n    call ext_store_job_free\n    cmp rax, rbx\n    jne esjt_fail\n    cmp rdx, 1',1)
    if mode in (9,13):
        expected=-12 if mode==9 else -24
        old='    call ext_store_job_start\n    test rax, rax\n    jz esjt_fail\n    mov r13, rax'
        assert fixture.count(old)==1
        fixture=fixture.replace(old,('    call ext_store_job_start\n    test rax, rax\n    jnz esjt_fail\n    cmp rdx, %d\n    jne esjt_fail\n    mov [rsp + 208], rdx\n    mov [rsp + 216], rcx\n    mov qword ptr [rsp + 224], 0\n    mov qword ptr [rsp + 192], 0\n    xor r13d, r13d\n    jmp 10f\n    mov r13, rax')%expected,1)
    fixture+='\n.equ ESJF_MODE, %d\n'%mode+(ROOT/'tests/faults/ext_store_job_native.s').read_text()
    return module.build(folder,fixture,{relative:source,'src/app/extstorejob.s':core},windows=windows)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--windows-build',action='store_true');parser.add_argument('--build-only',type=Path);parser.add_argument('--wine');parser.add_argument('--wine-drive-root',type=Path);args=parser.parse_args()
    windows=args.windows_build or bool(args.wine) or os.name=='nt'
    modes={0:0,1:0,2:0,3:-5,4:-5,5:0,7:0,9:-12,12:-125,13:-24,14:-125,15:0,16:-5}
    if windows:modes[17]=-5
    else:modes.update({6:-10,8:-24,10:-5})
    with tempfile.TemporaryDirectory(prefix='rhun-store-job-fault-',dir=args.wine_drive_root) as temporary:
        folder=Path(temporary).resolve()
        options={};poison_fd=None
        if os.name=='posix' and not windows:
            import fcntl,resource
            original=os.open(folder/'poison-parent',os.O_CREAT|os.O_RDWR,0o600)
            poison_fd=fcntl.fcntl(original,fcntl.F_DUPFD,150);os.close(original)
            options={'pass_fds':(poison_fd,),'preexec_fn':lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))}
        for mode,expected in modes.items():
            exe=build((args.build_only or folder)/str(mode),mode,windows)
            if args.build_only:continue
            root=folder/('root'+str(mode));root.mkdir()
            path='C:/'+root.relative_to(args.wine_drive_root.resolve()).as_posix() if args.wine else str(root)
            result=subprocess.run(([args.wine] if args.wine else [])+[str(exe),path,'0'],capture_output=True,timeout=30,**options)
            assert result.returncode==0 and not result.stderr and len(result.stdout)==32,(mode,result)
            status,secondary,rows,steps=struct.unpack('<qqQQ',result.stdout)
            assert status==expected and secondary in ((0,-13) if mode==17 else ((-5,) if mode==13 else (0,))) and rows==0,(mode,status,secondary,rows,steps)
            print('ok ext-store/job/fault/'+str(mode),flush=True)
        for mode,mutation,expected in ((14,'budget',-125),(12,'cancel',-125),(15,'inherit',0)):
            exe=build((args.build_only or folder)/('negative-'+mutation),mode,windows,mutation)
            if args.build_only:continue
            root=folder/('negative-root-'+mutation);root.mkdir()
            path='C:/'+root.relative_to(args.wine_drive_root.resolve()).as_posix() if args.wine else str(root)
            result=subprocess.run(([args.wine] if args.wine else [])+[str(exe),path,'0'],capture_output=True,timeout=30,**options)
            assert result.returncode==0 and not result.stderr and len(result.stdout)==32,result
            status,secondary,rows,steps=struct.unpack('<qqQQ',result.stdout)
            assert status==(-5 if mutation=='inherit' else -33) and status!=expected,(mutation,status)
            print('ok ext-store/job/negative-control/'+mutation,flush=True)
        if poison_fd is not None:os.close(poison_fd)
if __name__=='__main__':main()
