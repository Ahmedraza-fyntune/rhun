"""Activation constructor allocation/no-IO faults and retained supplier-drop outcomes."""
import importlib.util
from pathlib import Path
import re
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/faults'))
from ext_retire_build import bounded_tool

def build(folder,windows=False,audit=False,mutation=None):
    folder.mkdir(parents=True,exist_ok=True)
    fixture=(ROOT/'tests/ext_activation_owner_test.s').read_text()
    start=fixture.index('FN main\n');end=fixture.index('\naf_new:\n',start)
    fixture=fixture[:start]+(ROOT/'tests/ext_activation_fault_main.inc').read_text()+fixture[end:]
    fixture+='\n.bss\n.p2align 3\naf_armed: .quad 0\naf_alloc_calls: .quad 0\naf_fail_at: .quad 0\naf_mark_fault: .quad 0\naf_drop_mode: .quad 0\naf_io_calls: .quad 0\n.text\n'
    replacements={}
    mem=(ROOT/'src/mem.s').read_text();assert mem.count('FN mem_alloc_try\n')==1
    replacements['src/mem.s']=mem.replace('FN mem_alloc_try\n','FN af_real_mem_alloc_try\n',1)
    fixture+="""FN mem_alloc_try
    cmp qword ptr [rip + af_armed], 1
    jne af_real_mem_alloc_try
    inc qword ptr [rip + af_alloc_calls]
    mov rax, [rip + af_alloc_calls]
    cmp rax, [rip + af_fail_at]
    jne af_real_mem_alloc_try
    xor eax, eax
    ret
"""
    source=(ROOT/'src/app/extprepareretirecustom.s').read_text();symbol='ext_prepare_retire_mark_custom_po'
    assert source.count('FN '+symbol+'\n')==1
    replacements['src/app/extprepareretirecustom.s']=source.replace('FN '+symbol+'\n','FN af_real_mark\n',1)
    fixture+="""FN ext_prepare_retire_mark_custom_po
    cmp qword ptr [rip + af_mark_fault], 0
    je af_real_mark
    mov qword ptr [rip + af_mark_fault], 0
    mov rax, -22
    ret
"""
    source=(ROOT/'src/app/extprepareretirequeue.s').read_text();symbol='ext_prepare_release_deferred'
    assert source.count('FN '+symbol+'\n')==1
    replacements['src/app/extprepareretirequeue.s']=source.replace('FN '+symbol+'\n','FN af_real_ep_drop\n',1)
    fixture+="""FN ext_prepare_release_deferred
    cmp qword ptr [rip + af_drop_mode], 1
    je 1f
    cmp qword ptr [rip + af_drop_mode], 2
    jne af_real_ep_drop
    mov qword ptr [rip + af_drop_mode], 0
    PROLOGUE
    call af_real_ep_drop
    cmp rdx, 1
    jne 2f
    mov rax, -5
2:  EPILOGUE
1:  mov qword ptr [rip + af_drop_mode], 0
    mov rax, -5
    xor edx, edx
    ret
"""
    source=(ROOT/'src/app/extvalidatepath.s').read_text()
    for symbol in ('ext_root_open','ext_root_open_at','ext_root_reopen_dir','ext_root_reopen_dir_into','ext_root_stat','ext_root_identity','ext_root_read','ext_root_read_once','ext_root_close'):
        assert source.count('FN '+symbol+'\n')==1,symbol
        source=source.replace('FN '+symbol+'\n','FN af_real_'+symbol+'\n',1)
        fixture+='FN '+symbol+'\n    cmp qword ptr [rip + af_armed], 1\n    jne af_real_'+symbol+'\n    inc qword ptr [rip + af_io_calls]\n    mov rax, -5\n    xor edx, edx\n    ret\n'
    replacements['src/app/extvalidatepath.s']=source
    if audit:
        fixture=fixture.replace('    cmp r12d, 6\n    ja .Laf_fault_bad','    cmp r12d, 7\n    ja .Laf_fault_bad',1)
        a='3:  mov qword ptr [rip + af_armed], 1';assert fixture.count(a)==1;fixture=fixture.replace(a,'3:  cmp r12d, 7\n    jne 31f\n    mov qword ptr [rip + eia_admit_fail_at], 2\n31: mov qword ptr [rip + af_armed], 1',1)
        a='    mov qword ptr [rip + af_armed], 0\n    cmp qword ptr [rip + af_io_calls], 0';assert fixture.count(a)==1
        fixture=fixture.replace(a,'    mov qword ptr [rip + af_armed], 0\n    cmp qword ptr [rip + af_io_calls], 0\n    jne eia_bad\n    cmp r12d, 1\n    jne 32f\n    cmp qword ptr [rip + eia_drop_calls], 0\n    jne eia_bad\n    jmp 33f\n32: cmp qword ptr [rip + eia_drop_calls], 1\n    jne eia_bad\n33: cmp r12d, 7\n    jne 34f\n    test rax, rax\n    jnz eia_bad\n    cmp rdx, -EV_RESOURCE\n    jne eia_bad\n    jmp 9f\n34: cmp qword ptr [rip + af_io_calls], 0',1)
        path='src/app/extprepareretirequeue.s';a='FN ext_prepare_owner_release_deferred\n';assert replacements[path].count(a)==1;replacements[path]=replacements[path].replace(a,'FN eia_real_eo_release\n',1)
        path='src/app/extprepareretirealloc.s';text=(ROOT/path).read_text();a='FN prep_global_admit\n';assert text.count(a)==1;replacements[path]=text.replace(a,'FN eia_real_global_admit\n',1)
        # Audit the current constructor/owner primitives, never cached product copies.
        # Each replacement is assembled below against the current include files.
        for rel in ['src/app/extactivationcreate.s','src/app/extactivationwire.s','src/app/extactivation.s','src/app/extpreparemem.s','src/app/extprepareretirestep.s']:
            replacements.setdefault(rel,(ROOT/rel).read_text())
        fixture+='\n'+(ROOT/'tests/ext_activation_eo_audit.inc').read_text()
        if mutation=='missing-drop':
            path='src/app/extactivationcreate.s';text=replacements[path];a='    call ext_prepare_owner_release_deferred';assert text.count(a)==1;replacements[path]=text.replace(a,'    nop',1)
        elif mutation is not None:raise ValueError('unknown audit mutation')
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
    exe=folder/('activation-fault.exe'if windows else'activation-fault')
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
