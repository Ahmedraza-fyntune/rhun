#!/usr/bin/env python3
"""Omarchy composite observations reject primary and cleanup-only faults without partial output."""
import argparse,importlib.util,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def build(folder,mode,windows):
 spec=importlib.util.spec_from_file_location('link',ROOT/'tests/faults/ext_store_build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 fixture=(ROOT/'tests/theme_capture_omarchy_io_test.s').read_text()
 # Assert that failure short-circuits subsequent sources rather than hiding partial errors.
 captures=1 if mode<=3 or mode==7 else 2
 markers=1 if mode==6 else 0
 fixture=fixture.replace('    mov [rsp + 248], rdx\n','    mov [rsp + 248], rdx\n    cmp qword ptr [rip + tcof_captures], '+str(captures)+'\n    jne tcoit_fail\n    cmp qword ptr [rip + tcof_markers], '+str(markers)+'\n    jne tcoit_fail\n',1)
 fixture+='''\n.bss\n.p2align 3\ntcof_captures: .zero 8\ntcof_markers: .zero 8\n.text\nFN tc_file_capture\n    inc qword ptr [rip + tcof_captures]\n'''
 failat=1 if mode<=3 else 2
 if mode<=5:
  fixture+='    cmp qword ptr [rip + tcof_captures], '+str(failat)+'\n    jne tcof_real_capture\n'
  primary={1:-13,2:-2,3:0,4:-13,5:-2}[mode];cleanup=-5 if mode in(2,3,5)else 0
  fixture+='    mov rax, '+str(primary)+'\n    mov rdx, '+str(cleanup)+'\n    ret\n'
 else:fixture+='    jmp tcof_real_capture\n'
 fixture+='FN tc_marker_presence\n    inc qword ptr [rip + tcof_markers]\n'
 if mode in(6,7,8):fixture+='    mov rax, -13\n    ret\n'
 else:fixture+='    jmp tcof_real_marker\n'
 core=(ROOT/'src/app/themecaptureio.s').read_text();assert'FN tc_file_capture\n'in core
 core=core.replace('FN tc_file_capture\n','FN tcof_real_capture\n',1)
 om=(ROOT/'src/app/themecaptureomarchyio.s').read_text();assert'FN tc_marker_presence\n'in om
 om=om.replace('FN tc_marker_presence\n','FN tcof_real_marker\n',1)
 return m.build(folder,fixture,{'src/app/themecaptureio.s':core,'src/app/themecaptureomarchyio.s':om},windows)
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--build-only',type=Path);p.add_argument('--exe-root',type=Path);a=p.parse_args()
 win=bool(a.wine)or os.name=='nt'
 if a.build_only:
  for mode in range(1,9):build(a.build_only/str(mode),mode,True)
  return
 with tempfile.TemporaryDirectory(prefix='rhun-omfault-',dir=a.wine_drive_root)as td:
  directory=Path(td).resolve();(directory/'theme').mkdir();(directory/'theme.name').write_bytes(b'name\n')
  native='C:/'+directory.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(directory)if a.wine else str(directory)
  for mode in range(1,9):
   (directory/'theme/colors.toml').write_bytes(b'mode=light\n'if mode==8 else b'mode=dark\n')
   exe=a.exe_root/str(mode)/'ext_store_fault_test.exe'if a.exe_root else build(directory/('build-'+str(mode)),mode,win)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native,'1'if mode==7 else'2'],capture_output=True,timeout=15)
   assert r.returncode==0 and not r.stderr,(mode,r)
   expected={1:(-13,0),2:(-2,-5),3:(0,-5),4:(-13,0),5:(-2,-5),6:(-13,0),7:(0,0),8:(0,0)}[mode]
   assert struct.unpack_from('<qq',r.stdout)==expected,(mode,r,expected)
   if mode<=6:assert r.stdout[16:]==bytes(240),(mode,r.stdout)
   print('ok theme-capture-omarchy/fault/'+str(mode),flush=True)
if __name__=='__main__':main()
