# Persistent OVERLAPPED input for the fixed settings worker, never virtual FD wrappers.
.include "win.inc"
.include "app/extstorejob.inc"
.include "app/extsettingsnative.inc"
.include "app/extchoicesdisk.inc"
.section .rdata,"dr"
ecnw_prefix: .asciz "\\\\.\\pipe\\rhun-settings-"
.text
# Retire native operation only when its actual completion is proven.
FN ext_settings_native_windows_input
    PROLOGUE 160
    mov rbx, rdi
    lea rsi, [rip + ecnw_prefix]
    lea rdi, [rbx + ECN_pipe]
    xor ecx, ecx
1:  movzx eax, byte ptr [rsi + rcx]
    test eax, eax
    jz 2f
    mov word ptr [rdi + rcx*2], ax
    inc rcx
    jmp 1b
2:  lea rdi, [rdi + rcx*2]
    xor ecx, ecx
3:  movzx eax, byte ptr [rbx + ESJ_noncehex + rcx]
    mov word ptr [rdi + rcx*2], ax
    inc rcx
    cmp rcx, 33
    jb 3b
    lea rdi, [rbx + ECN_security]
    call ext_choices_security_prepare
    test rax, rax
    js .Lecnw_input_return
    mov qword ptr [rsp + 96], 24
    mov rax, [rbx + ECN_security + ECP_security]
    mov [rsp + 104], rax
    mov qword ptr [rsp + 112], 0
    lea rcx, [rbx + ECN_pipe]
    mov edx, 0x40080002      # outbound, first instance, OVERLAPPED
    mov r8d, 8              # byte pipe, remote clients rejected
    mov r9d, 1
    mov qword ptr [rsp + 32], 4096
    mov qword ptr [rsp + 40], 0
    mov qword ptr [rsp + 48], 0
    lea rax, [rsp + 96]
    mov [rsp + 56], rax
    API CreateNamedPipeW
    cmp rax, -1
    je .Lecnw_input_api
    mov [rbx + ECN_input], rax
    xor ecx, ecx
    mov edx, 1
    xor r8d, r8d
    xor r9d, r9d
    API CreateEventW
    test rax, rax
    jz .Lecnw_input_api
    mov [rbx + ECN_event], rax
    mov [rbx + ECN_overlapped + 24], rax
    mov rcx, [rbx + ECN_input]
    lea rdx, [rbx + ECN_overlapped]
    API ConnectNamedPipe
    test eax, eax
    jnz .Lecnw_client
    API GetLastError
    cmp eax, 535            # already connected
    je .Lecnw_client
    cmp eax, 997
    jne .Lecnw_input_api
    mov qword ptr [rbx + ECN_operation], 1
.Lecnw_client:
    mov qword ptr [rsp + 112], 1
    lea rcx, [rbx + ECN_pipe]
    mov edx, 0x80000000
    xor r8d, r8d
    lea r9, [rsp + 96]
    mov qword ptr [rsp + 32], 3
    mov qword ptr [rsp + 40], 0x80
    mov qword ptr [rsp + 48], 0
    API CreateFileW
    cmp rax, -1
    je .Lecnw_input_api
    mov [rbx + ESJ_native + 32], rax
    cmp qword ptr [rbx + ECN_operation], 0
    je .Lecnw_security
    mov rdi, rbx
    mov esi, 65536
    call ext_settings_native_write_poll
    test rax, rax
    js .Lecnw_input_return
    jz .Lecnw_input_pending
.Lecnw_security:
    lea rdi, [rbx + ECN_security]
    call ext_choices_security_free
.Lecnw_input_return:
    EPILOGUE
.Lecnw_input_api:
    call win_error
    EPILOGUE
.Lecnw_input_pending:
    mov rax, -115
    EPILOGUE

FN ext_settings_native_close_input
    PROLOGUE 96
    mov rbx, rdi
    test rbx, rbx
    jz .Lecnw_close_bad
    cmp qword ptr [rbx + ECN_operation], 0
    je .Lecnw_close_now
    cmp qword ptr [rbx + ECN_closing], 0
    jne .Lecnw_close_pending
    mov qword ptr [rbx + ECN_closing], 1
    mov rcx, [rbx + ECN_input]
    lea rdx, [rbx + ECN_overlapped]
    API CancelIoEx
    test eax, eax
    jnz .Lecnw_close_pending
    call win_error
    jmp .Lecnw_close_note
.Lecnw_close_now:
    mov qword ptr [rbx + ECN_closing], 1
    mov rax, [rbx + ECN_offset]
    mov [rbx + ECN_length], rax
    cmp qword ptr [rbx + ECN_debt], 0
    jne 2f
    mov qword ptr [rbx + ECN_length], 0
    mov qword ptr [rbx + ECN_offset], 0
2:  mov rcx, [rbx + ECN_input]
    mov qword ptr [rbx + ECN_input], -1
    cmp rcx, -1
    je .Lecnw_close_ok
    API CloseHandle
    test eax, eax
    jnz .Lecnw_close_ok
    call win_error
