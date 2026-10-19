#!/usr/bin/env python3
"""Actual scoped memory, admission faults and deadline-driven common cleanup."""
import argparse,importlib.util,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,windows=False,mutation=None):
 spec=importlib.util.spec_from_file_location('unit_fixture_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 replacements={}
 for name in ['extlaunchscratch','extpreparepump']:
  s=(ROOT/'src/app'/(name+'.s')).read_text()
  if mutation=='end-retry'and name=='extlaunchscratch':
   old='1:  jmp launch_result';new='1:  PROLOGUE\n    call time_ms\n    mov rdi, rax\n    call ext_launch_scratch_tick\n    EPILOGUE';assert s.count(old)==1;s=s.replace(old,new)
  if mutation=='free-borrowed'and name=='extlaunchscratch':
   old='    mov rdi, [rip + launch_po]\n    test rdi, rdi\n    jz 2f';new='''    mov rax, [rip + launch_argv]
    cmp qword ptr [rax + VEC_len], 0
    je 991f
    mov rax, [rax + VEC_ptr]
    mov rdi, [rax]
    call mem_free
991:
'''+old;assert s.count(old)==1;s=s.replace(old,new)
  if mutation=='early-retry'and name=='extpreparepump':
   old='    cmp r12, [rip + pump_due]\n    jb .Lpp_retire';assert s.count(old)==1;s=s.replace(old,'    nop')
  if mutation=='stale-clock'and name=='extpreparepump':
   old='    call time_ms';assert s.count(old)==1;s=s.replace(old,'    mov rax, r12')
  if mutation=='over-budget'and name=='extpreparepump':
   old='    mov eax, 16\n    cmp rdi, rax';assert s.count(old)==1;s=s.replace(old,'    mov eax, 64\n    cmp rdi, rax')
  if mutation=='uncapped-backoff'and name=='extpreparepump':
   old='    cmova rax, rdx';assert s.count(old)==1;s=s.replace(old,'    nop')
  s=s.replace('call time_ms','call lsu_time')
  if name=='extlaunchscratch':
   assert s.count('call prep_owned_dispose')==1 and s.count('call ext_prepare_owner_release_deferred')==1
   s=s.replace('call prep_owned_dispose','call lsu_dispose').replace('call ext_prepare_owner_release_deferred','call lsu_drop')
  replacements['src/app/'+name+'.s']=s
 s=(ROOT/'src/mem.s').read_text();assert s.count('FN mem_alloc_try\n')==1
 s=s.replace('FN mem_alloc_try\n','''FN mem_alloc_try
    cmp qword ptr [rip + lsu_fail_at], 0
    je lsu_allocate_actual
    inc qword ptr [rip + lsu_allocations]
    mov rax, [rip + lsu_allocations]
    cmp rax, [rip + lsu_fail_at]
    jne lsu_allocate_actual
    xor eax, eax
    ret
FN lsu_allocate_actual
''');assert s.count('SYS SYS_munmap')==1;s=s.replace('SYS SYS_munmap','call lsu_native_unmap');replacements['src/mem.s']=s
 s=(ROOT/'src/app/extprepareretirestep.s').read_text();assert s.count('call ext_root_close')==1;replacements['src/app/extprepareretirestep.s']=s.replace('call ext_root_close','call lsu_close')
 return b.build(folder,(ROOT/'tests/faults/ext_launch_scratch_unit.s').read_text(),replacements,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=['end-retry','free-borrowed','early-retry','stale-clock','over-budget','uncapped-backoff']);a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('negative controls build their own native fixtures')
 windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix=='.exe')
 codes={'end-retry':107,'free-borrowed':106,'early-retry':109,'stale-clock':110,'over-budget':109,'uncapped-backoff':111}
 with tempfile.TemporaryDirectory(prefix='rhun-launch-unit-')as t:
  t=Path(t)
  for mutation in ([None,*codes]if a.negative_controls else[a.mutation]):
   exe=a.exe if a.exe and not a.build_only else build(t/(mutation or'normal'),windows,mutation)
   if a.build_only:
    a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);print('built launch ownership fixture',flush=True);return
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],capture_output=True,timeout=30)
   assert r.returncode==(codes[mutation]if mutation else 0)and not r.stdout and not r.stderr,(mutation,r.returncode,r.stdout,r.stderr)
   print('ok launch ownership negative control '+mutation if mutation else'ok launch ownership faults, checked transfers and bounded retry cohorts',flush=True)
if __name__=='__main__':main()
