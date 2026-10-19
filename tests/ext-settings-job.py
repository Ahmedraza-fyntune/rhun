import argparse,hashlib,importlib.util,os,pathlib,re,shutil,struct,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--kind',choices=['job','memory','receipts','faults','pipe'],default='job')
p.add_argument('--faults',action='store_true')
p.add_argument('--exe',type=pathlib.Path)
p.add_argument('--build-only',action='store_true')
p.add_argument('--wine',type=pathlib.Path)
p.add_argument('--temp-root',type=pathlib.Path)
p.add_argument('--virtual-root')
a=p.parse_args()
if a.faults:a.kind='faults'
if a.build_only and not a.exe:p.error('--build-only requires --exe output')
if a.wine and (not a.exe or not a.temp_root or not a.virtual_root):p.error('--wine requires --exe, --temp-root and --virtual-root for a real Windows drive')
platform='windows' if os.name=='nt' or a.build_only and a.exe.suffix.lower()=='.exe' else 'macos' if sys.platform=='darwin' else 'linux'
def build_fixture(platform,folder,kind):
 builder=None;objects=[]
 if platform=='windows':
  spec=importlib.util.spec_from_file_location('worker_windows_builder',ROOT/'tools/build-windows.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
 modules=['extsettingsmemory','extsettingsframe','extsettingsjob','extsettingsjobframes','extsettingsjobcommon','extsettingsjobio','extsettingsjobstep']
 if kind=='pipe':modules.append('extsettingsworkerio')
 fixture={'pipe':'windows/ext_settings_worker_pipe_test.s','job':'ext_settings_job_test.s','memory':'ext_settings_memory_test.s','receipts':'ext_settings_receipts_test.s','faults':'ext_settings_job_fault_test.s'}[kind]
 paths=[('fixture',ROOT/'tests'/fixture)]+[(name,ROOT/'src/app'/(name+'.s')) for name in modules]
 for name,path in paths:
  text=path.read_text()
  if kind=='pipe' and name=='extsettingsworkerio':
   for api in ['GetStdHandle','GetFileType','SetNamedPipeHandleState','PeekNamedPipe','ReadFile','WriteFile']:text=text.replace('API '+api,'call swf_'+api)
  if kind=='faults' and name!='fixture':
   for suffix in ['start','read','write_begin','write_poll','close_input','poll','kill','free']:text=text.replace('ext_settings_native_'+suffix,'ecnf_'+suffix)
  elif kind=='job' and name=='extsettingsjobstep':
   assert text.count('call ext_settings_native_poll')==1
   text=text.replace('call ext_settings_native_poll','call ecjt_observation_poll')
  if builder:text=re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"',text)
  source=folder/(name+'.s');source.write_text(text);obj=source.with_suffix('.obj' if builder else '.o')
  definitions=[]
  if platform=='macos':
   translated=folder/(name+'-a64.s');cmd=[sys.executable,ROOT/'tools/arm64.py','-I',ROOT/'src','-D','MACOS']
   for definition in definitions:cmd+=['-D',definition]
   subprocess.run([*cmd,source,translated],check=True,timeout=120);cmd=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',obj,translated]
  elif builder:
   cmd=[builder.tool('llvm-mc'),'-triple=x86_64-pc-windows-msvc','-filetype=obj','-defsym=WINDOWS=1','-I',ROOT/'src','-I',ROOT/'src/win']
   for definition in definitions:cmd+=['-defsym='+definition+'=1']
   cmd += [source,'-o',obj]
  else:
   cmd=['as','--64','-I',ROOT/'src']
   for definition in definitions:cmd += ['--defsym',definition+'=1']
   cmd += ['-o',obj,source]
  subprocess.run(cmd,check=True,timeout=120);objects.append(obj)
 excluded={'src/main.s',*(('src/app/'+name+'.s') for name in modules)}
 if platform!='linux':excluded.update(['src/start.s','src/plat/wayland.s','src/plat/x11.s','src/plat/appearance.s'])
 build=ROOT/('build/windows' if builder else 'build/obj')
 for path in sorted((ROOT/'src').rglob('*.s')):
  relative=path.relative_to(ROOT).as_posix()
  if relative in excluded or relative.startswith('src/mac/') and platform!='macos' or relative.startswith('src/win/') and not builder:continue
  name=relative.replace('/','_');obj=build/(name+'.obj' if builder else name[:-2]+'.o')
  if not obj.is_file():raise AssertionError('build current runtime first: '+str(obj))
  objects.append(obj)
 assets=build/('build_windows_assets.s.obj' if builder else 'build_assets.o');assert assets.is_file();objects.append(assets)
 exe=folder/(('ext-settings-'+kind+'.exe') if builder else ('ext-settings-'+kind))
 if platform=='macos':
  cmd=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*objects]
  for framework in ['AppKit','QuartzCore','IOSurface','CoreServices','Carbon']:cmd+=['-framework',framework]
 elif builder:
  libs=[build/(p.stem+'.lib') for p in sorted((ROOT/'src/win').glob('*.def'))]
  cmd=[builder.tool('lld-link'),'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*objects,*libs,build/'rhun.res']
 else:cmd=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*objects]
 subprocess.run(cmd,check=True,timeout=120);return exe

