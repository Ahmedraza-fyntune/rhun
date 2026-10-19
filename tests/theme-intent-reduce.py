#!/usr/bin/env python3
"""Pure requested intent transitions match legacy migration without reading live config or registry."""
import argparse,importlib.util,itertools,os,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--wine');p.add_argument('--exe',type=Path);a=p.parse_args();win=bool(a.wine)or os.name=='nt';exe=a.exe or ROOT/('build/windows/theme_intent_reduce_test.exe'if win else'build/theme_intent_reduce_test')
 calls=0
 def run(vals=(b'old',b'dark',b'light',None,None,b'shown'),keys=7,follow=1,system=-1,kind=0,startup=0,arg=0,resolved=b'',found=0,dark=1,isfollow=0,available=0,epoch=3,ctx=1,status=0,expected=None,expectedflags=None,expectedfollow=None,expectedsystem=None):
  nonlocal calls
  applied=int(vals[5]is not None);header=bytearray(144);struct.pack_into('<IIiII',header,0,keys,follow,system,applied,1)
  struct.pack_into('<6i',header,24,*(-1 if v is None else len(v)for v in vals));struct.pack_into('<IIiIQQIIIIQQ',header,64,kind,startup,arg,0,0,len(resolved),found,dark,isfollow,available,epoch,ctx)
  data=header+b''.join(v+b'\0'for v in vals if v is not None)+resolved
  r=subprocess.run(([a.wine]if a.wine else[])+[str(exe)],input=data,capture_output=True,timeout=10);calls+=1
  assert r.returncode==0 and not r.stderr,(calls,kind,r)
  assert struct.unpack_from('<qq',r.stdout)==(status,0),(calls,kind,r.stdout[:16],status)
  if status:assert len(r.stdout)==16;return
  k,f,s,ap,pd,e,c,ce,ca=struct.unpack_from('<IIiIIIQQQ',r.stdout,16)
  slot,=struct.unpack_from('<Q',r.stdout,64);lengths=struct.unpack_from('<6Q',r.stdout,72);present,=struct.unpack_from('<Q',r.stdout,120)
  off=128;out=[]
  for i,n in enumerate(lengths):out.append(r.stdout[off:off+n]if present>>i&1 else None);off+=n
  assert off==len(r.stdout)and(k,ap,pd,c,ce,ca)==(keys,applied,1,1,2,3)
  ef=follow if expectedfollow is None else expectedfollow;es=system if expectedsystem is None else expectedsystem
  assert(f,s)==(ef,es),(calls,kind,f,s,ef,es)
  assert slot==(0 if not ef else 2 if es==0 else 1)
  if expected is not None:assert out==list(expected),(calls,kind,out,expected,e)
  if expectedflags is not None:assert e==expectedflags,(calls,kind,e,expectedflags)
  return out,f,s,e
 base=(b'old',b'dark',b'light',None,None,b'shown')
 run(expected=base,expectedflags=2) # capture normalizes inactive opaque pending_dark token
 for slot in range(3):
  exp=list(base);exp[slot]=b'pick';run(kind=3,arg=slot,resolved=b'pick',found=1,expected=exp,expectedflags=19)
  exp[slot]=b'';run(kind=3,arg=slot,resolved=b'',found=1,expected=exp,expectedflags=19)
 for keys,startup,available in itertools.product((0,2,3,7),(0,1),(0,1)):
  exp=list(base)
  if keys==0 and startup and available:exp[:3]=[b'omarchy']*3
  run(keys=keys,kind=1,startup=startup,available=available,expected=exp,expectedflags=3 if exp!=list(base)else 2)
 for system,dark,available,startup in itertools.product((-1,0,1),(0,1),(0,1),(0,1)):
  exp=list(base);first=1 if dark else 2;exp[first]=b'old';saved=exp[1];exp[2 if system==0 else 1]=b'old'
  if system<0:exp[3:5]=[b'old',saved]
  run(keys=1,system=system,kind=1,startup=startup,resolved=b'old',found=1,dark=dark,available=available,expected=exp,expectedflags=19)
 for available,startup in itertools.product((0,1),(0,1)):
  exp=(b'rhun-dark',b'dark',b'light',None,None,b'shown')
  if available or not startup:exp=(b'rhun-dark',b'rhun-dark',b'light',None,None,b'shown')
  run(vals=(b'rhun-dark',b'dark',b'light',None,None,b'shown'),keys=1,system=1,kind=1,startup=startup,resolved=b'rhun-dark',found=1,available=available,expected=exp)
 run(keys=1,kind=1,resolved=b'missing',found=0,expected=base,expectedflags=2)
 run(vals=(b'omarchy',*base[1:]),keys=1,kind=1,resolved=b'omarchy',found=1,isfollow=1,available=1,expected=(b'omarchy',b'omarchy',b'omarchy',None,None,b'shown'),expectedflags=19)
 pending=(b'old',b'old',b'light',b'old',b'saved-dark',b'shown')
 run(vals=pending,kind=2,arg=0,expectedsystem=0,expected=(b'old',b'saved-dark',b'old',None,None,b'shown'),expectedflags=27)
 run(vals=pending,kind=2,arg=1,expectedsystem=1,expected=(b'old',b'old',b'light',None,None,b'shown'),expectedflags=27)
 run(vals=pending,kind=2,arg=-1,expected=pending,expectedflags=0)
 run(kind=4,arg=0,resolved=b'shown',found=1,expectedfollow=0,expected=(b'shown',*base[1:]),expectedflags=23)
 run(follow=0,kind=4,arg=1,expectedfollow=1,expected=base,expectedflags=6)
 run(kind=5,resolved=b'next',found=1,expected=base,expectedflags=2)
 run(follow=0,kind=5,resolved=b'next',found=1,expected=(b'next',*base[1:]),expectedflags=19)
 run(kind=3,arg=3,resolved=b'x',found=1,status=-22);run(kind=2,arg=2,status=-22);run(kind=4,arg=2,status=-22)

 for kind in(0,2,5):run(kind=kind,resolved=b'a\0b',status=-22)
 run(kind=3,resolved=b'a\0b',found=1,status=-22);run(kind=3,resolved=b'x'*4096,found=1,status=-22)
 run(kind=1,keys=1,resolved=b'wrong',found=1,status=-22);run(kind=4,arg=0,resolved=b'wrong',found=1,status=-22)
 run(ctx=2,status=-116);run(epoch=4,status=-116)
 run(vals=(b'raw\xff',*base[1:]),expected=(b'raw\xff',*base[1:]))
 run(kind=3,resolved=b'x'*4095,found=1,expected=(b'x'*4095,*base[1:]))
 print('ok theme-intent/reduce-legacy-transition-matrix-'+str(calls),flush=True)
if __name__=='__main__':main()
