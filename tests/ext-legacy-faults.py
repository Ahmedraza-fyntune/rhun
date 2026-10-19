#!/usr/bin/env python3
"""Every relevant legacy helper allocation/read/stat/close failure preserves ownership and proof output."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
p.add_argument('--probe',type=Path)
a=p.parse_args()
for field in ('exe', 'probe', 'wine_drive_root'):
    value=getattr(a,field)
    if value is not None:setattr(a,field,value.resolve())
windows=bool(a.wine)or os.name=='nt';runner=[a.wine]if a.wine else[]
ROOT=Path(__file__).resolve().parents[1]
platform='windows-x64'if windows else'macos-arm64'if sys.platform=='darwin'else'linux-x86_64'
def native(path):return 'C:/'+str(path.relative_to(a.wine_drive_root)).replace(os.sep,'/')if a.wine else str(path)
with tempfile.TemporaryDirectory(prefix='rhun-legacy-fault-',dir=a.wine_drive_root)as tmp:
    top=Path(tmp).resolve();os.chdir(top)
    folder=top/'payload';folder.mkdir()
    selected=top/('external.exe'if windows else'external')
    if windows:shutil.copyfile(a.probe or ROOT/'build/windows/ext_validate_probe_test.exe',selected)
    else:selected.write_text('#!/bin/sh\nprintf forbidden > marker\n');selected.chmod(0o755)
    (folder/'extension.ini').write_text('owner=fixture\nname=example\ntitle=Example\nversion=1\nprotocol=1\nrun.'+platform+'='+native(selected)+'\n[commands]\na=A\nb=B\n[settings]\nb.type=bool\nb.default=true\ni.type=int\ni.default=12bad\nc.type=choice\nc.options=a b\nc.default=missing\n')
    (folder/'syntax').mkdir();(folder/'syntax'/'x.syn').write_text('name=Legacy\nunknown=warning\nkeywords=alpha beta gamma\n')
    (folder/'themes').mkdir();(folder/'themes'/'x.theme').write_text('[palette]\nname=Legacy\nkind=unknown\nbg=#bad\n')
    if a.exe:exe=a.exe.resolve()
    else:
        spec=importlib.util.spec_from_file_location('legacy_proof_build',ROOT/'tests/faults/ext_validate_build.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        exe=module.build(top/'build',windows,fixture_name='tests/ext_prepare_legacy_test.s')
    def check(extra=None):
        saved={key:os.environ.get(key)for key in(extra or{})}
        os.environ.update(extra or{})
        try:e=FixtureExchange([*runner,str(exe),native(folder),'fixture','example'],timeout=30,output_bound=224)
        finally:
            for key,value in saved.items():
                if value is None:os.environ.pop(key,None)
                else:os.environ[key]=value
        with e:
            first=e.read(128);primary,secondary=struct.unpack_from('<2q',first)
            if primary==0:e.send(b'1')
            out,err=e.finish();assert e.process.returncode==0 and len(out)==96 and not err,(extra,e.process.returncode,first,out,err)
            last,last_secondary=struct.unpack_from('<2q',out);release,live=struct.unpack_from('<2q',out,80)
            assert live==0,(extra,primary,secondary,last,last_secondary,release,live)
            failed=primary!=0 or last!=0 or release!=0
            if failed:assert out[16:80]==bytes(64),(extra,out.hex())
            assert not(folder/'marker').exists()
            return failed,secondary or last_secondary or release
    assert not check()[0]
    for key,maximum,tail in(('RHUN_EV_ALLOC_N',640,16),('RHUN_EV_READ_N',256,8),('RHUN_EV_STAT_N',256,8),('RHUN_EV_CLOSE_N',256,8)):
        failures=0;clean=0
        for ordinal in range(1,maximum+1):
            failed,_=check({key:str(ordinal)})
            if failed:failures+=1;clean=0
            else:clean+=1
            if clean==tail:break
        assert failures>=8 and clean==tail,(key,failures,ordinal)
        print('ok legacy',key,failures,'failure ordinals',flush=True)
    if not windows:
        # The new relative-runtime qualification owns both its intermediate and final strings.
        original=(folder/'extension.ini').read_bytes()
        runtime_dir=top/'tools';runtime_dir.mkdir();runtime=runtime_dir/'legacy-runtime'
        shutil.copyfile(selected,runtime);runtime.chmod(0o755)
        (folder/'extension.ini').write_bytes(original.replace(('run.'+platform+'='+native(selected)).encode(),('runtime=legacy-runtime\nrun='+native(selected)).encode()))
        oldpath=os.environ.get('PATH');os.environ['PATH']='tools'
        try:
            clean=0;failures=0
            for ordinal in range(1,640):
                failed,_=check({'RHUN_EV_ALLOC_N':str(ordinal)})
                if failed:failures+=1;clean=0
                else:clean+=1
                if clean==16:break
            assert failures>=8 and clean==16,(failures,ordinal)
            print('ok relative runtime owned qualification',failures,'allocation failure ordinals',flush=True)
        finally:
            if oldpath is None:os.environ.pop('PATH',None)
            else:os.environ['PATH']=oldpath
            (folder/'extension.ini').write_bytes(original)
    assert check({'RHUN_EV_READ_N':'1','RHUN_EV_ZERO':'1'})[0]
    assert check({'RHUN_EV_SCAN_FAIL':'1'})[0]
    assert not check({'RHUN_EP_PARTIAL':'1'})[0]
    # Classification failure plus mandatory cleanup failure must not become clean absence.
    failed,secondary=check({'RHUN_EV_STAT_N':'1','RHUN_EV_CLOSE_N':'1'})
    assert failed and secondary<0,(failed,secondary)
print('ok helper IO/allocation cleanup, failed proof output untouched, scan/EOF and doublefaults, no execution')
