# Distinct source-only legacy content commitment.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
FN ext_prepare_legacy_source_commitment
    cmp qword ptr [rdi + PO_ready], 1
    jne .Leplsc_bad
    PROLOGUE SH256_SIZE + 32
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsp
    call sha256_init
    mov rdi, rsp
    lea rsi, [rip + epls_domain]
    mov edx, 23
    call sha256_update
    mov eax, [rbx + EP_sources + VEC_len]
    mov [rsp + SH256_SIZE], eax
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    xor r13d, r13d
1:  cmp r13, [rbx + EP_sources + VEC_len]
    jae 2f
    imul r14, r13, SR_SIZE
    add r14, [rbx + EP_sources + VEC_ptr]
    mov eax, [r14 + SR_len]
    mov [rsp + SH256_SIZE], eax
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    mov rdi, rsp
    mov rsi, [r14 + SR_path]
    mov rdx, [r14 + SR_len]
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_size]
    mov edx, 8
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_exec]
    mov edx, 4
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_hash]
    mov edx, 32
    call sha256_update
    mov rdi, rsp
    lea rsi, [r14 + SR_roles]
    mov edx, 4
    call sha256_update
    inc r13
    jmp 1b
2:  mov rdi, [rbx + EP_ext + EXT_prog]
    call strlen
    mov [rsp + SH256_SIZE], eax
    mov r14, rax
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    mov rdi, rsp
    mov rsi, [rbx + EP_ext + EXT_prog]
    mov rdx, r14
    call sha256_update
    mov rdi, [rbx + EP_ext + EXT_script]
    xor r14d, r14d
    test rdi, rdi
    jz 3f
    call strlen
    mov r14, rax
3:  mov [rsp + SH256_SIZE], r14d
    mov rdi, rsp
    lea rsi, [rsp + SH256_SIZE]
    mov edx, 4
    call sha256_update
    test r14, r14
    jz 4f
    mov rdi, rsp
    mov rsi, [rbx + EP_ext + EXT_script]
    mov rdx, r14
    call sha256_update
4:  mov rdi, rsp
    mov rsi, r12
    call sha256_final
    xor eax, eax
    EPILOGUE
.Leplsc_bad:
    mov rax, -EV_BAD_PREPARE
    ret
.section .rodata
epls_domain: .asciz "rhun-legacy-sources-v1"
