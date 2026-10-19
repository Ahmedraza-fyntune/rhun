.ifdef WINDOWS
.include "win.inc"
.else
.include "rhun.inc"
.endif
.include "app/themecapture.inc"
.text
tcf_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 224
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 3
    jne tcf_fail
    mov rdi, [rbx + 16]
    call strlen
    mov r12, rax
    mov rsi, rax
    mov rdi, [rbx + 16]
    call parse_u64
    cmp rdx, r12
    jne tcf_fail
    mov r12, rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 72], rax
    call tcf_census
    mov [rsp + 80], rax
    mov rdi, rsp
    mov esi, 90
    mov edx, TCIO_SIZE
    call memset
    lea rdi, [rsp + 128]
    xor esi, esi
    mov edx, 64
    call memset
    call time_ms
    lea rcx, [rax + 10000]
    mov rdi, [rbx + 8]
    mov rsi, r12
    mov rdx, rsp
    call tc_file_capture
    mov [rsp + 128], rax
    mov [rsp + 136], rdx
    or rax, rdx
    jnz 2f
    mov rax, [rsp + TCIO_bytes]
    mov [rsp + 88], rax
    mov rax, [rsp + TCIO_length]
    mov [rsp + 144], rax
    lea rdi, [rsp + 152]
    lea rsi, [rsp + TCIO_digest]
    mov edx, 32
    call memcpy
    jmp 4f
2:  xor ecx, ecx
3:  cmp byte ptr [rsp + rcx], 90
    jne tcf_fail
    inc rcx
    cmp rcx, TCIO_SIZE
    jb 3b
    mov qword ptr [rsp + 88], 0
4:  mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 184], rax
    mov edi, 1
    lea rsi, [rsp + 128]
    mov edx, 64
    call write_all
    test rax, rax
    jnz tcf_fail
    mov rsi, [rsp + 88]
    test rsi, rsi
    jz 5f
    mov rdx, [rsp + 144]
    test rdx, rdx
    jz 5f
    mov edi, 1
    call write_all
    test rax, rax
    jnz tcf_fail
5:  mov rdi, [rsp + 88]
    call tc_free
    test rax, rax
    jnz tcf_fail
    mov rax, [rip + g_theme_capture_charge]
    mov [rsp + 192], rax
    test rax, rax
    jnz tcf_fail
    mov rax, [rip + g_mem_live]
    sub rax, [rsp + 72]
    mov [rsp + 200], rax
    test rax, rax
    jnz tcf_fail
    call tcf_census
    sub rax, [rsp + 80]
    mov [rsp + 208], rax
    test rax, rax
    jnz tcf_fail
    mov edi, 1
    lea rsi, [rsp + 192]
    mov edx, 24
    call write_all
    test rax, rax
    jnz tcf_fail
    xor eax, eax
    EPILOGUE
FN tcf_census
    PROLOGUE 112
.ifdef WINDOWS
    mov rcx, -1
    lea rdx, [rsp + 96]
    API GetProcessHandleCount
    test eax, eax
    jz tcf_fail
    mov eax, [rsp + 96]
.else
    xor ebx, ebx
    xor r12d, r12d
1:  mov rdi, rbx
    mov esi, 1
    xor edx, edx
    SYS SYS_fcntl
    test rax, rax
    js 2f
    inc r12
2:  inc rbx
    cmp rbx, 256
    jb 1b
    mov rax, r12
.endif
    EPILOGUE
