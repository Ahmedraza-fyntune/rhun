#!/usr/bin/env python3
"""Typed immutable CG source, real input copy, and ownership regressions."""
import argparse,importlib.util,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'type-bypass':110,'ignore-ready':111,'wrong-row-base':112,'wrong-count':112,
       'ignore-kind':112,'force-ksi':113,'forget-kind':113,'current-context':114}
def build(folder,windows=False,mutation=None):
 spec=importlib.util.spec_from_file_location('key_copy_fixture',ROOT/'tests/keyline-snapshot.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 extra={}
 def change(path,old,new):
  text=extra.get(path,(ROOT/path).read_text());assert text.count(old)==1,(mutation,path,old);extra[path]=text.replace(old,new,1)
 path='src/app/commandgenerationkeycopy.s'
 if mutation=='type-bypass':change(path,'    call cg_active\n','    xor eax, eax\n')
 if mutation=='ignore-ready':change(path,'    cmp qword ptr [rbx + PO_ready], 1\n    jne .Lkcpy_invalid','    cmp qword ptr [rbx + PO_ready], 1\n    nop')
 if mutation=='wrong-row-base':change(path,'    lea rcx, [rbx + CG_keylines]','    lea rcx, [rbx + KSI_rows]')
 if mutation=='wrong-count':change(path,'    mov rdx, [rbx + CG_nkeys]','    mov rdx, [rbx + CG_nmanifest]')
 if mutation=='ignore-kind':change(path,'    cmp rsi, KSC_CG\n    jne .Lkcpy_invalid','    cmp rsi, KSC_CG\n    nop')
 if mutation=='force-ksi':change(path,'    mov r8d, KSC_CG','    xor r8d, r8d')
 if mutation=='forget-kind':change('src/app/keylinesnapshotcopy.s','    mov [r15 + KSC_kind], r14','    nop')
 if mutation=='current-context':change(path,'    cmp qword ptr [rbx + PO_ready], 1','    mov rax, [rip + cgbt_context]\n    cmp [rbx + CG_intent], rax\n    jne .Lkcpy_invalid\n    cmp qword ptr [rbx + PO_ready], 1')
 return m.build(folder,windows,limits=True,addon_suffix=(ROOT/'tests/command_key_copy_cases.inc').read_text(),extra_sources=extra)
def main():
 p=argparse.ArgumentParser();p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--mutation',choices=CODES);p.add_argument('--negative-controls',action='store_true');a=p.parse_args()
 if a.build_only and not a.exe:p.error('--build-only requires --exe')
 if a.negative_controls and(a.exe or a.build_only or a.mutation):p.error('negative controls build their own fixtures')
 windows=os.name=='nt'or bool(a.wine)or bool(a.build_only and a.exe.suffix=='.exe')
 with tempfile.TemporaryDirectory(prefix='rhun-command-key-copy-')as temporary:
  folder=Path(temporary);config=folder/'config';(config/'rhun').mkdir(parents=True)
  env=os.environ.copy();env['XDG_CONFIG_HOME']=('Z:'+str(config.resolve()))if a.wine else str(config)
  def check(exe,mutation=None):
   (config/'rhun/config').write_text('[keys]\nctrl+alt+9 = none\nmalformed line\nctrl+q = quit\n')
   r=subprocess.run(([a.wine,'Z:'+str(exe.resolve())]if a.wine else[str(exe.resolve())]),cwd=ROOT,env=env,capture_output=True,timeout=180)
   if mutation:
    assert r.returncode==CODES[mutation]and not r.stdout and not r.stderr,(mutation,r.returncode,r.stdout,r.stderr)
    print('ok CG key-copy negative control '+mutation,flush=True)
   else:
    assert r.returncode==0 and r.stdout==b'ok immutable command-generation keyline copy and owner lifetimes\n'and not r.stderr,(r.returncode,r.stdout,r.stderr)
    print(r.stdout.decode().strip(),flush=True)
  if a.negative_controls:
   check(build(folder/'normal',windows))
   for mutation in CODES:check(build(folder/mutation,windows,mutation),mutation)
  else:
   exe=a.exe if a.exe and not a.build_only else build(folder/'build',windows,a.mutation)
   if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(exe,a.exe);shutil.copymode(exe,a.exe);return
   check(exe,a.mutation)
if __name__=='__main__':main()
