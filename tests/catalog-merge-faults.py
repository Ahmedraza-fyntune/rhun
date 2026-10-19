#!/usr/bin/env python3
"""Actual merge, every partial construction phase, and supplier ownership controls."""
import argparse
import contextlib
import importlib.util
import os
from pathlib import Path
import shutil
import tempfile
from fixture_exchange import FixtureExchange
ROOT=Path(__file__).resolve().parents[1]
CASES={'baseline':(None,0),**{'cancel-'+str(i):(i,0)for i in range(8)},
 **{'cursor-'+str(i):('cursor'+str(i),0)for i in range(100,108)},
 **{'oom-'+str(i):('oom'+str(i),0)for i in range(1,12)},
 **{'refusal-'+str(i):('ref'+str(i),0)for i in range(1,5)},
 'consumed-cleanup':('ref6',0),
 'fail-open-old-drop':('ref2bad',44),'fail-open-input-drop':('ref4bad',44),
 'wrong-output-order':('order',45),
 'missing-theme-only-ref':('themeonly',45),'wrong-theme-order':('themeorder',45),
 'losing-theme-only':('losertheme',0),'stale-theme-supplier':('lostthemedec',45),
 'stale-grammar-supplier':('lostgrdec',45),
 'pure-owned-merge':('pure',0),'forbidden-merge-open':('pureopen',44),
 'missing-user-io-path':('userpath',45),'raw-user-io-path':('userraw',45),
 'missing-user-io-length':('userlen',45),
 'missing-winning-gp-ref':('gp',45),'missing-final-ep-ref':('ep',45),
 'missing-input-prune':('inputs',45),'lost-replaced-gp':('old',46)}
@contextlib.contextmanager
def lease_folder(wine):
    if not wine:
        yield str(ROOT)
        return
    drive=(Path(os.environ.get('WINEPREFIX',str(Path.home()/'.wine'))))/'drive_c'
    drive=drive.expanduser().resolve()
    if not drive.is_dir():
        raise AssertionError('Initialize the private Wine prefix before the registry lease fixture')
    # Wine maps Z: through Unix symlinks. The rooted no-follow proof uses an owned C: directory.
    with tempfile.TemporaryDirectory(prefix='rhun-registry-lease-',dir=drive)as folder:
        yield 'C:/'+Path(folder).relative_to(drive).as_posix()

