#!/usr/bin/env python3
"""Expected proof, independent startup rows and double-observation mismatch boundaries."""
import argparse,hashlib,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,win,mutation=None):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_build_test.s').read_text()
 fixture+='''\n.bss\n.p2align 3\ntcbf_observations: .zero 8\ntcbf_users: .zero 8\n.text\nFN tcbf_user_capture\n    inc qword ptr [rip + tcbf_users]\n    jmp tc_file_capture\nFN tc_omarchy_capture\n    inc qword ptr [rip + tcbf_observations]\n'''
 failat=1 if mode in(1,3,6,8)else 2
 if mode in(1,2,3,4,6,7,8,9,12,13):
  fixture+='    cmp qword ptr [rip + tcbf_observations], '+str(failat)+'\n    jne tcbf_real_observation\n    mov rax, '+str(0 if mode in(3,4,8,9)else-13)+'\n    mov rdx, '+str(-5 if mode in(3,4,8,9)else 0)+'\n    ret\n'
 elif mode in(5,11):
  fixture+='''    PROLOGUE\n    mov rbx, rdx\n    call tcbf_real_observation\n    test rax, rax\n    jnz 1f\n    test rdx, rdx\n    jnz 1f\n    cmp qword ptr [rip + tcbf_observations], 2\n    jne 1f\n    xor byte ptr [rbx + TOB_proof], 1\n1:  EPILOGUE\n'''
 else:fixture+='    jmp tcbf_real_observation\n'
 om=(ROOT/'src/app/themecaptureomarchyio.s').read_text().replace('FN tc_omarchy_capture\n','FN tcbf_real_observation\n',1)
 core=(ROOT/'src/app/themecapturebuild.s').read_text();assert core.count('call tc_file_capture')==1;core=core.replace('call tc_file_capture','call tcbf_user_capture',1)
 # Hard assertion: expected precheck failure never opens the selected source.
 expected_users=0 if mode in(6,8,10)else 1
 fixture=fixture.replace('    mov [rsp + 16], rcx\n','    mov [rsp + 16], rcx\n',1)
 fixture=fixture.replace('    test rdx, rdx\n    jnz tcbt_fail\n','    test rdx, rdx\n    jnz tcbt_fail\n    cmp qword ptr [rip + tcbf_users], '+str(expected_users)+'\n    jne tcbt_fail\n',1)
 replacements={'src/app/themecaptureomarchyio.s':om,'src/app/themecapturebuild.s':core}
 if mode>=11:
  fixture=fixture.replace('    jmp tc_file_capture\n','    PROLOGUE\n    mov qword ptr [rip + tcbf_user_active], 1\n    call tc_file_capture\n    mov qword ptr [rip + tcbf_user_active], 0\n    EPILOGUE\n',1)
  fixture+='\n.bss\n.p2align 3\ntcbf_user_active: .zero 8\n.text\nFN tc_file_close\n    cmp qword ptr [rip + tcbf_user_active], 1\n    jne tcbf_real_close\n    PROLOGUE\n    call tcbf_real_close\n    mov rax, -5\n    EPILOGUE\n'
  filecore=(ROOT/'src/app/themecaptureio.s').read_text().replace('FN tc_file_close\n','FN tcbf_real_close\n',1)
  replacements['src/app/themecaptureio.s']=filecore
 if mutation:
  old,new=mutation;assert replacements['src/app/themecapturebuild.s'].count(old)==1
  replacements['src/app/themecapturebuild.s']=replacements['src/app/themecapturebuild.s'].replace(old,new,1)
 return m.build(folder,fixture,replacements,win)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for mode in range(14):build(a.build_only/str(mode),mode,True)
  return
 spec=importlib.util.spec_from_file_location('wire',ROOT/'tests/theme-capture-build.py');wire=importlib.util.module_from_spec(spec);spec.loader.exec_module(wire)
 with tempfile.TemporaryDirectory(prefix='rhun-tc-proof-',dir=a.wine_drive_root)as td:
  root=Path(td).resolve();om=root/'om';om.mkdir();(om/'theme.name').write_bytes(b'name\n');source=root/'source.theme';data=b'kind=light\n';source.write_bytes(data)
  def native(p):return'C:/'+p.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(p)if a.wine else str(p)
  directory=os.fsencode(native(om));record=struct.pack('<QQ',1,5)+hashlib.sha256(b'name\n').digest();record+=2*(struct.pack('<QQ',2,0)+bytes(32));proof=hashlib.sha256(b'RHUN_OMARCHY_CAPTURE_V2\0'+struct.pack('<QQ',1,len(directory))+directory+record).digest()
  for mode in range(14):
   expected_scope=1 if mode in(6,7,8,9,10,12)else 0;expectedproof=proof if expected_scope else bytes(32)
   if mode==10:expectedproof=bytes([proof[0]^1])+proof[1:]
   req=wire.request([native(source)],native(om),1,expected_scope,expectedproof)
   exe=a.exe_root/str(mode)/'ext_store_fault_test.exe'if a.exe_root else build(root/('build'+str(mode)),mode,win)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],input=req,capture_output=True,timeout=15)
   assert r.returncode==0 and not r.stderr,(mode,r)
   invalid=mode in(5,6,7,8,9,10,11,12);rowcleanup=-5 if mode>=11 else 0;out,name,rows=wire.decode(r.stdout,req,[(-1008,rowcleanup,b'')if invalid else(0,rowcleanup,b''if rowcleanup else data)])
   expected={0:(0,0),1:(-13,0),2:(-13,0),3:(0,-5),4:(0,-5),5:(-1008,0),6:(-13,0),7:(-13,0),8:(0,-5),9:(0,-5),10:(-1008,0),11:(-1008,0),12:(-13,0),13:(-13,0)}[mode]
   assert struct.unpack_from('<qq',out,104)==expected,(mode,struct.unpack_from('<qq',out,104),expected)
   if mode:assert name==b''and out[120:160]==bytes(40),(mode,)
   else:assert name==b'name'and out[128:160]==proof
   print('ok theme-capture-proof/isolation-mismatch/'+str(mode),flush=True)
if __name__=='__main__':main()
