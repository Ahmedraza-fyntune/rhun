#!/usr/bin/env python3
"""Pure effective names, aliases, first-mode semantics and scoped proof projections."""
import argparse,hashlib,os,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--wine-drive-root',type=Path);a=p.parse_args();windows=bool(a.wine)or os.name=='nt';exe=ROOT/('build/windows/theme_capture_omarchy_test.exe'if windows else'build/theme_capture_omarchy_test')
 def run(mode,data):
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(mode)],input=data,capture_output=True,timeout=10);assert r.returncode==0 and not r.stderr,(mode,r);return r.stdout
 for raw,want in[(b'',b''),(b'catppuccin\n\t ',b'catppuccin'),(b'  gruvbox ',b'  gruvbox'),(b'rose\0pine\n',b'rose'),(b'\xffname\0ignored',b'\xffname'),(b'\0\n',b''),(b'name \0ignored\n',b'name ')]:
  out=run(0,raw);assert out==struct.pack('<Q',len(want))+want,(raw,out)
 for raw,want in[(b'catppuccin',b'catppuccin-mocha'),(b'gruvbox',b'gruvbox-dark'),(b'rose-pine',b'rose-pine-dawn'),(b'Catppuccin',b'Catppuccin'),(b'',b''),(b'\xffname',b'\xffname'),(b'omarchy',b'omarchy'),(b'catppuccin\0suffix',b'catppuccin\0suffix')]:
  out=run(1,raw);assert out==struct.pack('<Q',len(want))+want,(raw,out)
 for raw,want in[(b'',0),(b'mode=light\n',1),(b'mode=dark\nmode=light\n',0),(b'[other]\nmode=darklight\n',1),(b'mode=Light\n',0),(b'notmode=light\n',0),(b'mode=dark\0light\n',1),(b'#mode=light\nmode=dark\n',0)]:assert run(2,raw)==struct.pack('<Q',want),(raw,run(2,raw))
 def record(state,data=b''):return struct.pack('<QQ',state,len(data))+ (hashlib.sha256(data).digest()if state==1 else bytes(32))
 unused=record(2);marker=struct.pack('<QQ',1,0)+hashlib.sha256(b'\x01').digest()
 name=record(1,b'name\0raw\n')
 vectors=[name+record(1,b'mode=dark\n')+record(0),name+record(1,b'mode=light\n')+unused,
          name+record(1,b'mode=dark\n')+marker,record(0)+record(0)+record(0),
          record(1,b'')+record(0)+record(0),record(1,b'')+record(1,b'')+marker]
 proofs={}
 for number,base in enumerate(vectors):
  for scope in(1,2):
   records=base[:48]+unused*2 if scope==1 else base
   want=hashlib.sha256(b'RHUN_OMARCHY_CAPTURE_V2\0'+struct.pack('<QQ',scope,6)+b'/theme'+records).digest()
   out=run(scope+2,base);assert out==bytes(8)+want,(number,scope,out.hex(),want.hex())
   proofs[number,scope]=out[8:]
 assert proofs[0,1]==proofs[1,1]==proofs[2,1]
 assert len({proofs[n,2]for n in(0,1,2)})==3
 assert proofs[3,1]!=proofs[4,1]
 print('ok theme-capture/omarchy-effective-alias-first-mode-and-scoped-proof')
if __name__=='__main__':main()
