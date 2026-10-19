#!/usr/bin/env python3
"""Private legacy snapshots, compatible parser products and selected-source proofs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
from fixture_exchange import FixtureExchange

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path,required=True)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
p.add_argument('--probe',type=Path)
a=p.parse_args()
for field in ('exe', 'probe', 'wine_drive_root'):
    value=getattr(a,field)
    if value is not None:setattr(a,field,value.resolve())

windows=bool(a.wine) or os.name=='nt'
platform='windows-x64' if windows else 'macos-arm64' if sys.platform=='darwin' else 'linux-x86_64'
runner=[a.wine]if a.wine else []
path_override=None
def fixture_command(folder):
    command=[*runner,str(a.exe),native(folder),'fixture','example']
    if windows and path_override is not None:command.append(path_override)
    return command

def native(path):
    return 'C:/'+str(path.relative_to(a.wine_drive_root)).replace(os.sep,'/')if a.wine else str(path)

def commitment(folder,selected,program,script):
    sources=[('extension.ini',folder/'extension.ini',1)]
    sources += [(str(x.relative_to(folder)).replace(os.sep,'/'),x,4)for x in(folder/'syntax').iterdir()if x.is_file()and x.name.endswith('.syn')]
    sources += [(str(x.relative_to(folder)).replace(os.sep,'/'),x,8)for x in(folder/'themes').iterdir()if x.is_file()and x.name.endswith('.theme')]
    sources += [(script or program,selected,18)]
    h=hashlib.sha256(b'rhun-legacy-sources-v1\0');h.update(struct.pack('<I',len(sources)))
    for path,file,role in sorted(sources):
        path=path.encode();st=file.stat()
        h.update(struct.pack('<I',len(path))+path+struct.pack('<QI',st.st_size,0 if windows else st.st_mode&0o111))
        h.update(hashlib.sha256(file.read_bytes()).digest()+struct.pack('<I',role))
    for argv in(program,script):
        argv=argv.encode();h.update(struct.pack('<I',len(argv))+argv)
    return h.digest()

def prepare(folder,launch):
    folder.mkdir(parents=True)
    (folder/'extension.ini').write_text('owner=fixture\nname=example\ntitle='+('t'*180)+'\nversion='+('v'*100)+'\nprotocol=1\n'+launch+'\n[commands]\nhello=Hello|ctrl+h\n')
    (folder/'syntax').mkdir();(folder/'syntax'/'.hidden.syn').write_text('name='+('g'*180)+'\nunknown=ignored\n')
    (folder/'themes').mkdir();(folder/'themes'/'sample.theme').write_text('[palette]\nname='+('z'*180)+'\nkind=unknown\nbg=#bad\n')
    return folder

def run(folder,selected,program,script,mutation=None,error=0):
    with FixtureExchange(fixture_command(folder),timeout=30,output_bound=224)as e:
        header=e.read(128);status=struct.unpack('<q',header[:8])[0]
        assert status==0,(folder.name,status,header)
        assert struct.unpack('<4q',header[16:48])==(1,1,1,4),header
        assert header[64:96]==commitment(folder,selected,program,script),(header[64:96].hex(),commitment(folder,selected,program,script).hex())
        if mutation:mutation(folder)
        e.send(b'1');out,err=e.finish()
        assert e.process.returncode==0 and len(out)==96 and not err,(e.process.returncode,out,err)
        assert struct.unpack('<2q',out[:16])==(error,0),(error,struct.unpack('<2q',out[:16]))
        assert struct.unpack('<2q',out[80:])==(0,0),out
        assert out[48:80]==bytes(32)
        assert out[16:48]==(bytes(32)if error else header[64:96]),out
    assert not(folder/'marker').exists()

with tempfile.TemporaryDirectory(prefix='rhun-legacy-products-',dir=a.wine_drive_root)as tmp:
    top=Path(tmp).resolve()
    os.chdir(top)  # Drive-rooted paths use this captured process drive.
    runtime=(a.wine_drive_root/'windows/system32/cmd.exe')if a.wine else Path('C:/Windows/System32/cmd.exe')if windows else Path('/bin/sh')
    runtime_path=native(runtime)if windows else '/bin/sh'
    external=top/('external script é.cmd'if windows else'external script é.sh');external.write_text('printf forbidden > marker\n')
    for index,launch in enumerate(('runtime='+runtime_path+'\nrun='+native(external),'run.'+platform+'='+runtime_path+'\nrun='+native(external))):
        folder=prepare(top/('absolute-'+str(index)),launch)
        run(folder,external,runtime_path,native(external))
    folder=prepare(top/'relative','runtime='+runtime_path+'\nrun=../'+external.name)
    run(folder,external,runtime_path,native(folder)+'/../'+external.name)
    folder=prepare(top/'runtime-only','runtime='+runtime_path)
    run(folder,runtime,runtime_path,'')
    native_source=top/('native.exe'if windows else'native')
    if windows:
        import shutil
        shutil.copyfile(a.probe or a.exe,native_source)
    else:
        native_source.write_text('#!/bin/sh\nprintf forbidden > marker\n');native_source.chmod(0o755)
    folder=prepare(top/'native-case','run.'+platform+'='+native(native_source))
    run(folder,native_source,native(native_source),'')
    if windows:
        folder=prepare(top/'drive-rooted','run.'+platform+'='+native(native_source)[2:])
        run(folder,native_source,native(native_source),'')
    # Search keeps legacy missing/empty and component spelling, but owns absolute argv.
    tools=top/'tools';tools.mkdir()
    import shutil
    basename='rhun-legacy-runtime'
    searched=tools/(basename+('.exe'if windows else''));shutil.copyfile(runtime,searched)
    if not windows:searched.chmod(0o755)
    prior_path=os.environ.get('PATH')
    def restore_path():
        if prior_path is None:os.environ.pop('PATH',None)
        else:os.environ['PATH']=prior_path
    separator=';'if windows else ':'
    try:
        for index,value in enumerate(('tools',separator+'tools','missing'+separator+separator+'tools','tools'+separator)):
            os.environ['PATH']=value
            path_override=value if windows else None
            folder=prepare(top/('path-'+str(index)),'runtime='+basename+'\nrun='+native(external))
            run(folder,external,native(searched),native(external))
        if not windows:
            os.environb[b'PATH']=b'\xff:tools'
            folder=prepare(top/'unused-invalid-path','runtime='+basename+'\nrun='+native(external))
            run(folder,external,native(searched),native(external))
            if sys.platform!='darwin':  # APFS rejects invalid UTF8 names before selection.
                invalid=top/os.fsdecode(b'\xff');invalid.mkdir()
                shutil.copyfile(searched,invalid/basename);(invalid/basename).chmod(0o755)
                os.environb[b'PATH']=b'\xff'
                folder=prepare(top/'selected-invalid-path','runtime='+basename+'\nrun='+native(external))
                with FixtureExchange(fixture_command(folder),timeout=30,output_bound=224)as e:
                    header=e.read(128);assert struct.unpack_from('<q',header)[0]<0,header
                    result,err=e.finish();assert e.process.returncode==0 and not err and len(result)==96
                    assert struct.unpack_from('<2q',result,80)==(0,0),result
        for index,value in enumerate(('',None)):
            if value is None:os.environ.pop('PATH',None)
            else:os.environ['PATH']=value
            path_override=('-'if value is None else value)if windows else None
            folder=prepare(top/('empty-path-'+str(index)),'runtime='+basename+'\nrun='+native(external))
            with FixtureExchange(fixture_command(folder),timeout=30,output_bound=224)as e:
                header=e.read(128);assert struct.unpack_from('<q',header)[0]<0,header
                result,err=e.finish();assert e.process.returncode==0 and not err and len(result)==96
                assert struct.unpack_from('<2q',result,80)==(0,0),result
        if not windows:
            os.environ.pop('PATH',None)
            candidate=next(Path(directory)/'sh'for directory in('/usr/local/bin','/usr/bin','/bin')if os.access(Path(directory)/'sh',os.X_OK))
            folder=prepare(top/'missing-path-fallback','runtime=sh\nrun='+native(external))
            run(folder,external,str(candidate),native(external))
    finally:
        restore_path();path_override=None
    for index,change in enumerate((lambda f:external.write_text('changed\n'),lambda f:(f/'syntax'/'added.syn').write_text('name=Added\n'),lambda f:(f/'themes'/'sample.theme').unlink(),lambda f:(f/'extension.ini').write_text('changed\n'))):
        external.write_text('printf forbidden > marker\n')
        folder=prepare(top/('mutation-'+str(index)),'runtime='+runtime_path+'\nrun='+native(external))
        run(folder,external,runtime_path,native(external),change,-1008 if index in(0,1,2)else -1003)
print('ok legacy external/relative/ordered/runtime-only/native source commitments, permissive private assets and freshness')
