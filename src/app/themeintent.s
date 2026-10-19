# Pure, bounded owned theme intent snapshot. Raw guards never authorize string dereference.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintent.inc"
.text
# capture(TIR128)->TI*/primary/cleanup. A nonNULL failed owner is RETIRING, never semantic data.
FN theme_intent_capture
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Ltic_bad
    cmp qword ptr [rbx + TIR_context], 0
    jle .Ltic_bad
    cmp qword ptr [rbx + TIR_config], 0
    jle .Ltic_bad
    cmp qword ptr [rbx + TIR_catalog], 0
    jle .Ltic_bad
    test dword ptr [rbx + TIR_keys], -8
    jnz .Ltic_bad
    cmp dword ptr [rbx + TIR_follow], 1
    ja .Ltic_bad
    mov eax, [rbx + TIR_system]
    inc eax
    cmp eax, 2
    ja .Ltic_bad
    cmp dword ptr [rbx + TIR_applied], 1
    ja .Ltic_bad
    cmp dword ptr [rbx + TIR_palette_dark], 1
    ja .Ltic_bad
    cmp dword ptr [rbx + 116], 0
    jne .Ltic_bad
    cmp dword ptr [rbx + TIR_applied], 0
    je 1f
    cmp qword ptr [rbx + TIR_current], 0
    je .Ltic_bad
1:  mov edi, TI_SIZE
    call tc_alloc_try
    test rax, rax
    jz .Ltic_oom
    mov r12, rax
    mov qword ptr [r12 + TI_refs], 1
    mov qword ptr [r12 + TI_state], TI_BUILDING
    mov qword ptr [r12 + TI_total], TI_SIZE
    mov rax, [rbx + TIR_context]
    mov [r12 + TI_context], rax
    mov rax, [rbx + TIR_config]
    mov [r12 + TI_config], rax
    mov rax, [rbx + TIR_catalog]
    mov [r12 + TI_catalog], rax
    lea rdi, [r12 + TI_keys]
    lea rsi, [rbx + TIR_keys]
    mov edx, 16
    call memcpy
    mov eax, [rbx + TIR_palette_dark]
    mov [r12 + TI_palette_dark], eax
    lea rdi, [r12 + TI_guard]
    mov rsi, rbx
    mov edx, TIR_SIZE
    call memcpy
    xor r13d, r13d
.Ltic_string:
    cmp r13, 6
    jae .Ltic_complete
    mov r14, [rbx + r13*8]
    cmp r13, 4
    jne 2f
    cmp qword ptr [rbx + TIR_pending], 0
    jne 2f
    test r14, r14
    jz .Ltic_next
    or qword ptr [r12 + TI_effects], 2
    jmp .Ltic_next
2:  cmp r13, 5
    jne 3f
    mov r14, [rbx + TIR_current]
3:  test r14, r14
    jz .Ltic_next
    mov rax, r13
    shl rax, 12
    lea r15, [r12 + TI_strings + rax]
    mov [r12 + r13*8 + TI_values], r15
    xor ecx, ecx
4:  mov al, [r14 + rcx]
    mov [r15 + rcx], al
    test al, al
    jz 5f
    inc ecx
    cmp ecx, TI_ID_CAP + 1
    jb 4b
    mov r15, -36
    jmp .Ltic_failed_owner
5:  mov [r12 + r13*8 + TI_lengths], rcx
.Ltic_next:
    inc r13
    jmp .Ltic_string
.Ltic_complete:
    mov qword ptr [r12 + TI_state], TI_LIVE
    mov rax, r12
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltic_failed_owner:
    mov [r12 + TI_primary], r15
    mov qword ptr [r12 + TI_state], TI_RETIRING
    mov rdi, r12
    call theme_intent_release
    mov rcx, rax
    test rdx, rdx
    jnz 6f
    mov rax, r12
    mov rdx, r15
    EPILOGUE
