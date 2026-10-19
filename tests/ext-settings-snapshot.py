import argparse,importlib.util,os,pathlib,re,shutil,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--exe',type=pathlib.Path)
p.add_argument('--build-only',action='store_true')
p.add_argument('--wine')
a=p.parse_args()
if a.build_only and not a.exe:p.error('--build-only requires --exe output')
if a.wine and not a.exe:p.error('--wine requires --exe')
platform='windows' if os.name=='nt' or a.build_only and a.exe.suffix.lower()=='.exe' else 'macos' if sys.platform=='darwin' else 'linux'
def build_fixture(platform,folder):
 builder=None;objects=[]
 if platform=='windows':
  spec=importlib.util.spec_from_file_location('worker_windows_builder',ROOT/'tools/build-windows.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
 modules=['extsettingsmemory','extsettingsframe','extsettingssnapshot','extsettingsini']
 fixture='ext_settings_snapshot_test.s'
 paths=[('fixture',ROOT/'tests'/fixture)]+[(name,ROOT/'src/app'/(name+'.s')) for name in modules]
 for name,path in paths:
  text=path.read_text()
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
 exe=folder/('ext-settings-snapshot.exe' if builder else 'ext-settings-snapshot')
 if platform=='macos':
  cmd=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*objects]
  for framework in ['AppKit','QuartzCore','IOSurface','CoreServices','Carbon']:cmd+=['-framework',framework]
 elif builder:
  libs=[build/(p.stem+'.lib') for p in sorted((ROOT/'src/win').glob('*.def'))]
  cmd=[builder.tool('lld-link'),'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*objects,*libs,build/'rhun.res']
 else:cmd=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*objects]
 subprocess.run(cmd,check=True,timeout=120);return exe

with tempfile.TemporaryDirectory(prefix='rhun-settings-snapshot-fixture-') as folder:
 if a.build_only or not a.exe:
  exe=build_fixture(platform,pathlib.Path(folder))
  if a.build_only:
   a.exe.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(exe,a.exe)
   print('built immutable settings snapshot fixture: '+str(a.exe),flush=True);sys.exit(0)
 else:exe=a.exe if a.wine else a.exe.resolve()
 result=subprocess.run(([a.wine] if a.wine else [])+[str(exe)],capture_output=True,timeout=40)
 expected=b'ok immutable snapshot spans and bounded INI cursor\n'
 assert result.returncode==0 and result.stdout==expected and not result.stderr,(result.returncode,result.stdout,result.stderr)
 print(expected.decode().strip(),flush=True)
