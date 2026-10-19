#!/usr/bin/env python3
"""Observe maximum-stream budgets, post-exit EOF, tag binding and Linux cadence."""
import argparse,importlib.util,os,struct,subprocess,tempfile,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows):
 spec=importlib.util.spec_from_file_location('stream_build',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 relative='src/win/extstorejob.s'if windows else'src/app/extstorejobposix.s';backend=(ROOT/relative).read_text().replace('FN ext_store_job_native_read\n','FN elf_real_read\n',1).replace('FN ext_store_job_native_poll\n','FN elf_real_poll\n',1)
 core=(ROOT/'src/app/extstorejob.s').read_text().replace('FN ext_store_job_step\n    PROLOGUE 32','FN ext_store_job_step\n    PROLOGUE 32\n    call elf_reset',1)
 if mode==2:
  backend=backend.replace('SYS SYS_pipe2','call elf_small_pipe')
  old='    cmp qword ptr [rdi + ESJ_purpose], ESJ_LEGACY_SNAPSHOT\n    jne 4f\n    mov eax, 1';assert old in core;core=core.replace(old,old[:-1]+'16',1)
 if mode==3:core=core.replace('cmp r15, 8','cmp r15, 1024',1)
 legacy=(ROOT/'src/app/extstorejoblegacy.s').read_text()
 if mode==4:legacy=legacy.replace('    call memeq\n    test eax, eax','    mov eax, 1\n    test eax, eax',1)
 fixture=(ROOT/'tests/ext_store_job_legacy_test.s').read_text()
 if mode==5:fixture='.equ ELF_BODY_CORRUPT, 1\n'+fixture
 if mode==1:fixture=fixture.replace('.Lesjt_done:\n','.Lesjt_done:\n    cmp qword ptr [rip + esjlt_seen_reaped], 1\n    jne esjt_fail\n',1)
 fixture+='''
.bss
elf_budget: .zero 8
elf_reads: .zero 8
elf_bytes: .zero 8
elf_polls: .zero 8
elf_pipe_calls: .zero 8
elf_delayed: .zero 8
.text
FN elf_reset
    mov [rip + elf_budget], rdx
    mov qword ptr [rip + elf_reads], 0
    mov qword ptr [rip + elf_bytes], 0
    mov qword ptr [rip + elf_polls], 0
    mov qword ptr [rip + elf_pipe_calls], 0
    ret
FN ext_store_job_native_poll
    inc qword ptr [rip + elf_polls]
    cmp qword ptr [rip + elf_polls], 1
    ja 8f
    jmp elf_real_poll
8:  mov rax, -33
    ret
FN ext_store_job_native_read
    inc qword ptr [rip + elf_reads]
    cmp qword ptr [rip + elf_reads], 8
    ja 8f
    cmp rdx, [rip + elf_budget]
    ja 8f
    PROLOGUE
    mov rbx, rdi
    call elf_real_read
    test rax, rax
    jle 1f
    add [rip + elf_bytes], rax
    mov rcx, [rip + elf_budget]
    cmp [rip + elf_bytes], rcx
    ja 7f
1:
'''
 if mode==1:
  fixture+='''    test rax, rax
    jnz 2f
    mov rcx, [rip + esjlt_owned_job]
    cmp rbx, [rcx + ESJ_stdout]
    jne 2f
    cmp qword ptr [rcx + ESJ_authority], ESJ_REAPED
    jne 3f
    cmp qword ptr [rip + elf_delayed], 5
    jae 2f
    inc qword ptr [rip + elf_delayed]
3:  mov rax, -11
2:
'''
 fixture+='''    EPILOGUE
7:  mov rax, -33
    EPILOGUE
8:  mov rax, -33
    ret
'''
 if mode==2:
  fixture+='''
FN elf_small_pipe
    PROLOGUE 16
    mov rbx, rdi
    SYS SYS_pipe2
    test rax, rax
    js 1f
    mov edi, [rbx]
    mov esi, 1031
    mov edx, 4096
    SYS SYS_fcntl
    cmp rax, 4096
    jne esjt_fail
    xor eax, eax
1:  EPILOGUE
'''
 if windows:
  for api in('PeekNamedPipe','ReadFile'):
   backend=backend.replace('API '+api,'call elf_'+api)
   fixture+='FN elf_'+api+'\n    inc qword ptr [rip + elf_pipe_calls]\n    cmp qword ptr [rip + elf_pipe_calls], 16\n    ja esjt_fail\n    jmp [rip + __imp_'+api+']\n'
 return m.build(folder,fixture,{relative:backend,'src/app/extstorejob.s':core,'src/app/extstorejoblegacy.s':legacy},windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);a=p.parse_args();windows=a.windows_build or bool(a.wine)or os.name=='nt'
 modes=[0,1,3,4,5]+([2]if sys.platform.startswith('linux')and not windows else[])
 for mode in modes:
  exe=build((a.build_only or ROOT/'build/legacy-stream-faults')/str(mode),mode,windows)
  if a.build_only:continue
  with tempfile.TemporaryDirectory(prefix='rhun-legacy-stream-',dir=a.wine_drive_root)as d:
   root=Path(d).resolve();size=18874368 if mode in(0,2,5)else 512;b=bytearray(size);b[:8]=b'RHLSS1\0\0';struct.pack_into('<IIQI',b,8,1,192,size,2);b[96:128]=b'\xbb'*32;struct.pack_into('<I',b,144,1);struct.pack_into('<I',b,152,0xffffffff if windows else 0);
   if size>65536:
    pattern=bytes((i*37+i//251)&255 for i in range(65521));b[192:]=(pattern*((size-192+65520)//65521))[:size-192]
   (root/'.job-wire').write_bytes(b)
   if mode in(3,4):(root/'.job-test-mode').write_text('q'if mode==3 else'T')
   native='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(root)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'31'if mode==2 else'20'],cwd=root,capture_output=True,timeout=30)
   if mode==5:
    assert r.returncode!=0 and not r.stdout,(mode,r)
    print('ok legacyjob/negative-control/late-body-byte-corruption',flush=True);continue
   assert r.returncode==0 and not r.stderr and len(r.stdout)==32,(mode,r)
   status,secondary,length,steps=struct.unpack('<qqQQ',r.stdout)
   assert status==(-110 if mode==2 else-33 if mode==3 else 0)and secondary==0,(mode,status,secondary,length,steps)
   assert length==(0 if mode in(2,3)else size),(mode,length)
   print('ok legacyjob/observed-stream-boundary/'+str(mode),flush=True)
if __name__=='__main__':main()
