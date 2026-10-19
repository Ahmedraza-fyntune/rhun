# Helper-only selected source capture with ordinary development launch semantics.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
FN prep_legacy_launch
    PROLOGUE 160
    mov rbx, rdi
    cmp qword ptr [rbx + EP_ext + EXT_script], 0
    je .Lepll_program
    mov rsi, [rbx + EP_ext + EXT_prog]
    call prep_legacy_runtime_resolve
    test rax, rax
    jz .Lepll_resolve_error
    mov r12, rax
    mov rdi, rbx
    mov rsi, [rbx + EP_ext + EXT_prog]
    call prep_owned_free
    test rax, rax
    jnz .Lepll_done
    mov [rbx + EP_ext + EXT_prog], r12
.Lepll_program:
    mov rdi, [rbx + EP_ext + EXT_prog]
    mov esi, ER_FILE
    call prep_legacy_open_absolute
    test rax, rax
    js .Lepll_open_error
    mov r12, rax
    mov rdi, [rbx + EP_ext + EXT_prog]
    mov esi, 1
    call prep_legacy_access
    mov r13, rax
    mov rdi, r12
    call ext_root_close
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    test r13, r13
    jnz .Lepll_primary
    cmp qword ptr [rbx + EP_cleanup], 0
    jne .Lepll_cleanup
    mov r14, [rbx + EP_ext + EXT_script]
    test r14, r14
    jz 1f
    cmp byte ptr [r14], 0
    jne 2f
1:  mov r14, [rbx + EP_ext + EXT_prog]
2:  mov rdi, r14
    mov esi, ER_FILE
    call prep_legacy_open_absolute
    test rax, rax
    js .Lepll_open_error
    mov r12, rax
    mov rdi, rax
    mov rsi, rsp
    xor edx, edx
    call prep_hash_file
    test rax, rax
    jnz .Lepll_close
    mov rdi, r14
    mov esi, 4
    cmp qword ptr [rbx + EP_ext + EXT_script], 0
    jne 3f
    mov esi, 1
3:  call prep_legacy_access
    test rax, rax
    jnz .Lepll_close
    mov rdi, r12
    lea rsi, [rsp + 64]
    xor edx, edx
    call prep_hash_file
    test rax, rax
    jnz .Lepll_close
    mov rdi, rsp
    lea rsi, [rsp + 64]
    mov edx, 64
    call memeq
    test eax, eax
    jz .Lepll_changed
    mov rdi, r14
    call strlen
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r14
    mov rcx, [rsp]
    mov r8, [rsp + 8]
    lea r9, [rsp + 16]
    mov r10d, SR_LAUNCH | SR_EXTERNAL
    call prep_source_add
.Lepll_close:
    mov r13, rax
    mov rdi, r12
    call ext_root_close
    mov rdi, rbx
    mov rsi, rax
    call prep_note_cleanup
    test r13, r13
    jnz .Lepll_primary
    cmp qword ptr [rbx + EP_cleanup], 0
    jne .Lepll_cleanup
    mov dword ptr [rbx + EP_ext + EXT_manifest_ok], 1
    xor eax, eax
.Lepll_done:
    EPILOGUE
.Lepll_changed:
    mov rax, -EV_CHANGED
    jmp .Lepll_close
.Lepll_primary:
    mov rax, r13
    EPILOGUE
.Lepll_cleanup:
    mov rax, [rbx + EP_cleanup]
    EPILOGUE
.Lepll_open_error:
    mov r13, rax
    mov rdi, rbx
    mov rsi, rdx
    call prep_note_cleanup
    jmp .Lepll_primary
.Lepll_resolve_error:
    mov rax, rdx
    EPILOGUE
