# Pure theme intent transitions. Six final string plans precede one bounded allocation/copy.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintent.inc"
.section .rodata
tir_omarchy: .ascii "omarchy"
tir_dark: .ascii "rhun-dark"
.text
# reduce(liveTI,event80)->newTI*/primary/cleanup. Input remains borrowed and immutable.
FN theme_intent_reduce
    PROLOGUE 160
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Ltr_bad
    test r12, r12
    jz .Ltr_bad
    cmp qword ptr [rbx + TI_state], TI_LIVE
    jne .Ltr_busy
    cmp qword ptr [rbx + TI_refs], 0
    je .Ltr_bad
    cmp dword ptr [r12], 5
    ja .Ltr_bad
    cmp dword ptr [r12 + 4], 1
    ja .Ltr_bad
    cmp dword ptr [r12 + 12], 0
    jne .Ltr_bad
    cmp qword ptr [r12 + 24], TI_ID_CAP
    ja .Ltr_bad
    mov rax, [r12 + 24]
    test rax, rax
    jz 1f
    cmp qword ptr [r12 + 16], 0
    je .Ltr_bad
1:  cmp dword ptr [r12 + 32], 1
    ja .Ltr_bad
    cmp dword ptr [r12 + 36], 1
    ja .Ltr_bad
    cmp dword ptr [r12 + 40], 1
    ja .Ltr_bad
    cmp dword ptr [r12 + 44], 1
    ja .Ltr_bad
    cmp dword ptr [r12 + 40], 0
    je 2f
    cmp dword ptr [r12 + 32], 1
    jne .Ltr_bad
    cmp dword ptr [r12 + 44], 1
    jne .Ltr_bad
2:  mov rax, [rbx + TI_catalog]
    cmp [r12 + 48], rax
    jne .Ltr_stale
    mov rax, [rbx + TI_context]
    cmp [r12 + 56], rax
    jne .Ltr_stale
    mov rax, [r12 + 64]
    or rax, [r12 + 72]
    jnz .Ltr_bad
    mov rdi, rsp
    lea rsi, [rbx + TI_values]
    mov edx, 96
    call memcpy
    mov rax, [rbx + TI_effects]
    mov [rsp + 96], rax
    mov eax, [rbx + TI_follow]
    mov [rsp + 104], eax
    mov eax, [rbx + TI_system]
    mov [rsp + 108], eax
    xor r15d, r15d
    mov eax, [r12]
    test eax, eax
    jz .Ltr_build
    cmp eax, 1
    je .Ltr_init
    cmp eax, 2
    je .Ltr_system
    cmp eax, 3
    je .Ltr_pick
    cmp eax, 4
    je .Ltr_follow
    # Toggle while following is a semantic no-op.
    cmp dword ptr [rsp + 104], 0
    jne .Ltr_build
    xor r13d, r13d
    jmp .Ltr_pick_resolved
.Ltr_follow:
    cmp dword ptr [r12 + 8], 1
    ja .Ltr_bad
    mov eax, [r12 + 8]
    cmp eax, [rsp + 104]
    je .Ltr_build
    mov [rsp + 104], eax
    or qword ptr [rsp + 96], 4
    test eax, eax
    jnz .Ltr_build
    # Turning follow off adopts the actually displayed ID, never a requested miss.
    cmp dword ptr [rbx + TI_applied], 1
    jne .Ltr_bad
    mov edi, 5
    call .Ltr_receipt_equal
    test eax, eax
    jz .Ltr_bad
    xor r13d, r13d
    jmp .Ltr_pick_resolved
.Ltr_pick:
    mov r13d, [r12 + 8]
    cmp r13d, 2
    ja .Ltr_bad
.Ltr_pick_resolved:
    cmp dword ptr [r12 + 32], 1
    jne .Ltr_bad
    mov rax, [r12 + 16]
    test rax, rax
    jz .Ltr_bad
    mov [rsp + r13*8], rax
    mov rax, [r12 + 24]
    mov [rsp + r13*8 + 48], rax
    or qword ptr [rsp + 96], 17
    jmp .Ltr_clear_pending
