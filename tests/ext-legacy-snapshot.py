#!/usr/bin/env python3
"""Initial legacy transcript ownership, framing, pure import and distinct source-only receipts."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
from fixture_exchange import FixtureExchange

CAP=18*1024*1024
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--producer',type=Path,required=True)
p.add_argument('--importer',type=Path,required=True)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
p.add_argument('--probe',type=Path)
p.add_argument('--fault-importer',type=Path)
a=p.parse_args()
for field in ('producer', 'importer', 'fault_importer', 'probe', 'wine_drive_root'):
    value=getattr(a,field)
    if value is not None:setattr(a,field,value.resolve())

windows=bool(a.wine)or os.name=='nt'
runner=[a.wine]if a.wine else []
platform='windows-x64'if windows else 'macos-arm64'if sys.platform=='darwin'else 'linux-x86_64'

def native(path):
    return 'C:/'+str(path.relative_to(a.wine_drive_root)).replace(os.sep,'/')if a.wine else str(path)

def call(exe,args,cap):
    with FixtureExchange([*runner,str(exe.resolve()),*args],timeout=30,output_bound=cap)as e:
        out,err=e.finish()
        assert e.process.returncode==0 and not err,(exe,e.process.returncode,out[:192],err)
        return out

def check_import(file,folder,wire,tag,drive,success=True,exe=None,fail_at=None,cwd=None):
    file.write_bytes(struct.pack('<Q',drive)+tag+wire)
    command=[native(file),native(folder),'fixture','example',cwd or native(Path.cwd())]
    if fail_at is not None:command.append(str(fail_at))
    out=call(exe or a.importer,command,160)
    assert len(out)==160,out
    status,secondary=struct.unpack_from('<2q',out)
    assert secondary==0 and ((status==0)if success else(status<0)),(status,secondary)
    assert struct.unpack_from('<4q',out,128)==(0,0,0,0),out.hex()
    assert struct.unpack_from('<I',out,124)[0]==0,('forbidden importer IO',out.hex())
    if success:
        assert struct.unpack_from('<5q',out,16)==(1,1,1,4,2),out.hex()
        assert out[64:96]==wire[96:128] and struct.unpack_from('<3q',out,96)==(-1,-1,-1)
    else:
        assert out[64:120]==bytes(56),out.hex()
    return out

def resign(wire):
    value=bytearray(wire);count=struct.unpack_from('<I',value,24)[0]
    pl,sl=struct.unpack_from('<2I',value,144);program=bytes(value[192:192+pl]);script=bytes(value[192+pl:192+pl+sl])
    off=192+pl+sl;h=hashlib.sha256(b'rhun-legacy-sources-v1\0');h.update(struct.pack('<I',count))
    for i in range(count):
        length,roles,size,ex=struct.unpack_from('<IIQI',value,off);data_len=struct.unpack_from('<Q',value,off+56)[0]
        path=bytes(value[off+80:off+80+length]);digest=bytes(value[off+24:off+56])
        h.update(struct.pack('<I',length)+path+struct.pack('<QI',size,ex)+digest+struct.pack('<I',roles))
        off+=80+length+data_len
    for arg in(program,script):h.update(struct.pack('<I',len(arg))+arg)
    value[96:128]=h.digest();return value

context_exe=a.importer.with_name('ext_legacy_context_test'+('.exe'if windows else''))
if context_exe.exists():
    for value,length,drive in (('C:/work',2,67),('z:\\work',2,90),('//server/share/work',14,0),('\\\\server\\share\\work',14,0),('//s/t',5,0)):
        out=call(context_exe,[value],16);assert struct.unpack('<2q',out)==(length,drive),(value,out)
    for value in ('','x','relative','C:work','//server','//server/','///share','//./share','//../share','//?/share','//server/.','//server/..','//server/share/'+('x'*4096)):
        out=call(context_exe,[value],16);status,drive=struct.unpack('<2q',out);assert status<0 and drive==0,(value,out)

with tempfile.TemporaryDirectory(prefix='rhun-legacy-snapshot-',dir=a.wine_drive_root)as tmp:
    root=Path(tmp).resolve();os.chdir(root)
    folder=root/'payload';folder.mkdir()
    target=root/('external.exe'if windows else 'external')
    if windows:shutil.copyfile(a.probe or a.producer,target)
    else:target.write_text('#!/bin/sh\nprintf forbidden > marker\n');target.chmod(0o755)
    program=native(target)
    (folder/'extension.ini').write_text('owner=fixture\nname=example\ntitle=Example\nversion=1\nprotocol=1\nrun.'+platform+'='+program+'\n[commands]\nhello=Hello\n')
    (folder/'syntax').mkdir();(folder/'syntax'/'legacy.syn').write_text('name='+('g'*180)+'\nunknown=ignored\n')
    (folder/'themes').mkdir();(folder/'themes'/'legacy.theme').write_text('[palette]\nname='+('t'*180)+'\nkind=unknown\nbg=#bad\n')
    wire=call(a.producer,[native(folder),'fixture','example'],CAP)
    assert wire[:8]==b'RHLSS1\0\0'and struct.unpack_from('<Q',wire,16)[0]==len(wire),wire[:192]
    tag=wire[32:96];drive=struct.unpack_from('<I',wire,152)[0];file=root/'input'
    assert drive==(ord('C')if a.wine else ord(root.drive[0].upper())if windows else 0),drive
    check_import(file,folder,wire,tag,drive)
    if a.fault_importer:
        out=check_import(file,folder,wire,tag,drive,exe=a.fault_importer)
        allocations=struct.unpack_from('<I',out,120)[0]
        assert 0<allocations<4096,allocations
        print('pure importer allocation ordinals',allocations,flush=True)
        for ordinal in range(1,allocations+1):
            check_import(file,folder,wire,tag,drive,False,a.fault_importer,ordinal)
        check_import(file,folder,wire,tag,drive,True,a.fault_importer,allocations+1)

    if windows:
        # Valid, re-signed transcripts establish context handling independently of native SMB.
        def rewrite_source(original,program,run):
            pl,sl=struct.unpack_from('<2I',original,144);assert sl==0
            records=[];off=192+pl
            for _ in range(struct.unpack_from('<I',original,24)[0]):
                n,role=struct.unpack_from('<2I',original,off);dlen=struct.unpack_from('<Q',original,off+56)[0]
                head=bytearray(original[off:off+80]);path=original[off+80:off+80+n];data=original[off+80+n:off+80+n+dlen]
                if role==18:path=program.encode()
                if role==1:
                    data=('owner=fixture\nname=example\ntitle=Example\nversion=1\nprotocol=1\nrun.'+platform+'='+run+'\n[commands]\nhello=Hello\n').encode()
                    struct.pack_into('<Q',head,8,len(data));struct.pack_into('<Q',head,56,len(data));head[24:56]=hashlib.sha256(data).digest()
                struct.pack_into('<I',head,0,len(path));records.append((path,bytes(head)+path+data))
                off+=80+n+dlen
            head=bytearray(original[:192]);struct.pack_into('<I',head,144,len(program.encode()));struct.pack_into('<I',head,152,0)
            out=head+program.encode()+b''.join(record for _,record in sorted(records))
            struct.pack_into('<Q',out,16,len(out));return resign(out)
        unc='//server/share/work'
        absolute=bytearray(wire);struct.pack_into('<I',absolute,152,0)
        check_import(file,folder,absolute,tag,0,cwd=unc)
        unc_program='//server/share/tool.exe'
        rooted=rewrite_source(wire,unc_program,'/tool.exe')
        check_import(file,folder,rooted,tag,0,cwd=unc)
        check_import(file,folder,rooted,tag,0,cwd='\\\\server\\share\\work')
        check_import(file,folder,rooted,tag,0,False,cwd='//other/share/work')
        explicit=rewrite_source(wire,unc_program,unc_program)
        check_import(file,folder,explicit,tag,0,cwd=unc)
        for bad in ('relative','C:/work','//server','//server/','///share','//./share','//../share','//?/share','//server/.','//server/..','//server/share/'+('x'*4096)):
            check_import(file,folder,absolute,tag,0,False,cwd=bad)
        check_import(file,folder,wire,tag,drive,False,cwd=unc)
        if a.fault_importer:
            out=check_import(file,folder,rooted,tag,0,exe=a.fault_importer,cwd=unc)
            allocations=struct.unpack_from('<I',out,120)[0]
            for ordinal in range(1,allocations+1):
                check_import(file,folder,rooted,tag,0,False,a.fault_importer,ordinal,cwd=unc)
    # Import is entirely memory-based: no payload or external source remains available.
    hidden=root/'hidden';folder.rename(hidden);target.unlink()
    check_import(file,folder,wire,tag,drive)
    hidden.rename(folder)
    # Every truncation fails without a partial ready candidate or owned lease.
    cuts=range(len(wire))
    if windows:
        cuts=set(range(193));pl,sl=struct.unpack_from('<2I',wire,144);off=192+pl+sl
        cuts.update((192+pl-1,192+pl,off-1,off))
        for i in range(struct.unpack_from('<I',wire,24)[0]):
            length=struct.unpack_from('<I',wire,off)[0];data_len=struct.unpack_from('<Q',wire,off+56)[0]
            cuts.update(range(off,off+81));cuts.update((off+80+length-1,off+80+length,off+80+length+data_len-1))
            off+=80+length+data_len
        cuts=sorted(cut for cut in cuts if 0<=cut<len(wire))
    for cut in cuts:
        check_import(file,folder,wire[:cut],tag,drive,False)
    mutations=[]
    for offset,value in((0,0),(8,2),(12,191),(16,len(wire)+1),(24,259),(28,1),(128,1),(136,1),(144,4096),(148,4096),(156,1)):
        v=bytearray(wire);struct.pack_into('<I',v,offset,value);mutations.append(v)
    for offset in(32,64,96,127,160,191):
        v=bytearray(wire);v[offset]^=1;mutations.append(v)
    mutations += [wire+b'x',bytes(CAP+1)]
    pl,sl=struct.unpack_from('<2I',wire,144);off=192+pl+sl;positions=[]
    for i in range(struct.unpack_from('<I',wire,24)[0]):
        positions.append(off);length=struct.unpack_from('<I',wire,off)[0];dlen=struct.unpack_from('<Q',wire,off+56)[0];off+=80+length+dlen
    for off in positions:
        for field,value,width in((0,4096,4),(4,0x4000,4),(8,2**64-1,8),(16,0x100,4),(20,1,4),(56,2**64-1,8),(64,1,8),(72,1,8)):
            v=bytearray(wire);struct.pack_into('<I'if width==4 else'<Q',v,off+field,value);mutations.append(v)
        v=bytearray(wire);v[off+24]^=1;mutations.append(v)
    # Recompute the commitment after validly framed path/data mutations. The importer must
    # independently reject data hashes, callback argv mismatch and wrong asset roles.
    for off in positions:
        length,roles=struct.unpack_from('<2I',wire,off)
        if roles==18:
            v=bytearray(wire);v[off+80+length-1]^=1;mutations.append(resign(v))
        if roles in(1,4,8):
            dlen=struct.unpack_from('<Q',wire,off+56)[0]
            if dlen:
                v=bytearray(wire);v[off+80+length]^=1;mutations.append(resign(v))
    for off in positions:
        roles=struct.unpack_from('<I',wire,off+4)[0]
        if roles in(4,8):
            v=bytearray(wire);struct.pack_into('<I',v,off+4,12);mutations.append(resign(v))
    # A self-consistent commitment does not excuse an out-of-order source list.
    first,second=positions[:2]
    third=positions[2]if len(positions)>2 else len(wire)
    v=wire[:first]+wire[second:third]+wire[first:second]+wire[third:]
    mutations.append(resign(v))
    for value in mutations:check_import(file,folder,value,tag,drive,False)
    wrongtag=bytes([tag[0]^1])+tag[1:];check_import(file,folder,wire,wrongtag,drive,False)
    check_import(file,folder,wire,tag,ord('D')if windows else 1,False)
    assert not(folder/'marker').exists()
    # The source-only wire uses a distinct magic, zero tree slot and unchanged output on error.
    legacy=a.importer.resolve().with_name('ext_validate_legacy_wire_test'+('.exe'if windows else''))
    managed=a.importer.resolve().with_name('ext_validate_wire_test'+('.exe'if windows else''))
    if legacy.exists()and managed.exists():
        source=wire[96:128];receipt=bytearray(192);receipt[:8]=b'RHLEGC1\0';struct.pack_into('<2I',receipt,8,1,192);receipt[16:80]=tag;receipt[112:144]=source
        def check_receipt(value,ok,exe=legacy):
            file.write_bytes(struct.pack('<Q',192)+value+tag+bytes(32)+source)
            out=call(exe,[native(file)],80);assert len(out)==80
            status,secondary=struct.unpack_from('<2q',out);assert secondary==0 and((status==0)if ok else(status<0)),out
            assert out[16:]==(source+bytes([0x55])*32 if ok else bytes([0x55])*64),out
        check_receipt(receipt,True);check_receipt(receipt,False,managed)
        for index in(0,8,12,16,80,111,112,144,152,160,191):
            v=bytearray(receipt);v[index]^=1;check_receipt(v,False)
        v=bytearray(receipt);v[:8]=b'RHEVAL1\0';check_receipt(v,False)
print('ok legacy transcript roundtrip, pure import after source removal, exhaustive truncation, framing/roles/hashes/argv, distinctzero-tree receipts')
