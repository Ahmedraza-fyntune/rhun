#!/usr/bin/env python3
"""Stable helper source reads preserve primary/cleanup failures and exact ownership."""
from pathlib import Path
import argparse,importlib.util,os,struct,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows,path_allocs=1):
 spec=importlib.util.spec_from_file_location('theme_file_link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_file_test.s').read_text()
 core=(ROOT/'src/app/themecaptureio.s').read_text()
 for name in('open','stat','read','close'):
  old='FN tc_file_'+name+'\n';assert old in core;core=core.replace(old,'FN tcf_real_'+name+'\n',1)
 old='FN tc_before_deadline\n';assert old in core;core=core.replace(old,'FN tcf_real_deadline\n',1)
 replacements={'src/app/themecaptureio.s':core}
 expected_closes=0 if mode==1 else 1
 fixture=fixture.replace('    mov [rsp + 136], rdx\n','    mov [rsp + 136], rdx\n    cmp qword ptr [rip + tcf_closes], '+str(expected_closes)+'\n    jne tcf_fail\n',1)
 fixture+='''
.bss
tcf_opens: .zero 8
tcf_stats: .zero 8
tcf_reads: .zero 8
tcf_closes: .zero 8
tcf_deadlines: .zero 8
tcf_native_stats: .zero 8
tcf_observation: .zero 64
.section .rodata
tcf_mutbyte: .byte 90
.text
FN tc_file_open
    inc qword ptr [rip + tcf_opens]
'''
 if mode==1:fixture+='    mov rax, -13\n    ret\n'
 elif mode==6:fixture+='    cmp qword ptr [rip + tcf_opens], 1\n    jne tcf_real_open\n    mov rax, -4\n    ret\n'
 else:fixture+='    jmp tcf_real_open\n'
 fixture+='FN tc_file_close\n    inc qword ptr [rip + tcf_closes]\n'
 if mode in(7,8,9):fixture+='    PROLOGUE\n    call tcf_real_close\n    mov rax, '+str(-13 if mode==8 else-5)+'\n    EPILOGUE\n'
 else:fixture+='    jmp tcf_real_close\n'
 fixture+='FN tc_before_deadline\n    inc qword ptr [rip + tcf_deadlines]\n'
 if mode in(15,16):fixture+='    cmp qword ptr [rip + tcf_deadlines], '+str(3 if mode==15 else 8)+'\n    jb tcf_real_deadline\n    mov rax, -110\n    ret\n'
 else:fixture+='    jmp tcf_real_deadline\n'
 fixture+='FN tc_file_stat\n    inc qword ptr [rip + tcf_stats]\n'
 if mode in(2,9):fixture+='    mov rax, '+str(-13 if mode==9 else-5)+'\n    ret\n'
 elif mode==5:fixture+='    cmp qword ptr [rip + tcf_stats], 1\n    jne tcf_real_stat\n    mov rax, -4\n    ret\n'
 elif mode in(10,12):
  fixture+='''    PROLOGUE
    mov rbx, rsi
    call tcf_real_stat
    test rax, rax
    js 9f
'''
  if mode==10:fixture+='    cmp qword ptr [rip + tcf_stats], 2\n    jne 9f\n    inc qword ptr [rbx + TCSTAT_mtime]\n    xor eax, eax\n'
  else:fixture+='''    cmp qword ptr [rip + tcf_stats], 1
    jne 1f
    lea rdi, [rip + tcf_observation]
    mov rsi, rbx
    mov edx, 64
    call memcpy
    xor eax, eax
    jmp 9f
1:  mov rdi, rbx
    lea rsi, [rip + tcf_observation]
    mov edx, 64
    call memcpy
    xor eax, eax
'''
  fixture+='9:  EPILOGUE\n'
 else:fixture+='    jmp tcf_real_stat\n'
 fixture+='FN tc_file_read\n    inc qword ptr [rip + tcf_reads]\n'
 if mode in(3,8):fixture+='    mov rax, -5\n    ret\n'
 elif mode==4:fixture+='    cmp qword ptr [rip + tcf_reads], 1\n    jne tcf_real_read\n    mov rax, -4\n    ret\n'
 elif mode==21:fixture+='    xor eax, eax\n    ret\n'
 elif mode==23:fixture+='    mov rax, -11\n    ret\n'
 elif mode in(12,13,14,20,22):
  fixture+='''    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
'''
  if mode in(12,13,14):fixture+='    cmp qword ptr [rip + tcf_reads], '+str(3 if mode==12 else 2)+'\n    jne 1f\n    call tcf_mutate\n1:\n'
  fixture+='    mov rdi, rbx\n    mov rsi, r12\n    mov rdx, r13\n    mov rcx, r14\n'
  if mode==22:fixture+='    cmp qword ptr [rip + tcf_reads], 1\n    jne 2f\n    mov edx, 1\n2:\n'
  fixture+='    call tcf_real_read\n'
  if mode==20:fixture+='    test rax, rax\n    js 3f\n    lea rax, [r13 + 1]\n3:\n'
  fixture+='    EPILOGUE\n'
 else:fixture+='    jmp tcf_real_read\n'
 if mode in(12,13,14):
  fixture+='''FN tcf_mutate
    PROLOGUE
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    mov esi, O_WRONLY | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js tcf_fail
    mov rbx, rax
'''
  if mode==13:fixture+='    mov rdi, rbx\n    xor esi, esi\n    mov edx, 2\n    SYS SYS_lseek\n    test rax, rax\n    js tcf_fail\n'
  if mode==14:fixture+='    mov rdi, rbx\n    xor esi, esi\n    SYS SYS_ftruncate\n    test rax, rax\n    js tcf_fail\n'
  else:fixture+='    mov rdi, rbx\n    lea rsi, [rip + tcf_mutbyte]\n    mov edx, 1\n    SYS SYS_write\n    cmp rax, 1\n    jne tcf_fail\n'
  fixture+='    mov rdi, rbx\n    SYS SYS_close\n    test rax, rax\n    js tcf_fail\n    EPILOGUE\n'
 if mode in(11,24):
  if windows:
   path='src/win/themecaptureio.s';replacements[path]=(ROOT/path).read_text().replace('API GetFileInformationByHandle','call tcf_native_stat')
   fixture+='''FN tcf_native_stat
    PROLOGUE 96
    mov rbx, rdx
    API GetFileInformationByHandle
    test eax, eax
    jz 9f
    inc qword ptr [rip + tcf_native_stats]
'''
   if mode==11:fixture+='    cmp qword ptr [rip + tcf_native_stats], 2\n    jne 9f\n    inc qword ptr [rbx + 12]\n'
   else:fixture+='    or dword ptr [rbx], 16\n'
  else:
   replacements['src/app/themecaptureio.s']=core.replace('SYS SYS_fstat','call tcf_native_stat')
   fixture+='''FN tcf_native_stat
    PROLOGUE
    mov rbx, rsi
    SYS SYS_fstat
    test rax, rax
    js 9f
    inc qword ptr [rip + tcf_native_stats]
'''
   if mode==11:fixture+='    cmp qword ptr [rip + tcf_native_stats], 2\n    jne 9f\n    inc qword ptr [rbx + 72]\n'
   else:fixture+='    mov dword ptr [rbx + 24], 0x4000\n'
  fixture+='9:  EPILOGUE\n'
 if windows and mode in(17,18,19,25,26):
  path='src/win/themecaptureio.s';api={17:'SetFilePointerEx',18:'ReadFile',19:'CreateFileW',25:'GetFileInformationByHandle',26:'GetFileType'}[mode]
  replacements[path]=(ROOT/path).read_text().replace('API '+api,'call tcf_native_fail')
  fixture+='FN tcf_native_fail\n    PROLOGUE 96\n    mov ecx, '+str(5 if mode in(17,26)else 997)+'\n    API SetLastError\n    '+('mov rax, -1'if mode==19 else'xor eax, eax')+'\n    EPILOGUE\n'
 if windows and mode==17:
  replacements['src/win/themecaptureio.s']=replacements['src/win/themecaptureio.s'].replace('API ReadFile','call tcf_forbidden_read')
  fixture+='FN tcf_forbidden_read\n    mov edi, 74\n    call sys_exit\n'
 if windows and mode in(18,19,25):
  fixture=fixture.replace('FN tcf_native_fail\n    PROLOGUE 96','FN tcf_native_fail\n    PROLOGUE 96\n    mov qword ptr [rip + tcf_pending], 1',1)
  replacements['src/mem.s']=(ROOT/'src/mem.s').read_text().replace('FN mem_free\n','FN tcf_real_free\n',1)
  fixture+='\n.bss\ntcf_pending: .zero 8\n.text\nFN mem_free\n    cmp qword ptr [rip + tcf_pending], 0\n    je tcf_real_free\n    mov edi, 74\n    call sys_exit\n'
 if mode>=101:
  ordinal=mode-100;mem=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN tcf_real_alloc\n',1);replacements['src/mem.s']=mem
  fixture=fixture.replace('    call tc_file_capture','    mov qword ptr [rip + tcf_alloc_armed], 1\n    call tc_file_capture',1)
  fixture=fixture.replace('    cmp qword ptr [rip + tcf_closes], 1','    cmp qword ptr [rip + tcf_closes], '+str(0 if windows and ordinal<=path_allocs else 1),1)
  fixture+='\n.bss\ntcf_alloc_armed: .zero 8\ntcf_alloc_count: .zero 8\n.text\nFN mem_alloc_try\n    cmp qword ptr [rip + tcf_alloc_armed], 0\n    je tcf_real_alloc\n    inc qword ptr [rip + tcf_alloc_count]\n    cmp qword ptr [rip + tcf_alloc_count], '+str(ordinal)+'\n    jne tcf_real_alloc\n    xor eax, eax\n    ret\n'
 return m.build(folder,fixture,replacements,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=a.windows_build or bool(a.wine)or os.name=='nt'
 expected={0:(0,0),1:(-13,0),2:(-5,0),3:(-5,0),4:(0,0),5:(0,0),6:(0,0),7:(0,-5),8:(-5,-13),9:(-13,-5),10:(-1008,0),11:(0,0),12:(-1008,0),13:(-1008,0),14:(-1008,0),15:(-110,0),16:(-110,0),20:(-5,0),21:(-1008,0),22:(0,0),23:(-11,0),24:(-22,0)}
 if windows:expected.update({17:(-13,0),18:None,19:None,25:None,26:(-13,0)})
 for ordinal in range(1,5 if windows else 4):expected[100+ordinal]=(-12,0)if ordinal<(4 if windows else 3)else(0,0)
 with tempfile.TemporaryDirectory(prefix='rhun-theme-file-fault-',dir=a.wine_drive_root)as folder:
  file=Path(folder).resolve()/'source.theme';data=b'kind=dark\nbg=#111111\n'
  native='C:/'+file.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(file)if a.wine else str(file)
  for mode,status in expected.items():
   exe=build((a.build_only or ROOT/'build/theme-file-faults')/str(mode),mode,windows)
   if a.build_only:continue
   file.write_bytes(data);r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'65536'],capture_output=True,timeout=15)
   if status is None:
    assert r.returncode==70 and not r.stdout and not r.stderr,(mode,r)
   else:
    assert r.returncode==0 and not r.stderr and len(r.stdout)>=88,(mode,r)
    primary,cleanup,length=struct.unpack_from('<qqQ',r.stdout)
    assert(primary,cleanup)==status,(mode,primary,cleanup,status)
    assert len(r.stdout)==88+length and r.stdout[-24:]==bytes(24),(mode,length,r.stdout[-24:])
    if status==(0,0):assert r.stdout[64:-24]==data,(mode,r.stdout)
    else:assert length==0 and r.stdout[24:64]==bytes(40),(mode,r.stdout)
   print('ok theme-capture/file-fault/'+str(mode),flush=True)
  if windows:
   longfile=Path(folder).resolve()/('x'*120)/('y'*120)/'source.theme'
   longfile.parent.mkdir(parents=True,exist_ok=True)
   native='C:/'+longfile.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(longfile)if a.wine else str(longfile)
   for ordinal in range(1,6):
    mode=100+ordinal
    exe=build((a.build_only or ROOT/'build/theme-file-faults')/('long-'+str(mode)),mode,windows,path_allocs=2)
    if a.build_only:continue
    longfile.write_bytes(data)
    r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'65536'],capture_output=True,timeout=15)
    assert r.returncode==0 and not r.stderr and len(r.stdout)>=88,(mode,'long',r)
    primary,cleanup,length=struct.unpack_from('<qqQ',r.stdout)
    assert(primary,cleanup)==((-12,0)if ordinal<5 else(0,0)),(mode,'long',primary,cleanup)
    assert len(r.stdout)==88+length and r.stdout[-24:]==bytes(24),(mode,'long')
    if ordinal==5:assert r.stdout[64:-24]==data
    else:assert length==0 and r.stdout[24:64]==bytes(40)
    print('ok theme-file/long-path-allocation/'+str(ordinal),flush=True)
if __name__=='__main__':main()