.Ltr_init:
    # Legacy initialization clears migration even when no recognized theme is found.
    mov qword ptr [rsp + 24], 0
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 80], 0
    cmp qword ptr [rbx + TI_values + 24], 0
    je 3f
    or qword ptr [rsp + 96], 2
3:  cmp dword ptr [rbx + TI_keys], 0
    jne 4f
    cmp dword ptr [r12 + 4], 1
    jne .Ltr_build
    cmp dword ptr [r12 + 44], 1
    jne .Ltr_build
    lea rax, [rip + tir_omarchy]
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov qword ptr [rsp + 48], 7
    mov qword ptr [rsp + 56], 7
    mov qword ptr [rsp + 64], 7
    or qword ptr [rsp + 96], 1
    jmp .Ltr_build
4:  cmp dword ptr [rbx + TI_keys], 1
    jne .Ltr_build
    cmp dword ptr [r12 + 32], 1
    jne .Ltr_build
    xor edi, edi
    call .Ltr_receipt_equal
    test eax, eax
    jz .Ltr_bad
    cmp dword ptr [r12 + 40], 1
    je .Ltr_init_follow
    cmp dword ptr [r12 + 44], 1
    je .Ltr_init_kind
    cmp dword ptr [r12 + 4], 1
    jne .Ltr_init_kind
    cmp qword ptr [rsp + 48], 9
    jne .Ltr_init_kind
    lea rdi, [rip + tir_dark]
    mov rsi, [rsp]
    mov edx, 9
    call memeq
    test eax, eax
    jnz .Ltr_build
.Ltr_init_kind:
    mov rax, [r12 + 16]
    mov rcx, [r12 + 24]
    mov edx, 1
    cmp dword ptr [r12 + 36], 0
    jne 5f
    mov edx, 2
5:  mov [rsp + rdx*8], rax
    mov [rsp + rdx*8 + 48], rcx
    # The saved dark setting is captured after the kind assignment.
    mov rdx, [rsp + 8]
    mov [rsp + 32], rdx
    mov rdx, [rsp + 56]
    mov [rsp + 80], rdx
    mov edx, 1
    cmp dword ptr [rsp + 108], 0
    jne 6f
    mov edx, 2
6:  mov [rsp + rdx*8], rax
    mov [rsp + rdx*8 + 48], rcx
    or qword ptr [rsp + 96], 19
    cmp dword ptr [rsp + 108], 0
    jge 7f
    mov [rsp + 24], rax
    mov [rsp + 72], rcx
    jmp .Ltr_build
7:  # Inactive saved dark is always normalized in the owned representation.
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 80], 0
    jmp .Ltr_build
.Ltr_init_follow:
    mov rax, [r12 + 16]
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov rax, [r12 + 24]
    mov [rsp + 56], rax
    mov [rsp + 64], rax
    or qword ptr [rsp + 96], 17
    jmp .Ltr_build
.Ltr_system:
    mov eax, [r12 + 8]
    inc eax
    cmp eax, 2
    ja .Ltr_bad
    mov eax, [r12 + 8]
    cmp eax, [rsp + 108]
    je .Ltr_build
    mov [rsp + 108], eax
    or qword ptr [rsp + 96], 8
    test eax, eax
    js .Ltr_build
    cmp qword ptr [rsp + 24], 0
    je .Ltr_build
    mov edx, 1
    test eax, eax
    jnz 8f
    mov edx, 2
    mov rcx, [rsp + 32]
    mov [rsp + 8], rcx
    mov rcx, [rsp + 80]
    mov [rsp + 56], rcx
8:  mov rcx, [rsp + 24]
    mov [rsp + rdx*8], rcx
    mov rcx, [rsp + 72]
    mov [rsp + rdx*8 + 48], rcx
    or qword ptr [rsp + 96], 17
.Ltr_clear_pending:
    cmp qword ptr [rsp + 24], 0
    jne 9f
    cmp qword ptr [rsp + 32], 0
    je 10f
9:  or qword ptr [rsp + 96], 2
10: mov qword ptr [rsp + 24], 0
    mov qword ptr [rsp + 32], 0
    mov qword ptr [rsp + 72], 0
    mov qword ptr [rsp + 80], 0
.Ltr_build:
    test r15, r15
    jne .Ltr_allocate
    mov rcx, [r12 + 24]
    mov rdx, [r12 + 16]
    xor eax, eax
