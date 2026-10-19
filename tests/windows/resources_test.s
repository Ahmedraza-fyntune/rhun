# The resources group's Windows parts, called directly: secrets in the Credential Manager
# (win_cred_op: set, a value split over two credentials, get, keys, delete, clear) and what a
# child's job costs (proc_usage on a copy of this program that burns CPU). "burn" as the only
# argument makes this program the child.
.include "win.inc"
.equ BIG, 3000                  # over one credential's 2560 bytes
.bss
.p2align 3
sr: .quad 0
usage: .zero 32
big: .zero BIG
.text
FN main
    PROLOGUE 64
    cmp qword ptr [rip + g_argc], 2
    jne 1f
    # the child: about 600 ms of CPU
    call time_ms
    lea rbx, [rax + 600]
0:  call time_ms
    cmp rax, rbx
    jb 0b
    xor eax, eax
    EPILOGUE
1:  mov edi, SECR_SIZE
    call mem_alloc
    mov [rip + sr], rax
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, SECR_SIZE - SECRET_BUF
    call memset
    lea rax, [rip + .Lservice]
    mov [rbx + SECR_service], rax
    # a value of BIG bytes: two credentials
    lea rdi, [rip + big]
    mov esi, 'z'
    mov edx, BIG
    call memset
    mov byte ptr [rip + big + BIG - 1], 'E'
    lea rax, [rip + .Ltoken]
    mov [rbx + SECR_key], rax
    lea rax, [rip + big]
    mov [rbx + SECR_val], rax
    mov qword ptr [rbx + SECR_len], BIG
    mov edi, SECO_SET
    call op
    jnz .Lfail_set
    mov edi, SECO_GET
    call op
    jnz .Lfail_get
    cmp qword ptr [rbx + SECR_outlen], BIG
    jne .Lfail_get
    cmp byte ptr [rbx + SECR_buf + BIG - 1], 'E'
    jne .Lfail_get
    # a second key, then the keys
    lea rax, [rip + .Lother]
    mov [rbx + SECR_key], rax
    mov qword ptr [rbx + SECR_len], 1
    mov edi, SECO_SET
    call op
    jnz .Lfail_set
    mov edi, SECO_KEYS
    call op
    jnz .Lfail_keys
    cmp qword ptr [rbx + SECR_outlen], 12     # "token\nother\n" in some order
    jne .Lfail_keys
    # delete: gone, and a get says none
    lea rax, [rip + .Ltoken]
    mov [rbx + SECR_key], rax
    mov edi, SECO_DELETE
    call op
    jnz .Lfail_delete
    mov edi, SECO_GET
    call op_status
    cmp eax, SECS_NONE
    jne .Lfail_delete
    # a shorter value replaces the long one without its old second part
    mov qword ptr [rbx + SECR_len], 5
    mov edi, SECO_SET
    call op
    jnz .Lfail_set
    mov edi, SECO_GET
    call op
    cmp qword ptr [rbx + SECR_outlen], 5
    jne .Lfail_get
    # clear: nothing left
    mov edi, SECO_CLEAR
    call op
    jnz .Lfail_clear
    mov edi, SECO_KEYS
    call op
    cmp qword ptr [rbx + SECR_outlen], 0
    jne .Lfail_clear
    lea rdi, [rip + .Lok_secrets]
    call log_cstr
    # proc_usage: this program again, burning CPU in its own job
    mov rax, [rip + g_argv]
    mov rax, [rax]
    mov [rsp + 32], rax
    lea rax, [rip + .Lburn]
    mov [rsp + 40], rax
    mov qword ptr [rsp + 48], 0
    lea rdi, [rsp + 32]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    mov r8d, 1
    mov r9d, 2
    push 0
    push 0
    call proc_spawn
    add rsp, 16
    test rax, rax
    jle .Lfail_spawn
    mov r12, rax
    lea rdi, [rip + nap]
    SYS 35                      # nanosleep: 400 ms
    mov rdi, r12
    lea rsi, [rip + usage]
    call proc_usage
    test rax, rax
    js .Lfail_usage
    cmp qword ptr [rip + usage + 16], 1
    jb .Lfail_usage
    cmp qword ptr [rip + usage + 8], 0
    je .Lfail_usage
    mov rdi, r12
    xor esi, esi
    call proc_wait
    lea rdi, [rip + .Lok_usage]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail_set:
    lea rdi, [rip + .Le_set]
    jmp .Lfail
.Lfail_get:
    lea rdi, [rip + .Le_get]
    jmp .Lfail
.Lfail_keys:
    lea rdi, [rip + .Le_keys]
    jmp .Lfail
.Lfail_delete:
    lea rdi, [rip + .Le_delete]
    jmp .Lfail
.Lfail_clear:
    lea rdi, [rip + .Le_clear]
    jmp .Lfail
.Lfail_spawn:
    lea rdi, [rip + .Le_spawn]
    jmp .Lfail
.Lfail_usage:
    lea rdi, [rip + .Le_usage]
.Lfail:
    call log_cstr
    mov edi, 1
    call sys_exit

# op(op) -> ZF set when the store answered SECS_OK
op:
    call op_status
    test eax, eax
    ret
# op_status(op) -> eax SECR_status
op_status:
    push rbx
    mov rbx, [rip + sr]
    mov [rbx + SECR_op], edi
    mov rdi, rbx
    call win_cred_op
    mov eax, [rbx + SECR_status]
    pop rbx
    ret

.data
.p2align 3
nap: .quad 0, 400000000
.section .rodata
.Lservice: .asciz "rhun-test-windows rt/res"
.Ltoken: .asciz "token"
.Lother: .asciz "other"
.Lburn: .asciz "burn"
.Lok_secrets: .asciz "ok secrets in the Credential Manager\n"
.Lok_usage: .asciz "ok the job's CPU, memory and processes\n"
.Le_set: .asciz "FAIL set\n"
.Le_get: .asciz "FAIL get\n"
.Le_keys: .asciz "FAIL keys\n"
.Le_delete: .asciz "FAIL delete\n"
.Le_clear: .asciz "FAIL clear\n"
.Le_spawn: .asciz "FAIL spawn\n"
.Le_usage: .asciz "FAIL proc_usage\n"
