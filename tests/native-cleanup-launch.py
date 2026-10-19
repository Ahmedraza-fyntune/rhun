#!/usr/bin/env python3
"""Real native constructor and post-launch cleanup ownership boundary faults."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 relative='src/win/extstorejob.s'if windows else'src/app/extstorejobposix.s';native=(ROOT/relative).read_text();replacements={}
 if mode in(0,1,3):
  arm='    mov rcx, [rbx + '+('ESJ_native + 96'if mode==3 else'ESJ_work')+']\n    sub rcx, 16\n    mov [rip + ncs_target], rcx\n    mov qword ptr [rip + ncs_fault], 1\n'
  if mode in(0,3):
   needle='    API CreateProcessW\n'if windows else'    SYS SYS_fork\n';assert native.count(needle)==1
   native=native.replace(needle,needle+'    test rax, rax\n    jle 981f\n'+arm+'981:\n',1)
  else:
   needle='    mov [rbx + ESJ_work], rax\n';assert native.count(needle)==1;native=native.replace(needle,needle+arm,1)
   needle='    API CreatePipe\n'if windows else'    SYS SYS_pipe2\n';assert native.count(needle)==1
   native=native.replace(needle,('    mov ecx, 5\n    API SetLastError\n    xor eax, eax\n'if windows else'    mov rax, -24\n'),1)
 else:
  native=native.replace('API MultiByteToWideChar','call ncs_conversion')
  replacements['src/app/extprepareretirealloc.s']=(ROOT/'src/app/extprepareretirealloc.s').read_text().replace('FN prep_cleanup_free\n','FN ncs_real_cleanup\n')
 if mode==3:
  old='    API InitializeProcThreadAttributeList\n'
  assert native.count(old)==2
  native=native.replace(old,old+'    mov qword ptr [rsp + 272], 65536\n',1)
  native=native.replace('    API DeleteProcThreadAttributeList\n','    inc qword ptr [rip + ncs_deletes]\n    API DeleteProcThreadAttributeList\n')
 replacements[relative]=native
 memory=(ROOT/'src/mem.s').read_text().replace('    SYS SYS_munmap\n','    call ncs_munmap\n');replacements['src/mem.s']=memory
 fixture=(ROOT/'tests/ext_settings_native_test.s').read_text();old='    call ext_settings_native_start\n    test rax, rax';assert fixture.count(old)==1
 fixture=fixture.replace(old,'    call ext_settings_native_start\n    jmp ncs_parent\n    test rax, rax',1)
 extra='''
.bss
.p2align 3
.globl ncs_target, ncs_fault
ncs_target: .quad 0
ncs_fault: .quad 0
ncs_calls: .quad 0
.globl ncs_deletes
ncs_deletes: .quad 0
ncs_conversions: .quad 0
.text
FN ncs_munmap
    cmp rdi, [rip + ncs_target]
    jne 1f
    inc qword ptr [rip + ncs_calls]
    cmp qword ptr [rip + ncs_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
ncs_parent:
    test rax, rax
    jz ecnt_fail
    mov r12, rax
'''
 extra+='    cmp rdx, %d\n    jne ecnt_fail\n'%(-5 if mode in(0,3) else-13 if windows else-24)
 extra+='    cmp rcx, %d\n    jne ecnt_fail\n'%(0 if mode in(0,3) else-5)
 extra+='    cmp qword ptr [r12 + ESJ_authority], %d\n    jne ecnt_fail\n'%(1 if mode in(0,3) else 0)
 if mode in(2,4):extra+='    mov rax, [r12 + ESJ_native + %d]\n    cmp rax, [rip + ncs_target]\n    jne ecnt_fail\n'%(104 if mode==4 else 112)
 if mode in(0,3):
  extra+='''    mov rdi, r12
    call ext_settings_native_free
    cmp rax, -16
    jne ecnt_fail
    test rdx, rdx
    jnz ecnt_fail
    test rcx, rcx
    jnz ecnt_fail
    mov rdi, r12
    call ext_settings_native_close_input
    mov rdi, r12
    call ext_settings_native_kill
    test rax, rax
    jnz ecnt_fail
    call time_ms
    add rax, 10000
    mov [rsp + 312], rax
ncs_collect:
    call time_ms
    cmp rax, [rsp + 312]
    jae ecnt_fail
    mov rdi, r12
    mov esi, 65536
    call ext_settings_native_write_poll
    mov rdi, r12
    call ext_settings_native_poll
    cmp rax, ESJ_REAPED
    je ncs_collected
    cmp rax, ESJ_OWNED
    jne ecnt_fail
    call ext_store_job_retire_wait
    jmp ncs_collect
ncs_collected:
'''
 extra+='''    mov rdi, r12
    call ext_settings_native_free
    cmp rax, -5
    jne ecnt_fail
    test rdx, rdx
    jnz ecnt_fail
    cmp rcx, 1
    jne ecnt_fail
    lea rax, [r15 + 2]
    cmp [rip + g_mem_live], rax
    jne ecnt_fail
    cmp qword ptr [rip + ncs_calls], 0
    je ecnt_fail
    mov qword ptr [rip + ncs_fault], 0
    mov rdi, r12
    call ext_settings_native_free
    cmp rax, -5
    jne ecnt_fail
    cmp rdx, 1
    jne ecnt_fail
    test rcx, rcx
    jnz ecnt_fail
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
 if mode==3:
  extra=extra.replace('    lea rax, [r15 + 2]','    cmp qword ptr [rip + ncs_deletes], 1\n    jne ecnt_fail\n    lea rax, [r15 + 2]',1)
 if mode in(2,4):
  extra+='''
FN prep_cleanup_free
    cmp rdi, [rip + ncs_target]
    jne 1f
    cmp qword ptr [rip + ncs_fault], 0
    je 1f
    inc qword ptr [rip + ncs_calls]
    mov rax, -5
    xor edx, edx
    ret
1:  jmp ncs_real_cleanup
FN ncs_conversion
    mov rax, [rsp + 40]
    test rax, rax
    jz 1f
    inc qword ptr [rip + ncs_conversions]
    cmp qword ptr [rip + ncs_conversions], NCS_CONVERSION
    jne 1f
    mov [rip + ncs_target], rax
    mov qword ptr [rip + ncs_fault], 1
    sub rsp, 40
    mov ecx, 5
    API SetLastError
    add rsp, 40
    xor eax, eax
    ret
1:  jmp [rip + __imp_MultiByteToWideChar]
'''
 return b.build(folder,fixture+'\n.equ NCS_CONVERSION, %d\n'%(2 if mode==4 else 1)+extra,replacements,windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=bool(a.wine)or a.windows_build or os.name=='nt'
 options={}
 if not windows:
  fd=os.open(__file__,os.O_RDONLY);os.dup2(fd,150,inheritable=True);os.close(fd);options={'pass_fds':(150,)}
 try:
  with tempfile.TemporaryDirectory(prefix='rhun-native-cleanup-launch-')as f:
   for mode in([0,1,2,3,4]if windows else[0,1]):
    exe=build((a.build_only or Path(f))/str(mode),mode,windows)
    if a.build_only:continue
    r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),'2'],capture_output=True,timeout=15,**options)
    assert r.returncode==0 and not r.stdout and not r.stderr,(mode,r)
    print('ok native-cleanup/actual-launch/'+str(mode),flush=True)
 finally:
  if not windows:os.close(150)
if __name__=='__main__':main()
