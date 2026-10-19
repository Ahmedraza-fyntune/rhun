"""Exact-inventory private typed-GP fixture, coherent borrowed runtime objects."""
import argparse,importlib.util,re,sys,shutil
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
    api=(ROOT/'tests/faults/discovery_gp_transfer_api.inc').read_text()
    fixture=fixture.replace('.include \"discovery-gp-transfer-api.inc\"',api)
    sources={'fixture.s':fixture}
    for name in ('extdiscoverygpvalidate','extdiscoverygprecord','extdiscoverygpstring','extdiscoverygpword','extdiscoverygpprobe','extdiscoverygpexport','extdiscoverygpemit','extdiscoverygpimport','extdiscoverygprelocate'):
        rel='src/app/'+name+'.s';sources[rel]=(ROOT/rel).read_text()
    if instrument:
        for key in list(sources):
            source=sources[key]
            if key.endswith('extdiscoverygpexport.s'):
                source=source.replace('    movzx eax, byte ptr [rsi]', '    movzx eax, byte ptr [rsi]\n    inc qword ptr [rip + xfer_byte_actual]')
                source=source.replace('    mov [rsi], dl','    mov [rsi], dl\n    inc qword ptr [rip + xfer_byte_actual]')
            if key.endswith('extdiscoverygpemit.s'):
                source=source.replace('    mov [rax], dl','    mov [rax], dl\n    inc qword ptr [rip + xfer_byte_actual]\n    inc qword ptr [rip + xfer_output_actual]')
            if key.endswith('extdiscoverygprelocate.s'):
                source=source.replace('    movzx eax, byte ptr [rsi]','    movzx eax, byte ptr [rsi]\n    inc qword ptr [rip + xfer_byte_actual]')
                source=source.replace('    mov [r13 + rcx], al','    mov [r13 + rcx], al\n    inc qword ptr [rip + xfer_byte_actual]')
                source=source.replace('    mov [r12 + r14], al','    mov [r12 + r14], al\n    inc qword ptr [rip + xfer_byte_actual]')
            if key.startswith('src/app/extdiscoverygp'):
                source=re.sub(r'(?m)^(    inc qword ptr \[r(?:bx|di) \+ (?:PGE|PGI)_units\])$',r'    inc qword ptr [rip + xfer_unit_actual]\n\1',source)
                source=re.sub(r'(?m)^(    mov qword ptr \[r(?:bx|di) \+ (?:PGE|PGI)_units\], ([1-9][0-9]*))$',r'    add qword ptr [rip + xfer_unit_actual], \2\n\1',source)
            sources[key]=source
        source=(ROOT/'src/lib.s').read_text()
        source=source.replace('FN memcpy\n','FN memcpy\n    cmp qword ptr [rip + xfer_active], 3\n    jne 991f\n    add [rip + xfer_byte_actual], rdx\n    add [rip + xfer_byte_actual], rdx\n991:\n',1)
        source=source.replace('FN memset\n','FN memset\n    cmp qword ptr [rip + xfer_active], 3\n    jne 991f\n    add [rip + xfer_byte_actual], rdx\n991:\n',1)
        poisoned={'src/lib.s':('strlen','str_eq','str_eq_cstr','str_ieq','utf8_decode'), 'src/sys.s':('file_open_read','file_read_all','file_read_limited','write_all'), 'src/app/extpreparegrammar.s':('grammar_parse_prepare','grammar_parse_prepare_legacy'), 'src/app/extpreparemem.s':('prep_object_create','prep_owned_alloc'), 'src/ini.s':('next_word',)}
        guard='    cmp qword ptr [rip + xfer_active], 0\n    je 992f\n    inc qword ptr [rip + xfer_forbidden_actual]\n    xor eax, eax\n    ret\n992:\n'
        for key,names in poisoned.items():
            text=source if key=='src/lib.s' else (ROOT/key).read_text()
            for name in names:
                text=text.replace('FN '+name+'\n','FN '+name+'\n'+guard,1)
            sources[key]=text
        mem=(ROOT/'src/mem.s').read_text()
        needle='.Lmf_large:\n'
        assert mem.count(needle)==1
        mem=mem.replace(needle,needle+"    inc qword ptr [rip + xfer_unmap_actual]\n    cmp qword ptr [rip + xfer_fail_unmap], 0\n    je 993f\n    dec qword ptr [rip + xfer_fail_unmap]\n    mov [rip + xfer_fail_raw], rdi\n    mov [rip + xfer_fail_charge], rcx\n    mov rax, [rdi]\n    mov [rip + xfer_fail_next], rax\n    mov rax, [rdi + 8]\n    mov [rip + xfer_fail_aocharge], rax\n    mov rax, [rip + prep_total_charge]\n    mov [rip + xfer_fail_total], rax\n    mov rax, [rip + xfer_fail_eo]\n    mov rax, [rax + EO_used]\n    mov [rip + xfer_fail_used], rax\n    mov rax, [rip + g_mem_live]\n    inc rax\n    mov [rip + xfer_fail_live], rax\n    mov rax, -5\n    ret\n993:\n",1)
        guard='    cmp qword ptr [rip + xfer_active], 0\n    je 994f\n    inc qword ptr [rip + xfer_forbidden_actual]\n    xor eax, eax\n    ret\n994:\n'
        for name in ('mem_alloc','mem_alloc_try','mem_realloc','vec_push'):
            mem=mem.replace('FN '+name+'\n','FN '+name+'\n'+guard,1)
        rawguard='    cmp qword ptr [rip + xfer_active], 0\n    je 995f\n    cmp qword ptr [rip + xfer_active], 3\n    jne 996f\n    cmp qword ptr [rip + pgi + PGI_phase], PGI_ACQUIRE_GP\n    je 995f\n    cmp qword ptr [rip + pgi + PGI_phase], PGI_ACQUIRE_BLOB\n    je 995f\n996: inc qword ptr [rip + xfer_forbidden_actual]\n    xor eax, eax\n    ret\n995:\n'
        mem=mem.replace('FN mem_alloc_uninit_try\n','FN mem_alloc_uninit_try\n'+rawguard,1)
        sources['src/mem.s']=mem.replace('.include \"rhun.inc\"', '.include \"rhun.inc\"\n.include \"app/extprepare.inc\"\n.include \"app/extdiscoverygpxfer.inc\"',1)
        source=(ROOT/'src/app/extvalidatepath.s').read_text()
        assert source.count('FN ext_root_close\n')==1
        sources['src/app/extvalidatepath.s']=source.replace('FN ext_root_close\n','FN xfer_close_real\n',1)
        for name in ('extdiscoveryalloc','extdiscoveryenroll'):
            key='src/app/'+name+'.s'
            sources[key]=(ROOT/key).read_text()
        for key,fn,code,phase,prefix,returns_pointer in [
            ('src/app/extdiscoveryalloc.s','pd_alloc_zero','h','PGI_ZERO_GP','',False),
            ('src/app/extdiscoveryalloc.s','pd_alloc_zero','i','PGI_ZERO_AO','',False),
            ('src/app/extdiscoveryalloc.s','pd_alloc_copy','j','PGI_COPY_BLOB','',False),
            ('src/app/extdiscoveryenroll.s','pd_alloc_enroll_gp','k','PGI_ENROLL_GP','',True),
            ('src/app/extdiscoveryenroll.s','pd_alloc_enroll_member','m','PGI_ENROLL_BLOB','',True),
        ]:
            guard=f"    cmp qword ptr [rip + xfer_active], 3\n    jne 997f\n    cmp qword ptr [rip + xfer_fault], '{code}'\n    jne 997f\n    cmp qword ptr [rip + pgi + PGI_phase], {phase}\n    jne 997f\n"
            if code in ('h','i'):
                guard+="    mov rax, rsi\n    shl rax, 6\n    cmp qword ptr [rdi + rax + DIA_slots + DTS_initialized], 0\n    je 997f\n"
            if code=='j':guard+="    cmp qword ptr [rip + pgi + PGI_cursor], 0\n    je 997f\n"
            guard+="    inc qword ptr [rip + xfer_inject_actual]\n"
            guard+=("    xor eax, eax\n    mov rdx, -5\n" if returns_pointer else "    mov rax, -5\n")+"    ret\n997:\n"
            sources[key]=sources[key].replace('FN '+fn+'\n','FN '+fn+'\n'+guard,1)
        for key in ('src/app/extdiscoveryalloc.s','src/app/extdiscoveryenroll.s'):
            sources[key]=sources[key].replace('.include \"rhun.inc\"','.include \"rhun.inc\"\n.include \"app/extdiscoverygpxfer.inc\"',1)
        guard="    cmp qword ptr [rip + xfer_active], 3\n    jne 998f\n    cmp qword ptr [rip + xfer_fault], 'd'\n    jne 1f\n    cmp qword ptr [rip + pgi + PGI_phase], PGI_ACQUIRE_GP\n    je 2f\n1:  cmp qword ptr [rip + xfer_fault], 'e'\n    jne 998f\n    cmp qword ptr [rip + pgi + PGI_phase], PGI_ACQUIRE_BLOB\n    jne 998f\n2:  inc qword ptr [rip + xfer_inject_actual]\n    xor eax, eax\n    ret\n998:\n"
        sources['src/mem.s']=sources['src/mem.s'].replace('FN mem_alloc_uninit_try\n','FN mem_alloc_uninit_try\n'+guard,1)
        sources['src/app/syntax.s']=(ROOT/'src/app/syntax.s').read_text()+'\nFN xfer_native_word_slot\n    jmp gr_word_slot\n'
    if mutation:
        key,before,after=mutation
        assert sources[key].count(before)>0,(key,before)
        sources[key]=sources[key].replace(before,after,1)
    fixture=sources['fixture.s']
    checked=sorted(set(re.findall(r'(?m)^    call (pg_(?:import|export)_\w+)$',fixture)))
    for fn in checked:
        fixture=fixture.replace('    call '+fn+'\n','    call xfer_abi_'+fn+'\n')
        fixture+='\nFN xfer_abi_'+fn+'\n    PROLOGUE 32\n'
        values=[('rbx',0x1020304050607080),('r12',0x2030405060708090),('r13',0x3040506070809010),('r14',0x4050607080901020),('r15',0x5060708090102030)]
        for reg,value in values:fixture+=f'    mov {reg}, {value}\n'
        fixture+='    call '+fn+'\n    mov [rsp], rax\n    mov [rsp + 8], rdx\n    mov [rsp + 16], rcx\n    mov [rsp + 24], r8\n'
        for reg,value in values:fixture+=f'    mov r10, {value}\n    cmp {reg}, r10\n    jne .Lxfer_abi_fail\n'
        fixture+='    mov rax, [rsp]\n    mov rdx, [rsp + 8]\n    mov rcx, [rsp + 16]\n    mov r8, [rsp + 24]\n    EPILOGUE\n'
    fixture+='\n.Lxfer_abi_fail:\n    mov edi, 73\n    SYS SYS_exit_group\n'
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

