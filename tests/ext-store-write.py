#!/usr/bin/env python3
"""Immutable rooted selection publication, READY checks, and bounded pruning."""
import argparse
from pathlib import Path
import os
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def index(generation, active=None, previous=None):
    return struct.pack('<8sIIQII', b'RHEXIDX\0', 1, 1 if active else 2, generation, 0, 0) + (active or bytes(64)) + (previous or bytes(64))

def checks(executable, wine, drive, folder):
    prefix = [wine] if wine else []
    root = folder/'store'
    root.mkdir()
    nextfile = folder/'next'
    def native(path):
        return 'C:/' + path.resolve().relative_to(drive).as_posix() if wine else str(path.resolve())
    def run(record, mode=0, expected=(0,0,0,3), target=root):
        nextfile.write_bytes(record)
        options = {}
        if os.name == 'posix' and not wine:
            import resource
            options['preexec_fn'] = lambda: resource.setrlimit(resource.RLIMIT_NOFILE, (32,32))
        result = subprocess.run([*prefix,str(executable.resolve()),native(target),'Foo','CON.',native(nextfile),str(mode)],capture_output=True,timeout=60,**options)
        assert result.returncode == 0 and not result.stderr and len(result.stdout) == 64, result
        words = struct.unpack('<8q', result.stdout)
        assert words[:4] == expected and words[6] == 0, words
        return words
    directory = root/'.installed'/'466f6f'/'434f4e2e'
    records = [index(1,b'a'*64),index(2,b'b'*64,b'a'*64),index(3,b'a'*64,b'b'*64),index(4),index(5,b'c'*64)]
    for number, record in enumerate(records,1):
        run(record)
        assert (directory/('%016x.idx' % number)).read_bytes() == record
        assert sorted(p.name for p in directory.iterdir()) == [('%016x.idx' % x) for x in range(max(1,number-1),number+1)]
    print('ok ext-store/write/first-update-rollback-removed-reinstall',flush=True)
    old = sorted(p.name for p in directory.iterdir())
    for mode, expected in ((1,(0,0,-125,2)),(2,(0,0,-116,2)),(3,(0,0,-22,2)),(5,(0,-116,0,1))):
        run(index(6),mode,expected)
        assert sorted(p.name for p in directory.iterdir()) == old
    run(index(9),expected=(-22,0,0,0))
    assert sorted(p.name for p in directory.iterdir()) == old
    print('ok ext-store/write/precommit-rejection-stale-proof-epoch',flush=True)
    def held(target, mode, record):
        nextfile.write_bytes(record)
        process=subprocess.Popen([*prefix,str(executable.resolve()),native(target),'Foo','CON.',native(nextfile),str(mode)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        assert process.stdout.read(6)==b'READY\n'
        return process
    def case(name):
        target=folder/name;path=target/'.installed'/'466f6f'/'434f4e2e';path.mkdir(parents=True)
        (path/'0000000000000001.idx').write_bytes(index(1))
        return target,path
    target,path=case('collision')
    process=held(target,4,index(2));collision=path/'0000000000000002.idx';collision.write_bytes(b'invalid')
    output,error=process.communicate(b'x',timeout=30)
    assert process.returncode==0 and not error and struct.unpack('<8q',output)[2:4]==(-5,4),(output,error)
    assert collision.read_bytes()==b'invalid' and (path/'0000000000000001.idx').read_bytes()==index(1)
    for mode in (6,7):
        target,path=case('kill'+str(mode));process=held(target,mode,index(2))
        process.kill();process.communicate(timeout=30)
        assert (path/'0000000000000001.idx').read_bytes()==index(1)
        assert (path/'0000000000000002.idx').exists()==(mode==7)
    if os.name=='posix' and not wine:
        target,path=case('ancestor')
        process=held(target,4,index(2))
        saved=path.with_name('held-object');path.rename(saved)
        outside=folder/'outside';outside.mkdir();(outside/'sentinel').write_bytes(b'preserve')
        path.symlink_to(outside,target_is_directory=True)
        output,error=process.communicate(b'x',timeout=30)
        assert process.returncode==0 and not error and struct.unpack('<8q',output)[2:4]==(0,3),(output,error)
        assert list(outside.iterdir())==[outside/'sentinel'] and (outside/'sentinel').read_bytes()==b'preserve'
        assert (saved/'0000000000000002.idx').read_bytes()==index(2)
    target,path=case('step-budget')
    for generation in range(2,31):(path/('%016x.idx'%generation)).write_bytes(index(generation))
    process=held(target,10,index(31));prior=set(p.name for p in path.iterdir());steps=0
    while True:
        current=set(p.name for p in path.iterdir())
        # The first step already completed before held() received READY.
        assert len(prior-current)<=3
        prior=current;steps+=1
        process.stdin.write(b'x');process.stdin.flush()
        line=process.stdout.readline()
        if line==b'DONE\n':break
        assert line==b'READY\n',line
    output=process.stdout.read();error=process.stderr.read();process.wait(timeout=30)
    assert process.returncode==0 and not error and len(output)==64 and steps==10,(steps,output,error)
    assert sorted(p.name for p in path.iterdir())==['000000000000001e.idx','000000000000001f.idx']
    print('ok ext-store/write/collision-crash-boundaries-ancestor-budget',flush=True)
    for p in directory.iterdir(): p.unlink()
    (directory/'ffffffffffffffff.idx').write_bytes(index((1<<64)-1))
    run(index(1),expected=(-75,0,0,0))
    assert [p.name for p in directory.iterdir()] == ['ffffffffffffffff.idx']
    for p in directory.iterdir(): p.unlink()
    for generation in range(1,31):
        (directory/('%016x.idx'%generation)).write_bytes(index(generation))
    words = run(index(31))
    assert words[7] == 10 and sorted(p.name for p in directory.iterdir()) == ['000000000000001e.idx','000000000000001f.idx'], words
    print('ok ext-store/write/unsigned-overflow-bounded-pruning-retention',flush=True)
    for p in directory.iterdir(): p.unlink()
    for number in range(4096): (directory/('.ignored%04d'%number)).touch()
    run(index(1),expected=(-27,0,0,6))
    assert len(list(directory.iterdir())) == 4096
    (directory/'.ignored0000').unlink()
    run(index(1))
    assert len(list(directory.iterdir())) == 4096
    print('ok ext-store/write/hidden-native-cap-and-one-slot-boundary',flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--wine-drive-root',type=Path)
    parser.add_argument('--exe',type=Path)
    args=parser.parse_args()
    windows=bool(args.wine) or os.name=='nt'
    executable=args.exe or ROOT/('build/windows/ext_store_write_test.exe' if windows else 'build/ext_store_write_test')
    base=args.wine_drive_root.resolve() if args.wine_drive_root else None
    with tempfile.TemporaryDirectory(prefix='rhun-ext-store-write-',dir=base) as folder:
        checks(executable,args.wine,base,Path(folder).resolve())
if __name__=='__main__': main()
