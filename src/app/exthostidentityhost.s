# Preheld identity transfer. Publication never retains, frees or closes an owner.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/exthostidentity.inc"
.text
# Hidden/native-collected slot with no package metadata or activation borrows.
FN hi_host_empty_metadata
    PROLOGUE
    mov rbx, rdi
    call ext_slot_native_quiet
    test rax, rax
    jnz .Lhihem_done
    cmp qword ptr [rbx + EXT_metadata_owner], 0
    jne .Lhihem_busy
    mov rdi, rbx
    xor esi, esi
    call ext_slot_metadata_fields_check
.Lhihem_done:
    EPILOGUE
.Lhihem_busy:
    mov rax, -16
    EPILOGUE

FN ext_host_identity_check_swap
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call hi_host_empty_metadata
    test rax, rax
    jnz .Lhics_done
    mov rdi, r12
    call hi_is_ready
    test eax, eax
    jz .Lhics_bad
    mov r14, [rbx + EXT_identity_owner]
    test r14, r14
    jz .Lhics_empty
    mov rdi, rbx
    call ext_host_identity_matches
    test eax, eax
    jz .Lhics_bad
    cmp r12, r14
    jne .Lhics_output
    cmp qword ptr [r12 + PO_refs], 2
    jb .Lhics_bad
    jmp .Lhics_output
.Lhics_empty:
    cmp qword ptr [rbx + EXT_owner], 0
    jne .Lhics_bad
    cmp qword ptr [rbx + EXT_name], 0
    jne .Lhics_bad
    cmp qword ptr [rbx + EXT_state], 0
    jne .Lhics_bad
.Lhics_output:
    mov rdi, r13
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r14
    call ext_owned_output_check
.Lhics_done:
    EPILOGUE
.Lhics_bad:
    mov rax, -22
    EPILOGUE

# Exact same arguments, unchanged since successful check, in a no-yield callback.
FN ext_host_identity_publish_swap
    mov rax, [rdi + EXT_identity_owner]
    mov [rdx], rax
    mov [rdi + EXT_identity_owner], rsi
    mov rax, [rsi + HI_owner]
    mov [rdi + EXT_owner], rax
    mov rax, [rsi + HI_name]
    mov [rdi + EXT_name], rax
    mov rax, [rsi + HI_state]
    mov [rdi + EXT_state], rax
    xor eax, eax
    mov edx, 1
    ret

FN ext_host_identity_swap
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_host_identity_check_swap
    test rax, rax
    jnz .Lhis_refuse
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call ext_host_identity_publish_swap
    EPILOGUE
.Lhis_refuse:
    xor edx, edx
    EPILOGUE

# External historical identity borrowers must already have been revoked by caller.
FN ext_host_identity_take
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call hi_host_empty_metadata
    test rax, rax
    jnz .Lhit_refuse
    mov r13, [rbx + EXT_identity_owner]
    test r13, r13
    jz .Lhit_empty
    mov rdi, rbx
    call ext_host_identity_matches
    test eax, eax
    jz .Lhit_bad
    jmp .Lhit_output
.Lhit_empty:
    cmp qword ptr [rbx + EXT_owner], 0
    jne .Lhit_bad
    cmp qword ptr [rbx + EXT_name], 0
    jne .Lhit_bad
    cmp qword ptr [rbx + EXT_state], 0
    jne .Lhit_bad
.Lhit_output:
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    xor ecx, ecx
    call ext_owned_output_check
    test rax, rax
    jnz .Lhit_refuse
    call extpage_prompt_invalidate_pure
    mov qword ptr [rbx + EXT_owner], 0
    mov qword ptr [rbx + EXT_name], 0
    mov qword ptr [rbx + EXT_state], 0
    mov qword ptr [rbx + EXT_identity_owner], 0
    mov [r12], r13
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lhit_bad:
    mov rax, -22
.Lhit_refuse:
    xor edx, edx
    EPILOGUE