6:  xor eax, eax
    mov rdx, r15
    EPILOGUE
.Ltic_bad:
    xor eax, eax
    mov rdx, -22
    xor ecx, ecx
    EPILOGUE
.Ltic_oom:
    xor eax, eax
    mov rdx, -12
    xor ecx, ecx
    EPILOGUE

# Retain never exposes construction/retirement state. No mutation on overflow.
FN theme_intent_retain
    test rdi, rdi
    jz .Lti_invalid
    cmp qword ptr [rdi + TI_state], TI_LIVE
    jne .Lti_busy
    mov rax, [rdi + TI_refs]
    test rax, rax
    jz .Lti_invalid
    cmp rax, -1
    je .Lti_overflow
    inc qword ptr [rdi + TI_refs]
    mov rax, rdi
    xor edx, edx
    ret
.Lti_overflow:
    xor eax, eax
    mov rdx, -75
    ret
.Lti_busy:
    xor eax, eax
    mov rdx, -16
    ret
.Lti_invalid:
    xor eax, eax
    mov rdx, -22
    ret

# One reference consumed only after actual release. Retained last ref stays1 with all bytes intact.
FN theme_intent_release
    test rdi, rdi
    jz .Ltir_empty
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + TI_refs], 0
    je .Ltir_bad
    cmp qword ptr [rbx + TI_refs], 1
    je 1f
    dec qword ptr [rbx + TI_refs]
    xor eax, eax
    mov edx, 1
    EPILOGUE
1:  movsxd r12, dword ptr [rbx + TI_cleanup]
    call tc_free
    test rdx, rdx
    jz 2f
    test r12, r12
    jz 5f
    mov rax, r12
5:  EPILOGUE
2:  test rax, rax
    js 3f
    mov rax, -5
3:  test r12, r12
    jnz 4f
    mov [rbx + TI_cleanup], eax
    mov r12, rax
4:  mov qword ptr [rbx + TI_state], TI_RETIRING
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Ltir_bad:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Ltir_empty:
    xor eax, eax
    mov edx, 1
    ret

# Borrowed immutable semantic snapshot, no source/config owner pointers in values.
FN theme_intent_view
    test rdi, rdi
    jz .Ltiv_bad
    test rsi, rsi
    jz .Ltiv_bad
    cmp qword ptr [rdi + TI_state], TI_LIVE
    jne .Ltiv_busy
    cmp qword ptr [rdi + TI_refs], 0
    je .Ltiv_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    lea rsi, [rbx + TI_values]
    mov edx, 96
    call memcpy
    lea rdi, [r12 + 96]
    lea rsi, [rbx + TI_keys]
    mov edx, 20
    call memcpy
    mov eax, [rbx + TI_effects]
    mov [r12 + 116], eax
    lea rdi, [r12 + 120]
    lea rsi, [rbx + TI_context]
    mov edx, 24
    call memcpy
    xor eax, eax
    EPILOGUE
.Ltiv_bad:
    mov rax, -22
    ret
.Ltiv_busy:
    mov rax, -16
    ret
FN theme_intent_guard
    test rdi, rdi
    jz .Lti_invalid
    cmp qword ptr [rdi + TI_state], TI_LIVE
    jne .Lti_busy
    cmp qword ptr [rdi + TI_refs], 0
    je .Lti_invalid
    lea rax, [rdi + TI_guard]
    xor edx, edx
    ret
FN theme_intent_status
    test rdi, rdi
    jz .Ltiv_bad
    test rsi, rsi
    jz .Ltiv_bad
    mov rax, [rdi + TI_state]
    mov [rsi], rax
    mov rax, [rdi + TI_primary]
    mov [rsi + 8], rax
    movsxd rax, dword ptr [rdi + TI_cleanup]
    mov [rsi + 16], rax
    mov rax, [rdi + TI_refs]
    mov [rsi + 24], rax
    xor eax, eax
    ret
