"""Bounded cross-platform host consumed/retained/unknown cleanup matrix."""
import importlib.util
from pathlib import Path
import re
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/faults'))
from ext_retire_build import bounded_tool

def build(folder,windows=False):
    folder.mkdir(parents=True,exist_ok=True)
    fixture=(ROOT/'tests/ext_keeper_host_fault_test.inc').read_text()
    source=(ROOT/'src/app/exthostretire.s').read_text()
    for old,new in [('call keeper_poll','call hf_poll'),('call keeper_cleanup_info','call hf_info_get'),('call keeper_close_checked','call hf_close'),('SYS SYS_read','call hf_read')]:
        assert old in source,old
        source=source.replace(old,new)
    close=(ROOT/'src/app/exthostcloseat.s').read_text()
    assert close.count('call ext_fd_close_checked')==1
    close=close.replace('call ext_fd_close_checked','call hf_fd_close')
    host=(ROOT/'src/app/ext.s').read_text()
    host=host.replace('call proc_wait','call hf_wait').replace('SYS SYS_kill','call hf_kill')
    a=host.index('FN ext_shutdown\n');b=host.index('FN ext_status_draw\n',a)
    host=host[:a]+host[a:b].replace('call loop_poll','call hf_loop')+host[b:]
    a=host.index('ext_prepare_supervised:\n');b=host.index('# build_argv(',a)
    part=host[a:b]
    for old,new in [('call ext_activation_host_check','call hf_activation_check'),('call keeper_extension_auth','call hf_auth'),('call keeper_prepare','call hf_prepare'),('call mem_free','call hf_auth_free')]:
        assert part.count(old)==1,old
        part=part.replace(old,new)
    host=host[:a]+part+host[b:]
    host+='\n.text\nFN hf_prepare_call\n    jmp ext_prepare_supervised\n'
    replacements={'src/app/exthostretire.s':source,'src/app/exthostcloseat.s':close,'src/app/ext.s':host,'fixture.s':fixture}
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
    exe=folder/('keeper-host-fault.exe'if windows else'keeper-host-fault')
    if windows:
        libs=sorted((ROOT/'build/windows').glob('*.lib'))
        command=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,ROOT/'build/windows/rhun.res',*libs]
    elif mac:command=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:command=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    bounded_tool(command)
    return exe

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--windows',action='store_true');a=p.parse_args();print(build(a.out.resolve(),a.windows))
