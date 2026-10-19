.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themeintent.inc"
.text
tit_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 512
    cmp qword ptr [rip + g_argc], 5
    jne tit_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 8]
    call strlen
    mov rsi, rax
    mov rdi, [rbx + 8]
    call parse_u64
    cmp rdx, rsi
    jne tit_fail
    mov r12, rax
    mov r15, [rip + g_mem_live]
    mov rdi, rsp
    xor esi, esi
    mov edx, 512
    call memset
    mov [rsp + 424], r12
    mov rax, [rbx + 16]
    mov [rsp], rax
    mov [rsp + TIR_current], rax
    mov rax, [rbx + 24]
    mov [rsp + 8], rax
    mov rax, [rbx + 32]
    mov [rsp + 16], rax
    mov qword ptr [rsp + TIR_pending_dark], 1  # inactive dangling token must never be read
    mov qword ptr [rsp + 40], 0x111
    mov qword ptr [rsp + 48], 0x222
    mov qword ptr [rsp + 56], 0x333
    mov qword ptr [rsp + TIR_context], 1
    mov qword ptr [rsp + TIR_config], 2
    mov qword ptr [rsp + TIR_catalog], 3
    mov dword ptr [rsp + TIR_keys], 7
    mov dword ptr [rsp + TIR_follow], 1
    mov dword ptr [rsp + TIR_system], -1
    mov dword ptr [rsp + TIR_applied], 1
    mov dword ptr [rsp + TIR_palette_dark], 1
    cmp r12, 1
    jne 1f
    mov rax, [rbx + 16]
    mov [rsp + TIR_pending], rax
    mov rax, [rbx + 24]
    mov [rsp + TIR_pending_dark], rax
1:  cmp r12, 2
    jne 2f
    mov dword ptr [rsp + TIR_applied], 0
    mov qword ptr [rsp + TIR_current], 0
2:  cmp r12, 3
    jne 3f
    mov dword ptr [rsp + TIR_keys], 8
3:  cmp r12, 4
    jne 4f
    mov qword ptr [rsp + TIR_context], 0
4:  cmp r12, 5
    jne 5f
    mov dword ptr [rsp + TIR_follow], 2
5:  cmp r12, 6
    jne 6f
    mov qword ptr [rsp + TIR_current], 0
6:  mov rdi, rsp
    call theme_intent_capture
    mov [rsp + 440], rax
    mov [rsp + 304], rdx
    mov [rsp + 312], rcx
    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 320], rax
    mov r14, [rsp + 440]
    test rdx, rdx
    jnz .Ltit_emit
    test rcx, rcx
    jnz tit_fail
    test r14, r14
    jz tit_fail
    cmp qword ptr [rsp + 424], 8
    jne 7f
    mov qword ptr [r14 + TI_refs], -1
    mov rdi, r14
    call theme_intent_retain
    test rax, rax
    jnz tit_fail
    cmp rdx, -75
    jne tit_fail
    mov qword ptr [r14 + TI_refs], 1
7:  cmp qword ptr [rsp + 424], 9
    jne 8f
    mov rdi, r14
    call theme_intent_retain
    cmp rax, r14
    jne tit_fail
    test rdx, rdx
    jnz tit_fail
    mov rdi, r14
    call theme_intent_release
    test rax, rax
    jnz tit_fail
    cmp rdx, 1
    jne tit_fail
    cmp qword ptr [r14 + TI_refs], 1
    jne tit_fail
8:  mov rdi, r14
    call theme_intent_guard
    test rdx, rdx
    jnz tit_fail
    mov rdi, rax
    mov rsi, rsp
    mov edx, TIR_SIZE
    call memeq
    test eax, eax
    jz tit_fail
    cmp qword ptr [rsp + 424], 10
    jne 9f
    mov rdi, [rbx + 16]
    call strlen
    mov rdx, rax
    mov rdi, [rbx + 16]
    mov esi, 81
    call memset
9:  mov rdi, r14
    lea rsi, [rsp + 128]
    call theme_intent_view
    test rax, rax
    jnz tit_fail
.Ltit_emit:
    mov edi, 1
    lea rsi, [rsp + 304]
    mov edx, 24
    call write_all
    cmp qword ptr [rsp + 304], 0
    jne .Ltit_free
    mov edi, 1
    lea rsi, [rsp + 128 + 96]
    mov edx, 48
    call write_all
    mov edi, 1
    lea rsi, [rsp + 128 + 48]
    mov edx, 48
    call write_all
    xor r12d, r12d
1:  mov edi, 1
    mov rsi, [rsp + 128 + r12*8]
    mov rdx, [rsp + 128 + 48 + r12*8]
    call write_all
    test rax, rax
    jnz tit_fail
    inc r12
    cmp r12, 6
    jb 1b
.Ltit_free:
    mov rdi, [rsp + 440]
    call theme_intent_release
    test rax, rax
    jnz tit_fail
    cmp rdx, 1
    jne tit_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tit_fail
    cmp r15, [rip + g_mem_live]
    jne tit_fail
    xor eax, eax
    EPILOGUE
