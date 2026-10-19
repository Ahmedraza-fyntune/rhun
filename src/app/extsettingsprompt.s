# Current row eligibility only. Caller must invalidate delayed prompt associations.
.include "rhun.inc"
.text
# prompt_resolve(ext,SD)->ordinal ornegative,RDX borrowedEP/0legacy,R8 index.
# No SD field read, edit/capability grant, retained pointer or active model requirement.
FN ext_setting_prompt_resolve
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rcx, [rip + g_exts + VEC_len]
    test rcx, rcx
    jz .Lspr_bad
    cmp rcx, 128
    ja .Lspr_bad
    mov rax, [rip + g_exts + VEC_ptr]
    test rax, rax
    jz .Lspr_bad
    cmp rbx, rax
    jb .Lspr_bad
    mov rdi, rbx
    sub rdi, rax
    imul rcx, rcx, EXT_SIZE
    cmp rdi, rcx
    jae .Lspr_bad
    mov rax, rdi
    xor edx, edx
    mov ecx, EXT_SIZE
    div rcx
    test rdx, rdx
    jnz .Lspr_bad
    mov r13, rax
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 1
    ja .Lspr_stale
    cmp dword ptr [rbx + EXT_catalog_state], 0
    jne .Lspr_prepared
    # Any prepared ownership in staging is ineligible, never a legacy fallback.
    cmp qword ptr [rip + g_ext_prepared_catalog_active], 0
    jne .Lspr_stale
    cmp dword ptr [rbx + EXT_activation_required], 0
    jne .Lspr_stale
    cmp qword ptr [rbx + EXT_metadata_owner], 0
    jne .Lspr_stale
    cmp qword ptr [rbx + EXT_identity_owner], 0
    jne .Lspr_stale
    cmp qword ptr [rbx + EXT_activation_owner], 0
    jne .Lspr_stale
    mov rdi, rbx
    call ext_is_visible
    cmp eax, 1
    jne .Lspr_stale
    mov rcx, [rbx + EXT_sdefs + VEC_len]
    test rcx, rcx
    jz .Lspr_bad
    cmp rcx, 256
    ja .Lspr_bad
    cmp [rbx + EXT_sdefs + VEC_cap], rcx
    jb .Lspr_bad
    mov rsi, [rbx + EXT_sdefs + VEC_ptr]
    test rsi, rsi
    jz .Lspr_bad
    cmp r12, rsi
    jb .Lspr_bad
    sub r12, rsi
    imul rcx, rcx, SD_SIZE
    cmp r12, rcx
    jae .Lspr_bad
    mov rax, r12
    xor edx, edx
    mov ecx, SD_SIZE
    div rcx
    test rdx, rdx
    jnz .Lspr_bad
    mov r8, rax
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lspr_prepared:
    mov rdi, rbx
    mov rsi, r12
    call ext_setting_resolve
    EPILOGUE
.Lspr_bad:
    mov rax, -22
    jmp .Lspr_error
.Lspr_stale:
    mov rax, -116
.Lspr_error:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    EPILOGUE
