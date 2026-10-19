#!/usr/bin/env python3
"""Private command-generation owned input and constructor failure gates."""
import argparse,importlib.util,os,subprocess,tempfile,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False):
 spec=importlib.util.spec_from_file_location('build_cg',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 source=(ROOT/'src/app/commandgeneration.s').read_text();old='call ext_prepare_retire_mark_custom_po';assert source.count(old)==1;source=source.replace(old,'call cgt_mark')
 mem=(ROOT/'src/mem.s').read_text();old='FN mem_alloc_try\n';assert mem.count(old)==1;mem=mem.replace(old,'FN mem_alloc_try\n    jmp cgt_alloc\nFN cgt_real_alloc\n',1)
 fixture='.equ CGT_INSTRUMENTED, 1\n'+(ROOT/'tests/command_generation_input_test.s').read_text()+(ROOT/'tests/faults/command_generation_input_faults.inc').read_text()
 return m.build(folder,fixture,{'src/app/commandgeneration.s':source,'src/mem.s':mem},windows=windows)

def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');a=p.parse_args()
 windows=bool(a.wine)or os.name=='nt'or bool(a.build_only and a.exe and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-cg-input-')as d:
  exe=a.exe if a.exe and not a.build_only else build(Path(d),windows)
  if a.build_only:
   assert a.exe;shutil.copy2(exe,a.exe);return
  result=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe)]),capture_output=True,timeout=30)
  assert result.returncode==0 and result.stdout==b'ok command generation owned inputs and deferred suppliers\n'and not result.stderr,result
 print('ok owned command-generation input, constructor faults, copied key chunks and bounded deferred suppliers')
if __name__=='__main__':main()
