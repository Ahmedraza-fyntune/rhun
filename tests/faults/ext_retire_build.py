"""Fault links preserve real allocator metadata and exercise explicit native close dispositions."""
import importlib.util
from pathlib import Path
import re
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests'))
from fixture_exchange import FixtureExchange

def bounded_tool(command):
    with FixtureExchange([str(x)for x in command],timeout=30,output_bound=32768,error_bound=65536)as e:
        out,err=e.finish()
        assert e.process.returncode==0,(command,e.process.returncode,out,err)

def build(folder,windows=False):
    folder.mkdir(parents=True,exist_ok=True)
    mem=(ROOT/'src/mem.s').read_text()
    old='.Lmf_large:\n';assert mem.count(old)==1
    mem=mem.replace(old,''' .Lmf_large:
    inc qword ptr [rip + rf_unmap_calls]
    cmp qword ptr [rip + rf_fail_unmap], 0
    je 8f
    dec qword ptr [rip + rf_fail_unmap]
    mov rax, -5
    ret
8:
''',1)
    path=(ROOT/'src/app/extvalidatepath.s').read_text()
    old='FN ext_root_close\n';assert path.count(old)==1
    path=path.replace(old,'FN rf_native_close_real\n',1)
    wrappers='''
FN ext_root_close
    inc qword ptr [rip + rf_native_calls]
    cmp qword ptr [rip + rf_mode], 2
    je 2f
    cmp qword ptr [rip + rf_mode], 3
    je 3f
    cmp qword ptr [rip + rf_mode], 1
    jne rf_native_close_real
    cmp qword ptr [rip + rf_native_calls], 1
    jne 4f
    mov rax, -5
    xor edx, edx
    ret
2:  mov rax, -5
    mov edx, 2
    ret
3:  mov rax, -5
    mov edx, 1
    ret
4:  xor eax, eax
    mov edx, 1
    ret
'''
    stat_name='src/win/extvalidatepath.s'if windows else'src/app/extvalidatepath.s'
    stat_symbol='win_ext_root_stat'if windows else'ext_root_stat'
    stat_source=(ROOT/stat_name).read_text()if windows else path
    old='FN '+stat_symbol+'\n';assert stat_source.count(old)==1
    stat_source=stat_source.replace(old,'FN rf_stat_real\n',1)
    wrappers+='''
FN '''+stat_symbol+'''
    cmp qword ptr [rip + rf_stat_fault], 0
    je rf_stat_real
    mov qword ptr [rip + rf_stat_fault], 0
    mov rax, -5
    ret
'''
    replacements={'src/mem.s':mem,'src/app/extvalidatepath.s':path,stat_name:stat_source,'fixture.s':(ROOT/'tests/ext_prepare_retire_fault_test.s').read_text()+wrappers}
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
    exe=folder/('retire-fault.exe'if windows else'retire-fault')
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
