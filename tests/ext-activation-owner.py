#!/usr/bin/env python3
"""Bounded native activation-owner and host-lifetime checks."""
import argparse
import importlib.util
import os
from pathlib import Path
import tempfile
from fixture_exchange import FixtureExchange

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--dir',type=Path,required=True)
p.add_argument('--fault-exe',type=Path)
p.add_argument('--lifecycle-exe',type=Path)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
a=p.parse_args()
if a.wine and a.wine_drive_root is None:p.error('--wine-drive-root is required with --wine')
drive=a.wine_drive_root.resolve()if a.wine_drive_root else None
windows=bool(a.wine)or os.name=='nt'
with tempfile.TemporaryDirectory(prefix='rhun-activation-',dir=drive)as tmp:
    native='C:/'+Path(tmp).relative_to(drive).as_posix()if a.wine else str(Path(tmp).resolve())
    exe=(a.dir/('ext_activation_owner_test'+('.exe'if windows else''))).resolve()
    def check(executable,extra=()):
        command=([a.wine]if a.wine else[])+[str(executable.resolve()),native,*extra]
        with FixtureExchange(command,timeout=30,output_bound=0,error_bound=4096)as e:
            out,err=e.finish()
            assert e.process.returncode==0 and not out and not err,(executable,extra,e.process.returncode,out,err)
    check(exe)
    if a.fault_exe:fault=a.fault_exe
    else:
        root=Path(__file__).resolve().parents[1]
        spec=importlib.util.spec_from_file_location('activation_fault_build',root/'tests/faults/ext_activation_build.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        fault=module.build(Path(tmp)/'fault',windows)
    for mode in range(1,7):check(fault,(str(mode),))
    root=Path(tmp)/'keeper-store'
    payload=root/'owner/name'
    payload.mkdir(parents=True)
    (root/'.change.lock').touch()
    lease=root/'.leases/legacy'/b'owner'.hex()/(b'name'.hex()+'.lock')
    lease.parent.mkdir(parents=True);lease.touch()
    state=Path(tmp)/'state';state.mkdir()
    home=Path(tmp)/'home';home.mkdir();(home/'approved').write_bytes(b'keeper')
    def argument(path):
        path=path.resolve()
        return 'C:/'+path.relative_to(drive).as_posix()if a.wine else str(path)
    lifecycle=(a.lifecycle_exe or a.dir/('extension_lifecycle_test'+('.exe'if windows else''))).resolve()
    command=([a.wine]if a.wine else[])+[str(lifecycle),*[argument(x)for x in(root,payload,state,home)]]
    with FixtureExchange(command,timeout=120,output_bound=128,error_bound=4096)as e:
        out,err=e.finish()
        assert e.process.returncode==0 and out+err==b'ok supervised extension lifecycle\n',(e.process.returncode,out,err)
print('ok managed/legacy activation evidence, exact launch borrows, stopped metadata lifetime six allocation/no-IO/supplier faults and real keeper collection',flush=True)
