# Queue pointers are derived only inside the current checked synchronous slice.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.text
# Internal counted fields: RAX borrowed EC prefix, RDX remove; NULL/RDX error.
# Raw spans belong to retained ESB or previous view. Dirty spans never persist here.
FN esv_input_fields
    test qword ptr [rdi + EV_workflags], EVF_DIRTY
    jnz 1f
    lea rax, [rdi + EV_rawsection]
    xor edx, edx
    ret
1:  mov rax, [rip + esv_service_queue]
    test rax, rax
    jz 3f
    mov rcx, [rdi + EV_dirtyslot]
    cmp rcx, EQ_MAX
    jae 3f
    imul rcx, EQ_SLOT
    mov rax, [rax + EQ_slots + rcx + EQS_cell]
    test rax, rax
    jz 3f
    mov rdx, [rdi + EV_dirtyseq]
    cmp [rax + EQC_seq], rdx
    jne 3f
    mov rdx, [rax + EC_remove]
    ret
3:  xor eax, eax
    mov rdx, -116
    ret
# Completes one input field; dirty intent is never acknowledged or removed here.
FN esv_field_advance
    test qword ptr [rdi + EV_workflags], EVF_DIRTY
    jnz 1f
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + EV_cursor]
    call ext_settings_ini_advance
    test rax, rax
    jnz 2f
    mov qword ptr [rbx + EV_phase], EVP_RAW_NEXT
2:  EPILOGUE
1:  inc qword ptr [rdi + EV_dirtyslot]
    mov qword ptr [rdi + EV_phase], EVP_DIRTY_NEXT
    xor eax, eax
    ret
# One fixed slot per dispatch, with no borrowed cell pointer across yields.
FN esv_dirty_step
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EV_phase], EVP_DIRTY_NEXT
    jne .Lesvd_bad
    mov rax, [rbx + EV_dirtyslot]
    cmp rax, EQ_MAX
    jae .Lesvd_done
    imul rax, EQ_SLOT
    mov rcx, [rip + esv_service_queue]
    mov rax, [rcx + EQ_slots + rax + EQS_cell]
    test rax, rax
    jnz 1f
    inc qword ptr [rbx + EV_dirtyslot]
    jmp .Lesvd_return
1:  mov rcx, [rax + EQC_seq]
    mov [rbx + EV_dirtyseq], rcx
    mov qword ptr [rbx + EV_workflags], EVF_DIRTY
    mov qword ptr [rbx + EV_matchpos], 0
    mov qword ptr [rbx + EV_scanpos], 0
    mov qword ptr [rbx + EV_rawkind], 0
    # The reusable raw-field prefix is explicitly cleared, not borrowed from this cell.
    mov qword ptr [rbx + EV_rawsection], 0
    mov qword ptr [rbx + EV_rawkey], 0
    mov qword ptr [rbx + EV_rawvalue], 0
    mov qword ptr [rbx + EV_phase], EVP_RAW_SECTION
    jmp .Lesvd_return
.Lesvd_done:
    mov qword ptr [rbx + EV_subphase], 0
    mov qword ptr [rbx + EV_phase], EVP_FINISH
.Lesvd_return:
    xor eax, eax
    EPILOGUE
.Lesvd_bad:
    mov rax, -22
    EPILOGUE
