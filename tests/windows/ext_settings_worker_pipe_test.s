.include "win.inc"
.section .rodata
swf_ok: .asciz "ok helper raw pipe preflight and native failures\n"
.bss
.p2align 3
swf_io: .zero 24
swf_buffer: .zero 16
swf_mode: .quad 0
swf_set: .quad 0
swf_read: .quad 0
swf_write: .quad 0
swf_stage: .quad 0
.text
FN main
    PROLOGUE
    lea rbx, [rip + swf_io]
    mov qword ptr [rip + swf_stage], 1
    mov qword ptr [rip + swf_mode], 1
    mov rdi, rbx
    call ext_settings_worker_io_init
    cmp rax, -22
    jne .Lswf_fail
    cmp qword ptr [rip + swf_set], 0
    jne .Lswf_fail
    mov qword ptr [rip + swf_stage], 2
    mov qword ptr [rip + swf_mode], 2
    mov rdi, rbx
    call ext_settings_worker_io_init
    cmp rax, -13
    jne .Lswf_fail
    cmp qword ptr [rbx + 16], 0
    jne .Lswf_fail
    call swf_try_read
    cmp rax, -9
    jne .Lswf_fail
    call swf_try_write
    cmp rax, -9
    jne .Lswf_fail
    cmp qword ptr [rip + swf_read], 0
    jne .Lswf_fail
    cmp qword ptr [rip + swf_write], 0
    jne .Lswf_fail
    mov qword ptr [rip + swf_stage], 3
    mov qword ptr [rip + swf_mode], 3
    mov rdi, rbx
    call ext_settings_worker_io_init
    cmp rax, -9
    jne .Lswf_fail
    mov qword ptr [rip + swf_mode], 0
    mov rdi, rbx
    call ext_settings_worker_io_init
    test rax, rax
    jnz .Lswf_fail
    cmp qword ptr [rbx + 16], 1
    jne .Lswf_fail
    # Empty input is quiet, empty write means backpressure, never false EOF.
    mov qword ptr [rip + swf_stage], 4
    mov qword ptr [rip + swf_mode], 4
    call swf_try_read
    cmp rax, -11
    jne .Lswf_fail
    mov rdi, rbx
    call ext_settings_worker_io_probe
    test rax, rax
    jnz .Lswf_fail
    call swf_try_write
    cmp rax, -11
    jne .Lswf_fail
    # Broken input is EOF/cancel, broken output is EPIPE.
    mov qword ptr [rip + swf_stage], 5
    mov qword ptr [rip + swf_mode], 5
    call swf_try_read
    test rax, rax
    jnz .Lswf_fail
    mov rdi, rbx
    call ext_settings_worker_io_probe
    cmp rax, -125
    jne .Lswf_fail
    call swf_try_write
    cmp rax, -32
    jne .Lswf_fail
    # Available input clamps ReadFile request, even with a much larger caller buffer.
    mov qword ptr [rip + swf_stage], 6
    mov qword ptr [rip + swf_mode], 6
    call swf_try_read
    cmp rax, 3
    jne .Lswf_fail
    cmp dword ptr [rip + swf_buffer], 0x00636261
    jne .Lswf_fail
    mov rdi, rbx
    call ext_settings_worker_io_probe
    cmp rax, -71
    jne .Lswf_fail
    call swf_try_write
    cmp rax, 3
    jne .Lswf_fail
    # Native overcount cannot authorize consumption beyond the submitted bytes.
    mov qword ptr [rip + swf_stage], 7
    mov qword ptr [rip + swf_mode], 7
    call swf_try_read
    cmp rax, -5
    jne .Lswf_fail
    call swf_try_write
    cmp rax, -5
    jne .Lswf_fail
    mov qword ptr [rip + swf_stage], 8
    mov qword ptr [rip + swf_mode], 8
    call swf_try_read
    cmp rax, -13
    jne .Lswf_fail
    mov rdi, rbx
    call ext_settings_worker_io_probe
    cmp rax, -13
    jne .Lswf_fail
    # A default4KiB byte pipe must never receive a larger nonblocking write attempt.
    mov qword ptr [rip + swf_stage], 9
    mov qword ptr [rip + swf_mode], 9
    mov rdi, rbx
    lea rsi, [rip + swf_buffer]
    mov edx, 65536
    call ext_settings_worker_io_write
    cmp rax, 4096
    jne .Lswf_fail
    mov edi, 1
    lea rsi, [rip + swf_ok]
    mov edx, 49
    call write_all
    xor eax, eax
    EPILOGUE
