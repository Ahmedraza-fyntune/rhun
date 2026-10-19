#!/usr/bin/env python3
"""Actual launch callers must relinquish per-attempt argv/environment allocations."""
import argparse,importlib.util,os,subprocess,tempfile,struct,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,setup_failure=False,windows=False,omit_end=False,optional_environment=False):
 spec=importlib.util.spec_from_file_location('launch_fixture_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 source=(ROOT/'src/app/ext.s').read_text();assert source.count('    call proc_spawn\n')==1;source=source.replace('    call proc_spawn\n','    call lsf_consumer\n')
 a=source.index('FN ext_supervised_start_impl\n');z=source.index('# Root calls after publication',a);body=source[a:z]
 assert body.count('    call ext_activation_host_check\n')==1;body=body.replace('    call ext_activation_host_check\n','    xor eax, eax\n')
 assert body.count('    call ext_prepare_supervised\n')==1;body=body.replace('    call ext_prepare_supervised\n','    call lsf_prepare\n')
 if setup_failure:
  assert body.count('    SYS SYS_fcntl\n')==4;body=body.replace('    SYS SYS_fcntl\n','    call lsf_setup_fcntl\n',2)
 source=source[:a]+body+source[z:]
 assert source.count('    call build_env\n')==2;source=source.replace('    call build_env\n','    call build_env\n    call lsf_env_count\n')
 if omit_end:
  assert source.count('    call ext_launch_scratch_end\n')==2;source=source.replace('    call ext_launch_scratch_end\n','    nop\n')
 source+='\n.text\nFN lsf_env_count\n    push rax\n    inc qword ptr [rip + lsf_builds]\n    mov rax, [rip + env_vec + VEC_len]\n    sub rax, 2\n    mov [rip + lsf_info + 16], rax\n    pop rax\n    ret\nFN lsf_prepare\n    mov rdi, [rip + argv_vec + VEC_ptr]\n    mov rsi, [rip + env_vec + VEC_ptr]\n    jmp lsf_consumer\n'
 fixture=(ROOT/'tests/faults/ext_launch_scratch.s').read_text().replace('.ifdef LSF_OPTIONAL','.if 1'if optional_environment else'.if 0')
 if optional_environment:
  inherited=6 if windows else 4
  assert fixture.count('    dec r13\n')==1
  fixture=fixture.replace('    dec r13\n','    sub r13, '+str(inherited)+'\n')
  assert source.count('    sub rax, 2\n')==1
  source=source.replace('    sub rax, 2\n','    sub rax, '+str(inherited+1)+'\n')
 return b.build(folder,fixture,{'src/app/ext.s':source},windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--expect-leak',action='store_true');p.add_argument('--optional-environment',action='store_true');p.add_argument('--build-dir',type=Path);p.add_argument('--exe-dir',type=Path);p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.build_dir and a.exe_dir:p.error('choose --build-dir or --exe-dir')
 if a.negative_controls and (a.build_dir or a.exe_dir or a.expect_leak):p.error('negative controls build their own native fixtures')
 windows=os.name=='nt' or bool(a.wine) or bool(a.build_dir)
 def argument(path):return 'Z:'+str(path.resolve()) if a.wine else str(path.resolve())
 with tempfile.TemporaryDirectory(prefix='rhun-launch-scratch-')as temporary:
  folder=Path(temporary);suffix='.exe'if windows else ''
  if a.build_dir:
   a.build_dir.mkdir(parents=True,exist_ok=True)
   for setup,name in [(False,'normal'),(True,'setup')]:shutil.copyfile(build(folder/name,setup,windows,optional_environment=a.optional_environment),a.build_dir/(name+suffix))
   print('built launch caller fixtures',flush=True);return
  variants=[False,True]if a.negative_controls else[False]
  for omit in variants:
   exes=[a.exe_dir/(name+suffix)if a.exe_dir else build(folder/(name+str(omit)),setup,windows,omit,a.optional_environment)for setup,name in [(False,'normal'),(True,'setup')]]
   for case in [0,1,2]:
    for arguments in [0,2]:
     state=folder/('state-'+str(omit)+'-'+str(case)+'-'+str(arguments));state.mkdir()
     r=subprocess.run(([a.wine]if a.wine else[])+[argument(exes[case==2]),argument(state),str(case),str(arguments)],capture_output=True,timeout=30)
     if a.expect_leak:
      assert r.returncode==73 and len(r.stdout)==32 and not r.stderr,(case,arguments,r)
      delta,calls,generated,words=struct.unpack('<4q',r.stdout)
      assert words==arguments and delta==4*(generated+words),(case,arguments,delta,calls,generated,words)
      assert calls==(0 if case==2 else 4),(case,calls)
      print('reproduced launch scratch retained allocations',case,arguments,delta,flush=True)
     elif omit:assert r.returncode==74 and not r.stdout and not r.stderr,(case,arguments,r)
     else:assert r.returncode==0 and not r.stdout and not r.stderr,(case,arguments,r)
   print('ok omit-end negative control'if omit else'ok actual legacy/supervised/setup launch allocation census',flush=True)
if __name__=='__main__':main()
