#!/usr/bin/env python3
"""Failed partial ESS decoding stays owned by the real collected ESJ."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False,negative=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 memory=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN ncu_real_alloc\n').replace('    SYS SYS_munmap\n','    call ncu_munmap\n')
 fixture=(ROOT/'tests/ext_store_job_test.s').read_text();fixture=fixture.replace('.Lesjt_done:\n','.Lesjt_done:\n    jmp ncuj_done\n',1)
 helpers=(ROOT/'tests/faults/native_cleanup_unpack.s').read_text();a=helpers.index('.bss\n');z=helpers.index('FN main\n');helpers=helpers[a:z].replace('    mov [rip + ncu_target], rcx','    mov [rip + ncu_target], rcx\n    mov qword ptr [rip + ncu_fault], 1')
 extra='''
ncuj_done:
    cmp qword ptr [r13 + ESJ_authority], ESJ_REAPED
    jne esjt_fail
    cmp qword ptr [r13 + ESJ_error], NCUJ_PRIMARY
    jne esjt_fail
    cmp qword ptr [r13 + ESJ_secondary], -5
    jne esjt_fail
    mov rbx, [r13 + ESJ_result]
    test rbx, rbx
    jz esjt_fail
    mov rax, [rbx + ESS_entries + VEC_ptr]
    sub rax, 16
    cmp rax, [rip + ncu_target]
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_take_snapshot
    test rax, rax
    jnz esjt_fail
    cmp rdx, NCUJ_PRIMARY
    jne esjt_fail
    cmp rcx, -5
    jne esjt_fail
    mov rdi, r13
    call ext_store_job_free
    cmp rax, -5
    jne esjt_fail
    test rdx, rdx
    jnz esjt_fail
    cmp [r13 + ESJ_result], rbx
    jne esjt_fail
    mov rdi, rsp
    call ext_store_job_start
    test rax, rax
    jnz esjt_fail
    cmp rdx, -16
    jne esjt_fail
    mov qword ptr [rip + ncu_fault], 0
    mov rdi, r13
    call ext_store_job_free
    cmp rax, -5
    jne esjt_fail
    cmp rdx, 1
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
 replacements={'src/mem.s':memory}
 if negative:
  core=(ROOT/'src/app/extstorejob.s').read_text();old='    lea rcx, [rbx + ESJ_result]\n    call ext_store_snapshot_unpack_owned_try';assert core.count(old)==1
  replacements['src/app/extstorejob.s']=core.replace(old,'    call ext_store_snapshot_unpack_try',1)
 return b.build(folder,'.equ NCF_MODE, %d\n.equ NCUJ_PRIMARY, %d\n'%(mode,-12 if mode==13 else-5)+fixture+helpers+extra,replacements,windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=bool(a.wine)or a.windows_build or os.name=='nt'
 with tempfile.TemporaryDirectory(prefix='rhun-native-cleanup-unpack-job-',dir=a.wine_drive_root)as f:
  folder=Path(f).resolve()
  for mode,negative in[(12,False),(13,False),(12,True)]:
   key=str(mode)+('-negative'if negative else'');exe=build((a.build_only or folder)/key,mode,windows,negative)
   if a.build_only:continue
   root=folder/('root'+key);root.mkdir();(root/'.job-test-mode').write_text('w');wire=bytearray(128+392*256+112);wire[:8]=b'RHESTOR\0';struct.pack_into('<IIIII',wire,8,1,128,256,1,0);(root/'.job-wire').write_bytes(wire)
   path='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(root)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),path,'20'],capture_output=True,timeout=15)
   assert r.returncode==(73 if negative else 0)and not r.stdout and not r.stderr,(mode,negative,r)
   print('ok native-cleanup/ESJ-partial-unpack/'+key,flush=True)
if __name__=='__main__':main()
