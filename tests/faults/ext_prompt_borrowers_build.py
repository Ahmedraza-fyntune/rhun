"""Real prompt flow; only persistent IO and post-hook loader bodies are fault cutpoints."""
from ext_metadata_borrowers_build import ROOT,link
from ext_catalog_borrowers_build import EXPORTS

def build(folder,windows=False,mutation=None):
    fixture=(ROOT/'tests/faults/ext_prompt_borrowers_test.s').read_text()
    hi=(ROOT/'tests/ext_host_identity_test.s').read_text()
    hi='\n'.join(line for line in hi.splitlines()if not line.startswith('.include '))+'\n'
    assert hi.count('FN main\n')==1
    fixture+='\n'+hi.replace('FN main\n','FN pp_hi_main\n',1)
    replacements={'fixture.s':fixture}
    extra={'src/app/extpage.s':['xp_line'],'src/app/palette.s':['pal_tf','palette_accept']}
    for relative,names in EXPORTS.items():
        source=(ROOT/relative).read_text()
        for name in names+extra.get(relative,[]):source+='\n.globl pi_'+name+'\n.set pi_'+name+', '+name+'\n'
        replacements[relative]=source
    source=(ROOT/'src/app/ext.s').read_text()
    for fn in ['ext_init','ext_load']:
        pos=source.index('FN '+fn+'\n');head,tail=source[:pos],source[pos:]
        marker='    call extpage_prompt_invalidate_pure\n';assert marker in tail
        tail=tail.replace(marker,marker+'    xor eax, eax\n    EPILOGUE\n',1)
        if mutation=='skip-'+fn:tail=tail.replace(marker,'',1)
        source=head+tail
    marker='FN ext_settings_save\n';assert source.count(marker)==1
    source=source.replace(marker,'FN pp_real_settings_save\n',1)
    source+='\n.text\nFN ext_settings_save\n    inc qword ptr [rip + pb_saves]\n    ret\n'
    replacements['src/app/ext.s']=source
    for relative,fn in [('src/app/extmetadata.s','ext_slot_metadata_take'),('src/app/exthostidentityhost.s','ext_host_identity_take')]:
        source=(ROOT/relative).read_text()
        marker='FN '+fn+'\n';assert source.count(marker)==1
        source=source.replace(marker,'FN pp_real_'+fn+'\n',1)
        if mutation=='skip-'+fn:
            pos=source.index('FN pp_real_'+fn+'\n');head,tail=source[:pos],source[pos:]
            marker='    call extpage_prompt_invalidate_pure\n';assert marker in tail
            source=head+tail.replace(marker,'',1)
        source+='''
.text
FN '''+fn+'''
    PROLOGUE 16
    mov qword ptr [rip + pi_xp_prompt_sd], 1
    call pp_real_'''+fn+'''
    mov [rsp], rax
    mov [rsp + 8], rdx
    cmp edx, 1
    jne 1f
    cmp qword ptr [rip + pi_xp_prompt_sd], 0
    jne pi_forbidden
    jmp 2f
1:  cmp qword ptr [rip + pi_xp_prompt_sd], 1
    jne pi_forbidden
2:  mov rax, [rsp]
    mov rdx, [rsp + 8]
    EPILOGUE
'''
        replacements[relative]=source
    if mutation in ['skip-open','skip-close','skip-pure']:
        relative='src/app/palette.s';source=replacements[relative]
        start={'skip-open':'palette_open:\n','skip-close':'FN palette_close\n','skip-pure':'.Lpal_detach_borrowers_pure:\n'}[mutation]
        pos=source.index(start);head,tail=source[:pos],source[pos:]
        marker='    call extpage_prompt_invalidate_pure\n';assert marker in tail
        replacements[relative]=head+tail.replace(marker,'',1)
    return link(folder,replacements,windows)
