#!/usr/bin/env python3
"""Fixed worker input, owned copies, collection, cancellation and native handle balance."""
import argparse
import os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--wine');args=parser.parse_args()
    windows=bool(args.wine) or os.name=='nt'
    exe=ROOT/('build/windows/ext_settings_native_test.exe' if windows else 'build/ext_settings_native_test')
    foreign=None
    if not windows:
        foreign=os.open(__file__,os.O_RDONLY);os.dup2(foreign,150,inheritable=True);os.close(foreign)
    try:
        for mode in [0,1,2]:
            options={}
            if not windows:
                import resource
                options={'pass_fds':(150,),'preexec_fn':lambda:resource.setrlimit(resource.RLIMIT_NOFILE,(32,32))}
            result=subprocess.run(([args.wine] if args.wine else [])+[str(exe),str(mode)],capture_output=True,timeout=20,**options)
            assert result.returncode==0 and not result.stdout and not result.stderr,(mode,result)
            print('ok ext-settings-native/'+['copy-nonblocking-progress','EOF-before-collected-exit','cancel-pending-input'][mode],flush=True)
    finally:
        if not windows:os.close(150)
if __name__=='__main__':main()