.Lecnw_close_note:
    cmp qword ptr [rbx + ECN_cleanup], 0
    jne 1f
    mov [rbx + ECN_cleanup], rax
1:  EPILOGUE
.Lecnw_close_pending:
    mov rax, -115
    EPILOGUE
.Lecnw_close_ok:
    xor eax, eax
    EPILOGUE
.Lecnw_close_bad:
    mov rax, -22
    EPILOGUE

FN ext_settings_native_write_poll
    PROLOGUE 128
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
    test rbx, rbx
    jz .Lecnw_poll_bad
    test r12, r12
    jz .Lecnw_poll_bad
    cmp r12, 65536
    ja .Lecnw_poll_bad
    mov rax, [rbx + ECN_operation]
    test rax, rax
    jnz .Lecnw_observe
    mov rax, [rbx + ECN_write_error]
    test rax, rax
    js .Lecnw_poll_return
    cmp qword ptr [rbx + ECN_debt], 0
    jne .Lecnw_charge
    cmp qword ptr [rbx + ECN_length], 0
    je .Lecnw_poll_done
    cmp qword ptr [rbx + ECN_closing], 0
    jne .Lecnw_poll_done
    mov r14, [rbx + ECN_length]
    sub r14, [rbx + ECN_offset]
    cmp r14, r12
    jbe 1f
    mov r14, r12
1:  lea rdi, [rbx + ECN_overlapped]
    xor esi, esi
    mov edx, 32
    call memset
    mov rax, [rbx + ECN_event]
    mov [rbx + ECN_overlapped + 24], rax
    mov [rbx + ECN_request], r14
    mov qword ptr [rbx + ECN_submitted], 1
    mov qword ptr [rbx + ECN_operation], 2
    mov rcx, [rbx + ECN_input]
    lea rdx, [rbx + ECN_chunk]
    add rdx, [rbx + ECN_offset]
    mov r8d, r14d
    lea r9, [rsp + 96]
    lea rax, [rbx + ECN_overlapped]
    mov [rsp + 32], rax
    API WriteFile
    test eax, eax
    jnz .Lecnw_written
    API GetLastError
    cmp eax, 997
    je .Lecnw_poll_pending
    cmp qword ptr [rbx + ECN_overlapped], 259
    je .Lecnw_poll_observation
    mov qword ptr [rbx + ECN_operation], 0
    call win_error
    jmp .Lecnw_poll_error
.Lecnw_observe:
    mov rcx, [rbx + ECN_input]
    lea rdx, [rbx + ECN_overlapped]
    lea r8, [rsp + 96]
    xor r9d, r9d
    API GetOverlappedResult
    test eax, eax
    jnz .Lecnw_observed
    API GetLastError
    cmp eax, 996
    je .Lecnw_poll_pending
    cmp eax, 997
    je .Lecnw_poll_pending
    cmp qword ptr [rbx + ECN_overlapped], 259
    je .Lecnw_poll_observation
    # A failed observation of a successful/ informational completion has not supplied
    # its byte count. Keep the exact request until a successful observation accounts it.
    cmp dword ptr [rbx + ECN_overlapped], 0
    jge .Lecnw_poll_observation
    mov qword ptr [rbx + ECN_operation], 0
    call win_error
    jmp .Lecnw_poll_error
.Lecnw_observed:
    cmp qword ptr [rbx + ECN_operation], 1
    jne .Lecnw_written
    mov qword ptr [rbx + ECN_operation], 0
    jmp .Lecnw_poll_done
.Lecnw_written:
    mov qword ptr [rbx + ECN_operation], 0
    mov eax, [rsp + 96]
    test eax, eax
    jz .Lecnw_poll_io
    cmp rax, [rbx + ECN_request]
    ja .Lecnw_poll_io
    add [rbx + ECN_offset], rax
    mov [rbx + ECN_debt], rax
.Lecnw_charge:
    mov r13, [rbx + ECN_debt]
    cmp r13, r12
    jbe 2f
    mov r13, r12
2:  sub [rbx + ECN_debt], r13
    cmp qword ptr [rbx + ECN_debt], 0
    jne .Lecnw_poll_pending
    mov rax, [rbx + ECN_offset]
    cmp rax, [rbx + ECN_length]
    jb .Lecnw_poll_pending
    mov qword ptr [rbx + ECN_length], 0
    mov qword ptr [rbx + ECN_offset], 0
.Lecnw_poll_done:
    mov eax, 1
    jmp .Lecnw_poll_return
.Lecnw_poll_io:
    mov rax, -5
.Lecnw_poll_error:
    mov [rbx + ECN_write_error], rax
    mov qword ptr [rbx + ECN_length], 0
    mov qword ptr [rbx + ECN_offset], 0
    mov qword ptr [rbx + ECN_debt], 0
    jmp .Lecnw_poll_return
.Lecnw_poll_observation:
    call win_error
    jmp .Lecnw_poll_return
.Lecnw_poll_pending:
    xor eax, eax
.Lecnw_poll_return:
    mov rdx, r13
    mov rcx, [rbx + ECN_submitted]
    EPILOGUE
.Lecnw_poll_bad:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
