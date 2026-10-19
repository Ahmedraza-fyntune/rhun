#!/usr/bin/env python3
"""Actual purpose5 producer, pure import and purpose4 fresh proof preserve legacy context."""
from pathlib import Path
import argparse,os,shutil,struct,subprocess,tempfile,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--importer',type=Path);a=p.parse_args();windows=bool(a.wine)or os.name=='nt'
 suffix='.exe'if windows else'';directory=ROOT/('build/windows'if windows else'build')
 exe=directory/('ext_store_job_legacy_real_test'+suffix)
 if a.importer:importer=a.importer.resolve()
 else:
  import importlib.util
  spec=importlib.util.spec_from_file_location('legacy_poison',ROOT/'tests/faults/ext_legacy_build.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  importer=module.build(ROOT/'build/legacy-job-import-poison',windows=windows)

 with tempfile.TemporaryDirectory(prefix='rhun-legacy-real-Ω space-',dir=a.wine_drive_root)as folder:
  root=Path(folder).resolve()
  def native(path):return'C:/'+path.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine else str(path)
  context=native(root)
  target=root/('external.exe'if windows else'external');shutil.copyfile(exe if windows else'/bin/echo',target);target.chmod(0o755)
  platform='windows-x64'if windows else'macos-arm64'if sys.platform=='darwin'else'linux-x86_64'
  prefix='owner=Foo\nname=Bar\ntitle=Legacy\nversion=1\nprotocol=1\n'
  def run(args,env,success=True):
   r=subprocess.run(([a.wine]if a.wine else[])+list(map(str,args)),cwd=root,env=env,capture_output=True,timeout=30)
   assert not r.stderr and(r.returncode==0 if success else r.returncode!=0),(r.returncode,r.stderr,r.stdout[:192]);return r.stdout
  def roundtrip(manifest,path_marker=None,expected_program=None):
   (root/'extension.ini').write_text(prefix+manifest+'\n[commands]\nhello=Hello\n')
   env=os.environ.copy()
   if path_marker is False:env.pop('PATH',None)
   elif path_marker is not None:env['PATH']=path_marker
   if windows and path_marker is not None:env['RHUN_TEST_LEGACY_NATIVE_PATH']='-'if path_marker is False else'+'+path_marker
   # An inherited spoof must not override the native-owned actual cwd capture.
   env['RHUN_LEGACY_CWD']='C:/nonexistent-spoof'if windows else'/nonexistent-spoof'
   value=run([exe,context,'5'],env)
   captured_drive,cwd_length=struct.unpack_from('<QQ',value)
   captured_cwd=value[16:16+cwd_length].decode()
   assert captured_cwd==(context if windows else''),(captured_cwd,context)
   wire=value[16+cwd_length:]
   if expected_program is not None:
    pl=struct.unpack_from('<I',wire,144)[0]
    assert wire[192:192+pl].decode()==expected_program,(wire[192:192+pl],expected_program)
   assert wire[:8]==b'RHLSS1\0\0'and struct.unpack_from('<Q',wire,16)[0]==len(wire)
   drive=struct.unpack_from('<I',wire,152)[0];tag=wire[32:96];source=wire[96:128]
   assert captured_drive==drive
   data=root/'import-input';data.write_bytes(struct.pack('<Q',drive)+tag+wire)
   manifest_path=root/'extension.ini';saved=root/'held-manifest';manifest_path.rename(saved)
   try:out=run([importer,native(data),context,'Foo','Bar',captured_cwd],env)
   finally:saved.rename(manifest_path)
   assert len(out)==160 and struct.unpack_from('<2q',out)==(0,0)and out[64:96]==source,out.hex()
   assert struct.unpack_from('<I',out,124)[0]==0 and struct.unpack_from('<4q',out,128)==(0,0,0,0),out.hex()
   (root/'.job-source').write_bytes(source)
   receipt_value=run([exe,context,'4'],env)
   rd,cl=struct.unpack_from('<QQ',receipt_value)
   assert rd==captured_drive and receipt_value[16:16+cl].decode()==captured_cwd
   receipt=receipt_value[16+cl:]
   assert len(receipt)==192 and receipt[:8]==b'RHLEGC1\0'and receipt[16:80]==tag and receipt[80:112]==bytes(32)and receipt[112:144]==source
   assert receipt[144:]==bytes(48)
   (root/'extension.ini').write_text(prefix+manifest+'\n[commands]\nchanged=Changed\n')
   assert run([exe,context,'4'],env,False)==b''
  roundtrip('run.'+platform+'='+native(target))
  if windows:
   (root/'bin').mkdir();runtime=root/'bin'/'legacy-context-runtime.exe';shutil.copyfile(exe,runtime);(root/'script.py').write_text('never execute\n')
   roundtrip('runtime=legacy-context-runtime\nrun=script.py',native(root/'bin'),native(runtime))
   roundtrip('runtime=./bin/legacy-context-runtime.exe\nrun=script.py','',context+'/./bin/legacy-context-runtime.exe')
   (root/'extension.ini').write_text(prefix+'runtime=legacy-context-runtime\nrun=script.py\n');empty_env=os.environ.copy();empty_env['PATH']=''
   if windows:empty_env['RHUN_TEST_LEGACY_NATIVE_PATH']='+'
   assert run([exe,context,'5'],empty_env,False)==b''
  if not windows:
   (root/'bin').mkdir();(root/'bin'/'legacy-context-runtime').symlink_to('/usr/bin/python3');(root/'script.py').write_text('raise SystemExit("must never execute")\n')
   roundtrip('runtime=python3\nrun=script.py',False)
   (root/'extension.ini').write_text(prefix+'runtime=python3\nrun=script.py\n')
   empty_python_env=os.environ.copy();empty_python_env['PATH']=''
   assert run([exe,context,'5'],empty_python_env,False)==b''
   for path in('bin','bad\udcff:bin'):
    roundtrip('runtime=legacy-context-runtime\nrun=script.py',path,native(root/'bin'/'legacy-context-runtime'))
   roundtrip('runtime=./bin/legacy-context-runtime\nrun=script.py','',context+'/./bin/legacy-context-runtime')
   (root/'extension.ini').write_text(prefix+'runtime=legacy-context-runtime\nrun=script.py\n')
   empty_env=os.environ.copy();empty_env['PATH']=''
   assert run([exe,context,'5'],empty_env,False)==b''
   try:
    invalid=root/'bad\udcff';invalid.mkdir();(invalid/'legacy-context-runtime').symlink_to('/usr/bin/python3')
   except OSError:
    assert sys.platform=='darwin'
   else:
    invalid_env=os.environ.copy();invalid_env['PATH']='bad\udcff'
    assert run([exe,context,'5'],invalid_env,False)==b''
  print('ok legacyjob/actual-snapshot-pure-import-fresh-proof-context-and-mutation',flush=True)
if __name__=='__main__':main()
