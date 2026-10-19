#!/usr/bin/env python3
"""Helper stack buffers retain native mappings and charge through failed release."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows=False,negative=False):
 spec=importlib.util.spec_from_file_location('b',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/theme_capture_file_test.s').read_text()
 if mode==3:fixture=fixture.replace('lea rcx, [rax + 10000]','lea rcx, [rax + 300]',1)
 core=(ROOT/'src/app/themecaptureio.s').read_text()
 if mode in(1,2):
  core=core.replace('FN tc_file_read\n','FN tcu_real_read\n',1)
  fixture+='\nFN tc_file_read\n    mov rax, -5\n    ret\n'
 if mode in(2,4):
  core=core.replace('FN tc_file_close\n','FN tcu_real_close\n',1)
  fixture+='\nFN tc_file_close\n    PROLOGUE\n    call tcu_real_close\n    test rax, rax\n    jnz tcf_fail\n    mov rax, '+str(-13 if mode==2 else -5)+'\n    EPILOGUE\n'
 if negative:
  old='2:  test rdx, rdx\n    jnz 3f\n    mov rdi, r12';assert core.count(old)==1
  core=core.replace(old,'2:  jmp 3f\n    mov rdi, r12',1)
 alloc=(ROOT/'src/app/themecapturemem.s').read_text().replace('FN tc_alloc_try\n','FN tcu_real_alloc\n',1)
 memory=(ROOT/'src/mem.s').read_text().replace('    SYS SYS_munmap\n','    call tcu_munmap\n')
 fixture+='''
.bss
.p2align 3
tcu_target: .quad 0
tcu_allocations: .quad 0
tcu_fired: .quad 0
.text
FN tc_alloc_try
    PROLOGUE
    mov rbx, rdi
    call tcu_real_alloc
    test rax, rax
    jz 1f
    cmp rbx, 65537
    jne 1f
    inc qword ptr [rip + tcu_allocations]
    cmp qword ptr [rip + tcu_allocations], TCU_TARGET
    jne 1f
    lea rcx, [rax - 16]
    mov [rip + tcu_target], rcx
1:  EPILOGUE
FN tcu_munmap
    cmp rdi, [rip + tcu_target]
    jne 2f
.if TCU_MODE != 3
    cmp qword ptr [rip + tcu_fired], 0
    jne 2f
.endif
    inc qword ptr [rip + tcu_fired]
    cmp qword ptr [rip + g_theme_capture_charge], TCU_CHARGE
    jne tcf_fail
    cmp qword ptr [rdi + 8], 65537
    jne tcf_fail
    mov rax, TCU_ERROR
    ret
2:  SYS SYS_munmap
    ret
'''
 definitions='.equ TCU_MODE, %d\n.equ TCU_TARGET, %d\n.equ TCU_CHARGE, %d\n.equ TCU_ERROR, %d\n'%(mode,1 if mode in(1,2)else 2,69632 if mode in(1,2)else 139264,-13 if mode==4 else -5)
 return b.build(folder,definitions+fixture,{'src/app/themecaptureio.s':core,'src/app/themecapturemem.s':alloc,'src/mem.s':memory},windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=bool(a.wine)or a.windows_build or os.name=='nt'
 expected={0:(0,-5),1:(-5,-5),2:(-5,-13),4:(0,-5)}
 with tempfile.TemporaryDirectory(prefix='rhun-theme-file-cleanup-',dir=a.wine_drive_root)as d:
  folder=Path(d).resolve();file=folder/'source.theme';file.write_bytes(bytes(65536));native='C:/'+file.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(file)if a.wine else str(file)
  for mode,negative in[(i,False)for i in range(5)]+[(3,True)]:
   key=str(mode)+('-negative'if negative else'');exe=build((a.build_only or folder)/key,mode,windows,negative)
   if a.build_only:continue
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'65536'],capture_output=True,timeout=15)
   if mode==3:
    assert r.returncode==(73 if negative else 70)and(not r.stdout or negative)and not r.stderr,(mode,negative,r)
   else:
    assert r.returncode==0 and not r.stderr and len(r.stdout)==88,(mode,r)
    assert struct.unpack_from('<qqQ',r.stdout)==(*expected[mode],0),(mode,r.stdout)
    assert r.stdout[24:]==bytes(64),(mode,r.stdout)
   print('ok theme-file/checked-buffer-release/'+key,flush=True)
if __name__=='__main__':main()
