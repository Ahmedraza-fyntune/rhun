#!/usr/bin/env python3
"""Constructor and first-admission failures preserve original suppliers and charge."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CASES={'baseline':0,'eo-allocation':1,'po-allocation':2,'base-retain':3,'input-allocation':4,'input-retain':5,'duplicate-bypass':-1,'registry-initial-eo':6,'base-initial-eo':7,'registry-initial-eo-cleared':-2,'base-initial-eo-cleared':-3}
def build(folder,windows=False,case='baseline'):
 spec=importlib.util.spec_from_file_location('catalog_admission_matrix',ROOT/'tests/catalog-limits.py')
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 fault=6 if case=='registry-initial-eo-cleared'else 7 if case=='base-initial-eo-cleared'else max(0,CASES[case]);fixture=(ROOT/'tests/catalog_admission_test.s').read_text().replace('.equ CL_FAULT, 0','.equ CL_FAULT, '+str(fault));replacements={}
 if fault:
  path,fn=('src/mem.s','mem_alloc_try')if fault in(1,2,4)else('src/app/catalogregistry.s','registry_base_retain')if fault==3 else('src/app/extprepareretirequeue.s','ext_prepare_owner_release_deferred')if fault in(6,7)else('src/app/extprepareowner.s','ext_prepare_retain')
  source=(ROOT/path).read_text();assert 'FN '+fn+'\n'in source
  replacements[path]=source.replace('FN '+fn+'\n','FN cl_actual_'+fn+'\n',1)
 if case=='duplicate-bypass':
  source=(ROOT/'src/app/catalogregistryinput.s').read_text();assert '    je .Lrga_duplicate'in source
  replacements['src/app/catalogregistryinput.s']=source.replace('    je .Lrga_duplicate','    nop',1)
 if case in('registry-initial-eo-cleared','base-initial-eo-cleared'):
  source=(ROOT/'src/app/catalogregistry.s').read_text();needle='.Lco_drop_failure:\n';assert source.count(needle)==1
  replacements['src/app/catalogregistry.s']=source.replace(needle,needle+'    mov qword ptr [r13 + r14], 0\n',1)
 return module.build(folder,windows,replacements,fixture)
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--build-only',type=Path);p.add_argument('--prebuilt',type=Path)
 p.add_argument('--windows',action='store_true');p.add_argument('--wine');p.add_argument('--case',choices=tuple(CASES))
 a=p.parse_args()
 if a.build_only and a.prebuilt:p.error('--build-only and --prebuilt are exclusive')
 windows=a.windows or bool(a.wine)or os.name=='nt';suffix='.exe'if windows else''
 with tempfile.TemporaryDirectory(prefix='rhun-catalog-admission-')as temporary:
  for case in([a.case]if a.case else CASES):
   executable=a.prebuilt/(case+suffix)if a.prebuilt else build(Path(temporary)/case,windows,case)
   if a.build_only:
    a.build_only.mkdir(parents=True,exist_ok=True);dest=a.build_only/(case+suffix)
    shutil.copyfile(executable,dest);shutil.copymode(executable,dest);continue
   with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=0,error_bound=4096)as exchange:
    out,err=exchange.finish()
    assert exchange.process.returncode==(62 if CASES[case]<0 else 0)and not out and not err,(case,exchange.process.returncode,out,err)
   print('ok catalog admission '+case,flush=True)
if __name__=='__main__':main()
