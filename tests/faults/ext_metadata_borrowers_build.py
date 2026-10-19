"""Link the real hidden-supplier fixture, optionally removing one admission check."""
import importlib.util
from pathlib import Path
import re
import sys
from ext_retire_build import bounded_tool
ROOT=Path(__file__).resolve().parents[2]
MUTATIONS={
    'provider':('src/app/extproviders.s','pp_match_for:','    call ext_has_metadata\n'),
    'icon':('src/app/exticon.s','FN ext_icon\n','    call ext_has_metadata\n'),
    'events':('src/app/extproto.s','FN extproto_events\n','    call ext_has_metadata\n'),
    'options':('src/app/extdocoption.s','FN ext_doc_option\n','    call ext_has_identity\n'),
    'marks':('src/app/extmarks.s','FN extmarks_counts\n','    call ext_has_metadata\n'),
    'command':('src/app/ext.s','FN ext_cmd_live\n','    call ext_has_metadata\n'),
    'titlebar':('src/app/extbar.s','FN extbar_count\n','    call ext_has_identity\n'),
    'mark-display':('src/app/extmarks.s','FN extmarks_line\n','    call mark_visible_flags\n'),
    'mark-bookkeeping':('src/app/extmarks.s','FN ext_note_insert\n',''),
}
def build(folder,windows=False,mutation=None):
    folder.mkdir(parents=True,exist_ok=True)
    replacements={'fixture.s':(ROOT/'tests/ext_metadata_borrowers_test.s').read_text()}
    if mutation:
        relative,start,marker=MUTATIONS[mutation]
        source=(ROOT/relative).read_text()
        if mutation=='mark-bookkeeping':
            marker='    inc rcx\n    mov rdx, [rax + MK_start]'
            pos=source.index(start);head,tail=source[:pos],source[pos:]
            assert marker in tail
            source=head+tail.replace(marker,'    inc rcx\n    call mark_visible_flags\n    jz 2b\n    mov rdx, [rax + MK_start]',1)
        elif mutation=='mark-display':
            pos=source.index(start);head,tail=source[:pos],source[pos:]
            assert marker in tail
            source=head+tail.replace(marker,'    test rax, rax\n',1)
        elif mutation=='events':
            relative='src/app/extproto.s'
            include='    PROLOGUE 16\n    mov rbx, rdi\n    call ext_has_metadata\n'
            events=(ROOT/'src/app/extprotoevents.inc').read_text()
            assert include in events
            events=events.replace(include,include.replace('call ext_has_metadata','mov eax, 1'),1)
            source=source.replace('.include "app/extprotoevents.inc"',events)
        else:
            pos=source.index(start);head,tail=source[:pos],source[pos:]
            assert marker in tail
            source=head+tail.replace(marker,'    mov eax, 1\n',1)
        replacements[relative]=source
    return link(folder,replacements,windows)

def link(folder,replacements,windows=False):
    folder.mkdir(parents=True,exist_ok=True)
    mac=sys.platform=='darwin'and not windows
    if windows:
        spec=importlib.util.spec_from_file_location('metadata_win_build',ROOT/'tools/build-windows.py')
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
    exe=folder/('metadata-borrowers.exe'if windows else'metadata-borrowers')
    if windows:command=[linker,'/nodefaultlib','/entry:win_start','/subsystem:console,6.02','/stack:33554432,33554432','/dynamicbase','/nxcompat','/largeaddressaware','/out:'+str(exe),*inventory,ROOT/'build/windows/rhun.res',*sorted((ROOT/'build/windows').glob('*.lib'))]
    elif mac:command=['clang','-arch','arm64','-mmacosx-version-min=12.0','-o',exe,*inventory,'-framework','AppKit','-framework','QuartzCore','-framework','IOSurface','-framework','CoreServices','-framework','Carbon']
    else:command=['ld','-static','-nostdlib','--no-dynamic-linker','-z','noexecstack','-o',exe,*inventory]
    bounded_tool(command)
    return exe
