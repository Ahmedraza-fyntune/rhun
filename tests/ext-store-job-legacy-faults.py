#!/usr/bin/env python3
"""Parent-side legacy transport never queries directory metadata or resolves its executable."""
import argparse,importlib.util,os,re
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--windows-build',action='store_true');p.add_argument('--build-only',type=Path);a=p.parse_args();windows=a.windows_build or bool(a.wine)or os.name=='nt'
 spec=importlib.util.spec_from_file_location('legacy_regular',ROOT/'tests/ext-store-job-legacy.py');regular=importlib.util.module_from_spec(spec);spec.loader.exec_module(regular)
 spec=importlib.util.spec_from_file_location('legacy_build',ROOT/'tests/faults/ext_store_build.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
 replacements={};wrappers=[]
 paths={'src/app/extvalidatepath.s':['ext_root_identity','ext_root_open','ext_root_open_at','ext_root_stat','ext_root_read']}
 paths['src/win/extstorejob.s'if windows else'src/proc.s']=['ext_store_job_module_path'if windows else'proc_self_path']
 for path,names in paths.items():
  source=(ROOT/path).read_text()
  for name in names:
   old='legacy_original_'+name;assert 'FN '+name+'\n'in source,(path,name);source=source.replace('FN '+name+'\n','FN '+old+'\n',1)
   wrappers.append('FN '+name+'\n    cmp qword ptr [rip + esjlt_forbid_io], 0\n    je 1f\n    inc qword ptr [rip + esjlt_forbidden_count]\n    mov rax, -33\n    xor edx, edx\n    ret\n1:  jmp '+old+'\n')
  replacements[path]=source
 # Instrument direct native metadata/context entry points as well as high-level helpers.
 if windows:
  for path in(ROOT/'src').rglob('*.s'):
   relative=path.relative_to(ROOT).as_posix()
   if 'mac'in path.parts or relative in('src/main.s','src/start.s','src/plat/x11.s','src/plat/wayland.s','src/plat/appearance.s'):continue
   text=replacements.get(relative,path.read_text());changed=text
   for name in('GetFileInformationByHandleEx','GetFileInformationByHandle'):
    changed=re.sub(r'API '+name+r'\b','call legacy_native_'+name,changed)
    changed=changed.replace('call [rip + __imp_'+name+']','call legacy_native_'+name)
   if changed!=text:replacements[relative]=changed
  for name in('GetFileInformationByHandleEx','GetFileInformationByHandle'):
   wrappers.append('FN legacy_native_'+name+'\n    cmp qword ptr [rip + esjlt_forbid_io], 0\n    je 1f\n    inc qword ptr [rip + esjlt_forbidden_count]\n    xor eax, eax\n    ret\n1:  jmp [rip + __imp_'+name+']\n')
 else:
  for path in(ROOT/'src').rglob('*.s'):
   relative=path.relative_to(ROOT).as_posix()
   if 'win'in path.parts or'mac'in path.parts or relative in('src/main.s','src/start.s','src/plat/x11.s','src/plat/wayland.s','src/plat/appearance.s'):continue
   text=replacements.get(relative,path.read_text())
   changed=text.replace('SYS SYS_fstat','call legacy_native_fstat').replace('SYS SYS_getcwd','call legacy_native_getcwd')
   if changed!=text:replacements[relative]=changed
  for name,syscall in(('fstat','SYS_fstat'),('getcwd','SYS_getcwd')):
   wrappers.append('FN legacy_native_'+name+'\n    cmp qword ptr [rip + esjlt_forbid_io], 0\n    je 1f\n    inc qword ptr [rip + esjlt_forbidden_count]\n    mov rax, -33\n    ret\n1:  SYS '+syscall+'\n    ret\n')
  import sys
  if sys.platform=='darwin':
   path='src/mac/rt.s';text=(ROOT/path).read_text()
   old='FN mac_exe_path\n';assert old in text
   text=text.replace(old,old+'    adrp x9, esjlt_forbid_io@PAGE\n    ldr x9, [x9, esjlt_forbid_io@PAGEOFF]\n    cbz x9, 91f\n    adrp x9, esjlt_forbidden_count@PAGE\n    ldr x10, [x9, esjlt_forbidden_count@PAGEOFF]\n    add x10, x10, #1\n    str x10, [x9, esjlt_forbidden_count@PAGEOFF]\n    mov x8, #-33\n    XRET\n91:\n',1)
   replacements[path]=text
 source=(ROOT/'tests/ext_store_job_legacy_test.s').read_text()+'\n'+''.join(wrappers)
 exe=builder.build((a.build_only or ROOT/'build')/'legacy-job-parent-io-fault',source,replacements,windows=windows)
 # Run exact regular cases against the instrumented native executable without replacing product.
 if not a.build_only:
  oldroot=regular.ROOT
  with tempfile.TemporaryDirectory(prefix='legacy-job-driver-')as d:
   tree=Path(d);target=tree/('build/windows/ext_store_job_legacy_test.exe'if windows else'build/ext_store_job_legacy_test');target.parent.mkdir(parents=True)
   import shutil;shutil.copy2(exe,target);regular.ROOT=tree
   import sys
   saved_argv=sys.argv
   sys.argv=[saved_argv[0]]+(['--wine',a.wine]if a.wine else[])+(['--wine-drive-root',str(a.wine_drive_root)]if a.wine_drive_root else[])
   try:regular.main()
   finally:sys.argv=saved_argv
  regular.ROOT=oldroot
  print('ok legacyjob/parent-root-IO-and-selfpath-poison-zero',flush=True)
 if windows:
  # A direct virtual-fd fstat bypasses ext_root helpers and must still hit poison.
  anchor='84: mov qword ptr [rip + esjlt_forbid_io], 1\n'
  assert anchor in source
  bypass=source.replace(anchor,anchor+'    xor edi, edi\n    lea rsi, [rip + esjlt_flood]\n    SYS SYS_fstat\n',1)
  negative=builder.build((a.build_only or ROOT/'build')/'legacy-job-native-poison-negative',bypass,replacements,windows=True)
  if not a.build_only:
   with tempfile.TemporaryDirectory(prefix='rhun-legacy-poison-negative-',dir=a.wine_drive_root)as folder:
    root=Path(folder).resolve();native='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(root)
    r=subprocess.run(([a.wine]if a.wine else[])+[str(negative),native,'0'],cwd=root,capture_output=True,timeout=20)
    assert r.returncode!=0 and not r.stdout,(r.returncode,r.stdout,r.stderr)
   print('ok legacyjob/negative-control/direct-native-fstat-poison',flush=True)
 for ordinal in range(1,5):
  memory=(ROOT/'src/mem.s').read_text().replace('FN mem_alloc_try\n','FN legacy_real_alloc\n',1)
  fixture=(ROOT/'tests/ext_store_job_legacy_test.s').read_text()+"\n.bss\nlegacy_alloc_count: .zero 8\n.text\nFN mem_alloc_try\n    cmp qword ptr [rip + esjlt_forbid_io], 0\n    je 1f\n    inc qword ptr [rip + legacy_alloc_count]\n    cmp qword ptr [rip + legacy_alloc_count], "+str(ordinal)+"\n    jne 1f\n    xor eax, eax\n    ret\n1:  jmp legacy_real_alloc\n"
  binary=builder.build((a.build_only or ROOT/'build')/('legacy-job-allocation-'+str(ordinal)),fixture,{'src/mem.s':memory},windows=windows)
  if a.build_only:continue
  with tempfile.TemporaryDirectory(prefix='rhun-legacy-alloc-',dir=a.wine_drive_root)as folder:
   native=str(Path(folder).resolve())
   if a.wine:native='C:/'+Path(folder).resolve().relative_to(a.wine_drive_root.resolve()).as_posix()
   r=subprocess.run(([a.wine]if a.wine else[])+[str(binary),native,'30'],capture_output=True,timeout=20)
   import struct
   assert r.returncode==0 and not r.stderr and len(r.stdout)==32,(ordinal,r)
   status,cleanup,length,steps=struct.unpack('<qqQQ',r.stdout)
   assert(status,cleanup,length,steps)==(-12,0,0,1),(ordinal,status,cleanup,length,steps)
 if not a.build_only:print('ok legacyjob/context-wire-launch-allocation-unwind',flush=True)

if __name__=='__main__':main()
