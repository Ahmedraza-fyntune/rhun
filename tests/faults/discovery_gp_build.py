"""Exact-inventory private typed-GP fixture, coherent borrowed runtime objects."""
import argparse,importlib.util,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests'))
from fixture_exchange import FixtureExchange

def run_tool(command):
    with FixtureExchange([str(x)for x in command],timeout=30,output_bound=32768,error_bound=65536)as exchange:
        out,err=exchange.finish()
        if exchange.process.returncode:raise RuntimeError(str(command[0])+" failed\n"+err.decode('utf-8','replace'))

def build(folder,fixture,windows=False,runtime_root=None,instrument=False,mutation=None):
    folder=Path(folder).resolve();folder.mkdir(parents=True,exist_ok=True)
    runtime=Path(runtime_root or ROOT).resolve()
    sources={'fixture.s':fixture}
    for name in ('extdiscoverygpvalidate','extdiscoverygprecord','extdiscoverygpstring','extdiscoverygpword','extdiscoverygpprobe'):
        rel='src/app/'+name+'.s';sources[rel]=(ROOT/rel).read_text()
    if instrument:
        key='src/app/extdiscoverygpvalidate.s'
        source=sources[key]
        source=source.replace('    movzx eax, byte ptr [rsi]', '    movzx eax, byte ptr [rsi]\n    inc qword ptr [rip + gpc_byte_actual]',1)
        source=source.replace('    mov [rsi], dl','    mov [rsi], dl\n    inc qword ptr [rip + gpc_byte_actual]',1)
        sources[key]=source
        key='src/app/extdiscoverygprecord.s'
        sources[key]=sources[key].replace('    call is_ident','    inc qword ptr [rip + gpc_byte_actual]\n    call is_ident',1)
        for key,source in sources.items():
            if key=='fixture.s':continue
            source=source.replace('inc qword ptr [rbx + GPC_units]','inc qword ptr [rip + gpc_unit_actual]\n    inc qword ptr [rbx + GPC_units]')
            source=source.replace('    add qword ptr [rbx + GPC_units], 9','    add qword ptr [rip + gpc_unit_actual], 9\n    add qword ptr [rbx + GPC_units], 9')
            sources[key]=source
        fold=(ROOT/'src/casefold.s').read_text()
        assert fold.count('    cmp edi, [r8 + r10 + 4]')==1
        assert fold.count('3:  shl ecx, 4')==1
        fold=fold.replace('    cmp edi, [r8 + r10 + 4]','    inc qword ptr [rip + gpc_fold_actual]\n    cmp edi, [r8 + r10 + 4]')
        fold=fold.replace('3:  shl ecx, 4','3:  inc qword ptr [rip + gpc_fold_actual]\n    shl ecx, 4')
        sources['src/casefold.s']=fold
    for key,source in sources.items():
        if not key.startswith('src/app/extdiscoverygp'):continue
        assert not re.search(r'(?m)^\s*(?:SYS|rep|syscall|int)\b',source), key
        calls=re.findall(r'(?m)^\s*call\s+(\w+)',source)
        assert all(name.startswith('pg_') or name in ('case_fold','is_ident') for name in calls), (key,calls)
    if instrument:
        # Actual native/source/parser/allocator guards are enabled only during each GPC step.
        poisoned={
            'src/lib.s':('strlen','str_eq','str_eq_cstr','str_ieq','utf8_decode'),
            'src/mem.s':('mem_alloc','mem_alloc_try','mem_alloc_uninit_try'),
            'src/sys.s':('file_open_read','file_read_all','file_read_limited','write_all'),
            'src/app/extpreparegrammar.s':('grammar_parse_prepare','grammar_parse_prepare_legacy'),
            'src/app/extpreparemem.s':('prep_object_create','prep_owned_alloc'),
            'src/ini.s':('next_word',),
        }
        guard='    cmp qword ptr [rip + gpc_active], 0\n    je 991f\n    inc qword ptr [rip + gpc_forbidden_actual]\n    xor eax, eax\n    ret\n991:\n'
        for key,names in poisoned.items():
            source=(ROOT/key).read_text()
            for name in names:
                target='FN '+name+'\n'
                assert source.count(target)==1,(key,name)
                source=source.replace(target,target+guard,1)
            sources[key]=source
    if mutation:
        key,before,after=mutation
        assert sources[key].count(before)>0,(key,before)
        sources[key]=sources[key].replace(before,after,1)
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
        if windows:cmd=[mc,'-triple=x86_64-pc-windows-msvc','-filetype=obj','-defsym=WINDOWS=1','-I',folder,'-I',ROOT/'src','-I',ROOT/'src/win','-I',runtime/'build/windows','-o',obj,path]
        elif mac:
            translated=path.with_suffix('.a64.s')
            run_tool([sys.executable,ROOT/'tools/arm64.py','-I',folder,'-I',ROOT/'src','-D','MACOS',path,translated])
            cmd=['as','-arch','arm64','-mmacosx-version-min=12.0','-o',obj,translated]
        else:cmd=['as','--64','-I',folder,'-I',ROOT/'src','-I',runtime/'build','-o',obj,path]
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
    exe=folder/('discovery-gp.exe' if windows else 'discovery-gp')
    if windows:
        out=runtime/'build/windows'
        cmd=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,out/'rhun.res',*[out/(p.stem+'.lib')for p in sorted((ROOT/'src/win').glob('*.def'))]]
    elif mac:cmd=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:cmd=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    run_tool(cmd)
    return exe

