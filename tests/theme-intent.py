#!/usr/bin/env python3
"""Owned theme intent preserves independent IDs and never follows inactive migration tokens."""
import argparse,os,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=ROOT/('build/windows/theme_intent_test.exe'if win else'build/theme_intent_test')
 def run(mode=0,ids=('unknown-requested','dark-requested','light-requested'),error=0):
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(mode),*ids],capture_output=True,timeout=10)
  assert r.returncode==0 and not r.stderr,(mode,r)
  primary,cleanup,charge=struct.unpack_from('<qqQ',r.stdout);assert(primary,cleanup)==(error,0),(mode,primary,cleanup,error)
  if error:assert r.stdout==struct.pack('<qqQ',error,0,0);return
  assert charge==32768
  keys,follow,system,applied,dark,effects,context,config,catalog=struct.unpack_from('<IIiIIIQQQ',r.stdout,24)
  assert(keys,follow,system,applied,dark,context,config,catalog)==(7,1,-1,int(mode!=2),1,1,2,3)
  assert effects==(0 if mode==1 else 2)
  lengths=struct.unpack_from('<6Q',r.stdout,72);off=120;values=[]
  for n in lengths:values.append(r.stdout[off:off+n]);off+=n
  assert off==len(r.stdout)
  expected=list(map(os.fsencode,ids))+([os.fsencode(ids[0]),os.fsencode(ids[1])]if mode==1 else[b'',b''])+[b''if mode==2 else os.fsencode(ids[0])]
  assert values==expected,(mode,values,expected)
 for mode in(0,1,2,8,9,10):run(mode)
 for mode in(3,4,5,6):run(mode,error=-22)
 run(ids=('','',''));run(1,ids=('','',''))
 run(ids=('x'*4095,'y'*4095,'z'*4095));run(7,ids=('x'*4096,'dark','light'),error=-36)
 if not win:run(ids=('raw\udcff','dark','light'))
 print('ok theme-intent/owned-three-IDs-migration-inactive-token-guard-retain-and-bounds',flush=True)
if __name__=='__main__':main()
