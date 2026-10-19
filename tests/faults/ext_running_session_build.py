"""Actual managed/legacy retained graphs and fixed-work hot-path tripwires."""
from ext_metadata_borrowers_build import ROOT,link
MUTATIONS=('bind-bytes','hi','ea','keeper','disabled','bytewalk')
def build(folder,windows=False,mutation=None,long=False):
    source=(ROOT/'tests/ext_activation_owner_test.s').read_text()
    a=source.index('af_running_matrix:\n');z=source.index('af_running_snapshot:\n',a)
    body=source[a:z]
    marker='    lea rbx, [rip + af_host]\n    mov qword ptr [rbx + EXT_keeper], 123\n'
    assert marker in body
    body=body.replace(marker,'    call ss_retain_identity\n    test rax, rax\n    jnz .Laf_abort\n'+marker,1)
    marker='    call af_running_snapshot\n    call af_running_call\n'
    body=body.replace(marker,'    call ss_bind\n    test rax, rax\n    jnz .Laf_abort\n    call ss_mismatch\n'+marker,1)
    body=body.replace('    call ext_activation_host_running_check\n','    call ss_check\n')
    body=body.replace('    mov rdi, [rip + af_ea]\n    call ext_activation_owner_release\n','    call ss_release_identity\n    call af_consumed\n    mov rdi, [rip + af_ea]\n    call ext_activation_owner_release\n',1)
    start=body.index('af_running_call:\n')
    body=body[:start]+'af_running_call:\n    jmp ss_call\n\n'
    source=source[:a]+body+source[z:]
    a=source.index('af_managed_ok:\n');z=source.index('# Both managed and legacy fixture hosts',a)
    body=source[a:z]
    marker='    cmp dword ptr [rip + af_host + EXT_activation_required], 1\n    jne .Laf_abort\n'
    assert marker in body
    body=body.replace(marker,marker+'    call ss_managed\n',1)
    source=source[:a]+body+source[z:]
    if long:
        owner='o'*100;name='n'*100;state=('/'if not windows else'C:/')+'s'*(4095-(1 if not windows else 3))
        source=source.replace('af_owner: .asciz "owner"','af_owner: .asciz "'+owner+'"').replace('af_name: .asciz "name"','af_name: .asciz "'+name+'"')
        source=source.replace('af_state: .asciz "/state"','af_state: .asciz "'+state+'"').replace('af_state: .asciz "C:/state"','af_state: .asciz "'+state+'"')
        source=source.replace('af_dir: .asciz "/rhun/owner/name"','af_dir: .asciz "/rhun/'+owner+'/'+name+'"').replace('af_dir: .asciz "C:/rhun/owner/name"','af_dir: .asciz "C:/rhun/'+owner+'/'+name+'"')
    source+='\n'+(ROOT/'tests/faults/ext_running_session.s').read_text()
    replacements={}
    for path,symbols in {'src/app/theme.s':('strcmp_eq',),'src/lib.s':('strlen','memeq'),'src/app/taskauth.s':('ext_activation_epoch_get',),'src/mem.s':('mem_alloc','mem_alloc_try','mem_free'),'src/app/extvalidatepath.s':('ext_root_close',),'src/app/exthostnative.s':('ext_fd_close_checked',),'src/app/taskproc.s':('keeper_close_checked',)}.items():
        text=(ROOT/path).read_text()
        for symbol in symbols:
            marker='FN '+symbol+'\n';assert text.count(marker)==1,(path,symbol)
            text=text.replace(marker,marker+'    cmp qword ptr [rip + ss_hot], 0\n    jne ss_forbidden\n',1)
        replacements[path]=text
    if mutation:
        text=(ROOT/'src/app/extactivationsession.s').read_text()
        if mutation=='bind-bytes':text=text.replace('    call ext_activation_host_running_check\n','    xor eax, eax\n',1)
        elif mutation=='bytewalk':text=text.replace('FN ext_activation_host_running_session_check\n','FN ext_activation_host_running_session_check\n    call strcmp_eq\n',1)
        else:
            field={'hi':'EXT_identity_owner','ea':'EXT_activation_owner','keeper':'EXT_keeper','disabled':'EXT_disabled'}[mutation]
            a=text.index('FN ext_activation_host_running_session_check\n');head,tail=text[:a],text[a:]
            import re
            tail,count=re.subn(r'    cmp [^\n]*\[rbx \+ '+field+r'\][^\n]*\n    jne \.Lass_stale\n','',tail,count=1)
            assert count==1,mutation
            text=head+tail
        replacements['src/app/extactivationsession.s']=text
    replacements['fixture.s']=source
    return link(folder,replacements,windows)
