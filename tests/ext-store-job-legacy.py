#!/usr/bin/env python3
"""Real isolated legacy transports accept only complete bound bytes and owned context."""
from pathlib import Path
import argparse,os,struct,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);a=p.parse_args();windows=bool(a.wine)or os.name=='nt'
 exe=ROOT/('build/windows/ext_store_job_legacy_test.exe'if windows else'build/ext_store_job_legacy_test')
 with tempfile.TemporaryDirectory(prefix='rhun-legacy-job-Ω space-',dir=a.wine_drive_root)as folder:
  root=Path(folder).resolve();native=str(root)
  if a.wine:native='C:/'+root.relative_to(a.wine_drive_root.resolve()).as_posix()
  def wire(size=512):
   b=bytearray(size)
   if size>65536:
    pattern=bytes((i*37+i//251)&255 for i in range(65521));b[192:]=(pattern*((size-192+65520)//65521))[:size-192]
   b[:8]=b'RHLSS1\0\0';struct.pack_into('<IIQI',b,8,1,192,size,2);b[96:128]=b'\xbb'*32;struct.pack_into('<I',b,144,1);struct.pack_into('<I',b,152,0xffffffff if windows else 0);return b
  def run(mode=20,value=None,marker='',expected=0,extra_env=None):
   (root/'.job-wire').write_bytes(wire()if value is None else value)
   if marker:(root/'.job-test-mode').write_text(marker)
   else:(root/'.job-test-mode').unlink(missing_ok=True)
   env=os.environ.copy()
   if extra_env is not None:
    if extra_env is False:env.pop('PATH',None)
    else:env['PATH']=extra_env
   command=([a.wine]if a.wine else[])+[str(exe),native,str(mode)]
   r=subprocess.run(command,capture_output=True,env=env,cwd=root,timeout=35)
   assert r.returncode==0 and not r.stderr and len(r.stdout)==32,(mode,marker,r)
   status,secondary,length,steps=struct.unpack('<qqQQ',r.stdout)
   assert status==expected and secondary==0 and steps>0,(mode,marker,status,secondary,length,steps,expected)
   expected_length=(len(value)if value is not None else 512)if expected==0 and(mode<10 or mode>=20)else 0
   assert length==expected_length,(mode,length,expected_length)
   return steps
  run(0);run(20);run(35,expected=-116);run(13,expected=-116);run(10);run(12);run(6);run(33);run(34,expected=-2)
  for mode,expected in((1,-125),(2,-110),(3,-116),(4,-125)):
   run(mode,marker='q',expected=expected)
  for marker in('s','x','p','z','T','N','R','F'):run(marker=marker,expected=-5)
  started=time.monotonic();run(marker='B',expected=-5);assert time.monotonic()-started<1
  started=time.monotonic();run(marker='D');assert time.monotonic()-started>=1
  run(marker='h')
  run(23,marker='h',expected=-125)
  run(24,marker='h',expected=-110)
  for offset in(0,8,12,24,28,96,128,136,144,148,152,156,191):
   b=wire();b[offset]^=1
   if offset==96:b[96:128]=bytes(32)
   if offset==24:struct.pack_into('<I',b,24,259)
   if offset==144:struct.pack_into('<I',b,144,0)
   if offset==148:struct.pack_into('<I',b,148,4096)
   if offset==152:struct.pack_into('<I',b,152,1)
   run(value=b,expected=-5)
  for size in(0,1,127,191):run(value=wire()[:size],expected=-5)
  b=wire();struct.pack_into('<Q',b,16,511);run(value=b,expected=-5)
  b=wire();struct.pack_into('<Q',b,16,513);run(value=b,expected=-5)
  b=wire();struct.pack_into('<Q',b,16,2**64-1);run(value=b,expected=-5)
  for child in('m','r','g','b','l','e','T','P','C','M'):run(10,marker=child,expected=-7 if child=='e'else-5)
  run(12,marker='S',expected=-5)
  for path in(False,'','bin:/usr/bin','bad\udcff:/usr/bin'):
   if windows and isinstance(path,str)and'\udcff'in path:continue
   run(extra_env=path)
  maximum=wire(18874368);started=time.monotonic();run(value=maximum)
  print('ok legacyjob/18MiB-complete-typed-take-in-%.2fs'%(time.monotonic()-started),flush=True)
  run(value=maximum+b'!',expected=-7)
  run(21,value=maximum,expected=-125)
  run(22,value=maximum,expected=-110)
  print('ok legacyjob/framing-crosskind-context-EOF-exit-stderr-cancel-timeout',flush=True)
if __name__=='__main__':main()
