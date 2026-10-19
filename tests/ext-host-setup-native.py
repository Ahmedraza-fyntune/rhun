#!/usr/bin/env python3
"""Real prepared host setup refuses START and preserves collection or quarantine ownership."""
import argparse
from pathlib import Path
import sys,tempfile
from fixture_exchange import FixtureExchange
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--exe',type=Path)
p.add_argument('--negative-controls',action='store_true')
p.add_argument('--expect-failure',action='store_true')
p.add_argument('--mode',type=int)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
p.add_argument('--build-only',type=Path)
p.add_argument('--windows-build',action='store_true')
a=p.parse_args()
if a.exe and a.mode is None:p.error('--exe requires --mode')
if a.wine and (not a.exe or not a.wine_drive_root):p.error('--wine requires --exe and --wine-drive-root')
sys.path.insert(0,str(Path(__file__).resolve().parent/'faults'))
from ext_host_setup_native_build import MODES,MUTATIONS,build
windows=a.windows_build or bool(a.wine)
if a.mode is not None and a.mode not in MODES:p.error('unsupported mode')
modes=(a.mode,)if a.mode else tuple(x for x in MODES if not windows or x not in(5,6))
drive=a.wine_drive_root.resolve()if a.wine else None
with tempfile.TemporaryDirectory(prefix='rhun-host-setup-',dir=drive)as tmp:
    variants=[(str(m),m,None)for m in modes]
    if a.negative_controls:variants.extend(('negative-'+k,m,k)for k,m in MUTATIONS.items())
    for label,mode,mutation in variants:
        folder=Path(tmp)/label
        executable=a.exe or build((a.build_only or folder/'bin')/label,mode,windows,mutation)
        if a.build_only:
            print('built',label,executable,flush=True);continue
        root=folder/'store';payload=root/'owner/name';payload.mkdir(parents=True)
        (root/'.change.lock').touch()
        lease=root/'.leases/legacy'/b'owner'.hex()/(b'name'.hex()+'.lock')
        lease.parent.mkdir(parents=True);lease.touch()
        state=folder/'state';state.mkdir()
        home=folder/'home';home.mkdir();(home/'approved').write_bytes(b'keeper')
        def argument(path):
            path=path.resolve()
            return 'C:/'+path.relative_to(drive).as_posix()if drive else str(path)
        command=([a.wine]if a.wine else[])+[str(executable.resolve()),*[argument(x)for x in(root,payload,state,home)]]
        with FixtureExchange(command,timeout=30,output_bound=0,error_bound=4096)as e:
            out,err=e.finish()
            expected=e.process.returncode!=0 if mutation or a.expect_failure else e.process.returncode==0
            assert expected and not out and not err,(label,e.process.returncode,out,err)
        print('ok real host setup',label,flush=True)
