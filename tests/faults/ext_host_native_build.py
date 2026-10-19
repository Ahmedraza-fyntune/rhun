"""Isolated fault build for checked close and reserve-first pipe construction."""
import importlib.util
from pathlib import Path
import re
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/faults'))
from ext_retire_build import bounded_tool

def build(folder,windows=False,normal=False):
    assert windows, 'Windows-only backend fault fixture'
    folder.mkdir(parents=True,exist_ok=True)
    fixture=(ROOT/('tests/ext_host_native_test.s'if normal else'tests/ext_host_native_fault_test.inc')).read_text()
    source=(ROOT/'src/win/sys.s').read_text()
    start=source.index('FN ws_pipe\n');end=source.index('FN ws_fcntl\n',start)
    body=source[start:end]
    assert body.count('call win_fd_alloc')==2
    assert body.count('API CreatePipe')==1
    body=body.replace('call win_fd_alloc','call hn_alloc').replace('API CreatePipe','call hn_create')
    replacements={'src/win/sys.s':(source[:start]+body+source[end:]).replace('API CloseHandle','call hn_close')}
    source=(ROOT/'src/win/exthostnative.s').read_text()
    assert source.count('API CloseHandle')==1
    replacements['src/win/exthostnative.s']=source.replace('API CloseHandle','call hn_close')
    if normal:replacements={}
    replacements['fixture.s']=fixture
    mac=sys.platform=='darwin'and not windows
    if windows:
        spec=importlib.util.spec_from_file_location('retire_win_build',ROOT/'tools/build-windows.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        mc,linker=module.tool('llvm-mc'),module.tool('lld-link')
    objects={}
    for relative,source in replacements.items():
        path=folder/relative.replace('/','_');obj=path.with_suffix('.obj'if windows else'.o')
        if windows:source=re.sub(r'(?m)^(\s*\.section) \.rodata[^\n]*',r'\1 .rdata,"dr"',source)
        path.write_text(source)
        if windows:command=[mc,'-triple=x86_64-pc-windows-msvc','-filetype=obj','-defsym=WINDOWS=1','-I',ROOT/'src','-I',ROOT/'src/win','-o',obj,path]
        elif mac:
            translated=path.with_suffix('.a64.s')
            bounded_tool([sys.executable,ROOT/'tools/arm64.py','-I',ROOT/'src','-D','MACOS',path,translated])
            command=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',obj,translated]
        else:command=['as','--64','-I',ROOT/'src','-I',ROOT/'build','-o',obj,path]
        bounded_tool(command);objects[relative]=obj
    inventory=[objects.pop('fixture.s')]
    excluded={'src/main.s'}
    if mac or windows:excluded|={'src/start.s','src/plat/wayland.s','src/plat/x11.s','src/plat/appearance.s'}
    for path in sorted((ROOT/'src').rglob('*.s')):
        relative=path.relative_to(ROOT).as_posix()
        if relative in excluded or('win'in path.parts and not windows)or('mac'in path.parts and not mac):continue
        fallback=ROOT/('build/windows'if windows else'build/obj')/(relative.replace('/','_')+'.obj'if windows else relative.replace('/','_')[:-2]+'.o')
        inventory.append(objects.pop(relative,fallback))
    assert not objects,objects
    inventory.append(ROOT/('build/windows/build_windows_assets.s.obj'if windows else'build/obj/build_assets.o'))
    assert all(x.is_file()for x in inventory),[str(x)for x in inventory if not x.is_file()]
    exe=folder/(('host-native-normal.exe'if normal else'host-native-fault.exe')if windows else'host-native-fault')
    if windows:
        libs=sorted((ROOT/'build/windows').glob('*.lib'))
        command=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,ROOT/'build/windows/rhun.res',*libs]
    elif mac:command=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:command=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    bounded_tool(command)
    return exe

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--windows',action='store_true');p.add_argument('--normal',action='store_true');a=p.parse_args();print(build(a.out.resolve(),a.windows,a.normal))
