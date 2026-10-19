import argparse,importlib.util,os,pathlib,re,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
mutant_codes={'ignore-sequence':163,'skip-canonical':162,'ignore-active-registry':164,'ignore-flags':166,'short-probe':166,'allocate-in-getter':170}
p=argparse.ArgumentParser();p.add_argument('--exe',type=pathlib.Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=list(mutant_codes));a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('--negative-controls builds its own native fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
expected=b'ok installed settings authority and canonical dirty overlays\n'
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('effective_fixture_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 view=(ROOT/'tests/ext_settings_view_test.s').read_text();catalog=(ROOT/'tests/ext_settings_catalog_cases.inc').read_text()
 assert view.count('FN main')==1 and catalog.count('FN main')==1
 fixture=view.replace('FN main','FN original_settings_view_main')+'\n'+catalog.replace('FN main','FN original_settings_catalog_main')+'\n'+(ROOT/'tests/ext_settings_effective_cases.inc').read_text()
 fixture=fixture.replace('.ifdef VT_FAULTS','.if 0')
 replacements={}
 def change(path,old,new):
  text=replacements.get(path,(ROOT/path).read_text());assert text.count(old)==1,(path,old,text.count(old));replacements[path]=text.replace(old,new)
 for path,names in [('src/mem.s',['mem_alloc','mem_alloc_try','mem_free']),('src/sys.s',['file_read_all','file_read_all_extra','file_write_all']),('src/app/ext.s',['ext_send','ext_flush'])]:
  for name in names:change(path,'FN '+name+'\n','FN '+name+'\n    cmp qword ptr [rip + av_read_poison], 0\n    jne av_poison_fail\n')
 if mutation=='ignore-sequence':change('src/app/extsettingseffective.s','    cmp rax, [r14 + ELM_sequence]\n    jbe .Lsev_model','    cmp rax, rax\n    jnz .Lsev_model')
 elif mutation=='skip-canonical':change('src/app/extsettingseffective.s','    call ext_settings_canonical_value','    xor eax, eax')
 elif mutation=='ignore-active-registry':change('src/app/extsettingsactive.s','    cmp [rax + ELM_registry], rcx','    cmp rcx, rcx')
 elif mutation=='ignore-flags':change('src/app/extsettingsflags.s','    mov r13, r8','    mov r13, r8\n    mov rax, r13\n    EPILOGUE')
 elif mutation=='short-probe':change('src/app/extsettingsproviderread.s','.Lsar_next:\n','.Lsar_next:\n    jmp .Lsar_absent\n')
 elif mutation=='allocate-in-getter':change('src/app/extsettingseffective.s','    PROLOGUE 272\n','    PROLOGUE 272\n    mov edi, 8\n    call mem_alloc_try\n')
 for text in [fixture,*replacements.values()]:assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(exe,mutation=None):
 result=subprocess.run(([a.wine] if a.wine else [])+[str(exe)],cwd=ROOT,capture_output=True,timeout=90)
 if mutation:assert result.returncode==mutant_codes[mutation],(mutation,result.returncode,result.stdout,result.stderr)
 else:assert result.returncode==0 and result.stdout==expected and not result.stderr,(result.returncode,result.stdout,result.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-effective-') as temporary:
 folder=pathlib.Path(temporary)
 if a.negative_controls:
  check(build(folder/'baseline'))
  for mutation in mutant_codes:
   check(build(folder/mutation,mutation),mutation);print('ok effective settings negative control '+mutation,flush=True)
 else:
  exe=a.exe if a.exe and not a.build_only else build(folder,a.mutation)
  if a.build_only:
   a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);print('built installed effective settings fixture: '+str(a.exe));sys.exit(0)
  check(exe,a.mutation);print('ok effective settings negative control '+a.mutation if a.mutation else expected.decode().strip(),flush=True)
