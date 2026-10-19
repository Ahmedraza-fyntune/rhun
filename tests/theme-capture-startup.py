#!/usr/bin/env python3
"""Startup qualification freezes ordinary path spelling and sealed calls reject before dereference."""
import argparse,ntpath,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--exe',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=(a.exe or ROOT/('build/windows/theme_capture_startup_test.exe'if win else'build/theme_capture_startup_test')).resolve()
 with tempfile.TemporaryDirectory(prefix='theme-start-',dir=a.wine_drive_root)as td:
  cwd=Path(td).resolve();base=('C:/'+cwd.relative_to(a.wine_drive_root.resolve()).as_posix())if a.wine_drive_root else'Z:'+str(cwd)if a.wine else str(cwd)
  drive=ntpath.splitdrive(base)[0]
  def run(raw,expected=None,error=0):
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),raw]+([base]if win else[]),cwd=cwd,capture_output=True,timeout=10)
   assert r.returncode==0 and not r.stderr,(raw,r)
   status,n=struct.unpack_from('<qQ',r.stdout);assert status==error and len(r.stdout)==16+n,(raw,status,error)
   out=r.stdout[16:]
   if not error:
    e=os.fsencode(expected)
    if win:out=out.replace(b'\\',b'/');e=e.replace(b'\\',b'/')
    assert out==e,(raw,out,e)
  for raw in('name','./theme','sub/../theme'):
   expected=ntpath.normpath(base+'/'+raw)if win else base+'/'+raw
   run(raw,expected)
  run('',error=-22);run('x'*4096,error=-36)
  if win:
   for raw in(drive+'/chosen/../theme',drive+'theme','/rooted','\\rooted'):
    expected=ntpath.normpath(raw if raw.startswith(drive+'/')else base+'/theme'if raw==drive+'theme'else drive+'/rooted')
    run(raw,expected)
   for raw in('\\\\?\\C:\\theme','\\\\.\\NUL','C:/NUL'):run(raw,error=-22)
   if a.wine and a.wine_drive_root:
    other=cwd/'other';other.mkdir();zpath='Z:'+str(other)
    batch=cwd/'per-drive.cmd'
    lines=['@echo off','cd /d "'+zpath.replace('/','\\')+'" || exit /b 1','cd /d "'+base.replace('/','\\')+'" || exit /b 1','"'+('Z:'+str(exe)).replace('/','\\')+'" "Z:theme" "'+base.replace('/','\\')+'"']
    batch.write_bytes(('\r\n'.join(lines)+'\r\n').encode('utf-8'))
    r=subprocess.run([a.wine,'cmd','/d','/c',base+'/per-drive.cmd'],capture_output=True,timeout=15)
    assert r.returncode==0 and not r.stderr,('per-drive',r)
    status,n=struct.unpack_from('<qQ',r.stdout);assert status==0 and len(r.stdout)==16+n
    assert r.stdout[16:].replace(b'\\',b'/')==os.fsencode(zpath+'/theme'),('per-drive',r.stdout)
    # Wine maps ordinary UNC roots through its private dosdevices/unc namespace.
    prefix=a.wine_drive_root.resolve().parent;unc=prefix/'dosdevices/unc/theme-capture'
    unc.mkdir(parents=True,exist_ok=True);link=unc/'share';link.symlink_to(cwd)
    try:
     for raw,expected in(('theme','//theme-capture/share/theme'),('\\rooted','//theme-capture/share/rooted')):
      r=subprocess.run([a.wine,str(exe),raw,'//theme-capture/share'],capture_output=True,timeout=15)
      assert r.returncode==0 and not r.stderr,('UNC',r)
      status,n=struct.unpack_from('<qQ',r.stdout);assert status==0 and len(r.stdout)==16+n
      assert r.stdout[16:].replace(b'\\',b'/')==os.fsencode(expected),('UNC',raw,r.stdout)
    finally:link.unlink()
  else:
   run('/absolute/./../theme','/absolute/./../theme');run('raw\udcff',base+'/raw\udcff')
   (cwd/'target').mkdir();(cwd/'link').symlink_to('target',target_is_directory=True)
   run('link/../theme',base+'/link/../theme')
   n=4095-len(os.fsencode(base))-1;run('x'*n,base+'/'+'x'*n);run('x'*(n+1),error=-36)
 print('ok theme-capture/startup-cwd-relative-byte-paths-and-sealed-no-lazy-qualification',flush=True)
if __name__=='__main__':main()
