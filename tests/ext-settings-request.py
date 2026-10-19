#!/usr/bin/env python3
"""Incremental REQUEST bytes against actual immutable queue and worker decoder."""
import argparse,importlib.util,os,re,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'body-cap':214,'header':212,'budget':211,'current-cell':212,'early-seal':211,'reset-position':211,'step-allocation':219}
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=CODES);a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('negative controls build their own fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
expected=b'ok counted settings REQUEST producer and immutable rows\n'
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('request_fixture_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settingsqueue_test.s').read_text().replace('FN main','FN original_queue_main')+'\n'+(ROOT/'tests/ext_settings_request_cases.inc').read_text();assert '.equ RQT_OKLEN, '+str(len(expected)) in fixture
 replacements={}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 change('src/mem.s','FN mem_alloc_try\n','''FN mem_alloc_try
    cmp qword ptr [rip + rqt_poison], 0
    jne rqt_poison_fail
    cmp qword ptr [rip + rqt_fail_alloc], 0
    je 8f
    mov qword ptr [rip + rqt_fail_alloc], 0
    xor eax, eax
    ret
8:
''')
 for path,names in [('src/mem.s',['mem_alloc','mem_free']),('src/sys.s',['file_read_all','file_write_all']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(path,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + rqt_poison], 0\n    jne rqt_poison_fail\n')
 text=(ROOT/'src/app/extsettingsmemory.s').read_text();assert text.count('call time_ms')==3;replacements['src/app/extsettingsmemory.s']=text.replace('call time_ms','call rqt_time')
 if windows:change('src/win/sys.s','API VirtualFree','call rqt_native_unmap')
 else:change('src/mem.s','SYS SYS_munmap','call rqt_native_unmap')
 if mutation=='body-cap':change('src/app/extsettingsrequest.s','    cmp r15, EW_LIMIT','    cmp r15, EC_LIMIT')
 elif mutation=='header':change('src/app/extsettingsrequeststep.s','    mov eax, [rcx + EC_seclen]','    xor eax, eax')
 elif mutation=='budget':change('src/app/extsettingsrequeststep.s','    cmova rdx, r14','    mov rdx, rdx')
 elif mutation=='current-cell':change('src/app/extsettingsrequeststep.s','    mov rcx, [r12 + rax + EQB_rows + EQBR_cell]','    mov rcx, [r12 + rax + EQB_rows + EQBR_slot]\n    imul rcx, rcx, EQ_SLOT\n    mov rdx, [r12 + EQB_queue]\n    mov rcx, [rdx + rcx + EQ_slots + EQS_cell]')
 elif mutation=='early-seal':change('src/app/extsettingsrequeststep.s','.Lrqs_next:\n','.Lrqs_next:\n    mov rdi, rbx\n    call ext_settings_frame_seal\n    mov eax, 1\n    jmp .Lrqs_return\n')
 elif mutation=='reset-position':change('src/app/extsettingsrequeststep.s','    add [r13 + ESQ_pos], rax','    mov [r13 + ESQ_pos], rax')
 elif mutation=='step-allocation':change('src/app/extsettingsrequeststep.s','    PROLOGUE 80\n','    PROLOGUE 80\n    mov edi, 8\n    call mem_alloc_try\n')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(e,mutation=None):
 r=subprocess.run(([a.wine] if a.wine else [])+[str(e)],cwd=ROOT,capture_output=True,timeout=90)
 if mutation:assert r.returncode==CODES[mutation],(mutation,r.returncode,r.stdout,r.stderr)
 else:assert r.returncode==0 and r.stdout==expected and not r.stderr,(r.returncode,r.stdout,r.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-request-') as t:
 f=Path(t)
 if a.negative_controls:
  check(build(f/'baseline'))
  for m in CODES:check(build(f/m,m),m);print('ok REQUEST producer negative control '+m,flush=True)
 else:
  e=a.exe if a.exe and not a.build_only else build(f,a.mutation)
  if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(e,a.exe);print('built REQUEST producer fixture '+str(a.exe));sys.exit(0)
  check(e,a.mutation);print('ok actual counted REQUEST bytes, budgets1/17/65536 and immutable intent')
