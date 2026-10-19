#!/usr/bin/env python3
"""Owned helper transport uses real reexec, bounded reads, exact completion and retirement."""
from pathlib import Path
import argparse
import os
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--wine');parser.add_argument('--wine-drive-root',type=Path);args=parser.parse_args()
    executable=ROOT/('build/windows/ext_store_job_test.exe' if args.wine or os.name=='nt' else 'build/ext_store_job_test')
    with tempfile.TemporaryDirectory(prefix='rhun-store-job-',dir=args.wine_drive_root) as folder:
        root=Path(folder).resolve()
        poison_fd=None
        if os.name=='posix' and not args.wine:
            import fcntl
            temporary_fd=os.open(root/'.poison-parent',os.O_CREAT|os.O_RDWR,0o600)
            poison_fd=fcntl.fcntl(temporary_fd,fcntl.F_DUPFD,150);os.close(temporary_fd)
        def run(mode=0,child='',expected_rows=0):
            marker=root/'.job-test-mode'
            if child:marker.write_text(child)
            else:marker.unlink(missing_ok=True)
            path=str(root)
            if args.wine:path='C:/'+root.relative_to(args.wine_drive_root.resolve()).as_posix()
            command=([args.wine] if args.wine else [])+[str(executable),path,str(mode)]
            options={}
            if os.name=='posix' and not args.wine:
                import resource
                options['preexec_fn']=lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))
                options['pass_fds']=(poison_fd,)
            result=subprocess.run(command,capture_output=True,timeout=40,**options)
            assert result.returncode==0 and not result.stderr and len(result.stdout)==32,result
            status,secondary,rows,steps=struct.unpack('<qqQQ',result.stdout)
            assert secondary==0 and rows==expected_rows and steps>0,(status,secondary,rows,steps)
            return status
        for mode in (0,5,6):assert run(mode)==0
        for mode,status in ((1,-125),(2,-110),(3,-116),(4,-125)):
            assert run(mode,'q')==status
        assert run(7)==-125
        assert run(8)==-22
        for child in ('s','x','p'):assert run(0,child)==-5
        import time
        started=time.monotonic();assert run(0,'h')==0;assert time.monotonic()-started>=1
        assert run(0,'z')==-5
        assert run(10)==0
        if args.wine or os.name=='nt':assert run(11)==0
        for child in ('m','r','g','b','l','e'):
            status=run(10,child);assert status==(-7 if child=='e' else -5),(child,status)
        header=bytearray(128);header[:8]=b'RHESTOR\0';struct.pack_into('<II',header,8,1,128)
        rows=[];owners=[]
        for number in range(4096):
            owner=('O%04d'%number).encode();row=bytearray(392);row[:len(owner)]=owner;row[104:105]=b'N';rows.append(row)
            entry=bytearray(112);entry[:len(owner)]=owner;struct.pack_into('<Q',entry,104,1);owners.append(entry)
        struct.pack_into('<IIIIQQ',header,16,4096,4096,0,0,4096,4096)
        maximum=bytes(header)+b''.join(rows)+b''.join(owners);assert len(maximum)==2064512
        wirefile=root/'.job-wire';wirefile.write_bytes(maximum);assert run(20,'w',4096)==0
        wirefile.write_bytes(maximum+b'!');assert run(20,'w')==-7
        for change in ('short','version','reserved','row'):
            bad=bytearray(maximum)
            if change=='short':bad=bad[:127]
            elif change=='version':bad[8]=2
            elif change=='reserved':bad[112]=1
            else:bad[128]=0
            wirefile.write_bytes(bad);status=run(20,'w');assert status==-5,(change,status)
        if poison_fd is not None:os.close(poison_fd)
        print('ok ext-store/job/real-reexec-owned-anchor-complete-only',flush=True)
        print('ok ext-store/job/cancel-timeout-stale-shutdown-caller-ownership',flush=True)
        print('ok ext-store/job/stderr-nonzero-extra-bytes-rejected',flush=True)
        print('ok ext-store/job/validator-wire-192-tag-source-reserved-framing',flush=True)
        print('ok ext-store/job/max-wire-overflow-malformed-eof-before-exit',flush=True)
if __name__=='__main__':main()
