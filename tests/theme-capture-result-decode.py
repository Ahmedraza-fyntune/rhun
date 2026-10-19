#!/usr/bin/env python3
"""Every result byte is validated incrementally before any owned row becomes visible."""
import argparse,hashlib,importlib.util,os,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_capture_result_decode_test.exe'if win else'build/theme_capture_result_decode_test')
 spec=importlib.util.spec_from_file_location('wire',ROOT/'tests/theme-capture-build.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 request=m.request(['C:/one.theme'if win else'/one.theme'])
 def row(data=b'kind=light\n',primary=0,cleanup=0):
  b=bytearray(400);struct.pack_into('<IIqq',b,0,0,0,primary,cleanup)
  if not(primary or cleanup):struct.pack_into('<Q',b,24,len(data));b[32:64]=hashlib.sha256(data).digest();struct.pack_into('<II',b,64,76,0);b+=data
  return b
 def wire(rows,req=request,name=b'',omprimary=0,omcleanup=0,presence=0,proof=bytes(32),light=0,globalprimary=0,globalcleanup=0):
  b=bytearray(256);b[:8]=b'RHTRES1\0';struct.pack_into('<II',b,8,1,256);struct.pack_into('<II',b,24,len(rows),struct.unpack_from('<I',req,28)[0]);b[32:96]=req[32:96];struct.pack_into('<IIqqII',b,96,len(name),76,omprimary,omcleanup,light,presence);b[128:160]=proof;struct.pack_into('<qq',b,160,globalprimary,globalcleanup);b+=name+b''.join(rows);struct.pack_into('<Q',b,16,len(b));return b
 def run(data,req=request,status=(-22,0),budget=65536,total=None):
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(budget)],input=struct.pack('<QQ',len(req),len(data))+req+data,capture_output=True,timeout=30)
  assert r.returncode==0 and not r.stderr and len(r.stdout)==64,(status,budget,r)
  primary,cleanup,charged,calls,maxbytes,validated,state,count=struct.unpack('<qq6Q',r.stdout)
  assert(primary,cleanup)==status,(primary,cleanup,status,budget)
  assert maxbytes<=budget and calls>0
  assert validated==int(status==(0,0))
  if total is not None:assert charged==total,(charged,total,budget)
  return charged
 good=wire([row()]);empty=wire([row(b'')]);failed=wire([row(primary=-13,cleanup=-5)])
 for budget in(1,2,7,303,304,4095,65536):
  run(good,status=(0,0),budget=budget,total=315);run(empty,status=(0,0),budget=budget,total=304);run(failed,status=(0,0),budget=budget,total=304)
 run(wire([row(b'x'*65536)]),status=(0,0),total=65840)
 for n in(0,1,7,128,255,256,399,len(good)-1):run(good[:n])
 run(bytes(1048577));run(good+b'!')
 cases=[(0,b'!'),(8,struct.pack('<I',2)),(12,struct.pack('<I',512)),(16,struct.pack('<Q',len(good)+1)),(24,struct.pack('<I',2)),(28,struct.pack('<I',1)),(32,b'!'),(48,b'!'),(64,b'!'),(96,struct.pack('<I',1)),(100,struct.pack('<I',75)),(104,struct.pack('<q',1)),(112,struct.pack('<q',-4096)),(120,struct.pack('<I',1)),(124,struct.pack('<I',1)),(128,b'!'),(160,struct.pack('<q',1)),(168,struct.pack('<q',-4096)),(176,b'!'),(255,b'!'),(256,struct.pack('<I',1)),(260,b'!'),(264,struct.pack('<q',1)),(272,struct.pack('<q',-4096)),(280,struct.pack('<Q',65537)),(288,b'!'),(320,struct.pack('<I',75)),(324,struct.pack('<I',2)),(336,struct.pack('<Q',4096)),(344,b'!'),(656,b'!')]
 for offset,value in cases:
  b=bytearray(good);b[offset:offset+len(value)]=value;run(b)
 for offset in(280,288,320,324,328,344,352,655):
  b=bytearray(failed);b[offset]=1;run(b)
 for primary,cleanup in((-13,0),(0,-5),(-13,-5)):run(wire([],globalprimary=primary,globalcleanup=cleanup),status=(primary,cleanup),total=0)
 omreq=m.request(['C:/one.theme'if win else'/one.theme'],'C:/om'if win else'/om',1)
 proof=b'\x55'*32;om=wire([row()],omreq,b'name',presence=1,proof=proof)
 run(om,omreq,status=(0,0),budget=1,total=319)
 run(wire([row()],omreq,b'',presence=1,proof=proof),omreq,status=(0,0))
 run(wire([row()],omreq),omreq)
 run(wire([row()],omreq,b'na\0me',presence=1,proof=proof),omreq,budget=1)
 run(wire([row()],omreq,omprimary=-1008),omreq,status=(0,0)) # A failed unstable source can preserve independent scope0 rows.
 required=m.request(['C:/one.theme'if win else'/one.theme'],'C:/om'if win else'/om',1,1,proof)
 run(wire([row()],required,omprimary=-13),required)
 run(wire([row(primary=-1008,cleanup=-5)],required,omprimary=-13),required,status=(0,0))
 run(wire([row()],required,b'name',presence=1,proof=proof),required,status=(0,0))
 run(wire([row()],required,b'name',presence=1,proof=b'\x66'*32),required)
 print('ok theme-capture-result/incremental-budget1-framing-status-proof-palette-hash-and-no-partial-view',flush=True)
if __name__=='__main__':main()
