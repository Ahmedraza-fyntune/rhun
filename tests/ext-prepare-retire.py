#!/usr/bin/env python3
"""Bounded preparation retirement, shared accounting and explicit native failure ownership."""
import argparse
import importlib.util
import os
from pathlib import Path
import tempfile
from fixture_exchange import FixtureExchange

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--dir',type=Path,required=True)
p.add_argument('--fault-exe',type=Path)
p.add_argument('--wine')
p.add_argument('--wine-drive-root',type=Path)
a=p.parse_args()
if a.wine and a.wine_drive_root is None:p.error('--wine-drive-root is required with --wine')
if a.wine_drive_root is not None:a.wine_drive_root=a.wine_drive_root.resolve()
root=Path(__file__).resolve().parent.parent
windows=bool(a.wine)or os.name=='nt'
suffix='.exe'if windows else''
runner=[a.wine]if a.wine else[]

def check(exe,args=()):
    with FixtureExchange([*runner,str(exe.resolve()),*args],timeout=30,output_bound=0,error_bound=4096)as e:
        out,err=e.finish()
        assert e.process.returncode==0 and not out and not err,(exe,args,e.process.returncode,out,err)

for name in ('ext_prepare_owner_test','ext_prepare_retire_test','ext_prepare_custom_retire_test','ext_prepare_private_settings_test','ext_prepare_retire_cap_test','ext_prepare_retire_graph_test'):
    check(a.dir/(name+suffix))
print('ok work budgets, FIFO shared owners, ref overflow, typed callbacks, immutable settings and rounded global cap',flush=True)
with tempfile.TemporaryDirectory(prefix='rhun-retire-fault-',dir=a.wine_drive_root)as tmp:
    if a.fault_exe:exe=a.fault_exe
    else:
        spec=importlib.util.spec_from_file_location('retire_fault_link',root/'tests/faults/ext_retire_build.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        exe=module.build(Path(tmp),windows)
    for mode in range(1,7):check(exe,(str(mode),))
    native_tmp='C:/'+Path(tmp).relative_to(a.wine_drive_root).as_posix()if a.wine else str(Path(tmp).resolve())
    check(exe,('7',native_tmp))
print('ok consumed/known/unknown close results, no unknown retry, failed AO/self unmap preservation and orphan parser cleanup and owned-slot classification failure',flush=True)
