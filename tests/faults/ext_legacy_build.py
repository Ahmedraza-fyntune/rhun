"""Focused pure-import allocation and forbidden-IO native fixture links in a built isolated tree."""
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]

def build(folder,windows=False,deferred=False):
    folder.mkdir(parents=True,exist_ok=True)
    replacements={}
    calls={
      'src/app/extvalidatepath.s':['ext_root_open','ext_root_open_at','ext_root_reopen_dir','ext_root_reopen_dir_into','ext_root_stat','ext_root_read','ext_root_read_once','ext_root_close'],
      'src/app/extpreparelegacypath.s':['prep_legacy_open_at','prep_legacy_open_absolute','prep_legacy_open_relative','prep_legacy_access','prep_legacy_runtime_resolve'],
      'src/app/extprepareruntime.s':['prep_runtime_resolve'],
    }
    wrappers=['\n.text\n']
    for name,symbols in calls.items():
        source=(ROOT/name).read_text()
        for symbol in symbols:
            old='FN '+symbol+'\n';assert source.count(old)==1,(name,symbol)
            source=source.replace(old,'FN elip_real_'+symbol+'\n')
            wrappers.append('FN '+symbol+'\n    inc qword ptr [rip + eli_io_calls]\n    mov rax, -5\n    xor edx, edx\n    ret\n')
        replacements[name]=source
    source=(ROOT/'src/mem.s').read_text();old='FN mem_alloc_try\n';assert source.count(old)==1
    replacements['src/mem.s']=source.replace(old,'FN elip_real_mem_alloc_try\n')
    wrappers.append('''FN mem_alloc_try
    cmp qword ptr [rip + eli_armed], 1
    jne elip_real_mem_alloc_try
    inc qword ptr [rip + eli_alloc_count]
    mov rax, [rip + eli_fail_at]
    cmp rax, [rip + eli_alloc_count]
    jne elip_real_mem_alloc_try
    xor eax, eax
    ret
''')
    replacements['fixture.s']=(ROOT/('tests/ext_prepare_legacy_deferred_test.s' if deferred else 'tests/ext_prepare_legacy_import_test.s')).read_text()+''.join(wrappers)
    mac=sys.platform=='darwin'and not windows
    if windows:
        spec=importlib.util.spec_from_file_location('legacy_win_build',ROOT/'tools/build-windows.py')
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
            subprocess.run([sys.executable,ROOT/'tools/arm64.py','-I',ROOT/'src','-D','MACOS',path,translated],check=True)
            command=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',obj,translated]
        else:command=['as','--64','-I',ROOT/'src','-I',ROOT/'build','-o',obj,path]
        subprocess.run(command,check=True);objects[relative]=obj
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
    exe=folder/('legacy-import-fault.exe'if windows else'legacy-import-fault')
    if windows:
        libs=sorted((ROOT/'build/windows').glob('*.lib'))
        command=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,ROOT/'build/windows/rhun.res',*libs]
    elif mac:command=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:command=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    subprocess.run(command,check=True)
    return exe

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--windows',action='store_true');a=p.parse_args();print(build(a.out.resolve(),a.windows))
