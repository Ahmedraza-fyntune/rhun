#!/usr/bin/env python3
"""Typed opaque native faults prove bounded bytes/calls and retained process/IO ownership."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ERRORS={2:(-10,0,3,0),3:(-13,0,0,0),4:(0,-5,2,0),5:(0,-5,2,0),6:(-5,0,2,0),7:(-5,0,2,-5),8:(-116,0,2,0),9:(-125,0,2,0),10:(-7,0,2,0),11:(-71,0,2,0),13:(-125,0,2,0),14:(-13,-5,0,0)}
def build(folder,mode,win,negative=None):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_job_test.s').read_text();fixture='.equ TCJM_MODE, '+str(mode)+'\n'+fixture
 if mode in(9,13):
  needle='    # No forward result may be taken before actual completion.\n';assert needle in fixture
  fixture=fixture.replace(needle,'    mov rdi, r12\n    call theme_capture_job_cancel\n'+needle,1)
 if mode==8:fixture=fixture.replace('    mov ecx, 2\n    call theme_capture_job_step','    mov ecx, 3\n    call theme_capture_job_step',1)
 if mode in ERRORS:
  primary,cleanup,auth,observation=ERRORS[mode]
  checks=f'''    cmp qword ptr [rsp + 16], {primary}
    jne tcjt_fail
    cmp qword ptr [rsp + 24], {cleanup}
    jne tcjt_fail
    cmp qword ptr [r12 + TCJ_primary], {primary}
    jne tcjt_fail
    cmp qword ptr [r12 + TCJ_cleanup], {cleanup}
    jne tcjt_fail
    cmp qword ptr [r12 + TCJ_authority], {auth}
    jne tcjt_fail
    cmp qword ptr [r12 + TCJ_observation], {observation}
    jne tcjt_fail
    cmp qword ptr [r12 + TCJ_native], 0
    jne tcjt_fail
    cmp qword ptr [r12 + TCJ_reservation], 0
    jne tcjt_fail
'''
  if mode in(2,3,14):checks+='    cmp qword ptr [rip + tcjm_killed], 0\n    jne tcjt_fail\n'
  if mode in(7,8,9,13):checks+='    cmp qword ptr [rip + tcjm_killed], 1\n    jne tcjt_fail\n'
  if mode in(8,9,13):checks+='    cmp qword ptr [rip + tcjm_begins], 0\n    jne tcjt_fail\n'
  if mode==5:checks+='    cmp qword ptr [rip + tcjm_free_count], 4\n    jne tcjt_fail\n'
  if mode in(6,13):checks+='    cmp qword ptr [rip + tcjm_free_count], 2\n    jb tcjt_fail\n'
  needle='.Ltcjt_error_free:\n';assert needle in fixture;fixture=fixture.replace(needle,needle+checks+'.Ltcjt_error_free_loop:\n',1)
  ending='''    test rdx, rdx
    jz .Ltcjt_error_free
    jmp tcjt_fail
''';assert fixture.count(ending)==1
  fixture=fixture.replace(ending,'''    test rdx, rdx
    jz .Ltcjt_error_free_loop
    cmp qword ptr [rip + g_theme_capture_job], 0
    jne tcjt_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcjt_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcjt_fail
    cmp r15, [rip + g_mem_live]
    jne tcjt_fail
    xor eax, eax
    EPILOGUE
''',1)
 fixture+='\n.bss\n.p2align 3\ntcjm_clock: .zero 8\n.text\nFN time_ms\n    mov rax, [rip + tcjm_clock]\n    inc qword ptr [rip + tcjm_clock]\n    add rax, 1000\n    ret\nFN tc_helper_wait\n    ret\n'
 fixture+=(ROOT/'tests/faults/theme_capture_job_native.s').read_text()
 replacements={}
 symbols={'src/app/extsettingsnative.s':['theme_capture_native_start','ext_settings_native_read','ext_settings_native_poll','ext_settings_native_kill','ext_settings_native_free','ext_settings_native_write_begin'],('src/win/extsettingsnative.s'if win else'src/app/extsettingsnativeposix.s'):['ext_settings_native_write_poll','ext_settings_native_close_input'],'src/app/themecapturejobstep.s':['theme_capture_job_step'],'src/app/themecapturedecode.s':['tc_result_decode_step'],'src/sys.s':['time_ms'],'src/app/themecaptureio.s':['tc_helper_wait']}
 for path,names in symbols.items():
  core=(ROOT/path).read_text()
  for name in names:
   old='FN '+name+'\n';assert core.count(old)==1,(path,name)
   replacement='tcjm_real_step'if name=='theme_capture_job_step'else'tcjm_real_decode'if name=='tc_result_decode_step'else'tcjm_real_'+name
   core=core.replace(old,'FN '+replacement+'\n',1)
  if path=='src/app/themecapturedecode.s':
   # Instrument actual payload accesses and SHA input independently of returned debits.
   for old,new in [
    ('    mov al, [r13 + rcx]\n','    mov al, [r13 + rcx]\n    inc qword ptr [rip + tcjm_bytes]\n'),
    ('    mov al, [r13 + rax]\n','    mov al, [r13 + rax]\n    inc qword ptr [rip + tcjm_bytes]\n'),
    ('    call sha256_update\n','    add [rip + tcjm_bytes], rdx\n    call sha256_update\n'),
    ('tcd_header:\n','tcd_header:\n    add qword ptr [rip + tcjm_control], 256\n'),
    ('    mov [r12 + TCD_row_start], rax\n','    add qword ptr [rip + tcjm_control], TC_RESULT_ROW\n    mov [r12 + TCD_row_start], rax\n')]:
    assert core.count(old)==1,(old,core.count(old));core=core.replace(old,new,1)
   if negative=='palette':
    old='    mov al, [r13 + rax]\n    inc qword ptr [rip + tcjm_bytes]\n    dec r14\n';assert core.count(old)==1;core=core.replace(old,old.replace('    dec r14\n',''),1)
   if negative=='hash':
    old='    sub r14, rax\n';assert core.count(old)==1;core=core.replace(old,'',1)
   if negative=='control':
    old='    sub r15, 256\n';assert core.count(old)==1;core=core.replace(old,'',1)
  replacements[path]=core
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for mode in range(15):build(a.build_only/str(mode),mode,True)
  for name in('palette','hash','control'):build(a.build_only/name,0,True,name)
  return
 spec=importlib.util.spec_from_file_location('wire',ROOT/'tests/theme-capture-build.py');wire=importlib.util.module_from_spec(spec);spec.loader.exec_module(wire)
 req=wire.request(['C:/mock.theme'if win else'/mock.theme'])
 with tempfile.TemporaryDirectory(prefix='rhun-theme-job-fault-')as td:
  for mode in range(15):
   exe=a.exe_root/str(mode)/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/str(mode),mode,win)
   budgets=(1,7,303,304,4095,65536)if mode in(0,1,5,7,12,13)else(65536,)
   for budget in budgets:
    r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(budget)],input=req,capture_output=True,timeout=20)
    assert r.returncode==0 and not r.stderr,(mode,budget,r)
    if mode in ERRORS:assert not r.stdout,(mode,budget,r)
    else:wire.decode(r.stdout,req,[(0,0,b'kind=light\n')])
   print('ok theme-capture-job/native-fault/'+str(mode),flush=True)
  for name in('palette','hash','control'):
   exe=a.exe_root/name/'ext_store_fault_test.exe'if a.exe_root else build(Path(td)/name,0,win,name)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),'65536'if name=='control'else'1'],input=req,capture_output=True,timeout=20)
   assert r.returncode==73 and not r.stdout and not r.stderr,(name,r)
   print('ok theme-capture-job/independent-budget-negative/'+name,flush=True)
if __name__=='__main__':main()
