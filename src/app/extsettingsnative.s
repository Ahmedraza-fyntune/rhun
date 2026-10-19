# Fixed settings-worker capsule. No ESJ model registry or publication protocol here.
.include "rhun.inc"
.include "app/extstorejob.inc"
.include "app/extsettingsnative.inc"
.include "app/extchoicesdisk.inc"
.section .rodata
ecn_marker: .asciz "--extension-settings-worker"
ecn_theme_marker: .asciz "--theme-source-worker"
ecn_version: .asciz "v1"
ecn_hex: .ascii "0123456789abcdef"
.text
ecn_cleanup_note:
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + ECN_cleanup], 0
    jne 1f
    mov [rdi + ECN_cleanup], rsi
1:  ret
FN ext_settings_native_start
    lea rsi, [rip + ecn_marker]
    xor edx, edx
    jmp ecn_start
# A separate closed constructor uses only the startup-cached executable and fixed marker.
FN theme_capture_native_start
    lea rsi, [rip + ecn_theme_marker]
    mov edx, 1
ecn_start:
    PROLOGUE 32
    mov [rsp + 16], rsi
    mov [rsp + 24], rdx
    mov r12, rdi
    test r12, r12
    jz .Lecn_start_bad
    cmp qword ptr [r12 + ECNR_job], 0
    jle .Lecn_start_bad
    cmp qword ptr [r12 + ECNR_context], 0
    jle .Lecn_start_bad
    cmp qword ptr [rsp + 24], 0
    je 90f
    mov rax, [r12 + ECNR_nonce]
    or rax, [r12 + ECNR_nonce + 8]
    jz .Lecn_start_bad
90:
    mov edi, ECN_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lecn_start_oom
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, ECN_SIZE
    call memset
    mov qword ptr [rbx + ESJ_purpose], ESJ_SETTINGS
    mov qword ptr [rbx + ESJ_anchor], -1
    mov qword ptr [rbx + ESJ_stdout], -1
    mov qword ptr [rbx + ESJ_stderr], -1
    mov qword ptr [rbx + ESJ_launch], -1
    mov qword ptr [rbx + ESJ_exit], -1
    mov qword ptr [rbx + ECN_input], -1
    mov qword ptr [rbx + ECN_event], -1
    lea rdi, [rbx + ESJ_native]
    mov esi, 255
    mov edx, 64
    call memset
    mov rax, [r12 + ECNR_job]
    mov [rbx + ESJ_tag + 8], rax
    mov rax, [r12 + ECNR_context]
    mov [rbx + ESJ_tag], rax
    lea rdi, [rbx + ESJ_tag + 16]
    lea rsi, [r12 + ECNR_nonce]
    mov edx, 16
    call memcpy
    lea rdi, [rbx + ESJ_exe]
    mov esi, 4096
    cmp qword ptr [rsp + 24], 0
    je 91f
    call ext_store_job_legacy_copy_executable
    jmp 92f
91:
.ifdef WINDOWS
    call ext_store_job_module_path
.else
    call proc_self_path
.endif
92: test rax, rax
    jz .Lecn_start_io
    js .Lecn_start_error
    lea rdi, [rbx + ESJ_jobtext]
    mov rsi, [rbx + ESJ_tag + 8]
    call fmt_u64
    mov byte ptr [rbx + ESJ_jobtext + rax], 0
    lea rdi, [rbx + ESJ_epochtext]
    mov rsi, [rbx + ESJ_tag]
    call fmt_u64
    mov byte ptr [rbx + ESJ_epochtext + rax], 0
    lea r8, [rip + ecn_hex]
    xor ecx, ecx
1:  movzx eax, byte ptr [rbx + ESJ_tag + 16 + rcx]
    mov edx, eax
    shr eax, 4
    and edx, 15
    mov al, [r8 + rax]
    mov dl, [r8 + rdx]
    mov [rbx + ESJ_noncehex + rcx*2], al
    mov [rbx + ESJ_noncehex + rcx*2 + 1], dl
    inc rcx
    cmp rcx, 16
    jb 1b
    lea rax, [rbx + ESJ_exe]
    mov [rbx + ESJ_argv], rax
    mov rax, [rsp + 16]
    mov [rbx + ESJ_argv + 8], rax
    lea rax, [rip + ecn_version]
    mov [rbx + ESJ_argv + 16], rax
    lea rax, [rbx + ESJ_jobtext]
    mov [rbx + ESJ_argv + 24], rax
    lea rax, [rbx + ESJ_epochtext]
    mov [rbx + ESJ_argv + 32], rax
    lea rax, [rbx + ESJ_noncehex]
    mov [rbx + ESJ_argv + 40], rax
    mov rdi, rbx
    call ext_store_job_native_spawn
    test rax, rax
    js .Lecn_start_error
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    jne .Lecn_start_io
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lecn_start_io:
    mov rax, -5
.Lecn_start_error:
    mov [rbx + ESJ_error], rax
    mov [rsp], rax
    mov rax, [rbx + ESJ_secondary]
    mov [rsp + 8], rax
    mov rdi, rbx
    call ext_settings_native_free
    test rdx, rdx
    jz .Lecn_start_retained
    mov rcx, [rsp + 8]
    test rcx, rcx
    jnz 2f
    mov rcx, rax
2:  mov rdx, [rsp]
    xor eax, eax
    EPILOGUE
