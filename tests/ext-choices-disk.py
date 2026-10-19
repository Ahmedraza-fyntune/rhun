#!/usr/bin/env python3
"""Native locked extension-settings reads, publication, ownership and fault gates."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import queue
import struct
import subprocess
import sys
import tempfile
import threading
import time

ROOT=Path(__file__).resolve().parents[1]
class FixtureExchange:
    """Bound the entire pipe exchange, including reads, then retire and reap the child."""
    def __init__(self, command, timeout=15):
        self.process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.deadline=time.monotonic()+timeout
        self.events=queue.Queue(maxsize=64)
        self.buffer=bytearray()
        self.errors=bytearray()
        self.failures=[]
        self.eof=False
        self.stop=threading.Event()
        self.readers=[]
        for stream, output in ((self.process.stdout,True),(self.process.stderr,False)):
            thread=threading.Thread(target=self._pump,args=(stream,output),daemon=True)
            thread.start();self.readers.append(thread)

    def _push(self, item):
        while not self.stop.is_set():
            try:self.events.put(item,timeout=0.1);return
            except queue.Full:pass

    def _pump(self, stream, output):
        size=0
        try:
            while not self.stop.is_set():
                chunk=os.read(stream.fileno(),65536)
                if not chunk:break
                size+=len(chunk)
                if size>(2*1048576 if output else 65536):
                    raise AssertionError('native fixture exceeded output bound')
                if output:self._push(chunk)
                else:self.errors.extend(chunk)
        except BaseException as error:
            self.failures.append(error)
            self._push(error)
        finally:
            if output:self._push(None)

    def _remaining(self):
        left=self.deadline-time.monotonic()
        if left<=0:raise TimeoutError('native fixture exchange timed out')
        return left

    def _next(self):
        try:item=self.events.get(timeout=self._remaining())
        except queue.Empty:raise TimeoutError('native fixture exchange timed out') from None
        if isinstance(item,BaseException):raise item
        if item is None:self.eof=True
        else:self.buffer.extend(item)

    def read(self, length):
        assert 0<=length<=1048576+256,length
        while len(self.buffer)<length:
            if self.eof:raise AssertionError(('early fixture EOF',length,len(self.buffer),self.process.poll(),bytes(self.errors)))
            self._next()
        result=bytes(self.buffer[:length]);del self.buffer[:length]
        return result

    def send(self, byte):
        assert len(byte)==1
        self._remaining()
        self.process.stdin.write(byte);self.process.stdin.flush()

    def finish(self):
        self.process.stdin.close()
        while not self.eof:self._next()
        self.process.wait(timeout=self._remaining())
        for reader in self.readers:
            reader.join(timeout=self._remaining())
            if reader.is_alive():raise TimeoutError('native fixture output did not close')
        if self.failures:raise self.failures[0]
        return bytes(self.buffer),bytes(self.errors)

    def __enter__(self):return self

    def __exit__(self, kind, value, traceback):
        try:
            if self.process.poll() is None:self.process.kill()
            self.process.wait(timeout=5)
        finally:
            self.stop.set()
            for reader in self.readers:reader.join(timeout=0.5)
            for stream in (self.process.stdin,self.process.stdout,self.process.stderr):stream.close()


def guard_tests(guard_exe, args):
    EXE=guard_exe.resolve()
    WINE=args.wine
    DRIVE=args.wine_drive_root if WINE else None
    WINDOWS=bool(WINE) or os.name=='nt'
    def native(path):
     if not WINE:return str(path)
     return 'C:/'+str(Path(path).relative_to(DRIVE)).replace(os.sep,'/')
    def command(root,exclusive,create,hold,fault=None):
     args=[native(root),str(exclusive),str(create),str(hold)]
     if fault is not None:args+=[str(fault)]
     return [WINE,'Z:'+EXE.as_posix(),*args] if WINE else [str(EXE),*args]
    
    def call(root, exclusive=1, create=1, error=0, content=None, exists=None, fault=0, cleanup=0, guard_cleanup=0):
     p=subprocess.run(command(root,exclusive,create,0,fault),capture_output=True,timeout=15)
     assert p.returncode==0 and len(p.stdout)>=64,(p.returncode,p.stdout,p.stderr)
     status,secondary,found,length=struct.unpack_from('<qqQQ',p.stdout)
     assert (status<0 if error=='negative' else status==error) and secondary==cleanup,(status,secondary,error)
     if status==0:
      assert length==len(p.stdout)-64-24
      body=p.stdout[64:64+length]
      assert p.stdout[32:64]==hashlib.sha256(body).digest()
      if content is not None:assert body==content
      if exists is not None:assert found==exists
     assert len(p.stdout)==64+length+24
     gerror,allocations,opens=struct.unpack_from('<qQQ',p.stdout,64+length)
     assert gerror==guard_cleanup,(gerror,guard_cleanup)
     if fault in (601,602):assert opens==fault-600,(fault,opens)
     return p.stdout
    
    def ready(holder):
     header=holder.read(64)
     length=struct.unpack_from('<Q',header,24)[0]
     assert length<=1048576
     body=holder.read(length)
     assert struct.unpack_from('<q',header)[0]==0 and body==b'x=yes',(header,body)

    with tempfile.TemporaryDirectory(prefix='rhun-choices-guard-',dir=DRIVE) as tmp:
     r=Path(tmp).resolve()
     call(r,create=0,error=-2)
     call(r,content=b'',exists=0)
     assert (r/'extensions.lock').is_file()
     call(r,exclusive=0,create=0,content=b'',exists=0)
     f=r/'extensions.ini';f.write_bytes(b'')
     call(r,content=b'',exists=1)
     for data in (b'[owner/tool]\npinned=yes\n',b'; untouched\r\n[removed/tool]\nsetting.x=old\n[providers]\ncomplete.py=other/tool\n'):
      f.write_bytes(data);call(r,content=data,exists=1)
     for bad in (b'bad line',b'x=\x00',b'x=\xc0\xaf'):
      f.write_bytes(bad);call(r,error=-22)
     f.write_bytes(b'#'+b'x'*1048575);call(r,content=f.read_bytes())
     f.write_bytes(b'#'+b'x'*1048576);call(r,error=-27)
     f.unlink();f.mkdir();call(r,error='negative');f.rmdir()
     if not WINDOWS:
      os.mkfifo(f);call(r,error=-22);f.unlink()
     outside=r/'outside';outside.write_bytes(b'x=yes')
     if not WINDOWS:
      f.symlink_to(outside);call(r,error=-40);f.unlink()
     f.write_bytes(b'x=yes')
     (r/'extensions.lock').chmod(0o444)
     call(r,create=0,content=b'x=yes')
     # A live holder excludes another process and permits independent shared readers.
     with FixtureExchange(command(r,1,0,1)) as holder:
      ready(holder)
      call(r,create=0,error=-11)
      call(r,exclusive=0,create=0,error=-11)
      holder.send(b'x')
      out,err=holder.finish()
      assert holder.process.returncode==0 and len(out)==24,(out,err)
     with FixtureExchange(command(r,0,0,1)) as holder:
      ready(holder)
      call(r,exclusive=0,create=0,content=b'x=yes')
      call(r,create=0,error=-11)
      holder.send(b'x')
      out,err=holder.finish()
      assert holder.process.returncode==0 and len(out)==24,(out,err)
     with FixtureExchange(command(r,1,0,1)) as holder:
      ready(holder)
      holder.process.kill()
      holder.finish()
     call(r,create=0,content=b'x=yes')
     for fault in (1,2,3):call(r,fault=fault,error=-12)
     call(r,fault=101,error=-9)
     call(r,fault=201,error=-5)
     call(r,fault=202,error=-11)
     call(r,fault=301,error=-5,cleanup=-9)
     call(r,fault=401,error=-5,cleanup=-9)
     call(r,fault=501,error=-5,cleanup=-9)
     call(r,fault=601,error=-2,cleanup=-9)
     call(r,fault=602,error=-17,cleanup=-9)
     call(r,exclusive=0,create=1,error=-22)
     call(r,exclusive=2,error=-22)
     print('ok native settings guards/snapshots, exact digest, missing/empty, limits, lock lifetime and contention')

def commit_tests(disk_exe, args):
    EXE=disk_exe.resolve()
    WINE=args.wine
    DRIVE=args.wine_drive_root if WINE else None
    def command(root,key,value,mode,fault):
     path='C:/'+str(root.relative_to(DRIVE)).replace(os.sep,'/') if WINE else str(root)
     return ([WINE,'Z:'+EXE.as_posix(),path,key,value,mode,str(fault),'wine'] if WINE else [str(EXE),path,key,value,mode,str(fault)])
    def call(root,key='pinned',value='yes',mode='commit',error=0,expected=None,noop=None,mutate=None,cleanup_error=0,fault=0,native_mutate=None,preserve=False,diagnostic=0):
     with FixtureExchange(command(root,key,value,mode,fault)) as exchange:
      p=exchange.process
      header=exchange.read(160)
      status,secondary,old_exists,old_len,new_len,was_noop=struct.unpack_from('<qqQQQQ',header)
      assert status==0 and secondary==0,(status,secondary)
      body=exchange.read(new_len)
      if expected is not None:assert body==expected,(body,expected)
      if noop is not None:assert was_noop==noop,(was_noop,noop)
      name=header[80:160].split(b'\0')[0].decode()
      if mode=='hold':
       if mutate:mutate(root,name)
       exchange.send(b'!')
      if fault==3:
       assert exchange.read(1)==b'!'
       assert native_mutate
       native_mutate(root,name,body)
       exchange.send(b'!')
      result=struct.unpack('<9q',exchange.read(72))
      assert result[0]==error and result[1]==diagnostic,(result,error,diagnostic)
      assert result[8]==(1 if (fault and fault not in (901,902)) or (error==0 and not was_noop) else 0),result
      trailer=struct.unpack('<3q',exchange.read(24));assert trailer==(cleanup_error,cleanup_error,0),trailer
      tail,err=exchange.finish();assert p.returncode==0 and not tail,(p.returncode,tail,err)
      if not preserve and cleanup_error==0:assert not list(root.glob('.extensions-*.pending'))
      return body,result
    with tempfile.TemporaryDirectory(prefix='rhun-choices-commit-',dir=DRIVE) as tmp:
     r=Path(tmp).resolve();f=r/'extensions.ini'
     body,result=call(r,expected=b'[owner/tool]\npinned=yes\n',noop=0)
     assert result[2:4]==(3,1),result
     assert f.read_bytes()==body
     if not WINE and os.name!='nt':assert f.stat().st_mode&0o777==0o600
     original=b'; keep\n[removed/tool]\nsetting.x=old\n[owner/tool]\npinned=no\n[providers]\ncomplete.py=other/tool\n'
     f.write_bytes(original)
     body,result=call(r,expected=original.replace(b'pinned=no\n',b'pinned=yes\n'),noop=0)
     assert f.read_bytes()==body
     body,result=call(r,key='missing',value='',expected=body.replace(b'[owner/tool]\n',b'[owner/tool]\nmissing=\n'))
     body,result=call(r,key='absent',value='',mode='delete',expected=f.read_bytes(),noop=1)
     assert result[2:4]==(3,0),result
     # Cancellation arriving during final/stage reads must be checked before native issue.
     for late in (901,902):
      f.write_bytes(b'[owner/tool]\npinned=no\n')
      old=f.read_bytes()
      body,result=call(r,fault=late,value='late-cancel',error=-125)
      assert result[2]==4 and result[8]==0 and f.read_bytes()==old,result
     f.write_bytes(b'[owner/tool]\npinned=no\n')
     old=f.read_bytes()
     body,result=call(r,fault=901,value='no',error=-125,noop=1)
     assert result[2]==4 and result[8]==0 and f.read_bytes()==old,result
     old=f.read_bytes();call(r,mode='x',error=-125);assert f.read_bytes()==old
     call(r,mode='invalid',error=-22);assert f.read_bytes()==old
     def change_final(root,name): (root/'extensions.ini').write_bytes(b'[other/tool]\nkeep=external\n')
     body,result=call(r,mode='hold',error=-11,mutate=change_final)
     assert f.read_bytes()==b'[other/tool]\nkeep=external\n'
     def change_stage(root,name):
      path=root/name;b=path.read_bytes();path.write_bytes(bytes([b[0]^1])+b[1:])
     old=f.read_bytes();call(r,mode='hold',error=-116,mutate=change_stage);assert f.read_bytes()==old
     def replace_stage(root,name):
      path=root/name;path.unlink();path.write_bytes(b'foreign')
     body,result=call(r,mode='hold',error=-116,mutate=replace_stage,cleanup_error=-116)
     foreign=list(r.glob('.extensions-*.pending'));assert len(foreign)==1 and foreign[0].read_bytes()==b'foreign';foreign[0].unlink()
     old=f.read_bytes();body,result=call(r,fault=1,value='before-error',error=-5);assert f.read_bytes()==old and result[2]==4,result
     body,result=call(r,fault=2,value='after-error');assert f.read_bytes()==body and result[2:5]==(3,1,-5),result
     def exact_new(root,name,body):(root/'extensions.ini').write_bytes(body)
     body,result=call(r,fault=3,value='independent-new',native_mutate=exact_new);assert f.read_bytes()==body and result[2:5]==(3,0,-5),result
     def different_final(root,name,body):(root/'extensions.ini').write_bytes(b'[foreign/tool]\nnew=other\n')
     body,result=call(r,fault=3,value='uncertain',native_mutate=different_final,error=-117,preserve=True)
     assert result[2:6]==(5,0,-5,1),result
     assert f.read_bytes()==b'[foreign/tool]\nnew=other\n'
     for path in r.glob('.extensions-*.pending'):path.unlink()
     old=f.read_bytes();body,result=call(r,fault=5,value='observation',error=-117,preserve=True,diagnostic=-13,cleanup_error=-13)
     assert f.read_bytes()==old and result[2:6]==(5,0,-5,1) and result[7]==-13,result
     for path in r.glob('.extensions-*.pending'):path.unlink()
     if WINE or os.name=='nt':
      for fault in (4,711):
       body,result=call(r,fault=fault,value='pending'+str(fault));assert f.read_bytes()==body and result[2:4]==(3,1) and result[6]==-5,result
     before=f.read_bytes()
     timed_out=False
     with FixtureExchange(command(r,'pinned','deadline','hold',0)) as exchange:
      header=exchange.read(160)
      status,secondary,exists,old_len,new_len,noop=struct.unpack_from('<qqQQQQ',header)
      assert (status,secondary,exists,noop)==(0,0,1,0) and new_len>0
      body=exchange.read(new_len)
      stage=r/header[80:160].split(b'\0')[0].decode()
      assert stage.is_file() and stage.read_bytes()==body and f.read_bytes()==before
      exchange.deadline=time.monotonic()+0.25
      try:exchange.read(72) # only this intentionally blocked read may time out.
      except TimeoutError:timed_out=True
     assert timed_out and exchange is not None and exchange.process.poll() is not None
     assert f.read_bytes()==before
     for path in r.glob('.extensions-*.pending'):path.unlink()
     # Foreign replacement is preserved by cleanup, never treated as the owned stage.
     print('ok private settings commit, exact old/stage rechecks, callback refusal, terminal idempotence, stale source identity')

def prepare_fault_tests(disk_exe, args):
    EXE=disk_exe.resolve()
    WINE=args.wine
    DRIVE=args.wine_drive_root if WINE else None
    def call(root,fault,prepare_error=0,cleanup_error=0,preserve=False,commit_error=0,prepare_secondary=0):
     path='C:/'+str(root.relative_to(DRIVE)).replace(os.sep,'/') if WINE else str(root)
     command=([WINE,'Z:'+EXE.as_posix()] if WINE else [str(EXE)])+[path,'pinned','yes','commit',str(fault)]+(['wine'] if WINE else [])
     p=subprocess.run(command,capture_output=True,timeout=20)
     assert p.returncode==0 and len(p.stdout)>=184,(fault,p.returncode,p.stdout,p.stderr)
     header=p.stdout[:160];status,secondary,oldexists,oldlen,newlen,noop=struct.unpack_from('<qqQQQQ',header)
     assert status==prepare_error and secondary==prepare_secondary,(fault,status,secondary,prepare_error,prepare_secondary)
     count=256+newlen if len(p.stdout)>184+newlen else 184+newlen
     assert len(p.stdout)==count,(fault,len(p.stdout),count)
     if count==256+newlen:
      result=struct.unpack_from('<9q',p.stdout,160+newlen)
      assert result[0]==(prepare_error or commit_error),(fault,result)
      assert result[8]==(0 if prepare_error else 1),(fault,result)
     trailer=struct.unpack_from('<3q',p.stdout,len(p.stdout)-24)
     assert trailer==(cleanup_error,cleanup_error,0),(fault,trailer)
     pending=list(root.glob('.extensions-*.pending'))
     assert bool(pending)==preserve,(fault,pending)
     for file in pending:file.unlink()
     return p.stdout[160:160+newlen]
    with tempfile.TemporaryDirectory(prefix='rhun-settings-prepare-faults-',dir=DRIVE) as tmp:
     root=Path(tmp).resolve(); final=root/'extensions.ini';old=b'; retained\n[owner/tool]\npinned=no\n'
     for fault in range(101,107):
      final.write_bytes(old);call(root,fault,prepare_error=-12);assert final.read_bytes()==old
     for fault in (201,202,203,205,207):
      final.write_bytes(old);call(root,fault,prepare_error=-5);assert final.read_bytes()==old
     final.write_bytes(old);call(root,208,prepare_error=-17);assert final.read_bytes()==old
     for fault in (209,210):
      final.write_bytes(old);call(root,fault,prepare_error=-5,cleanup_error=-116,preserve=True);assert final.read_bytes()==old
     for fault in (204,206):
      final.write_bytes(old);new=call(root,fault);assert final.read_bytes()==new
     final.write_bytes(old);new=call(root,211,cleanup_error=-9);assert final.read_bytes()==new
     if WINE or os.name=='nt':
      for fault in (702,703,704,705):
       final.write_bytes(old);call(root,fault,prepare_error=-13);assert final.read_bytes()==old
      final.write_bytes(old);new=call(root,701,cleanup_error=-13);assert final.read_bytes()==new
      final.write_bytes(old);new=call(root,706,cleanup_error=-9);assert final.read_bytes()==new
      for fault in (707,712):
       final.write_bytes(old);call(root,fault,prepare_error=-5);assert final.read_bytes()==old
      final.write_bytes(old);call(root,708,prepare_error=-5,cleanup_error=-13,preserve=True);assert final.read_bytes()==old
      final.write_bytes(old);call(root,709,prepare_error=-5,cleanup_error=-9);assert final.read_bytes()==old
     final.write_bytes(old);call(root,710,prepare_error=-5,prepare_secondary=-9,cleanup_error=-9);assert final.read_bytes()==old
     print('ok settings all six native buffer allocation failures, write/zero/partial/EINTR/sync/create/collision/classification/close faults')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wine')
    parser.add_argument('--wine-drive-root',type=Path)
    parser.add_argument('--windows-build',action='store_true')
    parser.add_argument('--build-only',type=Path)
    parser.add_argument('--prepared-dir',type=Path)
    args=parser.parse_args()
    if args.wine:
        if args.wine_drive_root is None:
            parser.error('--wine-drive-root is required with --wine')
        args.wine_drive_root=args.wine_drive_root.resolve()
    platform='windows' if args.windows_build or args.wine or os.name=='nt' else 'macos' if sys.platform=='darwin' else 'linux'
    spec=importlib.util.spec_from_file_location('choices_disk_build',ROOT/'tests/faults/ext_choices_disk_build.py')
    builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
    if args.build_only:
        args.build_only.mkdir(parents=True,exist_ok=True)
        builder.build(platform,args.build_only.resolve(),'guard')
        builder.build(platform,args.build_only.resolve(),'disk')
        return
    with tempfile.TemporaryDirectory(prefix='rhun-choices-disk-build-') as temporary:
        if args.prepared_dir:
            folder=args.prepared_dir.resolve()
            suffix='.exe' if platform=='windows' else '-'+platform
            guard_exe=folder/'guard'/('guard-test'+suffix)
            disk_exe=folder/'disk'/('disk-test'+suffix)
            assert guard_exe.is_file() and disk_exe.is_file(), 'missing prebuilt native fixtures'
        else:
            folder=Path(temporary)
            guard_exe=builder.build(platform,folder,'guard')
            disk_exe=builder.build(platform,folder,'disk')
        guard_tests(guard_exe,args)
        commit_tests(disk_exe,args)
        prepare_fault_tests(disk_exe,args)
    if args.wine:
        print('note Wine ACL round-trip requires restrictive subset; exact protected ACL and cross-account denial require real Windows')

if __name__=='__main__':
    main()
