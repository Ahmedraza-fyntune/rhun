# Bounded state-log or null open with immediate retained host ownership.
.include "rhun.inc"
.text
# EXT,absolute log path,mode0append/1null ->0/-errno.
FN ext_host_log_open
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .Lhlo_bad
    cmp r13, 1
    ja .Lhlo_bad
    cmp dword ptr [rbx + EXT_activation_required], 1
    jne .Lhlo_bad
    cmp dword ptr [rbx + EXT_log], 0
    jns .Lhlo_busy
    cmp dword ptr [rbx + EXT_host_cleanup_mask], 0
    jne .Lhlo_busy
    test r13, r13
    jnz 1f
    mov rdi, r12
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lhlo_bad
    mov rdi, r12
    mov rsi, rax
    call prep_legacy_path_absolute
    test eax, eax
    jz .Lhlo_bad
1:
.ifdef WINDOWS
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call win_ext_host_log_open
.else
    mov rdi, r12
    mov esi, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC
    mov edx, 0644
    test r13, r13
    jz 2f
    lea rdi, [rip + eh_null]
    mov esi, O_WRONLY | O_CLOEXEC
    xor edx, edx
2:  SYS SYS_open
    test rax, rax
    js .Lhlo_done
    mov [rbx + EXT_log], eax
    mov edi, eax
    mov esi, 2
    mov edx, 1
    SYS SYS_fcntl
.endif
.Lhlo_done:
    EPILOGUE
.Lhlo_bad:
    mov rax, -22
    EPILOGUE
.Lhlo_busy:
    mov rax, -16
    EPILOGUE
.section .rodata
eh_null: .asciz "/dev/null"
