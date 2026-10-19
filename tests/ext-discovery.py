#!/usr/bin/env python3
"""Complete managed discovery ownership and rooted selected candidate handoff."""
import argparse
import os
import shutil
from pathlib import Path
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
ID=b'a'*64
def record(generation,active=False):
    return struct.pack('<8sIIQII',b'RHEXIDX\0',1,1 if active else 2,generation,0,0)+(ID if active else bytes(64))+(b'b'*64 if active else bytes(64))
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--wine');parser.add_argument('--wine-drive-root',type=Path);args=parser.parse_args()
    exe=ROOT/('build/windows/ext_discovery_test.exe' if args.wine or os.name=='nt' else 'build/ext_discovery_test')
    with tempfile.TemporaryDirectory(prefix='rhun-discovery-',dir=args.wine_drive_root) as folder:
        root=Path(folder).resolve();owner=root/'.installed'/'466f6f';owner.mkdir(parents=True)
        for name,data in [('Bar',record(1,True)),('Removed',record(2)),('Broken',b'broken')]:
            directory=owner/name.encode().hex();directory.mkdir();(directory/'0000000000000001.idx').write_bytes(data if name!='Removed' else record(1))
        pending=owner/'50656e64696e67';pending.mkdir();(pending/'.pending-test').touch()
        package=root/'.packages'/'466f6f'/'426172'/ID.decode();payload=package/'payload';payload.mkdir(parents=True);lease=package/'lease';lease.touch()
        def run(mode=0,expected=0,target=None,count=1):
            target=target or root
            path='C:/'+target.relative_to(args.wine_drive_root.resolve()).as_posix() if args.wine else str(target)
            options={}
            if os.name=='posix' and not args.wine:
                import resource
                options['preexec_fn']=lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))
            result=subprocess.run(([args.wine] if args.wine else [])+[str(exe),path,str(mode)],capture_output=True,timeout=30,**options)
            assert result.returncode==0 and not result.stderr and len(result.stdout)==32,(mode,result)
            status,secondary,actual_count,steps=struct.unpack('<qqQQ',result.stdout)
            allowed=(expected,) if isinstance(expected,int) else expected
            assert status in allowed and secondary==0 and actual_count==count and steps>0,(mode,status,secondary,actual_count,steps)
        run();run(8);run(9);run(2,-116);run(3,-116);run(4,-116);run(6,-116)
        lease.unlink();run(1,-2);lease.touch()
        payload.rmdir();run(1,-2);payload.mkdir()
        payload.rmdir();payload.write_bytes(b'not a directory');run(1,(-20,-22));payload.unlink();payload.mkdir()
        if os.name=='posix' and not args.wine:
            outside=root/'outside';outside.mkdir();payload.rmdir();payload.symlink_to(outside,target_is_directory=True)
            run(1,(-20,-40));payload.unlink();payload.mkdir()
            for n,path in enumerate([root/'.packages',root/'.packages'/'466f6f',root/'.packages'/'466f6f'/'426172',package]):
                saved=root/('linked-original'+str(n));path.rename(saved);path.symlink_to(saved,target_is_directory=True)
                run(1,(-20,-40));path.unlink();saved.rename(path)
            target=root/'lease-target';target.touch();lease.unlink();lease.symlink_to(target)
            run(1,(-22,-40));lease.unlink();lease.touch()
        if args.wine or os.name=='nt':
            def native(path):
                return 'C:/'+path.relative_to(args.wine_drive_root.resolve()).as_posix() if args.wine else str(path)
            relatives=[Path('.packages'),Path('.packages/466f6f'),Path('.packages/466f6f/426172'),Path('.packages/466f6f/426172')/ID.decode(),Path('.packages/466f6f/426172')/ID.decode()/'payload',Path('.packages/466f6f/426172')/ID.decode()/'lease']
            for n,relative in enumerate(relatives):
                case=root/('reparse-case'+str(n));case.mkdir()
                shutil.copytree(root/'.installed',case/'.installed');shutil.copytree(root/'.packages',case/'.packages')
                path=case/relative;directory=path.is_dir();saved=case/'reparse-original';path.rename(saved)
                command=([args.wine] if args.wine else [])+['cmd','/c','mklink',*(['/D'] if directory else []),native(path),native(saved)]
                made=subprocess.run(command,capture_output=True,timeout=20)
                if made.returncode:
                    if args.wine:raise AssertionError(('NT reparse creation failed',made))
                    print('skip ext-discovery/NT-reparse privilege unavailable',flush=True);break
                run(1,(-2,-20,-22,-40),target=case)
        if os.name=='posix' and not args.wine:
            paths=[root,*root.rglob('*')]
            for path in paths:path.chmod(0o500 if path.is_dir() else 0o400)
            run(8)
            for path in paths:path.chmod(0o700 if path.is_dir() else 0o600)
        import sys
        platform='win' if args.wine or os.name=='nt' else 'mac' if sys.platform=='darwin' else 'linux'
        (payload/'extension.ini').write_text('owner = Foo\nname = Bar\ntitle = Example\nversion = 1\nprotocol = 1\nrun.'+{'win':'windows-x64','mac':'macos-arm64','linux':'linux-x86_64'}[platform]+' = '+('run.exe' if platform=='win' else 'run')+'\n')
        if platform=='win':shutil.copyfile(exe,payload/'run.exe')
        else:
            (payload/'run').write_text('#!/bin/sh\nexit 0\n');(payload/'run').chmod(0o755)
        run(10)
        empty=root/'empty' ;empty.mkdir();run(100,target=empty,count=0)
        cases=root/'cases';cases.mkdir()
        for owner_name,name in [('Foo','Bar'),('foo','Bar'),('Foo','bar'),('CON.','trail.'),('Trailing.','CON.')]:
            directory=cases/'.installed'/owner_name.encode().hex()/name.encode().hex();directory.mkdir(parents=True,exist_ok=True)
            (directory/'0000000000000001.idx').write_bytes(record(1,True))
        run(105,target=cases,count=5)
        maximal=root/'maximal';maximal.mkdir()
        for n in range(4096):
            directory=maximal/'.installed'/('Owner%04d'%n).encode().hex()/'4e616d65';directory.mkdir(parents=True)
            (directory/'0000000000000001.idx').write_bytes(record(1,n<128))
        run(228,target=maximal,count=128)
        print('ok ext-discovery/empty-exact-case-4096-owners-128-active',flush=True)
        print('ok ext-discovery/complete-classification-exact-shadow-bounded-plan',flush=True)
        print('ok ext-discovery/same-container-lease-payload-atomic-handoff',flush=True)
        print('ok ext-discovery/stale-after-plan-free-transfer-cleanup',flush=True)
if __name__=='__main__':main()
