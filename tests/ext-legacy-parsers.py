#!/usr/bin/env python3
"""Pure legacy manifest/default and private grammar/theme compatibility under explicit budgets."""
import argparse
import os
from pathlib import Path
import struct
import sys
import tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--dir',type=Path,required=True)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
a=p.parse_args();windows=bool(a.wine)or os.name=='nt';suffix='.exe'if windows else'';runner=[a.wine]if a.wine else[]
platform='windows-x64'if windows else'macos-arm64'if sys.platform=='darwin'else'linux-x86_64'

def native(path):return 'C:/'+str(path.relative_to(a.wine_drive_root)).replace(os.sep,'/')if a.wine else str(path)

def call(name,file,cap):
    with FixtureExchange([*runner,str((a.dir/(name+suffix)).resolve()),native(file)],timeout=30,output_bound=cap)as e:
        out,err=e.finish();assert e.process.returncode==0 and not err and len(out)==cap,(name,e.process.returncode,out,err);return out

cases=[('bool','yes',None,None,None,'yes'),('bool','true',None,None,None,'no'),('int','oops',None,None,None,'0'),('int','12junk',None,None,None,'12'),('int','999999999999',None,None,None,'2147483647'),('int','-1',None,None,None,'0'),('int','3','20','10',None,'10'),('choice','b',None,None,'a b','b'),('choice','missing',None,None,'a b','a'),('choice','missing',None,None,None,'missing'),('choice','missing',None,None,'','missing'),('string',None,None,None,None,'')]
with tempfile.TemporaryDirectory(prefix='rhun-legacy-parsers-',dir=a.wine_drive_root)as tmp:
    f=Path(tmp).resolve()/'source'
    base='owner=fixture\nname=example\ntitle='+('t'*180)+'\nversion='+('v'*100)+'\nprotocol=1\nrun.'+platform+'=/bin/sh\n'
    body=base+'[commands]\nhello=Hello|ctrl+h\n[settings]\n'
    for index,(kind,default,low,high,options,expected)in enumerate(cases):
        key='s'+str(index);body+=key+'.type='+kind+'\n'
        for field,value in zip(('default','min','max','options'),(default,low,high,options)):
            if value is not None:body+=key+'.'+field+'='+value+'\n'
    f.write_text(body);out=call('ext_prepare_legacy_parse_test',f,2048)
    assert struct.unpack_from('<2q',out)==(0,12)and struct.unpack_from('<2q',out,2000)==(1,0)
    assert struct.unpack_from('<2q',out,2032)==(0,0)
    for index,case in enumerate(cases):assert out[16+index*64:16+(index+1)*64].split(b'\0')[0].decode()==case[-1],(index,out)
    f.write_text(base+'[settings]\n'+''.join('s'+str(i)+'.default=x\n'for i in range(257)))
    out=call('ext_prepare_legacy_parse_test',f,2048);assert struct.unpack_from('<q',out)[0]==-1007 and struct.unpack_from('<2q',out,2032)==(0,0)
    for source,error in [('name='+('g'*180)+'\nunknown=ignored\n',0),('name=\nunknown=ignored\n',0),('name=Budget\nkeywords='+' '.join('word'+str(i)for i in range(65537))+'\n',-1007),('name=Budget\n'+'region=a b string\n'*4097,-1007)]:
        f.write_text(source);out=call('grammar_prepare_legacy_test',f,64);assert struct.unpack_from('<q',out)[0]==error,(error,out.hex());assert struct.unpack_from('<3q',out,40)==(0,0,0),out.hex()
    for source,name,kind in [('name=top\n[palette]\nname='+('z'*180)+'\nkind=light\nbg=#bad\n','z'*180,0),('name=\nkind=unknown\n','',1),('kind=light\n','sample',0),('','sample',1)]:
        f.write_text(source);out=call('theme_prepare_legacy_test',f,1024);assert struct.unpack_from('<3q',out)==(0,kind,len(name)),out.hex();assert out[32:32+len(name)].decode()==name;assert struct.unpack_from('<2q',out,1008)==(0,0)
    f.write_bytes(b'name=Bad\nbackground=\xff')
    out=call('theme_prepare_legacy_test',f,1024);assert struct.unpack_from('<q',out)[0]==-1012 and struct.unpack_from('<2q',out,1008)==(0,0)
print('ok pure legacy defaultcoercion, longmetadata, privatecommands, setting/grammar budgets, warning semantics and permissive owned theme headers')
