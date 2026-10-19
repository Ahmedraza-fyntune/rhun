# Bounded foreign clipboard decoding, including a source adjacent to an inaccessible page.
.include "win.inc"
.section .rodata
.p2align 3
wcr_vectors:
    .quad wcr_ascii,6,64,wcr_out_ascii,2,1
    .quad wcr_unicode,12,64,wcr_out_unicode,10,1
    .quad wcr_crlf,10,64,wcr_out_crlf,4,1
    .quad wcr_empty,2,0,wcr_out_empty,0,1
    .quad wcr_empty_room,2,64,wcr_out_empty_room,0,1
    .quad wcr_early_nul,8,64,wcr_out_early_nul,1,1
    .quad wcr_exact,6,2,wcr_out_exact,2,1
    .quad wcr_below,6,1,wcr_out_below,0,0
    .quad wcr_nonempty_zero,4,0,wcr_out_nonempty_zero,0,0
    .quad wcr_unicode_exact,4,2,wcr_out_unicode_exact,2,1
    .quad wcr_unicode_below,4,1,wcr_out_unicode_below,0,0
    .quad wcr_emoji_exact,6,4,wcr_out_emoji_exact,4,1
    .quad wcr_emoji_below,6,3,wcr_out_emoji_below,0,0
    .quad 0,2,64,wcr_out_nil,0,0
    .quad wcr_zero_bytes,0,64,wcr_out_zero_bytes,0,0
    .quad wcr_one_byte,1,64,wcr_out_one_byte,0,0
    .quad wcr_unterminated,4,64,wcr_out_unterminated,0,0
    .quad wcr_odd_terminated,5,64,wcr_out_odd_terminated,1,1
    .quad wcr_odd_unterminated,3,64,wcr_out_odd_unterminated,0,0
    .quad wcr_high,4,64,wcr_out_high,0,0
    .quad wcr_low,4,64,wcr_out_low,0,0
    .quad wcr_reversed,6,64,wcr_out_reversed,0,0
    .quad wcr_high_then_ascii,6,64,wcr_out_high_then_ascii,0,0
    .quad wcr_truncated_high,2,64,wcr_out_truncated_high,0,0
    .quad 1,2,-1,wcr_out_invalid_negative,0,0
    .quad 1,2,67108865,wcr_out_invalid_large,0,0
    .quad wcr_hard_cap_empty,2,67108864,wcr_out_hard_cap_empty,0,1
    .quad wcr_unpaired_after_nul,4,0,wcr_out_unpaired_after_nul,0,1
    .quad -1,0,0,0,0,0
