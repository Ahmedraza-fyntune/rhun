#!/usr/bin/env python3
"""POSIX endpoint flag failure and helper-only confinement never discard close owners."""
import importlib.util, subprocess, tempfile, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,disposition=2,stage=0,negative=False):
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    close=(ROOT/'src/app/exthostnative.s').read_text().replace('FN ext_fd_close_checked\n','FN kcu_real_close\n',1)
    replacements={'src/app/exthostnative.s':close}
    if mode==3:
        source=(ROOT/'src/app/taskposix.s').read_text();a=source.index('kp_nonblock:\n');z=source.index('kp_remap:\n',a)
        assert source[a:z].count('    SYS SYS_fcntl')==4
        replacements['src/app/taskposix.s']=source[:a]+source[a:z].replace('    SYS SYS_fcntl','    call kcu_fcntl')+source[z:]
    else:
        source=(ROOT/'src/app/confine.s').read_text()
        for name in('conf_helper_mode','conf_helper_cleanup_init','conf_helper_scratch','conf_helper_error','conf_rules'):
            old=name+':';assert source.count(old)==1;source=source.replace(old,'.globl '+name+'\n'+old,1)
        source=source.replace('interp_of:\n','interp_of:\nFN kcu_interp\n',1).replace('    call interp_of\n','    call kcu_interp\n')
        source=source.replace('add_rule:\n','add_rule:\nFN kcu_add_rule\n',1).replace('    call add_rule\n','    call kcu_add_rule\n')
        # Install the actual opened owner in the test hook before the first checked close.
        source=source.replace('    mov [rip + conf_helper_scratch], rax','    mov [rip + kcu_target], rax\n    mov [rip + conf_helper_scratch], rax',1)
        source=source.replace('    mov [rip + conf_helper_scratch + 8], rax','    mov [rip + kcu_target], rax\n    mov [rip + conf_helper_scratch + 8], rax',1)
        if mode==2:
            a=source.index('FN kcu_add_rule\n');z=source.index('FN kcu_interp\n',a)
            assert source[a:z].count('    SYS SYS_fstat')==1
            source=source[:a]+source[a:z].replace('    SYS SYS_fstat','    call kcu_stat',1)+source[z:]
        if mode==4:
            old='    call confine_probe\n    call rules_release';assert source.count(old)==1
            source=source.replace(old,'    call kcu_prep_probe\n    mov dword ptr [rip + conf_abi], -1\n    call rules_release',1)
        if negative:
            old='    jne confine_helper_release_checked';assert source.count(old)==1
            source=source.replace(old,'',1)
        replacements['src/app/confine.s']=source
    fixture=f'.equ KCU_MODE,{mode}\n.equ KCU_DISP,{disposition}\n.equ KCU_STAGE,{stage}\n'+(ROOT/'tests/faults/keeper_cleanup_producers.s').read_text().replace('kcu_target:','.globl kcu_target\nkcu_target:',1)
    return builder.build(folder,fixture,replacements)
def main():
    cases=[(4,d,0)for d in(0,1,2)]+[(m,d,0)for m in ([0,1]if sys.platform=='darwin'else range(3))for d in(0,1,2)]+[(3,2,s)for s in range(8)]
    with tempfile.TemporaryDirectory(prefix='rhun-keeper-producers-')as folder:
        for mode,disposition,stage in cases:
            label=f'{mode}-{disposition}-{stage}';exe=build(Path(folder)/label,mode,disposition,stage)
            r=subprocess.run([str(exe)],capture_output=True,timeout=10)
            assert r.returncode==0 and not r.stdout and not r.stderr,(label,r)
            print('ok keeper-cleanup-producers/'+label,flush=True)
        exe=build(Path(folder)/'negative-internal-release',4,2,0,True)
        r=subprocess.run([str(exe)],capture_output=True,timeout=10)
        assert r.returncode==73,r
        print('ok keeper-cleanup-producers/negative-control/internal-release',flush=True)
if __name__=='__main__':main()