.Lecn_start_retained:
    mov rax, rbx
    mov rdx, [rsp]
    mov rcx, [rbx + ESJ_secondary]
    test rcx, rcx
    jnz 3f
    mov rcx, [rbx + ECN_cleanup]
3:  EPILOGUE
.Lecn_start_bad:
    mov rdx, -22
    jmp .Lecn_start_null
.Lecn_start_oom:
    mov rdx, -12
.Lecn_start_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

FN ext_settings_native_read
    test rdi, rdi
    jz .Lecn_bad
    cmp rsi, 2
    ja .Lecn_bad
    test rcx, rcx
    jz .Lecn_bad
    cmp rcx, 65536
    ja .Lecn_bad
    test rdx, rdx
    jz .Lecn_bad
    mov rax, [rdi + ESJ_stdout + rsi*8]
    test rax, rax
    js .Lecn_eof
    mov rdi, rax
    mov rsi, rdx
    mov rdx, rcx
    jmp ext_store_job_native_read
.Lecn_eof:
    xor eax, eax
    ret
.Lecn_bad:
    mov rax, -22
    ret
FN ext_settings_native_write_begin
    test rdi, rdi
    jz .Lecn_bad
    test rsi, rsi
    jz .Lecn_bad
    test rdx, rdx
    jz .Lecn_bad
    cmp rdx, 65536
    ja .Lecn_bad
    cmp qword ptr [rdi + ECN_closing], 0
    jne .Lecn_pipe
    cmp qword ptr [rdi + ECN_input], 0
    jl .Lecn_pipe
    mov rax, [rdi + ECN_write_error]
    test rax, rax
    js .Lecn_return
    cmp qword ptr [rdi + ECN_length], 0
    jne .Lecn_eof
    cmp qword ptr [rdi + ECN_operation], 0
    jne .Lecn_eof
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    lea rdi, [rbx + ECN_chunk]
    call memcpy
    mov [rbx + ECN_length], r12
    mov qword ptr [rbx + ECN_offset], 0
    mov qword ptr [rbx + ECN_submitted], 0
    mov eax, 1
    EPILOGUE
.Lecn_pipe:
    mov rax, -32
.Lecn_return:
    ret

FN ext_settings_native_poll
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 1f
    call ext_store_job_native_poll
    mov rcx, rax
    mov rdx, [rbx + ESJ_exit]
    mov rax, [rbx + ESJ_authority]
    cmp rax, ESJ_REAPED
    jne 2f
    cmp rdx, 255
    jbe 2f
    mov edx, 255
2:  EPILOGUE
1:  xor eax, eax
    mov rdx, -1
    mov rcx, -22
    EPILOGUE
FN ext_settings_native_kill
    test rdi, rdi
    jz .Lecn_bad
    cmp qword ptr [rdi + ESJ_authority], ESJ_OWNED
    jne .Lecn_eof
    jmp ext_store_job_native_kill

FN ext_settings_native_free
    PROLOGUE 32
    mov rbx, rdi
    test rbx, rbx
    jz .Lecn_free_consumed
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    je .Lecn_free_busy
    cmp qword ptr [rbx + ECN_operation], 0
    jne .Lecn_free_busy
    cmp qword ptr [rbx + ECN_debt], 0
    jne .Lecn_free_busy
    call ext_settings_native_close_input
    mov rdi, rbx
    mov rsi, rax
    call ecn_cleanup_note
    mov r12, ESJ_stdout
1:  mov rdi, [rbx + r12]
    mov qword ptr [rbx + r12], -1
    test rdi, rdi
    js 2f
    call ext_store_job_native_close
    mov rdi, rbx
    mov rsi, rax
    call ecn_cleanup_note
2:  add r12, 8
    cmp r12, ESJ_launch
    jbe 1b
    mov rdi, rbx
    call ext_store_job_native_free
    mov [rsp + 8], rdx
    mov rdi, rbx
    mov rsi, rax
    call ecn_cleanup_note
.ifdef WINDOWS
    lea rdi, [rbx + ECN_security]
    call ext_choices_security_free
    mov rdi, rbx
    mov rsi, rax
    call ecn_cleanup_note
    cmp qword ptr [rbx + ECN_security + ECP_security], 0
    jne 5f
    cmp qword ptr [rbx + ECN_security + ECP_sid], 0
    je 6f
5:  mov qword ptr [rsp + 8], 0
6:
.endif
    mov rdi, [rbx + ECN_event]
    mov qword ptr [rbx + ECN_event], -1
    test rdi, rdi
    js 3f
    call ext_store_job_native_close
    mov rdi, rbx
    mov rsi, rax
    call ecn_cleanup_note
3:  cmp qword ptr [rsp + 8], 0
    je .Lecn_free_retained
    mov rax, [rbx + ECN_cleanup]
    mov [rsp], rax
    mov rdi, rbx
    call prep_cleanup_free
    test rdx, rdx
    jz .Lecn_free_self_retained
    mov rax, [rsp]
    mov edx, 1
    xor ecx, ecx
    EPILOGUE
.Lecn_free_self_retained:
    mov rdi, rbx
    mov rsi, rax
    call ecn_cleanup_note
.Lecn_free_retained:
    mov rax, [rbx + ECN_cleanup]
    test rax, rax
    js 4f
    mov rax, -16
4:  xor edx, edx
    mov ecx, 1
    EPILOGUE
.Lecn_free_consumed:
    xor eax, eax
    mov edx, 1
    xor ecx, ecx
    EPILOGUE
.Lecn_free_busy:
    mov rax, -16
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
