#!/usr/bin/env python3
"""Resumable sealed candidate lookup preserves legacy first-match and fallback semantics."""
import argparse,os,struct,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_capture_candidate_test.exe'if win else'build/theme_capture_candidate_test')
 def run(query,ids=('one','two','three'),follow=-1,budget=65536,mode=0,error=0):
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe),str(mode),str(budget),query,*ids,str(follow)],capture_output=True,timeout=15)
  assert r.returncode==0 and not r.stderr and len(r.stdout)==80,(mode,r)
  begin,step,index,selfreject,total,units,calls,maxbytes,maxunits,reserved=struct.unpack('<10q',r.stdout)
  assert reserved==0 and maxbytes<=budget and maxunits<=16,(mode,r.stdout)
  if error and mode not in(6,7)and error!=-36:assert begin==error and r.stdout[8:]==bytes(72);return
  assert begin==0,(mode,begin,error)
  if mode in(6,7):assert(step,index,total)==(error,error,1);return
  if error:assert(step,index)==(error,error);return
  assert step==0
  q={1:'rhun-dark',2:'rhun-light'}.get(mode,{'catppuccin':'catppuccin-mocha','gruvbox':'gruvbox-dark','rose-pine':'rose-pine-dawn'}.get(query,query))
  rows=[ids[0]]*65535+[ids[2]]if mode==3 else list(ids)
  if len(os.fsencode(q))>4095:expected=-2;expectedbytes=0;minimumunits=0
  else:
   expected=-2;expectedbytes=0;minimumunits=0
   for i,value in enumerate(rows):
    minimumunits+=1;rowbytes=0
    left,right=os.fsencode(q),os.fsencode(value)
    if len(left)!=len(right):continue
    for x,y in zip(left,right):
     expectedbytes+=2;rowbytes+=2
     if x!=y:break
    minimumunits+=(rowbytes+4095)//4096
    if left==right:expected=i;break
  rejected=int(expected==follow and expected>=0 and mode not in(1,2))
  if rejected:expected=-2
  assert(index,selfreject,total)==(expected,rejected,expectedbytes),(mode,budget,index,selfreject,total,expected,rejected,expectedbytes)
  assert units>=minimumunits,(mode,budget,units,minimumunits)
  if mode==3:assert calls>=4096
 for budget in(1,2,7,4096,65536):
  run('two',budget=budget);run('absent',budget=budget)
  run('same',('same','same','same'),0,budget);run('same',('other','same','same'),1,budget)
  run('',('','','other'),-1,budget)
  run('catppuccin',('none','catppuccin-mocha','catppuccin-mocha'),-1,budget)
  run('ignored',('rhun-dark','rhun-dark','other'),0,budget,1)
  run('ignored',('rhun-light','rhun-light','other'),0,budget,2)
  run('x'*4095,('x'*4094+'y','x'*4095,'short'),-1,budget)
 run('target',('other','unused','target'),-1,65536,3)
 run('x'*4096)
 run('x'*4095,('x'*4096,'other','third'),error=-36)
 run('query',mode=4,error=-7);run('query',mode=9,error=-22);run('query',mode=10,error=-22)
 run('query',follow=3,error=-22)
 for mode,error in((6,-116),(7,-125)):run('abcd',('abcd','else','other'),budget=1,mode=mode,error=error)
 run('two',mode=8)
 print('ok theme-capture-candidate/first-match-self-fallback-budget1-caps-and-freshness',flush=True)
if __name__=='__main__':main()
