#!/usr/bin/env python3
"""Verify pure dirty ACK preflight and fixed nonrefusing publication."""
import argparse,importlib.util,os,re,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CODES={'mutating-check':70,'ignore-epoch':71,'ignore-active-batch':72,'ignore-slot':74,
       'ignore-row-sequence':75,'clear-newer-intent':32,'recheck-in-publish':78,'allocate-in-publish':78}
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=CODES);a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('negative controls build their own fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('ack_fixture_build',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture='.equ TEST_SETTINGS_QUEUE_FAULT, 1\n'+(ROOT/'tests/ext_settingsqueue_test.s').read_text()
 assert fixture.count('call ext_settings_batch_ack\n')>=3
 fixture=fixture.replace('call ext_settings_batch_ack\n','call qa_pair\n')+'\n'+(ROOT/'tests/ext_settings_ack_cases.inc').read_text()
 replacements={}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 queue=(ROOT/'src/app/extsettingsqueue.s').read_text();replacements['src/app/extsettingsqueue.s']=queue.replace('call ext_settings_memory_try','call sq_alloc')
 change('src/app/extsettingsqueueack.s','FN ext_settings_batch_ack_check\n','FN ext_settings_batch_ack_check\n    cmp qword ptr [rip + qa_publish_guard], 0\n    jne qa_pure_fail\n')
 for path,names in [('src/mem.s',['mem_alloc','mem_alloc_try','mem_free']),('src/sys.s',['file_read_all','file_write_all']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(path,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + qa_poison], 0\n    jne qa_pure_fail\n')
 if mutation=='mutating-check':change('src/app/extsettingsqueueack.s','    cmp qword ptr [rbx + EQ_epoch], 0','    inc qword ptr [rbx + EQ_epoch]\n    cmp qword ptr [rbx + EQ_epoch], 0')
 elif mutation=='ignore-epoch':
  change('src/app/extsettingsqueueack.s','    jle .Lqac_overflow','    nop')
  change('src/app/extsettingsqueueack.s','    jae .Lqac_overflow','    nop')
 elif mutation=='ignore-active-batch':change('src/app/extsettingsqueueack.s','    cmp [rbx + EQ_batch], r12','    cmp r12, r12')
 elif mutation=='ignore-slot':change('src/app/extsettingsqueueack.s','    cmp qword ptr [r15 + EQBR_slot], EQ_MAX\n    jae .Lqac_invalid','    nop')
 elif mutation=='ignore-row-sequence':change('src/app/extsettingsqueueack.s','    test rax, rax\n    jle .Lqac_invalid','    nop')
 elif mutation=='clear-newer-intent':change('src/app/extsettingsqueue.s','    cmp [rdx + EQC_seq], rcx\n    jne 3f','    nop')
 elif mutation=='recheck-in-publish':change('src/app/extsettingsqueue.s','FN ext_settings_batch_ack_publish\n','FN ext_settings_batch_ack_publish\n    call ext_settings_batch_ack_check\n')
 elif mutation=='allocate-in-publish':change('src/app/extsettingsqueue.s','FN ext_settings_batch_ack_publish\n','FN ext_settings_batch_ack_publish\n    mov edi, 8\n    call mem_alloc_try\n')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(exe,mutation=None):
 r=subprocess.run(([a.wine] if a.wine else [])+[str(exe)],cwd=ROOT,capture_output=True,timeout=90)
 if mutation:assert r.returncode==CODES[mutation],(mutation,r.returncode,r.stdout,r.stderr)
 else:assert r.returncode==0 and r.stdout+r.stderr==b'ok owned settings queue\n',(r.returncode,r.stdout,r.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-ack-') as t:
 f=Path(t)
 if a.negative_controls:
  check(build(f/'baseline'))
  for m in CODES:check(build(f/m,m),m);print('ok pure settings ACK negative control '+m,flush=True)
 else:
  e=a.exe if a.exe and not a.build_only else build(f,a.mutation)
  if a.build_only:a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(e,a.exe);print('built pure settings ACK fixture: '+str(a.exe));sys.exit(0)
  check(e,a.mutation);print('ok pure settings ACK check and fixed publication',flush=True)