fixture_temporary=None
if a.build_only or not a.exe:
 fixture_temporary=tempfile.TemporaryDirectory(prefix='rhun-settings-parent-fixture-')
 built=build_fixture(platform,pathlib.Path(fixture_temporary.name),a.kind)
 if a.build_only:
  a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(built,a.exe)
  print('built settings '+a.kind+' fixture: '+str(a.exe),flush=True);sys.exit(0)
 a.exe=built
else:a.exe=a.exe.resolve() if not a.wine else a.exe

def run(args):
 command=([str(a.wine)] if a.wine else [])+[str(a.exe),*args]
 try:return subprocess.run(command,capture_output=True,timeout=35)
 except subprocess.TimeoutExpired as error:
  sys.stdout.buffer.write(error.stdout or b'');sys.stdout.buffer.flush()
  sys.stderr.buffer.write(error.stderr or b'');sys.stderr.buffer.flush()
  raise

if a.kind!='job':
 result=run([])
 expected={'pipe':b'ok helper raw pipe preflight and native failures\n','memory':b'ok settings aggregate allocation and owned frames\n','receipts':b'ok settings correlated receipts and incremental digest\n','faults':b'ok settings owned start failures and pending cleanup\n'}[a.kind]
 assert result.returncode==0 and result.stdout==expected and not result.stderr,(a.kind,result.returncode,result.stdout,result.stderr)
 print(expected.decode().strip(),flush=True);sys.exit(0)
if a.temp_root:
 root=pathlib.Path(a.temp_root);root.mkdir(parents=True,exist_ok=True);owner=tempfile.TemporaryDirectory(prefix='case-',dir=root);root=pathlib.Path(owner.name).resolve()
else:
 owner=tempfile.TemporaryDirectory(prefix='rhun-settings-job-e2e-');root=pathlib.Path(owner.name).resolve()
cfg=root/'space 雪 cfg';cfg.mkdir(exist_ok=True);ini=cfg/'extensions.ini';original=b'; retained\n[owner/tool]\npinned=no\nsetting.unknown=stay\n[providers]\ncomplete.py=other/tool\n'
def native(path):return str(a.virtual_root).rstrip('/')+'/'+root.name+'/'+path.relative_to(root).as_posix() if a.virtual_root else str(path)
for mode in range(1,12):
 ini.write_bytes(original);path=cfg
 if mode==8:path=root/'file'/'cfg';(root/'file').write_bytes(b'unchanged')
 r=run([native(path),str(mode),str(len(original)),hashlib.sha256(original).hexdigest()])
 assert r.returncode==0 and len(r.stdout)==64 and not r.stderr,(mode,r.returncode,r.stdout[:200],r.stderr[:1000])
 result=struct.unpack('<8q',r.stdout)
 assert ini.read_bytes()==(original.replace(b'pinned=no',b'pinned=yes') if mode in (2,5,11) else original),(mode,result,ini.read_bytes())
 print('ok parent/helper mode',mode,result,flush=True)

small=original
for mode in (12,13,14):
 original=small+b';'+b'x'*((1048576 if mode==12 else 1048000)-len(small)-2)+b'\n'
 ini.write_bytes(original)
 r=run([native(cfg),str(mode),str(len(original)),hashlib.sha256(original).hexdigest()])
 assert r.returncode==0 and len(r.stdout)==64 and not r.stderr,(mode,r.returncode,r.stdout[:200],r.stderr[:1000])
 result=struct.unpack('<8q',r.stdout)
 assert result[0]==(1 if mode==12 else 3),(mode,result)
 expected=original if mode==12 else original.replace(b'pinned=no',b'pinned=yes')
 assert ini.read_bytes()==expected,(mode,result)
 print('ok scheduled parent/helper maximum-size mode',mode,result,flush=True)
if owner:owner.cleanup()
