#!/usr/bin/env python3
"""Real dispatcher/base ownership baselines and independent missing-guard controls."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import tempfile
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CASES={
 'owner':('owner',None,0),
 'base':('base',None,0),
 'missing-initial-eo-drop':('owner','eo',42),
 'positive-retirement-ref-guard':('owner','refs',42),
 'building-view':('owner','view',42),
 'unsupported-plan-role':('owner','plan',46),
 'missing-base-source-guard':('base','source',41),
 'duplicate-scratch-header':('base','charge',43),
 'missing-owned-scratch-free':('base','free',43),
 'missing-row-unit-cap':('base','units',60),
}
def load(kind):
 spec=importlib.util.spec_from_file_location('catalog_'+kind,ROOT/'tests'/('catalog-'+kind+'.py'))
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module

def build(folder,windows=False,case='owner'):
 kind,mutation,_=CASES[case];replacements={}
 def change(path,function,old,new):
  source=replacements.get(path,(ROOT/path).read_text())
  head,body=source.split('FN '+function+'\n',1);body,sep,tail=body.partition('\nFN ')
  assert old in body,(case,path,function,old)
  replacements[path]=head+'FN '+function+'\n'+body.replace(old,new,1)+sep+tail
 if mutation=='eo':change('src/app/catalogregistry.s','catalog_object_create','    call ext_prepare_owner_release_deferred','    xor eax, eax\n    mov edx, 1')
 if mutation=='refs':change('src/app/catalogretire.s','catalog_retire_one','    cmp qword ptr [rdi + PO_refs], 0\n    jne .Lcr_bad','    cmp qword ptr [rdi + PO_refs], 0\n    je .Lcr_bad')
 if mutation=='plan':change('src/app/catalogretire.s','catalog_retire_one','    cmp qword ptr [rdi + C7_role], C7_REGISTRY','    cmp qword ptr [rdi + C7_role], C7_PLAN\n    je registry_retire_one\n    cmp qword ptr [rdi + C7_role], C7_REGISTRY')
 if mutation=='view':change('src/app/catalogregistry.s','registry_view','    call catalog_is_ready','    call catalog_is_owned')
 if mutation=='source':change('src/app/catalogregistrybase.s','registry_base_step','    call registry_base_input_check','    xor eax, eax')
 if mutation=='charge':change('src/app/catalogregistrybase.s','registry_base_qualify_one','    call prep_pointer_charge','    call prep_pointer_charge\n    add rax, 16')
 if mutation=='free':change('src/app/catalogregistryretire.s','registry_base_retire_one','    call catalog_base_scratch_consume','    xor eax, eax\n    xor r8d, r8d')
 if mutation=='units':change('src/app/catalogregistrybase.s','registry_base_step','    cmp qword ptr [rbx + RB_units], REG_STEP_UNITS','    cmp qword ptr [rbx + RB_units], 100000')
 return load(kind).build(folder,windows=windows,replacements=replacements)

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--build-only',type=Path);p.add_argument('--prebuilt',type=Path)
 p.add_argument('--windows',action='store_true');p.add_argument('--wine')
 p.add_argument('--case',choices=tuple(CASES))
 a=p.parse_args()
 if a.build_only and a.prebuilt:p.error('--build-only and --prebuilt are exclusive')
 windows=a.windows or bool(a.wine)or os.name=='nt';suffix='.exe'if windows else''
 with tempfile.TemporaryDirectory(prefix='rhun-catalog-foundation-')as temporary:
  for case in ([a.case]if a.case else CASES):
   kind,mutation,expected_code=CASES[case]
   executable=(a.prebuilt/(case+suffix))if a.prebuilt else build(Path(temporary)/case,windows=windows,case=case)
   if a.build_only:
    a.build_only.mkdir(parents=True,exist_ok=True);dest=a.build_only/(case+suffix)
    shutil.copyfile(executable,dest);shutil.copymode(executable,dest);continue
   command=([a.wine]if a.wine else[])+[str(executable.resolve())]
   with FixtureExchange(command,timeout=30,output_bound=4104 if case=='base'else 0,error_bound=4096)as exchange:
    out,err=exchange.finish()
    assert exchange.process.returncode==expected_code and not err,(case,exchange.process.returncode,out,err)
    if case=='base':
     assert len(out)>=8 and struct.unpack_from('<Q',out)[0]==len(out)-8,(case,out)
     expected=(('Z:'if a.wine else'')+os.getcwd()+'/themes/relative.theme').encode()
     assert out[8:].replace(b'\\',b'/')==expected.replace(b'\\',b'/'),(case,out[8:],expected)
    else:assert not out,(case,out)
   print('ok catalog foundation '+case,flush=True)
if __name__=='__main__':main()
