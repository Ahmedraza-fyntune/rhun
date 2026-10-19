#!/usr/bin/env python3
"""Reuse actual native error shims against the legacy purpose5 ownership path."""
import argparse,os,struct,subprocess,tempfile,types
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);a=p.parse_args();windows=a.windows_build or bool(a.wine)or os.name=='nt'
 source=(ROOT/'tests/ext-store-job-faults.py').read_text().replace("'tests/ext_store_job_test.s'","'tests/ext_store_job_legacy_test.s'")
 # Legacy fixture has its own NULL-start admission and post-close poison reset.
 a7=source.index("        old='    cmp rdx, 1\\n",source.index("    fixture=(ROOT/"))
 b7=source.index('    if mode==14:',a7)
 source=source[:a7]+"        old='    cmp rdx, 1\\n    jne esjt_fail\\n    mov qword ptr [rip + esjlt_forbid_io], 0'\n        assert fixture.count(old)==1\n        fixture=fixture.replace(old,'    cmp rdx, 1\\n    jne esjt_fail\\n    mov rdi, rsp\\n    call esjf_restart\\n    test rax, rax\\n    jnz esjt_fail\\n    mov qword ptr [rip + esjlt_forbid_io], 0',1)\n"+source[b7:]
 ac=source.index('    if mode in (9,13):');bc=source.index("    fixture+='",ac)
 source=source[:ac]+source[bc:]
 # Bind every actual native signal to the current owned process and enforce terminate-once.
 before="    return module.build(folder,fixture,{relative:source,'src/app/extstorejob.s':core},windows=windows)"
 assert before in source
 spy=r"""
    source=source.replace('FN ext_store_job_native_kill\n','FN ext_store_job_native_kill\n    mov rax, [rdi + ESJ_process]\n    mov [rip + esjlf_expected_process], rax\n',1)
    source=source.replace('API TerminateProcess'if windows else'SYS SYS_kill','call esjlf_checked_kill')
    fixture='.equ ESJLF_KILL_SPY, 1\n.equ ESJF_MODE, '+str(mode)+'\n'+fixture+'\n.bss\n.globl esjlf_expected_process, esjlf_kill_count\nesjlf_expected_process: .zero 8\nesjlf_kill_count: .zero 8\n.text\nFN esjlf_checked_kill\n'
    fixture+=('    cmp rcx, [rip + esjlf_expected_process]\n'if windows else'    cmp rdi, [rip + esjlf_expected_process]\n')+'    jne esjt_fail\n    inc qword ptr [rip + esjlf_kill_count]\n    cmp qword ptr [rip + esjlf_kill_count], 1\n    ja esjt_fail\n'
    if mode==20:
        fixture+=('    PROLOGUE 96\n    mov ecx, 5\n    API SetLastError\n    xor eax, eax\n    EPILOGUE\n'if windows else'    mov rax, -5\n    ret\n')
    else:fixture+=('    jmp [rip + __imp_TerminateProcess]\n'if windows else'    SYS SYS_kill\n    ret\n')
"""
 source=source.replace(before,spy+'\n'+before)
 builder=types.ModuleType('legacy_native_faults');builder.__file__=str(ROOT/'tests/ext-store-job-faults.py');exec(compile(source,builder.__file__,'exec'),builder.__dict__)
 expected={0:0,1:0,2:0,3:-5,4:-5,5:0,7:0,9:-12,13:-24,12:-125,14:-125,15:0,16:-5,20:-125}
 if windows:expected[17]=-5
 else:expected.update({6:-10,8:-24,10:-5})
 with tempfile.TemporaryDirectory(prefix='rhun-legacy-native-',dir=a.wine_drive_root)as directory:
  folder=Path(directory).resolve();options={};fd=None
  if not windows:
   import fcntl,resource
   original=os.open(folder/'poison',os.O_CREAT|os.O_RDWR,0o600);fd=fcntl.fcntl(original,fcntl.F_DUPFD,150);os.close(original)
   options={'pass_fds':(fd,),'preexec_fn':lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))}
  def run(mode,mutation=None):
   name=str(mode)+(('-'+mutation)if mutation else'');exe=builder.build((a.build_only or folder)/name,mode,windows,mutation)
   if a.build_only:return None
   root=folder/('root'+name);root.mkdir();wire=bytearray(512);wire[:8]=b'RHLSS1\0\0';struct.pack_into('<IIQI',wire,8,1,192,len(wire),2);wire[96:128]=b'\xbb'*32;struct.pack_into('<I',wire,144,1);struct.pack_into('<I',wire,152,0xffffffff if windows else 0);(root/'.job-wire').write_bytes(wire)
   if mode==20:(root/'.job-test-mode').write_text('q')
   native='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(root)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'1'if mode==20 else'30'if mode in(9,13)else'0'],cwd=root,capture_output=True,timeout=25,**options)
   assert r.returncode==0 and not r.stderr and len(r.stdout)==32,(mode,mutation,r)
   return struct.unpack('<qqQQ',r.stdout)
  for mode,status in expected.items():
   result=run(mode)
   if result is not None:
    primary,secondary,length,steps=result
    assert primary==status and secondary in((-5,)if mode==13 else(-13,)if windows and mode==20 else(-5,)if mode==20 else(0,-13)if mode==17 else(0,))and length==(512 if status==0 else 0),(mode,result)
    print('ok legacyjob/native-fault/'+str(mode),flush=True)
  for mode,mutation in((14,'budget'),(12,'cancel'),(15,'inherit')):
   result=run(mode,mutation)
   if result is not None:
    assert result[0]==(-5 if mutation=='inherit'else-33),result
    print('ok legacyjob/negative-control/'+mutation,flush=True)
  if fd is not None:os.close(fd)
if __name__=='__main__':main()
