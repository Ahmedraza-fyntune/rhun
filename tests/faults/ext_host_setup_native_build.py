"""Inject one failure at the real prepared-host setup boundary."""
from pathlib import Path
from ext_metadata_borrowers_build import ROOT,link
MODES=tuple(range(1,19))
MUTATIONS={"fake-eof":1,"keeper-owner":15,"setup-primary":9,"child-diagnostic":12,"unknown-disposition":14}
def build(folder,mode,windows=False,mutation=None):
    assert mode in MODES
    if windows and mode in(5,6):raise ValueError('POSIX explicit CLOEXEC only')
    fixture=(ROOT/'tests/extension_lifecycle_test.s').read_text()
    start=fixture.index('    # Stop during preparation must close the gate')
    end=fixture.index('.Ltek_return:',start)
    fixture=fixture[:start]+'    call hs_case\n'+fixture[end:]
    old='    test rax, rax\n    jle .Ltek_fail\n    EPILOGUE\n\nlc_wait:'
    assert old in fixture
    fixture=fixture.replace(old,'    EPILOGUE\n\nlc_wait:',1)
    fixture='.equ HS_MODE, '+str(mode)+'\n'+fixture+'\n'+(ROOT/'tests/faults/ext_host_setup_native.s').read_text()
    source=(ROOT/'src/app/ext.s').read_text()
    a=source.index('FN ext_supervised_start_impl\n');z=source.index('# Root calls after publication',a)
    head,body,tail=source[:a],source[a:z],source[z:]
    assert body.count('    SYS SYS_fcntl\n')==2
    body=body.replace('    SYS SYS_fcntl\n','    call hs_nonblock_out\n',1).replace('    SYS SYS_fcntl\n','    call hs_nonblock_in\n',1)
    source=head+body+tail
    a=source.index('ext_prepare_supervised:\n');z=source.index('# build_argv(',a)
    body=source[a:z];assert body.count('    call keeper_prepare\n')==1
    source=source[:a]+body.replace('    call keeper_prepare\n','    call hs_prepare\n',1)+source[z:]
    replacements={'fixture.s':fixture,'src/app/ext.s':source}
    for path,symbol,renamed in(('src/app/exthostpipe.s','ext_host_pipe_create','hs_real_pipe'),('src/app/exthostopen.s','ext_host_log_open','hs_real_log'),('src/loop.s','watch_try_add','hs_real_watch'),('src/app/exthostnative.s','ext_fd_close_checked','hs_real_close')):
        source=(ROOT/path).read_text();needle='FN '+symbol+'\n';assert source.count(needle)==1,(path,symbol)
        source=source.replace(needle,'FN '+renamed+'\n',1)
        if symbol=='ext_host_pipe_create':
            source=source.replace('    SYS SYS_fcntl\n','    call hs_cloexec_first\n',1).replace('    SYS SYS_fcntl\n','    call hs_cloexec_second\n',1)
        replacements[path]=source
        fixture+='\nFN '+symbol+'\n    jmp '+{'ext_host_pipe_create':'hs_pipe','ext_host_log_open':'hs_log','watch_try_add':'hs_watch','ext_fd_close_checked':'hs_close'}[symbol]+'\n'
    path='src/win/taskproc.s'if windows else'src/app/taskposix.s'
    source=(ROOT/path).read_text();needle='FN kp_backend_prepare\n';assert source.count(needle)==1
    replacements[path]=source.replace(needle,needle+'    call hs_capture\n',1)
    if mutation:
        assert MUTATIONS[mutation]==mode
        if mutation=='keeper-owner':
            text=replacements['src/app/ext.s'];needle='    mov [rbx + EXT_keeper], r12\n';assert text.count(needle)==1
            replacements['src/app/ext.s']=text.replace(needle,'',1)
        elif mutation=='setup-primary':
            text=replacements['src/app/ext.s'];a=text.index('.Les_watch_failed:');head,tail=text[:a],text[a:]
            needle='    call ext_host_prepared_setup_note\n';assert needle in tail
            replacements['src/app/ext.s']=head+tail.replace(needle,'    xor eax, eax\n',1)
        elif mutation=='child-diagnostic':
            text=replacements['src/app/ext.s'];a=text.index('    call ext_host_prepared_children_close\n',text.index('FN ext_supervised_start_impl\n'));z=text.index('    test r13, r13\n',a)
            replacements['src/app/ext.s']=text[:a]+'    call ext_host_prepared_children_close\n'+text[z:]
        elif mutation=='fake-eof':
            text=(ROOT/'src/app/exthostsetup.s').read_text();a=text.index('FN ext_host_prepared_abort\n');head,tail=text[:a],text[a:]
            needle='    mov dword ptr [rbx + EXT_activation_stale], 1\n';assert needle in tail
            replacements['src/app/exthostsetup.s']=head+tail.replace(needle,'    mov dword ptr [rbx + EXT_stdout_eof], 1\n'+needle,1)
        else:
            text=(ROOT/'src/app/exthostcleanup.s').read_text();a=text.index('.Lhcr_unknown:');head,tail=text[:a],text[a:]
            needle='mov edx, 2\n';assert needle in tail
            replacements['src/app/exthostcleanup.s']=head+tail.replace(needle,'xor edx, edx\n',1)
    replacements['fixture.s']=fixture
    return link(folder,replacements,windows)