wcr_ascii: .byte 65,0,66,0,0,0
wcr_out_ascii: .byte 65,66
wcr_unicode: .byte 97,0,233,0,52,108,61,216,0,222,0,0
wcr_out_unicode: .byte 97,195,169,230,176,180,240,159,152,128
wcr_crlf: .byte 65,0,13,0,10,0,66,0,0,0
wcr_out_crlf: .byte 65,13,10,66
wcr_empty: .byte 0,0
wcr_out_empty: .byte 0
wcr_empty_room: .byte 0,0
wcr_out_empty_room: .byte 0
wcr_early_nul: .byte 65,0,0,0,0,216,255,255
wcr_out_early_nul: .byte 65
wcr_exact: .byte 65,0,66,0,0,0
wcr_out_exact: .byte 65,66
wcr_below: .byte 65,0,66,0,0,0
wcr_out_below: .byte 0
wcr_nonempty_zero: .byte 65,0,0,0
wcr_out_nonempty_zero: .byte 0
wcr_unicode_exact: .byte 233,0,0,0
wcr_out_unicode_exact: .byte 195,169
wcr_unicode_below: .byte 233,0,0,0
wcr_out_unicode_below: .byte 0
wcr_emoji_exact: .byte 61,216,0,222,0,0
wcr_out_emoji_exact: .byte 240,159,152,128
wcr_emoji_below: .byte 61,216,0,222,0,0
wcr_out_emoji_below: .byte 0
wcr_nil: .byte 0,0
wcr_out_nil: .byte 0
wcr_zero_bytes: .byte 0,0
wcr_out_zero_bytes: .byte 0
wcr_one_byte: .byte 0,0
wcr_out_one_byte: .byte 0
wcr_unterminated: .byte 65,0,66,0
wcr_out_unterminated: .byte 0
wcr_odd_terminated: .byte 65,0,0,0,255,255
wcr_out_odd_terminated: .byte 65
wcr_odd_unterminated: .byte 65,0,66,0
wcr_out_odd_unterminated: .byte 0
wcr_high: .byte 0,216,0,0
wcr_out_high: .byte 0
wcr_low: .byte 0,220,0,0
wcr_out_low: .byte 0
wcr_reversed: .byte 0,220,0,216,0,0
wcr_out_reversed: .byte 0
wcr_high_then_ascii: .byte 0,216,65,0,0,0
wcr_out_high_then_ascii: .byte 0
wcr_truncated_high: .byte 0,216
wcr_out_truncated_high: .byte 0
wcr_invalid_negative: .byte 0,0
wcr_out_invalid_negative: .byte 0
wcr_invalid_large: .byte 0,0
wcr_out_invalid_large: .byte 0
wcr_hard_cap_empty: .byte 0,0
wcr_out_hard_cap_empty: .byte 0
wcr_unpaired_after_nul: .byte 0,0,0,220
wcr_out_unpaired_after_nul: .byte 0
wcr_ok: .ascii "ok Windows bounded clipboard read\n"
.equ wcr_ok_len, . - wcr_ok
.text
FN main
    PROLOGUE 128
    mov r14, [rip + g_mem_live]
    lea r12, [rip + wcr_vectors]
    mov r13d, 1
.Lwcr_vector:
    cmp qword ptr [r12], -1
    je .Lwcr_guard
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    call win_clip_decode
    mov [rsp + 96], rax
    cmp qword ptr [r12 + 40], 0
    je .Lwcr_rejected
    test rax, rax
    jz wcr_failed
    cmp rdx, [r12 + 32]
    jne wcr_failed
    cmp byte ptr [rax + rdx], 0
    jne wcr_failed
    mov rdi, rax
    mov rsi, [r12 + 24]
    call memeq
    test eax, eax
    jz wcr_failed
    mov rdi, [rsp + 96]
    call mem_free
    jmp .Lwcr_next
.Lwcr_rejected:
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
.Lwcr_next:
    cmp r14, [rip + g_mem_live]
    jne wcr_failed
    inc r13
    add r12, 48
    jmp .Lwcr_vector
