#!/usr/bin/env python3
"""Theme capture allocation boundaries and charged-memory negative controls."""
from pathlib import Path
import argparse,importlib.util,os,struct,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def build(folder,ordinal,windows):
 spec=importlib.util.spec_from_file_location('theme_fault_link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_request_test.s').read_text()
 fixture=fixture.replace('    call theme_capture_request_begin','    mov qword ptr [rip + tcf_armed], 1\n    call theme_capture_request_begin',1)
 replacements={}
 if ordinal:
  replacements['src/mem.s']=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN tcf_real_alloc\n',1)
  fixture+='\n.bss\ntcf_armed: .zero 8\ntcf_count: .zero 8\n.text\nFN mem_alloc_try\n    cmp qword ptr [rip + tcf_armed], 0\n    je tcf_real_alloc\n    inc qword ptr [rip + tcf_count]\n    cmp qword ptr [rip + tcf_count], '+str(ordinal)+'\n    jne tcf_real_alloc\n    xor eax, eax\n    ret\n'
 else:
  fixture+='\n.bss\ntcf_armed: .zero 8\n'
  source=(ROOT/'src/app/themecapturemem.s').read_text()
  for old in('    cmp r12, rcx\n    ja 9f','    cmp [rip + g_theme_capture_charge], rcx\n    ja 9f'):
   assert old in source;source=source.replace(old,'    nop\n    nop',1)
  replacements['src/app/themecapturemem.s']=source
 return m.build(folder,fixture,replacements,windows=windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=a.windows_build or bool(a.wine)or os.name=='nt'
 path='C:/source.theme'if windows else'/source.theme'
 for ordinal in(1,2,3,0):
  exe=build((a.build_only or ROOT/'build/theme-capture-faults')/str(ordinal),ordinal,windows)
  if a.build_only:continue
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),'22'if ordinal==0 else'0',path,'-'],capture_output=True,timeout=15)
  assert r.returncode==0 and not r.stderr and len(r.stdout)>=48,(ordinal,r)
  status,last,length,charge=struct.unpack_from('<qqQQ',r.stdout)
  assert status==(-12 if ordinal in(1,2)else 0)and last==0,(ordinal,status,last)
  assert r.stdout[-16:]==bytes(16)and len(r.stdout)==48+length,(ordinal,r.stdout[-16:])
  if ordinal==0:assert length>0 and charge>128
  print('ok theme-capture/'+('quota-negative-control'if ordinal==0 else'allocator-'+str(ordinal)),flush=True)
if __name__=='__main__':main()
