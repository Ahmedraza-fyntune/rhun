"""Build exact current settings sources with narrow fault injection, outside product objects."""
from pathlib import Path
import importlib.util
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]

def build(platform,folder,kind):
 r=runtime=ROOT
 w=folder/kind
 w.mkdir(exist_ok=True)
 if platform=='windows':
  s=importlib.util.spec_from_file_location('b',r/'tools/build-windows.py');b=importlib.util.module_from_spec(s);s.loader.exec_module(b)
 objects=[]
 modules=('extchoicesguard','extchoicessnapshot') if kind=='guard' else ('extchoicesguard','extchoicessnapshot','extchoicesprepare','extchoicescheck','extchoicescleanup','extchoicesio','extchoicessecurity','extchoicescommit','extchoices','extstoreio')
 paths=[(r/('tests/ext_choices_'+kind+'_test.s'),'fixture')]+[(r/'src/app'/(name+'.s'),name) for name in modules]
 for source,name in paths:
  text=source.read_text()
  if kind=='guard' and name!='fixture':
   for old,new in [('mem_alloc_try','cgt_alloc'),('ext_root_close','cgt_close'),('ext_root_read','cgt_read'),('ext_root_stat','cgt_stat'),('ext_root_identity','cgt_identity'),('ext_root_open_at','cgt_open')]:text=text.replace('call '+old+'\n','call '+new+'\n')
  if kind=='disk' and name!='fixture':
   for old,new in [('mem_alloc_try','cpt_alloc'),('ext_store_raw_write','cpt_write'),('ext_store_raw_sync','cpt_sync'),('ext_choices_raw_create','cpt_create'),('ext_root_stat','cpt_stat'),('ext_root_identity','cpt_identity'),('ext_root_close','cpt_close')]:text=text.replace('call '+old+'\n','call '+new+'\n')
  if kind=='disk' and name=='extchoicescommit':
   for old,new in [('ext_choices_raw_replace','cpt_replace'),('ext_choices_raw_replace_poll','cpt_replace_poll'),('ext_choices_read_final','cpt_read_final'),('ext_choices_stage_check','cpt_stage_check')]:text=text.replace('call '+old+'\n','call '+new+'\n')
  if platform=='windows' and name=='extchoicessecurity':
   for old,new in [('LocalFree','cpt_security_local_free'),('OpenProcessToken','cpt_security_open_token'),('GetTokenInformation','cpt_security_token_info'),('ConvertSidToStringSidW','cpt_security_sid'),('ConvertStringSecurityDescriptorToSecurityDescriptorW','cpt_security_descriptor'),('CloseHandle','cpt_security_close_token')]:text=text.replace('API '+old+'\n','call '+new+'\n')
  if name=='extchoicesprepare':text=text.replace('call ext_choices_snapshot_try\n','call cpt_snapshot\n')
  if platform=='windows' and name in ('extchoicesio','extstoreio'):
   for old,new in [('NtSetInformationFile','cpt_native_set_info'),('WaitForSingleObject','cpt_native_wait')]:text=text.replace('API '+old+'\n','call '+new+'\n')
  if platform=='windows' and name=='extstoreio':text=text.replace('call cpt_close\n','call cpt_store_close\n')
  if platform=='windows':text=re.sub(r'(?m)^\.section \.rodata$', '.section .rdata,"dr"',text)
  path=w/('prep-'+name+'-'+platform+'.s');path.write_text(text);obj=w/('prep-'+name+('-win.obj' if platform=='windows' else '-'+platform+'.o'))
  if platform=='macos':
   out=w/(name+'-prep-a64.s')
   subprocess.run(['python3',str(r/'tools/arm64.py'),'-I',str(w/'src'),'-I',str(r/'src'),'-D','MACOS',str(path),str(out)],check=True)
   command=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',str(obj),str(out)]
  elif platform=='windows':command=[b.tool('llvm-mc'),'-triple=x86_64-pc-windows-msvc','-filetype=obj','-defsym=WINDOWS=1','-I',str(w/'src'),'-I',str(r/'src'),'-I',str(r/'src/win'),str(path),'-o',str(obj)]
  else:command=['as','--64','-I',str(w/'src'),'-I',str(r/'src'),'-o',str(obj),str(path)]
  subprocess.run(command,check=True);objects.append(obj)
 if platform=='macos' and kind=='disk':
  obj=w/'prep-native-mac.o';subprocess.run(['as','-arch','arm64','-mmacosx-version-min=12.0','-I',str(r/'src/mac'),'-o',str(obj),str(r/'src/mac/extchoicesio.s')],check=True);objects.append(obj)
 s=importlib.util.spec_from_file_location('t',r/'tests/task-core.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.ROOT=runtime
 exclude={n for name in modules for n in ('src_app_'+name+'.o','src_app_'+name+'.s.obj')}
 if kind=='disk':exclude.add('src_mac_extchoicesio.o')
 objects+=[o for o in m.runtime_objects(platform) if o.name not in exclude]
 for name in ('src_app_taskcore','src_memtry'):objects.append(runtime/('build/windows/'+name+'.s.obj' if platform=='windows' else 'build/obj/'+name+'.o'))
 exe=w/(kind+'-test.exe' if platform=='windows' else kind+'-test-'+platform)
 if platform=='macos':
  command=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',str(exe),*map(str,objects)]
  for f in ('AppKit','QuartzCore','IOSurface','CoreServices','Carbon'):command+=['-framework',f]
 elif platform=='windows':
  libs=[str(runtime/'build/windows'/(d.stem+'.lib')) for d in sorted((runtime/'src/win').glob('*.def'))]
  command=[b.tool('lld-link'),'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*map(str,objects),str(runtime/'build/windows/rhun.res'),*libs]
 else:command=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',str(exe),*map(str,objects)]
 subprocess.run(command,check=True);return exe
