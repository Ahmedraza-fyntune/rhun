#!/usr/bin/env python3
"""Failed pre-spawn ESJ disposal retains registry and returns an owned abort."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 nativepath='src/win/extstorejob.s'if windows else'src/app/extstorejobposix.s'
 native=(ROOT/nativepath).read_text().replace('FN ext_store_job_native_spawn\n','FN nct_real_spawn\n')
 mem=(ROOT/'src/mem.s').read_text().replace('    SYS SYS_munmap\n','    call nct_munmap\n')
 fixture=(ROOT/'tests/ext_store_job_test.s').read_text();old='    call ext_store_job_start\n    test rax, rax\n    jz esjt_fail\n    mov r13, rax';assert fixture.count(old)==1
 fixture=fixture.replace(old,'    call ext_store_job_start\n    jmp nct_parent\n    test rax, rax\n    jz esjt_fail\n    mov r13, rax',1)
 extra='''
.bss
.p2align 3
nct_target: .quad 0
nct_fault: .quad 0
nct_spawns: .quad 0
.text
FN nct_munmap
    cmp rdi, [rip + nct_target]
    jne 1f
    cmp qword ptr [rip + nct_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
FN ext_store_job_native_spawn
    PROLOGUE
    mov rbx, rdi
    mov edi, 131072
    call mem_alloc_try
    test rax, rax
    jz esjt_fail
    mov [rbx + ESJ_work], rax
    sub rax, 16
    mov [rip + nct_target], rax
    inc qword ptr [rip + nct_spawns]
    cmp qword ptr [rip + nct_spawns], 1
    jne 1f
    mov qword ptr [rip + nct_fault], 1
1:  mov rax, -24
    EPILOGUE
nct_parent:
    test rax, rax
    jz esjt_fail
    cmp rdx, -24
    jne esjt_fail
    cmp rcx, -5
    jne esjt_fail
    mov r13, rax
    cmp qword ptr [rax + ESJ_authority], ESJ_NONE
    jne esjt_fail
    cmp qword ptr [rax + ESJ_terminal], 1
    jne esjt_fail
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jnz esjt_fail
    cmp rdx, -16
    jne esjt_fail
    cmp qword ptr [rip + nct_spawns], 1
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_take_snapshot
    test rax, rax
    jnz esjt_fail
    cmp rdx, -24
    jne esjt_fail
    cmp rcx, -5
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_free
    cmp rax, -5
    jne esjt_fail
    test rdx, rdx
    jnz esjt_fail
    mov qword ptr [rip + nct_fault], 0
    mov rdi, r13
    call ext_store_job_free
    cmp rax, -5
    jne esjt_fail
    cmp rdx, 1
    jne esjt_fail
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jnz esjt_fail
    cmp rdx, -24
    jne esjt_fail
    test rcx, rcx
    jnz esjt_fail
    cmp qword ptr [rip + nct_spawns], 2
    jne esjt_fail
.ifdef WINDOWS
    mov rdi, [rsp + 240]
    call ext_root_close
    test rax, rax
    jnz esjt_fail
.endif
    mov rdi, r12
    call ext_store_guard_free
    test rax, rax
    jnz esjt_fail
    cmp [rip + g_mem_live], r15
    jne esjt_fail
    xor eax, eax
    EPILOGUE
'''
 return b.build(folder,fixture+extra,{nativepath:native,'src/mem.s':mem},windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=bool(a.wine)or a.windows_build or os.name=='nt'
 with tempfile.TemporaryDirectory(prefix='rhun-native-cleanup-start-',dir=a.wine_drive_root)as f:
  folder=Path(f).resolve();exe=build(a.build_only or folder,windows)
  if a.build_only:return
  root=folder/'root';root.mkdir();native='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(root)
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'0'],capture_output=True,timeout=15)
  assert r.returncode==0 and not r.stdout and not r.stderr,r
  print('ok native-cleanup/ESJ-NONE-retained-start-and-registry')
if __name__=='__main__':main()
