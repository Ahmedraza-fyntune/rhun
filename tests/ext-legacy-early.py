#!/usr/bin/env python3
"""Actual early legacy helper entries bind inherited anchors before application initialization."""
import argparse
import os
from pathlib import Path
import struct
import tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--exe',type=Path,required=True);a=p.parse_args();exe=a.exe.resolve()
if os.name=='nt':raise SystemExit('Windows inherited-anchor launch is covered by the separate native job transport gates')
def call(command,fd,cap):
    with FixtureExchange(command,timeout=30,output_bound=cap,pass_fds=(fd,))as e:
        output,error=e.finish()
        return e.process.returncode,output,error

with tempfile.TemporaryDirectory(prefix='rhun-legacy-early-')as tmp:
    root=Path(tmp).resolve();folder=root/'payload';folder.mkdir();target=root/'external';target.write_text('#!/bin/sh\nprintf forbidden > marker\n');target.chmod(0o755)
    platform='macos-arm64'if __import__('sys').platform=='darwin'else'linux-x86_64'
    (folder/'extension.ini').write_text('owner=fixture\nname=example\ntitle=Example\nversion=1\nprotocol=1\nrun.'+platform+'='+str(target)+'\n')
    fd=os.open(folder,os.O_RDONLY|os.O_DIRECTORY)
    try:
        args=[str(fd),str(folder),'fixture','example','101','202','ab'*16]
        code,wire,error=call([str(exe),'--snapshot-legacy-anchored',*args,'-'],fd,18*1024*1024)
        assert code==0 and 192<len(wire)<=18*1024*1024 and not error,(code,wire,error)
        assert wire[:8]==b'RHLSS1\0\0'and struct.unpack_from('<Q',wire,16)[0]==len(wire)
        source=wire[96:128];tag=wire[32:96];os.fstat(fd)
        code,receipt,error=call([str(exe),'--validate-legacy-anchored',*args,source.hex()],fd,192)
        assert code==0 and len(receipt)==192 and not error,(code,receipt,error)
        assert receipt[:8]==b'RHLEGC1\0'and receipt[16:80]==tag and receipt[80:112]==bytes(32)and receipt[112:144]==source and receipt[144:]==bytes(48)
        os.fstat(fd)
        for expected in('ff'*32,source.hex().upper()):
            code,receipt,error=call([str(exe),'--validate-legacy-anchored',*args,expected],fd,192)
            assert code==1 and len(receipt)==192 and not error
            assert struct.unpack_from('<q',receipt,144)[0]<0 and receipt[80:144]==bytes(64)
            os.fstat(fd)
        target.write_text('changed\n')
        code,receipt,error=call([str(exe),'--validate-legacy-anchored',*args,source.hex()],fd,192)
        assert code==1 and len(receipt)==192 and struct.unpack_from('<q',receipt,144)[0]==-1008
        assert receipt[80:144]==bytes(64);os.fstat(fd)
    finally:os.close(fd)
    assert not(folder/'marker').exists()and sorted(x.name for x in folder.iterdir())==['extension.ini']
print('ok actual early legacy snapshot/source helpers, inherited anchor ownership, exacttag/EOF/exit, no app state or execution')