.Lswf_fail:
    mov rdi, [rip + swf_stage]
    add edi, 30
    jmp sys_exit
swf_try_read:
    mov rdi, rbx
    lea rsi, [rip + swf_buffer]
    mov edx, 65536
    jmp ext_settings_worker_io_read
swf_try_write:
    mov rdi, rbx
    lea rsi, [rip + swf_buffer]
    mov edx, 8
    jmp ext_settings_worker_io_write

# Typed Win64 shims intercept this module only; runtime output remains native.
FN swf_GetStdHandle
    cmp qword ptr [rip + swf_mode], 3
    je 2f
    cmp ecx, -10
    jne 1f
    mov eax, 0x1234
    ret
1:  cmp ecx, -11
    jne .Lswf_fail
    mov eax, 0x5678
    ret
2:  xor eax, eax
    ret
FN swf_GetFileType
    mov eax, 3
    cmp qword ptr [rip + swf_mode], 1
    jne 1f
    mov eax, 1
1:  ret
FN swf_SetNamedPipeHandleState
    cmp rcx, 0x5678
    jne .Lswf_fail
    cmp dword ptr [rdx], 1
    jne .Lswf_fail
    test r8, r8
    jnz .Lswf_fail
    test r9, r9
    jnz .Lswf_fail
    inc qword ptr [rip + swf_set]
    cmp qword ptr [rip + swf_mode], 2
    je swf_access_denied
    mov eax, 1
    ret
FN swf_PeekNamedPipe
    cmp rcx, 0x1234
    jne .Lswf_fail
    cmp qword ptr [rip + swf_mode], 5
    je swf_broken
    cmp qword ptr [rip + swf_mode], 8
    je swf_access_denied
    mov rax, [rsp + 40]
    mov dword ptr [rax], 9
    cmp qword ptr [rip + swf_mode], 4
    jne 1f
    mov dword ptr [rax], 0
1:  mov eax, 1
    ret
FN swf_ReadFile
    cmp rcx, 0x1234
    jne .Lswf_fail
    inc qword ptr [rip + swf_read]
    cmp r8d, 9
    ja .Lswf_fail
    cmp qword ptr [rip + swf_mode], 7
    je 2f
    mov byte ptr [rdx], 'a'
    mov eax, 1
    cmp r8d, 1
    je 1f
    mov word ptr [rdx + 1], 0x6362
    mov eax, 3
1:  mov [r9], eax
    mov eax, 1
    ret
2:  inc r8d
    mov [r9], r8d
    mov eax, 1
    ret
FN swf_WriteFile
    cmp rcx, 0x5678
    jne .Lswf_fail
    inc qword ptr [rip + swf_write]
    cmp qword ptr [rip + swf_mode], 9
    jne 2f
    cmp r8d, 4096
    jne .Lswf_fail
    mov dword ptr [r9], 4096
    mov eax, 1
    ret
2:  cmp qword ptr [rip + swf_mode], 5
    je swf_broken
    xor eax, eax
    cmp qword ptr [rip + swf_mode], 4
    je 1f
    mov eax, 3
    cmp qword ptr [rip + swf_mode], 7
    jne 1f
    lea eax, [r8d + 1]
1:  mov [r9], eax
    mov eax, 1
    ret
swf_access_denied:
    CALLBACK 96
    mov ecx, 5
    API SetLastError
    xor eax, eax
    CALLBACK_END 96
swf_broken:
    CALLBACK 96
    mov ecx, 109
    API SetLastError
    xor eax, eax
    CALLBACK_END 96
