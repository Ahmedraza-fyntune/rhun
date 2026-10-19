#!/usr/bin/env python3
"""Complete isolated theme responses, independent rows and expected Omarchy proof binding."""
import argparse,hashlib,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def request(paths,directory='',scope=0,expected_scope=0,proof=bytes(32)):
 b=bytearray(256);b[:8]=b'RHTREQ1\0';struct.pack_into('<II',b,8,1,256);struct.pack_into('<IIQQ',b,24,len(paths),[0,1,3][scope],1,2);b[48:64]=bytes(range(1,17));d=os.fsencode(directory);struct.pack_into('<III',b,96,len(d),76,expected_scope);b[128:160]=proof;b+=d
 for i,path in enumerate(paths):
  raw=os.fsencode(path);b+=struct.pack('<IIQ',i,len(raw),0)+raw
 struct.pack_into('<Q',b,16,len(b));b[64:96]=hashlib.sha256(b).digest();return bytes(b)
def decode(wire,req,expected):
 assert wire[:8]==b'RHTRES1\0'and struct.unpack_from('<IIQ',wire,8)==(1,256,len(wire))
 count,flags=struct.unpack_from('<II',wire,24);assert(count,flags)==struct.unpack_from('<II',req,24)
 assert wire[32:96]==req[32:96]and wire[176:256]==bytes(80)
 assert struct.unpack_from('<qq',wire,160)==(0,0)
 n,palette=struct.unpack_from('<II',wire,96);assert palette==76
 assert n<=4096;name=wire[256:256+n];off=256+n;rows=[]
 for i,(primary,cleanup,data)in enumerate(expected):
  h=wire[off:off+96];off+=96;p=wire[off:off+304];off+=304
  ordinal,flags,status,close,length=struct.unpack_from('<IIqqQ',h)
  assert(ordinal,flags,status,close)==(i,0,primary,cleanup),(i,status,close,primary,cleanup)
  assert h[88:]==bytes(8)
  if primary or cleanup:
   assert h[24:]==bytes(72)and p==bytes(304)
  else:
   assert length==len(data)and wire[off:off+length]==data
   assert h[32:64]==hashlib.sha256(data).digest()
   assert struct.unpack_from('<I',h,64)[0]==76 and struct.unpack_from('<I',h,68)[0]in(0,1)
   assert struct.unpack_from('<Q',h,80)[0]>>12==0
  rows.append((h,p,wire[off:off+length]));off+=length
 assert off==len(wire)
 return wire,name,rows
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);p.add_argument('--exe',type=Path);a=p.parse_args()
 win=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_capture_job_test.exe'if win else'build/theme_capture_job_test')
 with tempfile.TemporaryDirectory(prefix='rhun-theme-build-',dir=a.wine_drive_root)as td:
  root=Path(td).resolve();om=root/'om';om.mkdir();(om/'theme').mkdir();source=root/'one.theme';missing=root/'missing.theme'
  def native(p):return'C:/'+p.relative_to(a.wine_drive_root.resolve()).as_posix()if a.wine and a.wine_drive_root else'Z:'+str(p)if a.wine else str(p)
  def run(paths,scope=0,escope=0,proof=bytes(32),expected=None):
   req=request(list(map(native,paths)),native(om)if scope else'',scope,escope,proof)
   r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],input=req,capture_output=True,timeout=15)
   assert r.returncode==0 and not r.stderr,(r,)
   expected=expected or[(0,0,path.read_bytes())for path in paths]
   return decode(r.stdout,req,expected)
  data=b'kind=light\nbackground=#112233\nunknown=ignored\n';source.write_bytes(data)
  run([source,missing],expected=[(0,0,data),(-2,0,b'')]);source.write_bytes(b'');run([source])
  source.write_bytes(b'x'*65536);run([source]*8)
  source.write_bytes(b'x'*65537);run([source],expected=[(-27,0,b'')]);source.write_bytes(data)
  (om/'theme.name').write_bytes(b'catppuccin\n');w,name,rows=run([],1);assert name==b'catppuccin';proof=w[128:160]
  run([source],1,1,proof);(om/'theme/colors.toml').write_bytes(b'mode=dark\n');(om/'theme/light.mode').mkdir()
  w,name,rows=run([source],2,1,proof);assert struct.unpack_from('<II',w,120)==(1,15)
  bad=bytes([proof[0]^1])+proof[1:];w,name,rows=run([source],1,1,bad,expected=[(-1008,0,b'')]);assert name==b''and w[120:160]==bytes(40)and struct.unpack_from('<qq',w,104)==(-1008,0)
  (om/'theme.name').unlink();(om/'theme.name').mkdir()
  w,name,rows=run([source],1,expected=[(0,0,data)]);assert name==b''and w[120:160]==bytes(40)and struct.unpack_from('<qq',w,104)==(-13 if win else-22,0)
  w,name,rows=run([source],1,1,proof,expected=[(-1008,0,b'')]);assert struct.unpack_from('<qq',w,104)==(-13 if win else-22,0)
 print('ok theme-capture-job/complete-rows-bounds-parsing-projection-and-failure-isolation',flush=True)
if __name__=='__main__':main()
