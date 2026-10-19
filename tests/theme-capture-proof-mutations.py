#!/usr/bin/env python3
"""The proof-isolation harness must reject deliberate policy regressions."""
import argparse,hashlib,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 def load(name,file):
  spec=importlib.util.spec_from_file_location(name,ROOT/'tests'/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
 faults=load('faults','theme-capture-proof-faults.py');wire=load('wire','theme-capture-build.py')
 cases=[
  ('precheck',10,('    call tc_capture_expected\n    test rax, rax\n    jns .Ltcb_rows','    xor eax, eax\n    test rax, rax\n    jns .Ltcb_rows')),
  ('independent-row',1,('.Ltcb_before_error:\n    cmp dword ptr [rbx + 104], 0\n    je .Ltcb_rows','.Ltcb_before_error:\n    jmp .Ltcb_invalidate_before')),
  ('complete-vector-mismatch',5,('    test eax, eax\n    jnz .Ltcb_compact','    test eax, eax\n    jmp .Ltcb_compact')),
  ('preserved-row-cleanup',11,('    mov [r15 + 16], rax\n    add r15, TC_RESULT_ROW','    mov qword ptr [r15 + 16], 0\n    add r15, TC_RESULT_ROW')),
  ('required-after-failure',7,('.Ltcb_after_error:\n    cmp dword ptr [rbx + 104], 0\n    je .Ltcb_compact','.Ltcb_after_error:\n    jmp .Ltcb_compact')),
 ]
 if a.build_only:
  for i,(_,mode,mutation)in enumerate(cases):faults.build(a.build_only/str(i),mode,True,mutation)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-tc-mutation-',dir=a.wine_drive_root)as td:
  root=Path(td).resolve();om=root/'om';om.mkdir();(om/'theme.name').write_bytes(b'name\n');source=root/'source.theme';data=b'kind=light\n';source.write_bytes(data)
  def native(p):return'C:/'+p.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(p)if a.wine else str(p)
  directory=os.fsencode(native(om));records=struct.pack('<QQ',1,5)+hashlib.sha256(b'name\n').digest()+2*(struct.pack('<QQ',2,0)+bytes(32));proof=hashlib.sha256(b'RHUN_OMARCHY_CAPTURE_V2\0'+struct.pack('<QQ',1,len(directory))+directory+records).digest()
  for i,(name,mode,mutation)in enumerate(cases):
   escope=int(mode in(7,10));expectedproof=proof if escope else bytes(32)
   if mode==10:expectedproof=bytes([proof[0]^1])+proof[1:]
   req=wire.request([native(source)],native(om),1,escope,expectedproof)
   exe=a.exe_root/str(i)/'ext_store_fault_test.exe'if a.exe_root else faults.build(root/('build'+str(i)),mode,win,mutation)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],input=req,capture_output=True,timeout=15)
   assert not r.stderr,(name,r)
   if mode==10:assert r.returncode==73 and not r.stdout,(name,r)
   else:
    assert r.returncode in(0,73),(name,r)
    if r.returncode==73:
     assert not r.stdout,(name,r)
     print('ok theme-capture-proof/mutation/'+name,flush=True);continue
    expected=(0,0,data)if mode==1 else(-1008,-5 if mode==11 else 0,b'')
    try:wire.decode(r.stdout,req,[expected])
    except AssertionError:pass
    else:raise AssertionError(('mutation escaped harness',name,r))
   print('ok theme-capture-proof/mutation/'+name,flush=True)
if __name__=='__main__':main()
