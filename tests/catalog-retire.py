#!/usr/bin/env python3
"""Actual LARGE registry scratch free preserves header, ledger and charge on refusal."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CASES={'baseline':0,'destroyed-header':62,'missing-live-restore':62}
def build(folder,windows=False,case='baseline'):
 spec=importlib.util.spec_from_file_location('catalog_retire_matrix',ROOT/'tests/catalog-limits.py')
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 fixture=(ROOT/'tests/catalog_retire_test.s').read_text();mem=(ROOT/'src/mem.s').read_text();needle='.Lmf_large:\n';assert mem.count(needle)==1
 native=''' .Lmf_large:
    inc qword ptr [rip + cl_unmap_calls]
    cmp qword ptr [rip + cl_fail_unmap], 0
    je 8f
    mov qword ptr [rip + cl_fail_unmap], 0
    mov [rip + cl_failed_header], rax
    mov [rip + cl_failed_size], rcx
    mov rdx, [rax + 8]
    mov [rip + cl_failed_request], rdx
'''
 if case=='destroyed-header':native+='    mov qword ptr [rax], 0\n'
 native+='    mov rax, -5\n    ret\n8:\n'
 replacements={'src/mem.s':mem.replace(needle,native,1)}
 if case=='missing-live-restore':
  source=(ROOT/'src/app/extprepareretirealloc.s').read_text();needle='    inc qword ptr [rip + g_mem_live]';assert source.count(needle)==1
  replacements['src/app/extprepareretirealloc.s']=source.replace(needle,'    nop',1)
 return module.build(folder,windows,replacements,fixture)
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--build-only',type=Path);p.add_argument('--prebuilt',type=Path)
 p.add_argument('--windows',action='store_true');p.add_argument('--wine');p.add_argument('--case',choices=tuple(CASES))
 a=p.parse_args()
 if a.build_only and a.prebuilt:p.error('--build-only and --prebuilt are exclusive')
 windows=a.windows or bool(a.wine)or os.name=='nt';suffix='.exe'if windows else''
 with tempfile.TemporaryDirectory(prefix='rhun-catalog-retire-')as temporary:
  for case in([a.case]if a.case else CASES):
   executable=a.prebuilt/(case+suffix)if a.prebuilt else build(Path(temporary)/case,windows,case)
   if a.build_only:
    a.build_only.mkdir(parents=True,exist_ok=True);dest=a.build_only/(case+suffix)
    shutil.copyfile(executable,dest);shutil.copymode(executable,dest);continue
   with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve())],timeout=30,output_bound=0,error_bound=4096)as exchange:
    out,err=exchange.finish()
    assert exchange.process.returncode==CASES[case]and not out and not err,(case,exchange.process.returncode,out,err)
   print('ok catalog LARGE retire '+case,flush=True)
if __name__=='__main__':main()
