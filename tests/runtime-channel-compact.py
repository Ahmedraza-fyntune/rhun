#!/usr/bin/env python3
"""Memory-only bounded output compaction, exact refusals, and copy byte accounting."""
import argparse,importlib.util,os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'skip-quota':91,'wrong-offset':92,'mutate-refusal':91,'skip-span':104}
def build(folder,windows=False,mutation=None):
 spec=importlib.util.spec_from_file_location('channel_compact_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 source=(ROOT/'src/app/extqueuecompact.s').read_text()
 assert re.findall(r'\bcall ([A-Za-z_][A-Za-z_0-9]*)',source)==['memmove']
 assert not re.search(r'^\s*(?:SYS|API)\b',source,re.M)
 if mutation:
  old,new={
   'skip-quota':('    cmp rax, rsi\n    ja .Lqcb_again','    cmp rax, rsi\n    nop'),
   'wrong-offset':('    lea rsi, [r8 + rcx]','    mov rsi, r8'),
   'mutate-refusal':('.Lqcb_again:\n    mov rax, -11','.Lqcb_again:\n    mov qword ptr [rdi + EXT_wq_off], 0\n    mov rax, -11'),
   'skip-span':('    add rdx, r8\n    jc .Lqcb_bad','    add rdx, r8\n    nop'),
  }[mutation];assert source.count(old)==1;source=source.replace(old,new,1)
 assert source.count('call memmove')==1;source=source.replace('call memmove','call cq_move')
 fixture=(ROOT/'tests/runtime_channel_compact_cases.inc').read_text()
 assert not any(re.search(r'(?m)^\s*\.section \.rodata\.',s)for s in [source,fixture])
 return b.build(folder,fixture,{'src/app/extqueuecompact.s':source},windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--mutation',choices=list(CODES));p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and(a.exe or a.build_only or a.mutation):p.error('controls require fresh builds')
 windows=os.name=='nt'or bool(a.wine)or bool(a.build_only and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-channel-compact-')as d:
  def check(exe,mutation):
   r=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe.resolve())]),capture_output=True,timeout=60)
   assert r.returncode==CODES.get(mutation,0)and not r.stderr,(mutation,r)
   assert r.stdout==(b''if mutation else b'ok bounded channel queue compaction\n'),(mutation,r)
   print('ok channel compactor '+(mutation or'baseline'),flush=True)
  if a.negative_controls:
   for mutation in [None,*CODES]:check(build(Path(d)/(mutation or'baseline'),windows,mutation),mutation)
  else:
   exe=a.exe if a.exe and not a.build_only else build(Path(d),windows,a.mutation)
   if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);return
   check(exe,a.mutation)
if __name__=='__main__':main()