14: cmp rax, rcx
    jae .Ltr_allocate
    cmp byte ptr [rdx + rax], 0
    je .Ltr_bad
    inc rax
    jmp 14b
.Ltr_allocate:
    mov edi, TI_SIZE
    call tc_alloc_try
    test rax, rax
    jz .Ltr_oom
    mov r13, rax
    mov qword ptr [r13 + TI_refs], 1
    mov qword ptr [r13 + TI_state], TI_BUILDING
    mov qword ptr [r13 + TI_total], TI_SIZE
    mov rax, [rsp + 96]
    mov [r13 + TI_effects], rax
    lea rdi, [r13 + TI_context]
    lea rsi, [rbx + TI_context]
    mov edx, 44
    call memcpy
    mov eax, [rsp + 104]
    mov [r13 + TI_follow], eax
    mov eax, [rsp + 108]
    mov [r13 + TI_system], eax
    lea rdi, [r13 + TI_guard]
    lea rsi, [rbx + TI_guard]
    mov edx, TIR_SIZE
    call memcpy
    xor r14d, r14d
.Ltr_copy:
    cmp r14, 6
    jae .Ltr_done
    mov rsi, [rsp + r14*8]
    test rsi, rsi
    jz .Ltr_next
    mov rdx, [rsp + r14*8 + 48]
    mov rax, r14
    shl rax, 12
    lea rdi, [r13 + TI_strings + rax]
    mov [r13 + TI_values + r14*8], rdi
    mov [r13 + TI_lengths + r14*8], rdx
    xor ecx, ecx
11: cmp rcx, rdx
    jae 12f
    mov al, [rsi + rcx]
    test al, al
    jz .Ltr_owned_bad
    mov [rdi + rcx], al
    inc rcx
    jmp 11b
12: mov byte ptr [rdi + rcx], 0
.Ltr_next:
    inc r14
    jmp .Ltr_copy
.Ltr_done:
    mov qword ptr [r13 + TI_state], TI_LIVE
    mov rax, r13
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Ltr_owned_bad:
    mov qword ptr [r13 + TI_primary], -22
    mov qword ptr [r13 + TI_state], TI_RETIRING
    mov rdi, r13
    call theme_intent_release
    mov rcx, rax
    test rdx, rdx
    jnz 13f
    mov rax, r13
    mov rdx, -22
    EPILOGUE
13: xor eax, eax
    mov rdx, -22
    EPILOGUE
.Ltr_oom:
    mov rdx, -12
    jmp .Ltr_null
.Ltr_bad:
    mov rdx, -22
    jmp .Ltr_null
.Ltr_busy:
    mov rdx, -16
    jmp .Ltr_null
.Ltr_stale:
    mov rdx, -116
.Ltr_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE
# Private bounded receipt equality. rdi semantic index, rbx TI, r12 event.
# One compare, at most4095 bytes, also rejects embedded NUL in the counted receipt.
.Ltr_receipt_equal:
    mov rcx, [rbx + TI_lengths + rdi*8]
    cmp rcx, [r12 + 24]
    jne 3f
    mov rsi, [rbx + TI_values + rdi*8]
    test rsi, rsi
    jz 3f
    mov rdx, [r12 + 16]
    test rdx, rdx
    jz 3f
    xor eax, eax
1:  test rcx, rcx
    jz 2f
    mov al, [rdx]
    test al, al
    jz 3f
    cmp al, [rsi]
    jne 3f
    inc rdx
    inc rsi
    dec rcx
    jmp 1b
2:  mov r15d, 1
    mov eax, 1
    ret
3:  xor eax, eax
    ret

# Effective configured slot, independent of current preview/palette.
FN theme_intent_effective_slot
    test rdi, rdi
    jz 2f
    cmp qword ptr [rdi + TI_state], TI_LIVE
    jne 2f
    cmp qword ptr [rdi + TI_refs], 0
    je 2f
    xor eax, eax
    cmp dword ptr [rdi + TI_follow], 0
    je 1f
    mov eax, 1
    cmp dword ptr [rdi + TI_system], 0
    jne 1f
    mov eax, 2
1:  ret
2:  mov rax, -22
    ret
