#!/usr/bin/env python3
"""Early snapshot helper emits only complete relocation-free tagged wire."""
import os
from pathlib import Path
import struct
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def main():
    if os.name!='posix':return
    executable=ROOT/'build/ext_store_cli_test'
    with tempfile.TemporaryDirectory(prefix='rhun-store-cli-') as name:
        root=Path(name).resolve();raw=os.open(root,os.O_RDONLY|os.O_DIRECTORY)
        try:
            nonce=bytes(range(16));args=[str(executable),'--extension-store-snapshot',str(raw),'7','9',nonce.hex()]
            def run(arguments,success):
                result=subprocess.run(arguments,capture_output=True,pass_fds=(raw,),timeout=10)
                assert result.returncode==(0 if success else 1) and not result.stderr,result
                if success:
                    wire=result.stdout;assert len(wire)==128 and wire[:8]==b'RHESTOR\0'
                    assert struct.unpack_from('<QQ',wire,48)==(7,9) and wire[64:80]==nonce
                    st=os.fstat(raw);assert struct.unpack_from('<QQ',wire,80)==(st.st_dev,st.st_ino)
                else:assert not result.stdout,result.stdout
            run(args,True)
            borrowed=subprocess.run([str(executable),'--emit-borrowed',str(raw)],capture_output=True,pass_fds=(raw,),timeout=10)
            assert borrowed.returncode==0 and not borrowed.stderr and len(borrowed.stdout)==128,borrowed
            os.fstat(raw)
            for position,value in ((2,'-1'),(2,'18446744073709551616'),(3,'0'),(3,'18446744073709551616'),(4,'0'),(4,'18446744073709551616'),(5,nonce.hex().upper()),(5,'00'*15),(5,'gg'*16)):
                changed=args.copy();changed[position]=value;run(changed,False)
            run(args[:-1],False)
            (root/'.installed').mkdir();(root/'.installed'/'corrupt').mkdir();run(args,False)
        finally:os.close(raw)
    # Child-owned inherited copy close must precede successful output.
    import importlib.util
    spec=importlib.util.spec_from_file_location('builder',ROOT/'tests/faults/ext_store_build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    adapter=(ROOT/'src/app/extvalidatepath.s').read_text().replace('FN ext_root_close\n','FN cli_real_close\n')
    fixture=(ROOT/'tests/ext_store_cli_test.s').read_text()+'\nFN ext_root_close\n    PROLOGUE\n    call cli_real_close\n    mov rax, -5\n    EPILOGUE\n'
    with tempfile.TemporaryDirectory(prefix='rhun-store-cli-close-') as name:
        folder=Path(name).resolve();executable=module.build(folder/'build',fixture,{'src/app/extvalidatepath.s':adapter})
        raw=os.open(folder,os.O_RDONLY|os.O_DIRECTORY)
        try:
            result=subprocess.run([str(executable),'--extension-store-snapshot',str(raw),'7','9',bytes(range(16)).hex()],capture_output=True,pass_fds=(raw,),timeout=10)
            assert result.returncode==1 and not result.stdout and not result.stderr,result
            os.fstat(raw)
        finally:os.close(raw)
    print('ok ext-store/cli/tag-framing-complete-only-strict-arguments',flush=True)
if __name__=='__main__':main()
