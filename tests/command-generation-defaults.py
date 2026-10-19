#!/usr/bin/env python3
"""Immutable runtime shortcut fallback evidence under retained real suppliers."""
import argparse,importlib.util,os,subprocess,tempfile,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'skip-later':80,'duplicate-word':80,'ignore-user':81,'prepend':80,'skip-supplier':80,'getter-allocation':80,'wrong-winner':80}
def build(folder,windows=False,mutation=None,limits=False):
 spec=importlib.util.spec_from_file_location('cg_default_builder',ROOT/'tests/command-generation-build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 extra={}
 if mutation:
  relative='src/app/commandgenerationinputs.s'if mutation=='skip-supplier'else'src/app/commandgenerationdefaults.s'
  s=(ROOT/relative).read_text()
  old,new={
   'skip-later':('    cmp [r14], r13\n    je .Lcgd_note_ok','    jmp .Lcgd_note_ok'),
   'duplicate-word':('    cmp [r14], r13\n    je .Lcgd_note_ok','    nop'),
   'ignore-user':('    bts qword ptr [r12], CG_DEFAULT_USER_BIT','    nop'),
   'prepend':('    test r14, r14\n    jz 1f\n    mov [r14 + 8], r15\n    jmp 2f','    mov rdx, [r12]\n    mov [rax + 8], rdx\n    mov [r12], r15\n    jmp 2f'),
   'skip-supplier':('    call ext_runtime_retain','    xor eax, eax'),
   'getter-allocation':('FN command_generation_binding_route\n    PROLOGUE 48','FN command_generation_binding_route\n    PROLOGUE 48\n    call cfd_getter_alloc_noise'),
   'wrong-winner':('    mov [rsp], rax\n    mov rax, [rbx + CG_defaultnodes]','    call keys_none_command\n    mov [rsp], rax\n    mov rax, [rbx + CG_defaultnodes]'),
  }[mutation]
  assert s.count(old)==1,(mutation,s.count(old));extra[relative]=s.replace(old,new)
 addon=(ROOT/'tests/faults/command_generation_defaults.s').read_text()
 if limits:
  addon=addon.replace('FN main\n','FN original_defaults_main\n')+'\n'+(ROOT/'tests/faults/command_generation_defaults_limits.inc').read_text()
 return b.build(folder,windows=windows,addon=addon,extra_replacements=extra,mem_unmap_hook='cfl_native_unmap'if limits else None)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=list(CODES));p.add_argument('--limits',action='store_true');a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and(a.exe or a.build_only or a.mutation):p.error('negative controls build their own fixtures')
 if a.limits and(a.negative_controls or a.mutation):p.error('--limits uses its own cases; ordinary semantic controls require their original inputs')
 windows=os.name=='nt'or bool(a.wine)or bool(a.build_only and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-command-defaults-')as t:
  for mutation in ([None,*CODES]if a.negative_controls else[a.mutation]):
   exe=a.exe if a.exe and not a.build_only else build(Path(t)/(mutation or'normal'),windows,mutation,a.limits)
   if a.build_only:
    a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);print('built immutable runtime defaults fixture',flush=True);return
   result=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe)]),capture_output=True,timeout=180 if a.limits else 60)
   if mutation:assert result.returncode==CODES[mutation]and not result.stdout and not result.stderr,(mutation,result.returncode,result.stdout,result.stderr)
   else:assert result.returncode==0 and result.stdout==(b'ok maximum runtime default chains and allocation phases\n'if a.limits else b'ok immutable runtime default chains and override authority\n')and not result.stderr,(result.returncode,result.stdout,result.stderr)
   print('ok runtime default negative control '+mutation if mutation else result.stdout.decode().strip(),flush=True)
if __name__=='__main__':main()
