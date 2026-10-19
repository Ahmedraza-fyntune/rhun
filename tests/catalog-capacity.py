#!/usr/bin/env python3
"""Real near-cap owner/global ledgers refuse qualification before helper entry."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import tempfile
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CASES={'owner':(1,0),'owner-bypass':(1,42),'global':(2,0),'global-bypass':(2,42)}
def build(folder,windows=False,case='owner'):
 spec=importlib.util.spec_from_file_location('catalog_capacity_matrix',ROOT/'tests/catalog-limits.py')
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 mode,_=CASES[case];fixture=(ROOT/'tests/catalog_capacity_test.s').read_text().replace('.equ CAP_MODE, 1','.equ CAP_MODE, '+str(mode)).replace('.equ CAP_INSTRUMENTED, 0','.equ CAP_INSTRUMENTED, 1')
 source=(ROOT/'src/app/themecapturestartup.s').read_text();needle='FN theme_capture_path_snapshot\n';assert source.count(needle)==1
 replacements={'src/app/themecapturestartup.s':source.replace(needle,'FN cap_actual_theme_capture_path_snapshot\n',1)}
 if case.endswith('bypass'):
  source=(ROOT/'src/app/catalogregistrybase.s').read_text()
  needle='    cmp rax, [r13 + EO_cap]\n    ja .Lrbq_resource'if mode==1 else'    call prep_global_admit\n    test rax, rax\n    js .Lrbq_fail'
  assert source.count(needle)==1
  replacements['src/app/catalogregistrybase.s']=source.replace(needle,needle.replace('    ja .Lrbq_resource','    nop')if mode==1 else'    xor eax, eax',1)
 return module.build(folder,windows,replacements,fixture)
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--build-only',type=Path);p.add_argument('--prebuilt',type=Path)
 p.add_argument('--windows',action='store_true');p.add_argument('--wine');p.add_argument('--case',choices=tuple(CASES))
 a=p.parse_args()
 if a.build_only and a.prebuilt:p.error('--build-only and --prebuilt are exclusive')
 windows=a.windows or bool(a.wine)or os.name=='nt';suffix='.exe'if windows else''
 with tempfile.TemporaryDirectory(prefix='rhun-catalog-capacity-')as temporary:
  for case in([a.case]if a.case else CASES):
   executable=a.prebuilt/(case+suffix)if a.prebuilt else build(Path(temporary)/case,windows,case)
   if a.build_only:
    a.build_only.mkdir(parents=True,exist_ok=True);dest=a.build_only/(case+suffix)
    shutil.copyfile(executable,dest);shutil.copymode(executable,dest);continue
   with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=4104,error_bound=4096)as exchange:
    out,err=exchange.finish()
    assert exchange.process.returncode==CASES[case][1]and not err,(case,exchange.process.returncode,out,err)
    if CASES[case][1]==0:
     assert len(out)>=8 and struct.unpack_from('<Q',out)[0]==len(out)-8,(case,out)
     expected=(('Z:'if a.wine else'')+os.getcwd()+'/themes/relative.theme').encode()
     assert out[8:].replace(b'\\',b'/')==expected.replace(b'\\',b'/'),(case,out,expected)
    else:assert not out,(case,out)
   print('ok catalog capacity '+case,flush=True)
if __name__=='__main__':main()
