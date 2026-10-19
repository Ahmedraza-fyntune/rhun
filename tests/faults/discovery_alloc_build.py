"""Private charged construction fixture links against coherent runtime objects."""
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
    mem=mem.replace('FN os_map_try\n','FN da_map_real\n',1)
    assert mem.count('FN mem_alloc_uninit_try\n')==1
    mem=mem.replace('FN mem_alloc_uninit_try\n','FN da_alloc_real\n',1)
    needle='.Lmf_large:\n';assert mem.count(needle)==1
    mem=mem.replace(needle,needle+'''    inc qword ptr [rip + da_unmap_calls]
    cmp qword ptr [rip + da_fail_unmap], 0
    je 8f
    dec qword ptr [rip + da_fail_unmap]
    mov rax, -5
    ret
8:
''',1)
    sources={'src/mem.s':mem,'fixture.s':(ROOT/'tests/faults/discovery_alloc.s').read_text()}
    for stem in ('extdiscoveryalloc','extdiscoveryenroll','extdiscoveryallocretire'):
        name='src/app/'+stem+'.s';sources[name]=(ROOT/name).read_text()
    mutations={
        'extra-commit':('src/app/extdiscoveryalloc.s','    add [rip + discovery_extra_charge], rdx\n',''),
        'extra-release':('src/app/extdiscoveryallocretire.s','    sub [rip + discovery_extra_charge], rax\n',''),
        'prep-transfer':('src/app/extdiscoveryenroll.s','    add [rip + prep_total_charge], rcx\n',''),
        'member-link':('src/app/extdiscoveryenroll.s','    mov [r14 + PO_allocs], r15\n',''),
        'owner-deferred':('src/app/extdiscoveryenroll.s','    mov qword ptr [r15 + EO_deferred], 1\n',''),
        'ep-default':('src/app/extdiscoveryenroll.s','    mov qword ptr [r15 + EP_root], -1\n',''),
        'setting-publish':('src/app/extdiscoveryenroll.s','    inc qword ptr [rcx + EP_ext + EXT_sdefs + VEC_len]\n',''),
        'binding-reset':('src/app/extdiscoveryenroll.s','    mov qword ptr [rdi + DIA_settings], 0\n',''),
        'gp-move':('src/app/extdiscoveryenroll.s','    mov qword ptr [rdi + DIA_gp], 0\n',''),
        'retained-charge':('src/app/extdiscoveryallocretire.s','5:  mov [r15 + DTS_due], rax\n','5:  mov [r15 + DTS_due], rax\n    mov qword ptr [rip + discovery_extra_charge], 0\n'),
        'quarantine-retry':('src/app/extdiscoveryallocretire.s','    test qword ptr [rbx + DIA_blocked], 2\n','    test qword ptr [rbx + DIA_blocked], 0\n'),
        'copy-state':('src/app/extdiscoveryalloc.s','    call pd_alloc_init_state\n    mov rax, r13\n    EPILOGUE','    mov rax, r13\n    EPILOGUE'),
        'prep-cap':('src/app/extdiscoveryenroll.s','    cmp rax, PREP_TOTAL_CAP\n    ja 8f\n',''),
        'minimum-deadline':('src/app/extdiscoveryallocretire.s','    cmp rdx, r14\n    jae 6f\n','    jmp 6f\n'),
        'copy-prefix':('src/app/extdiscoveryalloc.s','    cmp qword ptr [rbx + DTS_initialized], AO_SIZE\n    jb .Lpda_init_invalid\n',''),
    }
    if mutation is not None:
        name,old,new=mutations[mutation];assert sources[name].count(old)==1,(mutation,sources[name].count(old))
        sources[name]=sources[name].replace(old,new,1)
    queue=(ROOT/'src/app/extprepareretirequeue.s').read_text()
    for old,new in [('ext_prepare_release_deferred','da_release_ep_real'),('grammar_prepare_release_deferred','da_release_gp_real'),('ext_prepare_owner_release_deferred','da_release_eo_real')]:
        needle='FN '+old+'\n';assert queue.count(needle)==1
        queue=queue.replace(needle,'FN '+new+'\n',1)
    sources['src/app/extprepareretirequeue.s']=queue
    allocator=(ROOT/'src/app/extprepareretirealloc.s').read_text()
    needle='FN prep_cleanup_free\n';assert allocator.count(needle)==1
    sources['src/app/extprepareretirealloc.s']=allocator.replace(needle,'FN da_cleanup_free_real\n',1)
    fixture=sources['fixture.s']
    checked=sorted(set(re.findall(r'(?m)^    call (pd_\w+)$',fixture)))
    for fn in checked:
        fixture=fixture.replace('    call '+fn+'\n','    call dac_'+fn+'\n')
        fixture+='\nFN dac_'+fn+'\n    PROLOGUE 32\n'
        values=[('rbx',0x1020304050607080),('r12',0x2030405060708090),('r13',0x3040506070809010),('r14',0x4050607080901020),('r15',0x5060708090102030)]
        for reg,value in values:fixture+=f'    mov {reg}, {value}\n'
        fixture+='    call '+fn+'\n    mov [rsp], rax\n    mov [rsp + 8], rdx\n    mov [rsp + 16], rcx\n'
        for reg,value in values:fixture+=f'    mov r10, {value}\n    cmp {reg}, r10\n    jne .Lda_helper_fail\n'
        fixture+='    mov rax, [rsp]\n    mov rdx, [rsp + 8]\n    mov rcx, [rsp + 16]\n    EPILOGUE\n'
    sources['fixture.s']=fixture
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
    exe=folder/('discovery-alloc.exe' if windows else 'discovery-alloc')
    if windows:
        out=runtime/'build/windows'
        cmd=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,out/'rhun.res',*[out/(p.stem+'.lib')for p in sorted((ROOT/'src/win').glob('*.def'))]]
    elif mac:cmd=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:cmd=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    run_tool(cmd)
    return exe

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--runtime-root',type=Path);p.add_argument('--windows',action='store_true');p.add_argument('--mutation');a=p.parse_args()
    print(build(a.out.resolve(),a.windows,a.runtime_root,a.mutation))
