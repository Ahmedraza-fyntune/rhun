#!/usr/bin/env python3
"""Counted theme capture requests preserve bounded paths, tags and owner lifetimes."""
from pathlib import Path
import argparse,hashlib,os,struct,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--exe',type=Path);p.add_argument('--decoder',type=Path);a=p.parse_args()
 windows=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_capture_request_test.exe'if windows else'build/theme_capture_request_test')
 path='C:/config Ω/source.theme'if windows else'/config Ω/source.theme';directory='C:/config/omarchy'if windows else'/config/omarchy'
 def run(mode=0,source=path,d='-',primary=0,operation=0,count=1):
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(mode),source,d],capture_output=True,timeout=10)
  assert r.returncode==0 and not r.stderr,(mode,r)
  assert len(r.stdout)>=48,(mode,r.stdout)
  status,last,length,charge=struct.unpack_from('<qqQQ',r.stdout)
  assert(status,last)==(primary,operation),(mode,source,d,status,last,primary,operation)
  assert len(r.stdout)==48+length and r.stdout[-16:]==bytes(16),(mode,length,r.stdout[-16:])
  if primary or not length:return
  wire=r.stdout[32:-16];assert wire[:8]==b'RHTREQ1\0'
  version,header,total,rows,flags=struct.unpack_from('<IIQII',wire,8)
  assert(version,header,total,rows)==(1,256,len(wire),count),(mode,version,header,total,rows,count)
  assert charge==69760,(mode,charge)
  expected=bytearray(wire);expected[64:96]=bytes(32)
  assert wire[64:96]==hashlib.sha256(expected).digest(),mode
  assert wire[48:64]==bytes(range(1,17))
  assert struct.unpack_from('<Q',wire,40)[0]==2
  assert wire[128:160]==(b'\xbb'*32 if mode==2 else bytes(32))
  assert struct.unpack_from('<I',wire,104)[0]==(1 if mode==2 else 0)
  assert struct.unpack_from('<Q',wire,32)[0]==(2**63-1 if mode==6 else 1)
  dl,palette,expected_scope=struct.unpack_from('<III',wire,96)
  assert palette==76 and flags==({1:1,2:3,16:1}.get(mode,0))
  assert wire[108:128]==bytes(20)and wire[160:256]==bytes(96)
  assert wire[256:256+dl]==(d.encode()if d!='-'else b'')
  off=256+dl
  for ordinal in range(rows):
   value,n,reserved=struct.unpack_from('<IIQ',wire,off);off+=16
   assert value==ordinal and reserved==0
   assert wire[off:off+n]==os.fsencode(source);off+=n
  assert off==len(wire)
  return wire
 normal=run()
 for mode in(0,3,6,17):run(mode,count=8 if mode==3 else 1,operation=-22 if mode==17 else 0)
 name_only=run(1,d=directory,count=0);full=run(2,d=directory);run(4,count=8,operation=-7);run(5,operation=-17)
 for mode in(7,8,9,10,11,12,13,14,15):run(mode,d=directory if mode in(11,14,15)else'-',primary=-22,count=0)
 for mode in(21,22):run(mode,primary=-12,count=0)
 run(18,primary=-22,count=0)
 run(source='relative.theme',operation=-22,count=0)
 run(2,source='relative.theme',d=directory,operation=-22,count=0)
 run(source=('C:/'if windows else'/')+'x'*(4095-(3 if windows else 1)))
 run(source=('C:/'if windows else'/')+'x'*(4096-(3 if windows else 1)),operation=-36,count=0)
 run(16,d=('C:/'if windows else'/')+'d'*(4077-(3 if windows else 1)),count=0)
 run(16,d=('C:/'if windows else'/')+'d'*(4078-(3 if windows else 1)),primary=-36,count=0)
 if windows:
  for source in('C:relative','/root-relative','//?/C:/device','//./C:/device','//server','///share','//server/..'):
   run(source=source,operation=-22,count=0)
  for name in('NUL','nul.theme','NUL .theme','CON','PRN','AUX','COM1','com9.theme','LPT1','LPT9','COM¹.theme','COM².theme','LPT³.theme','CONIN$','CONOUT$','NUL:stream'):
   run(source='C:/config/'+name,operation=-22,count=0)
  for name in('COM0.theme','COM10.theme','LPT0.theme','NULify.theme','auxiliary.theme','PRN-file.theme','COM±.theme','LPT±.theme'):
   run(source='C:/config/'+name)
  run(source='//COM1/NUL/ordinary.theme')
  run(source='//server/share/Ω.theme')
 else:run(source='/raw\udcff.theme')
 decoder=a.decoder or ROOT/('build/windows/theme_capture_decode_test.exe'if windows else'build/theme_capture_decode_test')
 with tempfile.TemporaryDirectory(prefix='rhun-theme-wire-',dir=a.wine_drive_root)as folder:
  file=Path(folder).resolve()/'input'
  native='C:/'+file.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(file)if a.wine else str(file)
  def rehash(wire):
   b=bytearray(wire);b[64:96]=bytes(32);b[64:96]=hashlib.sha256(b).digest();return b
  def decode(wire,expected=-22):
   file.write_bytes(wire);r=subprocess.run(([a.wine]if a.wine else[])+[str(decoder),native],capture_output=True,timeout=10)
   assert r.returncode==0 and not r.stderr and len(r.stdout)==8,(expected,r)
   assert struct.unpack('<q',r.stdout)[0]==expected,(expected,struct.unpack('<q',r.stdout)[0],wire[:256].hex())
  for wire in(normal,name_only,full):decode(wire,0)
  for n in(0,1,127,255):decode(normal[:n])
  decode(bytes(65537),-7)
  cases=[(0,b'!'),(8,struct.pack('<I',2)),(12,struct.pack('<I',512)),(16,struct.pack('<Q',len(normal)+1)),(24,struct.pack('<I',0)),(24,struct.pack('<I',9)),(28,struct.pack('<I',2)),(28,struct.pack('<I',4)),(32,bytes(8)),(32,struct.pack('<Q',2**63)),(40,bytes(8)),(40,struct.pack('<Q',2**63)),(48,bytes(16)),(96,struct.pack('<I',1)),(100,struct.pack('<I',75)),(104,struct.pack('<I',1)),(108,b'!'),(127,b'!'),(128,b'!'),(160,b'!'),(255,b'!'),(260,struct.pack('<I',0)),(260,struct.pack('<I',4096)),(264,b'!')]
  for offset,value in cases:
   b=bytearray(normal);b[offset:offset+len(value)]=value;decode(rehash(b))
  b=bytearray(normal);b[64]^=1;decode(b)
  for pos,value in((273 if windows else 272,ord('?')if windows else ord('x')),(276,0)):
   b=bytearray(normal);b[pos]=value;decode(rehash(b))
  b=bytearray(normal+b'!');struct.pack_into('<Q',b,16,len(b));decode(rehash(b))
  duplicate=bytearray(normal+normal[256:]);struct.pack_into('<Q',duplicate,16,len(duplicate));struct.pack_into('<I',duplicate,24,2);decode(rehash(duplicate))
  struct.pack_into('<I',duplicate,len(normal),1);decode(rehash(duplicate),0)
  b=bytearray(full);struct.pack_into('<I',b,104,2);decode(rehash(b),0)
  b=bytearray(name_only);struct.pack_into('<I',b,104,2);b[128:160]=b'\xbb'*32;decode(rehash(b))
 print('ok theme-capture/untrusted-request-bounds-digest-fields-and-duplicates',flush=True)
 print('ok theme-capture/request-tags-limits-sealing-charge-and-lifetime',flush=True)
if __name__=='__main__':main()
