#!/usr/bin/env python3
"""Actual helper-local regular-file snapshots follow user links and preserve exact bytes."""
from pathlib import Path
import argparse,hashlib,os,struct,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--exe',type=Path);a=p.parse_args();windows=bool(a.wine)or os.name=='nt'
 exe=a.exe or ROOT/('build/windows/theme_capture_file_test.exe'if windows else'build/theme_capture_file_test')
 with tempfile.TemporaryDirectory(prefix='rhun-theme-file-Ω ',dir=a.wine_drive_root)as folder:
  root=Path(folder).resolve()
  def native(path):return'C:/'+path.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(path)if a.wine else str(path)
  def run(path,maximum=65536,expected=None,data=None):
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),native(path),str(maximum)],capture_output=True,timeout=15)
   assert r.returncode==0 and not r.stderr and len(r.stdout)>=88,(path,maximum,r)
   primary,cleanup,length=struct.unpack_from('<qqQ',r.stdout);digest=r.stdout[24:56]
   assert cleanup==0 and len(r.stdout)==88+length and r.stdout[-24:]==bytes(24),(path,primary,cleanup,length,r.stdout[-24:])
   if expected is not None:
    assert primary in expected,(path,primary,expected)
    assert length==0 and digest==bytes(32)and struct.unpack_from('<Q',r.stdout,56)[0]==0
   else:
    assert primary==0 and length==len(data)and digest==hashlib.sha256(data).digest(),(path,primary,length)
    assert r.stdout[64:-24]==data
  file=root/'Ω.theme'
  for data in(b'',b'kind=light\nbg=#ffffff\n',b'raw\0bytes\xff',bytes(range(256))*256):
   file.write_bytes(data);run(file,data=data)
  file.write_bytes(b'x'*65537);run(file,expected=(-27,))
  file.write_bytes(b'');run(file,maximum=0,data=b'')
  file.write_bytes(b'x');run(file,maximum=0,expected=(-27,));run(file,maximum=65537,expected=(-22,))
  run(root/'missing',expected=(-2,));run(root,expected=(-22,-13,-21))
  file.write_bytes(b'linked theme data');link=root/'linked.theme'
  try:link.symlink_to(file)
  except OSError:
   assert windows
  else:run(link,data=file.read_bytes())
  actual=root/'actual';actual.mkdir();(actual/'source.theme').write_bytes(b'parent link');alias=root/'alias'
  try:alias.symlink_to(actual,target_is_directory=True)
  except OSError:
   assert windows
  else:run(alias/'source.theme',data=b'parent link')
  if not windows:
   fifo=root/'fifo';os.mkfifo(fifo);started=time.monotonic();run(fifo,expected=(-22,));assert time.monotonic()-started<2
   run(Path('/dev/null'),expected=(-22,))
   if os.geteuid()!=0:
    file.chmod(0)
    try:run(file,expected=(-13,))
    finally:file.chmod(0o600)
  print('ok theme-capture/files-exact-digest-links-limits-type-and-census',flush=True)
if __name__=='__main__':main()
