"""Test-only exports and refusal tripwires around real pure borrower invalidation."""
from pathlib import Path
from ext_metadata_borrowers_build import link,ROOT
EXPORTS={'src/app/extpage.s': ['xp_prompt_sd', 'xp_scroll', 'xp_content_h'], 'src/app/extbar.s': ['xb_ext', 'xb_open', 'xb_items'], 'src/app/extinstall.s': ['rm_ext', 'remove_commit'], 'src/app/extproto.s': ['pr_ext', 'pr_revoked', 'pr_body', 'pr_cmd'], 'src/app/palette.s': ['pal_mode', 'pal_prompt', 'pal_label', 'pal_focus_before', 'items', 'results'], 'src/app/extproviders.s': ['pp_state', 'pp_ext', 'pp_transfer', 'pp_deadline', 'pp_path', 'pp_language', 'pp_choices'], 'src/app/complete.s': ['cp_source', 'cp_open', 'cp_session', 'cp_due', 'cp_nshown', 'cp_rect', 'cp_items', 'cp_bytes', 'cp_reqs', 'sg_open', 'sg_wait', 'sg_again', 'sg_ext', 'sg_text'], 'src/app/langfeat.s': ['lf_kind', 'lf_ready', 'lf_list_kind', 'lf_ws_ext', 'lf_deadline', 'lf_reqs', 'lf_res', 'lf_bytes'], 'src/app/app.s': ['dlg_kind', 'dlg_title', 'dlg_text', 'dlg_ok', 'dlg_fn', 'dlg_cancel'], 'src/app/explorer.s': ['menu_open', 'menu_list']}
def build(folder,windows=False,mutation=None):
    replacements={'fixture.s':(ROOT/'tests/faults/ext_catalog_borrowers_test.s').read_text()}
    for relative,names in EXPORTS.items():
        source=(ROOT/relative).read_text()
        for name in names:source+='\n.globl pi_'+name+'\n.set pi_'+name+', '+name+'\n'
        replacements[relative]=source
    for relative,names in {'src/mem.s':['mem_alloc','mem_alloc_try','mem_realloc','mem_free'],'src/app/exthostnative.s':['ext_fd_close_checked'],'src/app/extvalidatepath.s':['ext_root_close'],'src/app/taskproc.s':['keeper_close_checked']}.items():
        source=(ROOT/relative).read_text()
        for name in names:
            marker='FN '+name+'\n';assert source.count(marker)==1
            source=source.replace(marker,'FN pi_real_'+name+'\n',1)
            source+='\n.text\nFN '+name+'\n    cmp qword ptr [rip + pi_guard], 0\n    jne pi_forbidden\n    jmp pi_real_'+name+'\n'
        replacements[relative]=source
    if mutation:
        relative='src/app/extpage.s';source=replacements[relative]
        marker='FN extpage_catalog_invalidate_pure\n';assert source.count(marker)==1
        if mutation=='allocation':change='    mov edi, 32\n    call mem_alloc\n'
        elif mutation=='free':change='    mov edi, 1\n    call mem_free\n'
        elif mutation=='native-close':change='    mov edi, 1\n    call ext_fd_close_checked\n'
        elif mutation=='callback':change='    mov rax, 1\n    call rax\n'
        elif mutation=='skip-page':change='    ret\n'
        else:raise AssertionError(mutation)
        replacements[relative]=source.replace(marker,marker+change,1)
    return link(folder,replacements,windows)
