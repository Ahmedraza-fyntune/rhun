#!/usr/bin/env python3
"""Context bounds, native capture faults and child-only cwd bootstrap ownership."""
from pathlib import Path
import argparse,importlib.util,os,struct,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows):
 spec=importlib.util.spec_from_file_location('legacy_context_build',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/ext_store_job_legacy_test.s').read_text();changes={}
 if windows:
  path='src/win/extstorejoblegacy.s';source=(ROOT/path).read_text()
  api={0:'GetCurrentDirectoryW',1:'GetCurrentDirectoryW',2:'WideCharToMultiByte',3:'GetEnvironmentVariableW',4:'GetEnvironmentVariableW',5:'MultiByteToWideChar',6:'SetCurrentDirectoryW',7:'SetCurrentDirectoryW'}
  if mode==13:
   fixture=(ROOT/'tests/ext_store_job_legacy_bootstrap_test.s').read_text()
   source=source.replace('API SetCurrentDirectoryW','call elf_boot_chdir')
  elif mode in api:
   source=source.replace('API '+api[mode],'call elf_fail_api')
   if mode in(1,4):shim='FN elf_fail_api\n    mov eax, '+str(4096 if mode==1 else 32767)+'\n    ret\n'
   elif mode==7:shim='FN elf_fail_api\n    PROLOGUE 96\n    mov ecx, 15000\n    API Sleep\n    mov eax, 1\n    EPILOGUE\n'
   else:shim='FN elf_fail_api\n    PROLOGUE 96\n    mov ecx, 5\n    API SetLastError\n    xor eax, eax\n    EPILOGUE\n'
   if mode>=5:
    fixture='.equ ELR_EXPECT_FAILURE, '+str(111 if mode==7 else 1)+'\n'+(ROOT/'tests/ext_store_job_legacy_real_test.s').read_text()
    path2='src/app/extvalidatepath.s';changes[path2]=(ROOT/path2).read_text().replace('FN ext_root_close\n','FN elf_real_close\n',1)
    fixture+='\nFN ext_root_close\n    cmp qword ptr [rip + g_argc], 10\n    jne 1f\n    inc qword ptr [rip + elf_child_closes]\n1:  jmp elf_real_close\n'
    if mode in(5,6):
     backend='src/win/extstorejob.s';changes[backend]=(ROOT/backend).read_text().replace('API TerminateProcess','call elf_no_terminate')
     fixture+='\nFN elf_no_terminate\n    mov eax, 1\n    ret\n'
   fixture+='\n'+shim
  elif mode in(8,10,11,12):
   source=source.replace('API GetCurrentDirectoryW','call elf_unc_cwd').replace('API SetCurrentDirectoryW','call elf_unc_chdir').replace('API GetEnvironmentVariableW','call elf_mock_path')
   backend='src/win/extstorejob.s';changes[backend]=(ROOT/backend).read_text().replace('API CreateProcessW','call elf_check_create')
   if mode==10:
    old='    cmp rcx, 1\n    ja 12f\n    mov rax, [rbx + ESJ_legacy]';assert old in changes[backend];changes[backend]=changes[backend].replace(old,old.replace('ja 12f','jmp 12f'),1)
   fixture+='''
.section .rdata,"dr"
elf_mock_path_value: .short 'C',':','/','p','a','t','h',' ',0x3a9,0
elf_expected_env: .short 'L','C','_','A','L','L','=','C',0,'P','A','T','H','=','C',':','/','p','a','t','h',' ',0x3a9,0,'R','H','U','N','_','L','E','G','A','C','Y','_','C','W','D','=','/','/','s','e','r','v','e','r','/','s','h','a','r','e','/','w','o','r','k',' ',0x3a9,0,0
elf_expected_env_end:
elf_unc_wide: .short '/','/','s','e','r','v','e','r','/','s','h','a','r','e','/','w','o','r','k',' ',0x3a9,0
.text
FN elf_mock_path
    lea r10, [rip + elf_mock_path_value]
    xor eax, eax
1:  mov r11w, [r10 + rax*2]
    mov [rdx + rax*2], r11w
    inc eax
    test r11w, r11w
    jnz 1b
    dec eax
    ret
FN elf_unc_cwd
    lea r10, [rip + elf_unc_wide]
    xor eax, eax
1:  mov r11w, [r10 + rax*2]
    mov [rdx + rax*2], r11w
    inc eax
    test r11w, r11w
    jnz 1b
    dec eax
    ret
FN elf_unc_chdir
    lea r10, [rip + elf_unc_wide]
1:  mov ax, [r10]
    cmp ax, [rcx]
    jne 2f
    test ax, ax
    jz 3f
    add r10, 2
    add rcx, 2
    jmp 1b
2:  xor eax, eax
    ret
3:  mov eax, 1
    ret
FN elf_check_create
    push rcx
    push rdx
    push r8
    push r9
    mov r10, [rsp + 88]
    lea r11, [rip + elf_expected_env]
4:  mov ax, [r10]
    cmp ax, [r11]
    jne 2f
    add r10, 2
    add r11, 2
    lea rax, [rip + elf_expected_env_end]
    cmp r11, rax
    jb 4b
    mov r10, [rsp + 96]
    lea r11, [rip + esjlt_expected_windows_directory]
1:  mov ax, [r10]
    cmp ax, [r11]
    jne 2f
    test ax, ax
    jz 3f
    add r10, 2
    add r11, 2
    jmp 1b
2:  pop r9
    pop r8
    pop rdx
    pop rcx
    xor eax, eax
    ret
3:  pop r9
    pop r8
    pop rdx
    pop rcx
    jmp [rip + __imp_CreateProcessW]
'''
  if mode in(11,12):
   entry="'P','A','T','H','=','C',':','/','p','a','t','h',' ',0x3a9,0,"
   fixture=fixture.replace(entry,"'P','A','T','H','=',0,"if mode==11 else'')
   start=fixture.index('FN elf_mock_path\n');end=fixture.index('FN elf_unc_cwd\n',start)
   fixture=fixture[:start]+('FN elf_mock_path\n    xor eax, eax\n    ret\n'if mode==11 else'FN elf_mock_path\n    PROLOGUE 96\n    mov ecx, 203\n    API SetLastError\n    xor eax, eax\n    EPILOGUE\n')+fixture[end:]
  changes[path]=source
 return m.build(folder,fixture,changes,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);a=p.parse_args();windows=a.windows_build or bool(a.wine)or os.name=='nt'
 modes=[*range(9),10,11,12,13]if windows else(9,)
 for mode in modes:
  exe=build((a.build_only or ROOT/'build/legacy-context-faults')/str(mode),mode,windows)
  if a.build_only:continue
  if mode==13:
   for case in range(16):
    r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(case)],capture_output=True,timeout=10)
    assert r.returncode==0 and not r.stderr and len(r.stdout)==16,(case,r)
    status,calls=struct.unpack('<qq',r.stdout)
    assert(status==0 and calls==(case!=0))if case in(0,13,14)else(status<0 and calls==0),(case,status,calls)
   print('ok legacyjob/child-bootstrap-absent-malformed-device-UNC-bounds-UTF8',flush=True);continue
  with tempfile.TemporaryDirectory(prefix='rhun-legacy-context-Ω ',dir=a.wine_drive_root)as folder:
   root=Path(folder).resolve();native='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(root)
   env=os.environ.copy()
   if not windows:env['PATH']='x'*65535
   if mode>=5 and mode<=7:
    (root/'extension.ini').write_text('owner=Foo\nname=Bar\ntitle=Legacy\nversion=1\nprotocol=1\nrun.windows-x64=C:/unused.exe\n')
    parent_mode='5'
   elif mode in(8,10,11,12):
    b=bytearray(512);b[:8]=b'RHLSS1\0\0';struct.pack_into('<IIQI',b,8,1,192,512,2);b[96:128]=b'\xbb'*32;struct.pack_into('<I',b,144,1);struct.pack_into('<I',b,152,0xffffffff);(root/'.job-wire').write_bytes(b);parent_mode='32'
   else:parent_mode='30'
   if mode in(5,6):
    (root/'.job-source').write_bytes(b'\xbb'*32)
    proof=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'4'],env=env,cwd=root,capture_output=True,timeout=25)
    assert proof.returncode==0 and not proof.stdout and not proof.stderr,(mode,proof)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,parent_mode],env=env,cwd=root,capture_output=True,timeout=25)
   if mode==10:
    assert r.returncode!=0 and not r.stdout,(mode,r)
    print('ok legacyjob/context-fixed-environment-negative-control',flush=True);continue
   assert r.returncode==0 and not r.stderr,(mode,r)
   if mode in(5,6,7):assert r.stdout==b'',(mode,r.stdout)
   else:
    status,cleanup,length,steps=struct.unpack('<qqQQ',r.stdout)
    expected=0 if mode in(8,11,12) else-7 if mode in(1,4,9)else-13
    assert status==expected and cleanup==0 and length==(512 if mode in(8,11,12) else 0),(mode,status,cleanup,length,steps)
   print('ok legacyjob/context-boundary/'+str(mode),flush=True)
if __name__=='__main__':main()
