import argparse,importlib.util,os,pathlib,re,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--exe',type=pathlib.Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--faults',action='store_true');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=['dense-slots','provider-epoch','skip-dirty','publish-recheck','gc-one','stale-entry']);a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('--negative-controls builds its own native fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
expected=b'ok whole sparse settings models and provider publication\n'
mutant_codes={'dense-slots':131,'provider-epoch':132,'skip-dirty':133,'publish-recheck':146,'gc-one':136,'stale-entry':140}
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('catalog_fixture_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_view_test.s').read_text();assert fixture.count('FN main')==1;fixture=fixture.replace('FN main','FN original_settings_view_main')+'\n'+(ROOT/'tests/ext_settings_catalog_cases.inc').read_text();replacements={}
 def change(relative,old,new):
  text=replacements.get(relative,(ROOT/relative).read_text());assert text.count(old)==1,(relative,old,text.count(old));replacements[relative]=text.replace(old,new)
 if a.faults:
  fixture=fixture.replace('.ifdef VT_FAULTS','.if 1')
  text=(ROOT/'src/app/extsettingsmemory.s').read_text();assert text.count('call time_ms')==3;replacements['src/app/extsettingsmemory.s']=text.replace('call time_ms','call vt_time')
  if windows:change('src/win/sys.s','API VirtualFree','call vt_native_unmap')
  else:change('src/mem.s','SYS SYS_munmap','call vt_native_unmap')
 else:fixture=fixture.replace('.ifdef VT_FAULTS','.if 0')
 # Pure publication must not call an allocator, free, freshness recheck, or protocol.
 for relative,names in [('src/mem.s',['mem_alloc','mem_alloc_try','mem_free']),('src/app/extsettingscatalog.s',['cp_check_epochs']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(relative,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + ct_poison], 0\n    jne ct_poison_fail\n')
 if mutation=='dense-slots':change('src/app/extsettingscatalogcapture.s','mov rcx, [r13 + CPR_slot]','mov rcx, r12')
 elif mutation=='provider-epoch':change('src/app/extsettingscatalogprovidercompare.s','mov qword ptr [rbx + CP_ppdiff], 0','mov qword ptr [rbx + CP_ppdiff], 1')
 elif mutation=='skip-dirty':change('src/app/extsettingscatalogproviders.s','.Lpp_raw_done:\n    mov qword ptr [rbx + CP_ppdirtyslot], 0\n    mov qword ptr [rbx + CP_ppphase], PPS_DIRTY_NEXT','.Lpp_raw_done:\n    mov qword ptr [rbx + CP_ppdirtyslot], 0\n    mov qword ptr [rbx + CP_ppphase], PPS_COMPARE_BEGIN')
 elif mutation=='publish-recheck':change('src/app/extsettingscatalogpublish.s','FN ext_settings_catalog_publish\n    PROLOGUE\n    mov rbx, rdi','FN ext_settings_catalog_publish\n    PROLOGUE\n    mov rbx, rdi\n    call cp_check_epochs')
 elif mutation=='gc-one':change('src/app/extsettingscataloggc.s','    test r12, r12\n    jz .Lcpg_return','    cmp r12, 2\n    jb .Lcpg_return')
 elif mutation=='stale-entry':change('src/app/extsettingscatalogstep.s','    call cp_check_epochs\n    test rax, rax\n    js .Lcps_no_work','    xor eax, eax\n    test rax, rax\n    js .Lcps_no_work')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(exe,mutation=None):
 result=subprocess.run(([a.wine] if a.wine else [])+[str(exe)],cwd=ROOT,capture_output=True,timeout=90)
 if mutation:assert result.returncode==mutant_codes[mutation],(mutation,result.returncode,result.stdout,result.stderr)
 else:assert result.returncode==0 and result.stdout==expected and not result.stderr,(result.returncode,result.stdout,result.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-catalog-') as temporary:
 folder=pathlib.Path(temporary)
 if a.negative_controls:
  check(build(folder/'baseline'))
  for mutation in mutant_codes:
   check(build(folder/mutation,mutation),mutation);print('ok settings catalog negative control '+mutation,flush=True)
 else:
  exe=a.exe if a.exe and not a.build_only else build(folder,a.mutation)
  if a.build_only:
   a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);print('built sparse settings catalog fixture: '+str(a.exe),flush=True);sys.exit(0)
  check(exe,a.mutation);print('ok settings catalog negative control '+a.mutation if a.mutation else expected.decode().strip(),flush=True)
