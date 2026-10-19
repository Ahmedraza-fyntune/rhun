#!/usr/bin/env python3
"""Bounded real radix baseline and independent structural/accounting controls."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CASES={
 'baseline':(None,None,0),
 'lost-prefix-terminal':('    mov [rdx + RM_value], rcx\n    mov rcx, [rbx + RM_old_byte]','    mov qword ptr [rdx + RM_value], 0\n    mov rcx, [rbx + RM_old_byte]',41),
 'held-byte-loss':('    mov r9, [rbx + RM_held]','    xor r9d, r9d',41),
 'missing-prefix-shorten':('    mov [r14 + RM_edgelen], r12','    nop',41),
 'missing-split-capacity':('    cmp rax, [rbx + RM_capacity]\n    ja .Lrm_resource','    nop\n    nop',46),
 'wrong-duplicate-result':('    mov qword ptr [rbx + RM_existing], 1','    mov qword ptr [rbx + RM_existing], 0',41),
 'oversized-unit':('    cmp r14, 4096\n    jbe 2f\n    mov r14d, 4096','    cmp r14, 65536\n    jbe 2f\n    mov r14d, 65536',45),
 'uncharged-edge-byte':('    add [rbx + RM_bytes], r15','    nop',45),
}
def build(folder,windows=False,case='baseline'):
 spec=importlib.util.spec_from_file_location('catalog_map_matrix',ROOT/'tests/catalog-map.py')
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 old,new,_=CASES[case];replacements={}
 if old is not None:
  source=(ROOT/'src/app/catalogregistrymap.s').read_text()
  assert old in source,case
  replacements['src/app/catalogregistrymap.s']=source.replace(old,new,1)
 return module.build(folder,windows=windows,replacements=replacements)
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--build-only',type=Path);p.add_argument('--prebuilt',type=Path)
 p.add_argument('--windows',action='store_true');p.add_argument('--wine')
 p.add_argument('--case',choices=tuple(CASES))
 a=p.parse_args()
 if a.build_only and a.prebuilt:p.error('--build-only and --prebuilt are exclusive')
 windows=a.windows or bool(a.wine)or os.name=='nt';suffix='.exe'if windows else''
 with tempfile.TemporaryDirectory(prefix='rhun-catalog-map-faults-')as temporary:
  for case in([a.case]if a.case else CASES):
   executable=a.prebuilt/(case+suffix)if a.prebuilt else build(Path(temporary)/case,windows,case)
   if a.build_only:
    a.build_only.mkdir(parents=True,exist_ok=True);dest=a.build_only/(case+suffix)
    shutil.copyfile(executable,dest);shutil.copymode(executable,dest);continue
   with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=0,error_bound=4096)as exchange:
    out,err=exchange.finish()
    assert exchange.process.returncode==CASES[case][2] and not out and not err,(case,exchange.process.returncode,out,err)
   print('ok catalog radix '+case,flush=True)
if __name__=='__main__':main()