.Lwcr_guard:
    mov r13d, 100
    xor ecx, ecx
    mov edx, 8192
    mov r8d, 0x2000             # reserve two pages, commit only the first
    mov r9d, 4
    API VirtualAlloc
    test rax, rax
    jz wcr_failed
    mov rbx, rax
    mov rcx, rax
    mov edx, 4096
    mov r8d, 0x1000
    mov r9d, 4
    API VirtualAlloc
    cmp rax, rbx
    jne wcr_failed
    mov word ptr [rbx + 4094], 'X'
    lea rdi, [rbx + 4094]
    mov esi, 2
    mov edx, 64
    call win_clip_decode
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    lea rdi, [rbx + 4095]
    mov esi, 1
    mov edx, 64
    call win_clip_decode
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    mov word ptr [rbx + 4094], 0
    lea rdi, [rbx + 4094]
    mov esi, 2
    xor edx, edx
    call win_clip_decode
    test rax, rax
    jz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    cmp byte ptr [rax], 0
    jne wcr_failed
    mov rdi, rax
    call mem_free
    mov rcx, rbx
    xor edx, edx
    mov r8d, 0x8000
    API VirtualFree
    test eax, eax
    jz wcr_failed
    cmp r14, [rip + g_mem_live]
    jne wcr_failed

    # The HGLOBAL reader must bound itself by the full actual allocation, including padding.
    mov r13d, 110
    mov ecx, 2
    mov edx, 12
    API GlobalAlloc
    test rax, rax
    jz wcr_failed
    mov rbx, rax
    mov rcx, rax
    API GlobalLock
    test rax, rax
    jz wcr_failed
    mov rdi, rax
    lea rsi, [rip + wcr_unicode]
    mov edx, 12
    call memcpy
    mov rcx, rbx
    API GlobalUnlock
    mov rdi, rbx
    mov esi, 9
    call win_clip_read_handle
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    mov rdi, rbx
    mov esi, 10
    call win_clip_read_handle
    test rax, rax
    jz wcr_failed
    cmp rdx, 10
    jne wcr_failed
    mov r15, rax
    mov rcx, rbx
    API GlobalFree             # returned text owns its bytes independently
    test rax, rax
    jnz wcr_failed
    mov rdi, r15
    lea rsi, [rip + wcr_out_unicode]
    mov edx, 10
    call memeq
    test eax, eax
    jz wcr_failed
    cmp byte ptr [r15 + 10], 0
    jne wcr_failed
    mov rdi, r15
    call mem_free
    cmp r14, [rip + g_mem_live]
    jne wcr_failed

    mov r13d, 120
    mov ecx, 2
    mov edx, 2
    API GlobalAlloc
    test rax, rax
    jz wcr_failed
    mov rbx, rax
    mov rcx, rax
    API GlobalSize
    test rax, rax
    jz wcr_failed
    mov r12, rax
    mov rcx, rbx
    API GlobalLock
    test rax, rax
    jz wcr_failed
    mov rdi, rax
    mov esi, 0x41
    mov rdx, r12
    call memset
    mov rcx, rbx
    API GlobalUnlock
    mov rdi, rbx
    mov esi, 64
    call win_clip_read_handle
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    mov rcx, rbx
    API GlobalFree
    test rax, rax
    jnz wcr_failed
    xor edi, edi
    mov esi, 64
    call win_clip_read_handle
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    mov ecx, 2
    xor edx, edx
    API GlobalAlloc            # discarded, zero-sized movable allocation
    test rax, rax
    jz wcr_failed
    mov rbx, rax
    mov rdi, rax
    mov esi, 64
    call win_clip_read_handle
    test rax, rax
    jnz wcr_failed
    test rdx, rdx
    jnz wcr_failed
    mov rcx, rbx
    API GlobalFree
    test rax, rax
    jnz wcr_failed
    cmp r14, [rip + g_mem_live]
    jne wcr_failed

    mov r13d, 130
    mov edi, 262146
    call mem_alloc
    mov rbx, rax
    xor ecx, ecx
1:  mov word ptr [rbx + rcx*2], 'x'
    inc ecx
    cmp ecx, 131072
    jb 1b
    mov rdi, rbx
    mov esi, 262146
    mov edx, 131072
    call win_clip_decode
    test rax, rax
    jz wcr_failed
    cmp rdx, 131072
    jne wcr_failed
    mov r15, rax
    mov rdi, rbx
    call mem_free
    xor ecx, ecx
1:  cmp byte ptr [r15 + rcx], 'x'
    jne wcr_failed
    inc ecx
    cmp ecx, 131072
    jb 1b
    cmp byte ptr [r15 + 131072], 0
    jne wcr_failed
    mov rdi, r15
    call mem_free
    cmp r14, [rip + g_mem_live]
    jne wcr_failed
    lea rdi, [rip + wcr_ok]
    mov esi, offset wcr_ok_len
    call log_write
    xor eax, eax
    EPILOGUE
wcr_failed:
    mov edi, r13d
    SYS SYS_exit
