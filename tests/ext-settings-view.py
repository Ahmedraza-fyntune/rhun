import argparse,importlib.util,os,pathlib,re,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--exe',type=pathlib.Path);p.add_argument('--build-only',action='store_true');p.add_argument('--wine');p.add_argument('--faults',action='store_true');p.add_argument('--negative-controls',action='store_true');p.add_argument('--mutation',choices=['saturation','frame-size','stale-entry','gc-one']);a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe')
if a.negative_controls and (a.exe or a.build_only or a.mutation):p.error('--negative-controls builds its own native fixtures')
windows=os.name=='nt' or bool(a.wine) or bool(a.build_only and a.exe.suffix.lower()=='.exe')
expected=b'ok own-schema values, replacements, dirty intent and bounded retirement\n'
def build(folder,mutation=None):
 spec=importlib.util.spec_from_file_location('view_fixture_builder',ROOT/'tests/faults/ext_store_build.py');b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 fixture=(ROOT/'tests/ext_settings_view_test.s').read_text();replacements={}
 if a.faults:
  # The shared translator's explicit fixture flag is resolved before assembly.
  fixture=fixture.replace('.ifdef VT_FAULTS','.if 1')
  memory=(ROOT/'src/app/extsettingsmemory.s').read_text();assert memory.count('call time_ms')==3;replacements['src/app/extsettingsmemory.s']=memory.replace('call time_ms','call vt_time')
  if windows:
   native=(ROOT/'src/win/sys.s').read_text();assert native.count('API VirtualFree')==1;replacements['src/win/sys.s']=native.replace('API VirtualFree','call vt_native_unmap')
  else:
   native=(ROOT/'src/mem.s').read_text();assert native.count('SYS SYS_munmap')==1;replacements['src/mem.s']=native.replace('SYS SYS_munmap','call vt_native_unmap')
 else:fixture=fixture.replace('.ifdef VT_FAULTS','.if 0')
 if mutation:
  name={'saturation':'extsettingsviewscalar','frame-size':'extsettingsviewnormalize','stale-entry':'extsettingsviewstep','gc-one':'extsettingsviewgc'}[mutation]
  text=(ROOT/'src/app'/(name+'.s')).read_text()
  old,new={
   'saturation':('cmp rdx, 214748364','cmp rdx, -1'),
   'frame-size':('add rax, 12','add rax, 10'),
   'stale-entry':('call esv_check_epochs','xor eax, eax'),
   'gc-one':('    test r12, r12\n    jz .Lesvg_return','    cmp r12, 2\n    jb .Lesvg_return'),
  }[mutation]
  assert text.count(old)==1,(mutation,text.count(old));replacements['src/app/'+name+'.s']=text.replace(old,new)
 # Every replaced section is ordinary .rodata or native PE data. Reject new suffixes
 # rather than letting the shared test-only converter collapse subsection identities.
 for text in [fixture,*replacements.values()]:
  assert not re.search(r'(?m)^\s*\.section \.rodata[^\s\n]',text)
 return b.build(folder,fixture,replacements,windows=windows)
def check(exe,mutation=None):
 command=([a.wine] if a.wine else [])+[str(exe)]
 result=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=60)
 if mutation:assert result.returncode=={'saturation':71,'frame-size':89,'stale-entry':75,'gc-one':115}[mutation],(mutation,result.returncode,result.stdout,result.stderr)
 else:assert result.returncode==0 and result.stdout==expected and not result.stderr,(result.returncode,result.stdout,result.stderr)
with tempfile.TemporaryDirectory(prefix='rhun-settings-view-') as temporary:
 folder=pathlib.Path(temporary)
 if a.negative_controls:
  check(build(folder/'baseline'))
  for mutation in ['saturation','frame-size','stale-entry','gc-one']:
   check(build(folder/mutation,mutation),mutation);print('ok settings view negative control '+mutation,flush=True)
 else:
  exe=a.exe if a.exe and not a.build_only else build(folder,a.mutation)
  if a.build_only:
   a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe);print('built own-schema settings view fixture: '+str(a.exe),flush=True);sys.exit(0)
  check(exe,a.mutation);print('ok settings view negative control '+a.mutation if a.mutation else expected.decode().strip(),flush=True)
