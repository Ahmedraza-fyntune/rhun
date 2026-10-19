"""Private raw allocator fixture links against coherent runtime objects."""
import argparse
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests'))
from fixture_exchange import FixtureExchange

def run_tool(command):
    with FixtureExchange([str(x)for x in command],timeout=30,output_bound=32768,error_bound=65536)as exchange:
        out,err=exchange.finish()
        if exchange.process.returncode:raise RuntimeError(str(command[0])+" failed\n"+err.decode('utf-8','replace'))

def build(folder, windows=False, runtime_root=None, mutation=None):
    folder.mkdir(parents=True,exist_ok=True)
    runtime=Path(runtime_root or ROOT).resolve()
    mem=(ROOT/'src/mem.s').read_text()
    assert mem.count('FN os_map_try\n')==1
    mem=mem.replace('FN os_map_try\n','FN mu_map_real\n',1)
    mem+='\n.globl free_lists, chunk_ptr, chunk_end\n'
    needle='.Lmf_large:\n';assert mem.count(needle)==1
    mem=mem.replace(needle,needle+'''    inc qword ptr [rip + mu_unmap_calls]
    cmp qword ptr [rip + mu_fail_unmap], 0
    je 8f
    dec qword ptr [rip + mu_fail_unmap]
    mov rax, -5
    ret
8:
''',1)
    if mutation=='raw-clears':
        needle='    jne .Lma_small_ready\n';assert mem.count(needle)==1
        mem=mem.replace(needle,'    # mutation: raw allocation also clears\n',1)
    elif mutation=='zero-skips':
        needle='    jne .Lma_small_ready\n';assert mem.count(needle)==1
        mem=mem.replace(needle,'    jmp .Lma_small_ready\n',1)
    elif mutation=='raw-census':
        needle='.Lma_small_ready:\n';assert mem.count(needle)==1
        mem=mem.replace(needle,needle+'    cmp qword ptr [rsp], 0\n    je 9f\n    dec qword ptr [rip + g_mem_live]\n9:\n',1)
    elif mutation=='ordinary-entry-skips':
        needle='    call .Lma_begin\n';assert mem.count(needle)==1
        mem=mem.replace(needle,'    call mem_alloc_uninit_try\n',1)
    elif mutation=='raw-bump-clears':
        needle='.Lma_take:\n';assert mem.count(needle)==1
        mem=mem.replace(needle,needle+'    mov qword ptr [rsp], 0\n',1)
    elif mutation=='raw-large-clears':
        needle='    add rax, 16\n    inc qword ptr [rip + g_mem_live]\n';assert mem.count(needle)==1
        mem=mem.replace(needle,'    add rax, 16\n    cmp qword ptr [rsp], 0\n    je 9f\n    mov r8, rax\n    mov rdi, rax\n    lea rcx, [rbx - 16]\n    xor eax, eax\n    rep stosb\n    mov rax, r8\n9:  inc qword ptr [rip + g_mem_live]\n',1)
    elif mutation=='raw-callee':
        needle='FN mem_alloc_uninit_try\n';assert mem.count(needle)==1
        mem=mem.replace(needle,needle+'    xor r13d, r13d\n',1)
    elif mutation is not None:raise ValueError(mutation)
    sources={'src/mem.s':mem,'fixture.s':(ROOT/'tests/faults/mem_uninit.s').read_text()}
    mac=sys.platform=='darwin' and not windows
    if windows:
        spec=importlib.util.spec_from_file_location('mu_windows',ROOT/'tools/build-windows.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        mc,linker=module.tool('llvm-mc'),module.tool('lld-link')
    objects={}
    for name,source in sources.items():
        path=folder/name.replace('/','_');obj=path.with_suffix('.obj' if windows else '.o')
        if windows:source=re.sub(r'(?m)^(\s*\.section) \.rodata[^\n]*',r'\1 .rdata,"dr"',source)
        path.write_text(source)
        if windows:cmd=[mc,'-triple=x86_64-pc-windows-msvc','-filetype=obj','-defsym=WINDOWS=1','-I',ROOT/'src','-I',ROOT/'src/win','-I',runtime/'build/windows','-o',obj,path]
        elif mac:
            translated=path.with_suffix('.a64.s')
            run_tool([sys.executable,ROOT/'tools/arm64.py','-I',ROOT/'src','-D','MACOS',path,translated])
            cmd=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',obj,translated]
        else:cmd=['as','--64','-I',ROOT/'src','-I',runtime/'build','-o',obj,path]
        run_tool(cmd);objects[name]=obj
    inventory=[objects.pop('fixture.s')]
    excluded={'src/main.s'}
    if mac or windows:excluded|={'src/start.s','src/plat/wayland.s','src/plat/x11.s','src/plat/appearance.s'}
    for path in sorted((ROOT/'src').rglob('*.s')):
        rel=path.relative_to(ROOT).as_posix()
        if rel in excluded or('win'in path.relative_to(ROOT).parts and not windows)or('mac'in path.relative_to(ROOT).parts and not mac):continue
        fallback=runtime/('build/windows' if windows else 'build/obj')/(rel.replace('/','_')+'.obj' if windows else rel.replace('/','_')[:-2]+'.o')
        inventory.append(objects.pop(rel,fallback))
    assert not objects,objects
    inventory.append(runtime/('build/windows/build_windows_assets.s.obj' if windows else 'build/obj/build_assets.o'))
    assert len(inventory)==len(set(inventory))
    assert all(p.is_file()for p in inventory),[str(p)for p in inventory if not p.is_file()]
    exe=folder/('mem-uninit.exe' if windows else 'mem-uninit')
    if windows:
        out=runtime/'build/windows'
        cmd=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,out/'rhun.res',*[out/(p.stem+'.lib')for p in sorted((ROOT/'src/win').glob('*.def'))]]
    elif mac:cmd=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:cmd=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    run_tool(cmd)
    return exe

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--runtime-root',type=Path);p.add_argument('--windows',action='store_true');p.add_argument('--mutation',choices=['raw-clears','zero-skips','raw-census','ordinary-entry-skips','raw-bump-clears','raw-large-clears','raw-callee']);a=p.parse_args()
    print(build(a.out.resolve(),a.windows,a.runtime_root,a.mutation))