def build(folder,windows=False,case='baseline'):
 spec=importlib.util.spec_from_file_location('catalog_merge_matrix',ROOT/'tests/catalog-merge.py')
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 mutation,_=CASES[case];fixture=(ROOT/'tests/catalog_merge_test.s').read_text();replacements={}
 if isinstance(mutation,int):fixture=fixture.replace('.equ CM_CANCEL_PHASE, -1','.equ CM_CANCEL_PHASE, '+str(mutation))
 def change(path,function,old,new):
  source=(ROOT/path).read_text();head,body=source.split('FN '+function+'\n',1);body,sep,tail=body.partition('\nFN ')
  assert old in body,(case,old);replacements[path]=head+'FN '+function+'\n'+body.replace(old,new,1)+sep+tail
 if isinstance(mutation,str)and mutation.startswith('cursor'):
  fixture=fixture.replace('.equ CM_CANCEL_POINT, -1','.equ CM_CANCEL_POINT, '+mutation[6:])
 if isinstance(mutation,str)and mutation.startswith('oom'):
  fixture=fixture.replace('.equ CM_OOM_N, 0','.equ CM_OOM_N, '+mutation[3:])
  source=(ROOT/'src/mem.s').read_text();assert 'FN mem_alloc_try\n'in source
  replacements['src/mem.s']=source.replace('FN mem_alloc_try\n','FN cm_actual_mem_alloc_try\n',1)
 if isinstance(mutation,str)and mutation.startswith('ref'):
  fault=int(mutation[3]);fixture=fixture.replace('.equ CM_REF_FAULT, 0','.equ CM_REF_FAULT, '+str(fault))
  path,fn={1:('src/app/extpreparegrammar.s','grammar_prepare_retain'),2:('src/app/extprepareretirequeue.s','prep_object_release_deferred'),3:('src/app/extprepareowner.s','ext_prepare_retain'),4:('src/app/extprepareretirequeue.s','ext_prepare_release_deferred'),6:('src/app/extprepareretirequeue.s','prep_object_release_deferred')}[fault]
  source=(ROOT/path).read_text();assert 'FN '+fn+'\n'in source
  replacements[path]=source.replace('FN '+fn+'\n','FN cm_actual_'+fn+'\n',1)
 if mutation in('ref2bad','ref4bad'):
  change('src/app/catalogregistryretire.s','catalog_retire_drop','    cmp r15, 1\n    jne .Lcrd_retained','    cmp r15, 1\n    nop')
 if mutation=='order':
  change('src/app/catalogregistryfinal.s','registry_final_view_one','    mov rax, [rax + GRR_gr]','    cmp rcx, 2\n    jne .Lorder_second\n    add rax, GRR_SIZE\n.Lorder_second:\n    cmp rcx, 3\n    jne .Lorder_load\n    sub rax, GRR_SIZE\n.Lorder_load:\n    mov rax, [rax + GRR_gr]')
 if mutation=='themeonly':
  change('src/app/catalogregistryfinal.s','registry_final_ref_one','    or rax, [r13 + RGS_themes]','    test rax, rax')
 if mutation=='themeorder':
  change('src/app/catalogregistrytheme.s','registry_theme_one','    imul rdi, r12, TH_SIZE\n    add rdi, [rbx + RG_themes]','    mov rdi, r12\n    cmp rdi, 4\n    je .Ltheme_order_swap\n    cmp rdi, 5\n    jne .Ltheme_order_copy\n.Ltheme_order_swap:\n    xor rdi, 1\n.Ltheme_order_copy:\n    imul rdi, rdi, TH_SIZE\n    add rdi, [rbx + RG_themes]')
 if mutation in('losertheme','lostthemedec'):
  needle='5: cmp r12, 4\n';assert fixture.count(needle)==1
  fixture=fixture.replace(needle,'5: cmp r12, 0\n jne .Lcm_losing_theme_other\n lea rsi, [rip + cm_path1]\n mov rdi, r13\n call cm_pt\n jmp 8f\n.Lcm_losing_theme_other:\n cmp r12, 4\n',1)
 if mutation=='lostthemedec':
  change('src/app/catalogregistrytheme.s','registry_theme_one','    dec qword ptr [rax + RGS_themes]','    nop')
 if mutation=='lostgrdec':
  change('src/app/catalogregistrygrammar.s','registry_grammar_one','    dec qword ptr [rax + RGS_grammars]','    nop')
 if mutation in('pure','pureopen'):
  fixture=fixture.replace('.equ CM_PURE_IO, 0','.equ CM_PURE_IO, 1')
  for path,fn in [('src/app/extvalidatepath.s','ext_root_open'),('src/filetry.s','file_read_limited_try'),('src/app/syntax.s','grammar_fill_context'),('src/app/theme.s','theme_parse_into')]:
   source=(ROOT/path).read_text();needle='FN '+fn+'\n';assert source.count(needle)==1
   replacements[path]=source.replace(needle,'FN cm_actual_'+fn+'\n',1)
 if mutation=='pureopen':
  change('src/app/catalogregistrytheme.s','registry_theme_one','    mov rbx, rdi','    mov rbx, rdi\n    mov rax, [rip + g_argv]\n    mov rdi, [rax + 8]\n    call ext_root_open\n    mov rdi, rbx')
 if mutation in('userpath','userraw','userlen'):
  old,new={'userpath':('    mov rax, [r14 + BTM_path]','    xor eax, eax'),'userraw':('    mov rax, [r14 + BTM_path]','    mov rax, [r14 + BTM_key]'),'userlen':('    mov rax, [r14 + BTM_pathlen]','    xor eax, eax')}[mutation]
  change('src/app/catalogregistrymergebase.s','registry_copy_base_one',old,new)
 if mutation=='gp':change('src/app/catalogregistrygrammar.s','registry_grammar_one','    call grammar_prepare_retain','    xor eax, eax')
 if mutation=='ep':change('src/app/catalogregistryfinal.s','registry_final_ref_one','    call ext_prepare_retain','    xor eax, eax')
 if mutation=='inputs':change('src/app/catalogregistryfinal.s','registry_drop_input_one','    call catalog_retire_drop','    mov eax, 1')
 if mutation=='old':change('src/app/catalogregistrygrammar.s','registry_grammar_one','    call catalog_retire_drop','    mov qword ptr [rbx + RG_old_gp], 0\n    mov eax, 1')
 return module.build(folder,windows,replacements,fixture)
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--build-only',type=Path);p.add_argument('--prebuilt',type=Path)
 p.add_argument('--windows',action='store_true');p.add_argument('--wine');p.add_argument('--case',choices=tuple(CASES))
 a=p.parse_args()
 if a.build_only and a.prebuilt:p.error('--build-only and --prebuilt are exclusive')
 windows=a.windows or bool(a.wine)or os.name=='nt';suffix='.exe'if windows else''
 with tempfile.TemporaryDirectory(prefix='rhun-catalog-merge-faults-')as temporary, lease_folder(a.wine if not a.build_only else None)as lease:
  for case in([a.case]if a.case else CASES):
   executable=a.prebuilt/(case+suffix)if a.prebuilt else build(Path(temporary)/case,windows,case)
   if a.build_only:
    a.build_only.mkdir(parents=True,exist_ok=True);dest=a.build_only/(case+suffix)
    shutil.copyfile(executable,dest);shutil.copymode(executable,dest);continue
   with FixtureExchange(([a.wine]if a.wine else[])+[str(executable.resolve()),lease],timeout=30,output_bound=0,error_bound=4096)as exchange:
    out,err=exchange.finish()
    assert exchange.process.returncode==CASES[case][1] and not out and not err,(case,exchange.process.returncode,out,err)
   print('ok catalog merge '+case,flush=True)
if __name__=='__main__':main()
