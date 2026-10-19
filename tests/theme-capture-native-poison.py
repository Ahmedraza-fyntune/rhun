#!/usr/bin/env python3
"""The theme factory must not rediscover its executable after startup."""
import argparse,importlib.util,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe',type=Path);p.add_argument('--negative-control',action='store_true');a=p.parse_args()
 windows=bool(a.wine)or os.name=='nt'
 def build(folder):
  spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  symbol='ext_store_job_module_path'if windows else'proc_self_path';path='src/win/extstorejob.s'if windows else'src/proc.s'
  core=(ROOT/path).read_text();old='FN '+symbol+'\n';assert old in core;core=core.replace(old,'FN tcn_real_self\n',1)
  fixture=(ROOT/'tests/theme_capture_native_test.s').read_text().replace('90: mov r15, [rip + g_mem_live]','90: mov qword ptr [rip + tcn_poison], 1\n    mov r15, [rip + g_mem_live]',1)
  fixture+='\n.bss\n.p2align 3\ntcn_poison: .zero 8\n.text\nFN '+symbol+'\n    cmp qword ptr [rip + tcn_poison], 0\n    je tcn_real_self\n    mov rax, -13\n    ret\n'
  replacements={path:core}
  if a.negative_control:
   path='src/app/extsettingsnative.s';core=(ROOT/path).read_text();assert'call ext_store_job_legacy_copy_executable'in core
   replacements[path]=core.replace('call ext_store_job_legacy_copy_executable','call '+symbol,1)
  return m.build(folder,fixture,replacements,windows)
 if a.build_only:
  build(a.build_only);return
 with tempfile.TemporaryDirectory(prefix='rhun-theme-native-poison-')as td:
  exe=a.exe or build(Path(td));foreign=None
  if not windows:
   foreign=os.open(__file__,os.O_RDONLY);os.dup2(foreign,150,inheritable=True);os.close(foreign)
  try:
   for mode in(0,1,2,3,4):
    opts={}
    if not windows:
     import resource
     opts={'pass_fds':(150,),'preexec_fn':lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))}
    r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(mode)],capture_output=True,timeout=20,**opts)
    if a.negative_control:
     assert r.returncode==73 and not r.stdout and not r.stderr,(mode,r);break
    assert r.returncode==0 and not r.stdout and not r.stderr,(mode,r)
  finally:
   if not windows:os.close(150)
 print('ok theme-capture-native/'+('parent-path-IO-negative-control'if a.negative_control else'cached-executable-parent-IO-poison'),flush=True)
if __name__=='__main__':main()
