#!/usr/bin/env python3
"""Real extension helper cleanup failures must collect the gated target and helper."""
import argparse, importlib.util, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    fixture=(ROOT/'tests/task_extension_keeper_test.s').read_text().replace('FN main\n    PROLOGUE 16','FN main\n    PROLOGUE 64',1)
    old='''    test eax, KP_FAILED
    jnz .Ltek_fail
    cmp qword ptr [rip + tek_started], 0'''
    assert fixture.count(old)==1
    fixture=fixture.replace(old,'''    test eax, KP_STARTED
    jnz .Ltek_fail
    cmp qword ptr [rip + tek_started], 0''',1)
    a=fixture.index('    cmp qword ptr [rip + tek_started], 0\n',fixture.index('.Ltek_loop:'))
    z=fixture.index('4:  mov rdi, [rip + tek_handle]',a)
    stop=''
    if mode==9:
        stop='''    test eax, KP_READY
    jz 4f
    mov rdi, [rip + tek_handle]
    call keeper_stop
'''
    if mode in(13,14):stop=fixture[a:z]
    fixture=fixture[:a]+stop+fixture[z:]
    a=fixture.index('    test edx, edx\n',fixture.index('.Ltek_complete:'))
    z=fixture.index('    mov rdi, [rip + tek_handle]\n    lea rsi, [rip + tek_info]',a)
    expected=-22 if mode in(13,14,15,16)else -125 if mode==9 else (-12 if windows else -11) if mode==10 else -22 if mode==11 else -5 if mode==12 else -13
    fixture=fixture[:a]+f'''    test eax, KP_FAILED
    jz .Ltek_fail
    cmp r8d, {expected}
    jne .Ltek_fail
    mov rdi, [rip + tek_handle]
    call kp_find
    test rax, rax
    jz .Ltek_fail
    cmp dword ptr [rax + KX_reaped], 1
    jne .Ltek_fail
    cmp dword ptr [rax + KX_helper_exit], 111
    jne .Ltek_fail
    cmp qword ptr [rax + KX_lifetime_ready], 1
    jne .Ltek_fail
    mov rbx, rax
.if KCL_MODE == 12
    call kcl_parent_target_check
.endif
    call kcl_parent_lease_check
    mov rdi, [rbx + KX_lease]
    lea rsi, [rip + kcl_statbuf]
    call ext_root_stat
    test rax, rax
    jnz .Ltek_fail
    cmp qword ptr [rip + kcl_statbuf], 1
    jne .Ltek_fail
.ifdef WINDOWS
    mov rcx, [rbx + KX_job]
    mov edx, 1
    lea r8, [rip + kcl_statbuf]
    mov r9d, 48
    mov qword ptr [rsp + 32], 0
    API QueryInformationJobObject
    test eax, eax
    jz .Ltek_fail
    cmp dword ptr [rip + kcl_statbuf + 40], 0
    jne .Ltek_fail
.else
    mov rdi, [rbx + KX_target]
    test rdi, rdi
    jz 91f
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    jne .Ltek_fail
    mov rdi, [rbx + KX_target]
    neg rdi
    xor esi, esi
    SYS SYS_kill
    cmp rax, -3
    jne .Ltek_fail
91:
.endif
'''+fixture[z:]
    fixture=fixture.replace('''    call keeper_close
    test rax, rax
    jnz .Ltek_fail''','''    call keeper_close_checked
    cmp rdx, 1
    jne .Ltek_fail
    test rax, rax
    jnz .Ltek_fail''',1)
    a=fixture.index('    cmp qword ptr [rip + tek_used], 6\n',fixture.index('.Ltek_complete:'))
    z=fixture.index('    lea rdi, [rip + tek_ok]\n',a)
    fixture=fixture[:a]+'''    cmp qword ptr [rip + tek_used], 0
    jne .Ltek_fail
'''+fixture[z:]
    fault=(ROOT/'tests/faults/keeper_cleanup_live.s').read_text();fault=fault[fault.index('.section .rodata'): ]
    if windows:fixture=fixture.replace('.include \"rhun.inc\"','.include \"win.inc\"',1)
    fixture=f'.equ KCL_MODE, {mode}\n'+fixture+'\n'+fault
    replacements={
        'src/app/exthostnative.s':(ROOT/'src/app/exthostnative.s').read_text().replace('FN ext_fd_close_checked\n','FN kcl_real_fd_close\n',1),
        'src/app/extvalidatepath.s':(ROOT/'src/app/extvalidatepath.s').read_text().replace('FN ext_root_close\n','FN kcl_real_root_close\n',1),
        'src/app/extstorelookup.s':(ROOT/'src/app/extstorelookup.s').read_text().replace('FN ext_store_selection_matches\n','FN kcl_real_selection\n',1),
        'src/app/extstorelease.s':(ROOT/'src/app/extstorelease.s').read_text().replace('FN ext_store_lease_try\n','FN kcl_real_lease\n',1),
        'src/app/extstoreguard.s':(ROOT/'src/app/extstoreguard.s').read_text().replace('FN ext_store_guard_try\n','FN kcl_real_guard\n',1),
        'src/app/taskauth.s':(ROOT/'src/app/taskauth.s').read_text().replace('FN kp_extension_authorize\n','FN kcl_real_authorize\n',1).replace('FN kp_extension_start\n','FN kcl_real_start\n',1),
        'src/app/taskcleanup.s':(ROOT/'src/app/taskcleanup.s').read_text().replace('FN kh_guard_release\n','FN kcl_real_guard_release\n',1),
        'src/mem.s':(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN kcl_real_alloc\n',1).replace('    SYS SYS_munmap\n','    call kcl_munmap\n',1)}
    if not windows:
        replacements['src/app/taskconfine.s']=(ROOT/'src/app/taskconfine.s').read_text().replace('kh_close_probe:\n','FN kcl_real_probe\n',1)
        if mode==11:replacements['src/app/taskconfine.s']=replacements['src/app/taskconfine.s'].replace('    SYS SYS_fstat\n','    call kcl_probe_stat\n',1)
        posix=(ROOT/'src/app/taskposix.s').read_text().replace('kp_setup_poll:\n','FN kcl_real_setup_poll\n',1)
        if mode==12:
            a=posix.index('FN kcl_real_setup_poll\n');z=posix.index('FN kp_target_poll\n',a)
            posix=posix[:a]+posix[a:z].replace('    SYS SYS_read\n','    call kcl_setup_read\n',1)+posix[z:]
        replacements['src/app/taskposix.s']=posix
    if mode in(10,12):
        relative='src/win/taskproc.s' if windows else 'src/app/taskposix.s'
        source=replacements.get(relative,(ROOT/relative).read_text());a=source.index('FN kp_target_prepare\n');z=source.index('FN kp_target_start\n',a)
        target=source[a:z]
        if windows:
            old='    call kpw_spawn\n';assert target.count(old)==1
            target=target.replace(old,'    mov rax, -12\n    jmp .Lkpw_target_fail\n',1)
        else:
            old='    SYS SYS_fork\n';assert target.count(old)==1
            target=target.replace(old,'    call kcl_target_fork\n',1)
        replacements[relative]=source[:a]+target+source[z:]
    return builder.build(folder,fixture,replacements,windows)
def main():
    p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args()
    windows=bool(a.wine)or a.windows_build or os.name=='nt'
    modes=[0,1,2,3,4,5,6,9,10,13,14,15,16] if windows else [0,1,2,3,4,5,6,7,9,10,11,12,13,14,15,16]
    drive=a.wine_drive_root.resolve() if a.wine_drive_root else None
    def argument(path):
        path=path.resolve()
        if a.wine:
            if drive:
                try:return 'C:/'+path.relative_to(drive).as_posix()
                except ValueError:pass
            return 'Z:'+path.as_posix()
        return str(path)
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-live-build-')as temporary:
        for mode in modes:
            executable=build((a.build_only or Path(temporary))/str(mode),mode,windows)
            if a.build_only:continue
            with tempfile.TemporaryDirectory(prefix='rhun-keeper-live-',dir=drive)as folder:
                base=Path(folder).resolve();root=base/'store';payload=root/'owner/name';payload.mkdir(parents=True)
                (root/'.change.lock').touch();lease=root/'.leases/legacy'/b'owner'.hex()/(b'name'.hex()+'.lock');lease.parent.mkdir(parents=True);lease.touch()
                state=base/'state';state.mkdir();home=base/'home';home.mkdir();(home/'approved').write_bytes(b'keeper')
                command=([a.wine]if a.wine else[])+[argument(p)for p in(executable,root,payload,state,home)]
                r=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
                assert r.returncode==0 and r.stdout+r.stderr==b'ok independent extension keeper\n',(mode,r)
                print('ok keeper-cleanup-live/'+str(mode),flush=True)
if __name__=='__main__':main()
