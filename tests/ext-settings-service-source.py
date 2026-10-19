#!/usr/bin/env python3
"""Pure settled source authority on the real settings constructor."""
import argparse,importlib.util,os,re,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine')
a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
expected=b'ok settings domain constructor and retained retirement\n'
def build(folder):
 spec=importlib.util.spec_from_file_location('service_fixture_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_service_cases.inc').read_text();fixture=fixture.replace('    mov qword ptr [rip + svt_stage], 176\n','    call svst_check\n    mov qword ptr [rip + svt_stage], 176\n');fixture += (ROOT/'tests/ext_settings_service_source_cases.inc').read_text();assert '.equ SVT_OKLEN, '+str(len(expected)) in fixture
 replacements={}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 change('src/mem.s','FN mem_alloc_try\n','''FN mem_alloc_try
    cmp qword ptr [rip + svt_poison], 0
    jne svt_poison_fail
    cmp qword ptr [rip + svt_fail_alloc], 0
    je 8f
    inc qword ptr [rip + svt_alloc_count]
    mov rax, [rip + svt_alloc_count]
    cmp [rip + svt_fail_alloc], rax
    jne 8f
    xor eax, eax
    ret
8:
''')
 change('src/app/extsettingsmodelstate.s','FN ext_settings_model_context_init\n','''FN ext_settings_model_context_init
    cmp qword ptr [rip + svt_fail_context], 0
    je 8f
    mov rax, -75
    ret
8:
''')
 change('src/app/extsettingsmemory.s','FN ext_settings_memory_free\n','''FN ext_settings_memory_free
    test rdi, rdi
    jz 8f
    cmp [rip + svt_refuse_free], rdi
    jne 8f
    mov rax, -16
    xor edx, edx
    xor ecx, ecx
    ret
8:
''')
 for path,names in [('src/mem.s',['mem_alloc','mem_free']),('src/sys.s',['file_read_all','file_write_all']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(path,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + svt_poison], 0\n    jne svt_poison_fail\n')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
with tempfile.TemporaryDirectory(prefix='rhun-settings-service-') as t:
 e=a.exe if a.exe and not a.build_only else build(Path(t))
 if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(e,a.exe);print('built settings service foundation '+str(a.exe));sys.exit(0)
 r=subprocess.run(([a.wine] if a.wine else [])+[str(e)],cwd=ROOT,capture_output=True,timeout=90)
 assert r.returncode==0 and r.stdout==expected and not r.stderr,(r.returncode,r.stdout,r.stderr)
 print('ok settings domain constructor faults, owned model detach and budget1 retirement')
