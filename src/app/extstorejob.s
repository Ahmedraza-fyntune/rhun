# Bounded owned transport for two fixed current-executable anchored helpers.
.include "rhun.inc"
.include "app/extstore.inc"
.include "app/extstorejob.inc"
.include "app/extstorejoblegacy.inc"
.bss
.p2align 3
esj_active: .zero 8
esj_closing: .zero 8
.section .rodata
esj_snapshot: .asciz "--extension-store-snapshot"
esj_validator: .asciz "--validate-extension-anchored"
esj_legacy_validator: .asciz "--validate-legacy-anchored"
esj_legacy_snapshot: .asciz "--snapshot-legacy-anchored"
esj_dash: .asciz "-"
esj_hex: .ascii "0123456789abcdef"
.text
# Set first primary and first secondary only.
esj_error:
    test rsi, rsi
    jns 1f
    cmp qword ptr [rdi + ESJ_error], 0
    jne 1f
    mov [rdi + ESJ_error], rsi
1:  test rdx, rdx
    jns 2f
    cmp qword ptr [rdi + ESJ_secondary], 0
    jne 2f
    mov [rdi + ESJ_secondary], rdx
2:  ret

esj_hex_encode:
    lea r8, [rip + esj_hex]
1:  movzx eax, byte ptr [rsi]
    mov ecx, eax
    shr ecx, 4
    mov cl, [r8 + rcx]
    mov [rdi], cl
    and eax, 15
    mov cl, [r8 + rax]
    mov [rdi + 1], cl
    add rdi, 2
    inc rsi
    dec rdx
    jnz 1b
    mov byte ptr [rdi], 0
    ret

# Prefix validation accepts the same drive and UNC absolute forms as rooted opening.
# Whole DIR validation and exact anchor/path binding remain the validator's responsibility.
esj_absolute_check:
.ifdef WINDOWS
    PROLOGUE
    mov rbx, rdi
    cmp byte ptr [rbx + 1], ':'
    jne 2f
    mov al, [rbx]
    or al, 32
    sub al, 'a'
    cmp al, 25
    ja 8f
    cmp byte ptr [rbx + 2], '/'
    je 7f
    cmp byte ptr [rbx + 2], 92
    jne 8f
    jmp 7f
2:  mov al, [rbx]
    cmp al, '/'
    je 21f
    cmp al, 92
    jne 8f
21: mov al, [rbx + 1]
    cmp al, '/'
    je 22f
    cmp al, 92
    jne 8f
22: lea r12, [rbx + 2]
    mov r13d, 2
3:  mov r14, r12
4:  movzx r15d, byte ptr [r12]
    test r15b, r15b
    jz 5f
    cmp r15b, '/'
    je 5f
    cmp r15b, 92
    je 5f
    inc r12
    jmp 4b
5:  mov byte ptr [r12], 0
    mov rdi, r14
    call ext_root_name
    mov [r12], r15b
    test rax, rax
    js 9f
    dec r13
    jz 7f
    test r15b, r15b
    jz 8f
    inc r12
    jmp 3b
7:  xor eax, eax
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
.else
    cmp byte ptr [rdi], '/'
    jne 1f
    xor eax, eax
    ret
1:  mov rax, -22
    ret
.endif

# Check borrowed metadata epoch and the retained anchor identity on actual handles.
esj_current:
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + ESJ_guard]
    test rax, rax
    jz 1f
    mov rcx, [rbx + ESJ_tag + EST_epoch]
    cmp [rax + ESG_epoch], rcx
    jne 4f
1:  mov rax, [rbx + ESJ_purpose]
    sub rax, ESJ_LEGACY_VALIDATOR
    cmp rax, 1
    jbe 6f
    mov rdi, [rbx + ESJ_anchor]
    lea rsi, [rbx + ESJ_identity]
    call ext_root_identity
    test rax, rax
    js 5f
    lea rdi, [rbx + ESJ_identity]
    lea rsi, [rbx + ESJ_tag + EST_root_id]
    mov edx, 32
    call memeq
    test eax, eax
    jz 4f
6:  xor eax, eax
5:  EPILOGUE
4:  mov rax, -116
    EPILOGUE

# All native resources are initialized before any fallible work.
FN ext_store_job_start
    PROLOGUE 16
    mov r12, rdi
    test r12, r12
    jz .Lesj_start_bad
    cmp qword ptr [rip + esj_closing], 0
    jne .Lesj_start_closed
    cmp qword ptr [rip + esj_active], 0
    jne .Lesj_start_busy
    mov qword ptr [rip + esj_active], 1
    mov edi, ESJ_SIZE
    call mem_alloc_try
    test rax, rax
    jz .Lesj_start_oom_reserved
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, ESJ_SIZE
    call memset
    mov rdi, rbx
    mov rsi, r12
    mov edx, ESJR_SIZE
    call memcpy
    mov [rip + esj_active], rbx
    mov qword ptr [rbx + ESJ_anchor], -1
    mov qword ptr [rbx + ESJ_stdout], -1
    mov qword ptr [rbx + ESJ_stderr], -1
    mov qword ptr [rbx + ESJ_launch], -1
    lea rdi, [rbx + ESJ_native]
    mov esi, 255
    mov edx, 64
    call memset
    mov rax, [rbx + ESJ_purpose]
    cmp rax, ESJ_SNAPSHOT
    je 1f
    cmp rax, ESJ_VALIDATOR
    je 1f
    sub rax, ESJ_LEGACY_VALIDATOR
    cmp rax, 1
    ja .Lesj_start_owned_bad
1:  cmp qword ptr [rbx + ESJ_tag + EST_epoch], 0
    jle .Lesj_start_owned_bad
    cmp qword ptr [rbx + ESJ_tag + EST_job], 0
    jle .Lesj_start_owned_bad
    mov rax, [rbx + ESJ_deadline]
    add rax, 10000
    jc .Lesj_start_owned_bad
    mov [rbx + ESJ_deadline], rax
    mov rdi, [r12 + ESJR_anchor]
    call kp_raw_duplicate
    test rax, rax
    js .Lesj_start_owned_error
    mov [rbx + ESJ_anchor], rax
    mov rdi, rbx
    call esj_current
    test rax, rax
    js .Lesj_start_owned_error
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SNAPSHOT
    jne .Lesj_start_validator
    mov rax, [rbx + ESJ_guard]
    test rax, rax
    jz .Lesj_start_owned_bad
    mov rdi, [rax + ESG_root]
    lea rsi, [rbx + ESJ_identity]
    call ext_root_identity
    test rax, rax
    js .Lesj_start_owned_error
    lea rdi, [rbx + ESJ_identity]
    lea rsi, [rbx + ESJ_tag + EST_root_id]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lesj_start_owned_stale
    mov qword ptr [rbx + ESJ_cap], ESW_WIRE_MAX
    jmp .Lesj_start_buffers
.Lesj_start_validator:
    mov qword ptr [rbx + ESJ_cap], 192
    cmp qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    jne 28f
    cmp qword ptr [rbx + ESJ_source], 0
    jne .Lesj_start_owned_bad
    mov qword ptr [rbx + ESJ_cap], ESJL_CAP
28:
    mov rdi, [rbx + ESJ_dir]
    test rdi, rdi
    jz .Lesj_start_owned_bad
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Lesj_start_owned_bad
    mov r13, rax
    mov rdi, [rbx + ESJ_dir]
    lea rdi, [rbx + ESJ_dirbuf]
    mov rsi, [rbx + ESJ_dir]
    lea rdx, [r13 + 1]
    call memcpy
    lea rdi, [rbx + ESJ_dirbuf]
    call esj_absolute_check
    test rax, rax
    js .Lesj_start_owned_error
    lea rax, [rbx + ESJ_dirbuf]
    mov [rbx + ESJ_dir], rax
    mov r14, ESJ_owner
    mov r15, ESJ_ownerbuf
.Lesj_identity_copy:
    mov rdi, [rbx + r14]
    call ext_store_identity_len
    test rax, rax
    jz .Lesj_start_owned_bad
    lea rdi, [rbx + r15]
    mov rsi, [rbx + r14]
    lea rdx, [rax + 1]
    call memcpy
    lea rax, [rbx + r15]
    mov [rbx + r14], rax
    cmp r14, ESJ_name
    je 3f
    mov r14, ESJ_name
    mov r15, ESJ_namebuf
    jmp .Lesj_identity_copy
3:  mov rsi, [rbx + ESJ_source]
    test rsi, rsi
    jz .Lesj_start_buffers
    lea rdi, [rbx + ESJ_sourcebuf]
    mov edx, 32
    call memcpy
    lea rsi, [rbx + ESJ_sourcebuf]
    mov [rbx + ESJ_source], rsi
    lea rdi, [rbx + ESJ_sourcehex]
    mov edx, 32
    call esj_hex_encode
.Lesj_start_buffers:
    mov rax, [rbx + ESJ_purpose]
    sub rax, ESJ_LEGACY_VALIDATOR
    cmp rax, 1
    ja 29f
    mov rdi, rbx
    call ext_store_job_legacy_capture
    test rax, rax
    js .Lesj_start_owned_error
29: mov rdi, [rbx + ESJ_cap]
    inc rdi
    call mem_alloc_try
    test rax, rax
    jz .Lesj_start_owned_oom
    mov [rbx + ESJ_wire], rax
    lea rdi, [rbx + ESJ_exe]
    mov rax, [rbx + ESJ_purpose]
    sub rax, ESJ_LEGACY_VALIDATOR
    cmp rax, 1
    ja 30f
    call ext_store_job_legacy_copy_executable
    jmp 31f
30: mov esi, 4096
.ifdef WINDOWS
    call ext_store_job_module_path
.else
    call proc_self_path
.endif
31: test rax, rax
    jle .Lesj_start_owned_error
    lea rdi, [rbx + ESJ_epochtext]
    mov rsi, [rbx + ESJ_tag + EST_epoch]
    call fmt_u64
    mov byte ptr [rbx + ESJ_epochtext + rax], 0
    lea rdi, [rbx + ESJ_jobtext]
    mov rsi, [rbx + ESJ_tag + EST_job]
    call fmt_u64
    mov byte ptr [rbx + ESJ_jobtext + rax], 0
    lea rdi, [rbx + ESJ_noncehex]
    lea rsi, [rbx + ESJ_tag + EST_nonce]
    mov edx, 16
    call esj_hex_encode
    lea rax, [rbx + ESJ_exe]
    mov [rbx + ESJ_argv], rax
    lea rax, [rbx + ESJ_rawtext]
    mov [rbx + ESJ_argv + 16], rax
    lea rax, [rip + esj_snapshot]
    mov [rbx + ESJ_argv + 8], rax
    lea rax, [rbx + ESJ_epochtext]
    mov [rbx + ESJ_argv + 24], rax
    lea rax, [rbx + ESJ_jobtext]
    mov [rbx + ESJ_argv + 32], rax
    lea rax, [rbx + ESJ_noncehex]
    mov [rbx + ESJ_argv + 40], rax
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SNAPSHOT
    je 4f
    lea rax, [rip + esj_validator]
    cmp qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_VALIDATOR
    jne 32f
    lea rax, [rip + esj_legacy_validator]
32: cmp qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    jne 33f
    lea rax, [rip + esj_legacy_snapshot]
33: mov [rbx + ESJ_argv + 8], rax
    mov rax, [rbx + ESJ_dir]
    mov [rbx + ESJ_argv + 24], rax
    mov rax, [rbx + ESJ_owner]
    mov [rbx + ESJ_argv + 32], rax
    mov rax, [rbx + ESJ_name]
    mov [rbx + ESJ_argv + 40], rax
    lea rax, [rbx + ESJ_epochtext]
    mov [rbx + ESJ_argv + 48], rax
    lea rax, [rbx + ESJ_jobtext]
    mov [rbx + ESJ_argv + 56], rax
    lea rax, [rbx + ESJ_noncehex]
    mov [rbx + ESJ_argv + 64], rax
    lea rax, [rip + esj_dash]
    cmp qword ptr [rbx + ESJ_source], 0
    je 5f
    lea rax, [rbx + ESJ_sourcehex]
5:  mov [rbx + ESJ_argv + 72], rax
4:  mov rax, [rbx + ESJ_cancel]
    test rax, rax
    jz 6f
    mov rdi, [rbx + ESJ_user]
    call rax
    test rax, rax
    jz 6f
    js .Lesj_start_owned_error
    jmp .Lesj_start_owned_bad
6:  cmp qword ptr [rip + esj_closing], 0
    jne .Lesj_start_owned_closed
    mov rax, [rbx + ESJ_error]
    test rax, rax
    js .Lesj_start_owned_error
    mov rdi, rbx
    call ext_store_job_native_spawn
    test rax, rax
    jns .Lesj_start_success
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    jne .Lesj_start_owned_error
    mov rsi, rax
    xor edx, edx
    mov rdi, rbx
    call esj_error
    mov rdi, rbx
    call esj_abort
    mov rax, rbx
    mov rdx, [rbx + ESJ_error]
    mov rcx, [rbx + ESJ_secondary]
    EPILOGUE
.Lesj_start_success:
    mov rax, rbx
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesj_start_owned_closed:
    mov rax, -125
    jmp .Lesj_start_owned_error
.Lesj_start_owned_stale:
    mov rax, -116
    jmp .Lesj_start_owned_error
.Lesj_start_owned_oom:
    mov rax, -12
    jmp .Lesj_start_owned_error
.Lesj_start_owned_bad:
    mov rax, -22
.Lesj_start_owned_error:
    test rax, rax
    js 25f
    mov rax, -5
25: mov [rbx + ESJ_error], rax
    mov [rsp], rax
    mov rax, [rbx + ESJ_secondary]
    mov [rsp + 8], rax
    mov rdi, rbx
    call ext_store_job_free
    test rdx, rdx
    jz .Lesj_start_cleanup_retained
    mov rcx, [rsp + 8]
    test rcx, rcx
    js 26f
    mov rcx, rax
26: 
    mov rdx, [rsp]
    xor eax, eax
    EPILOGUE
.Lesj_start_cleanup_retained:
    mov qword ptr [rbx + ESJ_terminal], 1
    mov rax, rbx
    mov rdx, [rsp]
    mov rcx, [rbx + ESJ_secondary]
    EPILOGUE
.Lesj_start_oom_reserved:
    mov qword ptr [rip + esj_active], 0
    mov rdx, -12
    jmp .Lesj_start_null
.Lesj_start_closed:
    mov rdx, -125
    jmp .Lesj_start_null
.Lesj_start_busy:
    mov rdx, -16
    jmp .Lesj_start_null
.Lesj_start_bad:
    mov rdx, -22
.Lesj_start_null:
    xor eax, eax
    xor ecx, ecx
    EPILOGUE

# Abort invalidates callback/results before closing streams or signalling a child.
esj_abort:
    PROLOGUE
    mov rbx, rdi
    mov qword ptr [rbx + ESJ_cancel], 0
    mov qword ptr [rbx + ESJ_user], 0
    mov r12, ESJ_stdout
3:  mov rdi, [rbx + r12]
    mov qword ptr [rbx + r12], -1
    test rdi, rdi
    js 4f
    call ext_store_job_native_close
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
4:  add r12, 8
    cmp r12, ESJ_launch
    jbe 3b
    mov qword ptr [rbx + ESJ_eof], 7
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    jne 5f
    cmp qword ptr [rbx + ESJ_killed], 0
    jne 5f
    mov qword ptr [rbx + ESJ_killed], 1
    mov rdi, rbx
    call ext_store_job_native_kill
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
5:  xor eax, eax
    EPILOGUE

FN ext_store_job_cancel
    test rdi, rdi
    jz 1f
    mov rsi, -125
    xor edx, edx
    call esj_error
    jmp esj_abort
1:  xor eax, eax
    ret

# One bounded nonblocking read per stream per pass; combined byte/op counters.
FN ext_store_job_step
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .Lesj_step_terminal
    cmp qword ptr [rbx + ESJ_terminal], 0
    jne .Lesj_step_terminal
    test r13, r13
    jz .Lesj_step_bad
    cmp r13, 65536
    ja .Lesj_step_bad
    cmp qword ptr [rbx + ESJ_error], 0
    jne .Lesj_step_abort
    cmp r12, [rbx + ESJ_deadline]
    jae .Lesj_step_timeout
    mov rax, [rbx + ESJ_cancel]
    test rax, rax
    jz 1f
    mov rdi, [rbx + ESJ_user]
    call rax
    test rax, rax
    jz 1f
    js .Lesj_step_error
    jmp .Lesj_step_bad
1:  mov rdi, rbx
    call esj_current
    test rax, rax
    js .Lesj_step_error
    xor r14d, r14d
    xor r15d, r15d
.Lesj_read_loop:
    test r13, r13
    jz .Lesj_step_poll
    cmp r15, 8
    jae .Lesj_step_poll
    inc r15
    mov rdi, [rbx + ESJ_stdout + r14*8]
    test rdi, rdi
    js .Lesj_read_next
    lea rsi, [rbx + ESJ_scratch]
    mov edx, 4096
    cmp r14, 2
    jne 21f
    mov rax, [rbx + ESJ_native + 120]
    lea rsi, [rbx + ESJ_native + 112 + rax]
    mov edx, 5
    sub rdx, rax
    jmp 2f
21: cmp r14, 0
    jne 2f
    mov rax, [rbx + ESJ_used]
    mov rsi, [rbx + ESJ_wire]
    add rsi, rax
    mov rdx, [rbx + ESJ_cap]
    inc rdx
    sub rdx, rax
2:  cmp rdx, r13
    jbe 3f
    mov rdx, r13
3:  mov [rsp], rdx
    mov [rsp + 8], rdi
    mov [rsp + 16], rsi
    mov rax, [rbx + ESJ_cancel]
    test rax, rax
    jz 27f
    mov rdi, [rbx + ESJ_user]
    call rax
    test rax, rax
    jz 27f
    js .Lesj_step_error
    jmp .Lesj_step_bad
27: mov rdi, [rsp + 8]
    mov rsi, [rsp + 16]
    mov rdx, [rsp]
    call ext_store_job_native_read
    cmp rax, -11
    je .Lesj_read_next
    cmp rax, -4
    je .Lesj_read_next
    test rax, rax
    js .Lesj_step_error
    jz .Lesj_read_eof
    cmp rax, [rsp]
    ja .Lesj_step_exit
    sub r13, rax
    cmp r14, 2
    jne 22f
    add [rbx + ESJ_native + 120], rax
    cmp qword ptr [rbx + ESJ_native + 120], 4
    ja .Lesj_step_exit
    jmp .Lesj_read_next
22: cmp r14, 0
    jne .Lesj_read_unexpected
    add [rbx + ESJ_used], rax
    mov rcx, [rbx + ESJ_used]
    cmp rcx, [rbx + ESJ_cap]
    ja .Lesj_step_large
    cmp qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    jne .Lesj_read_next
    cmp rcx, 192
    jb .Lesj_read_next
    mov rdi, rbx
    call ext_store_job_legacy_snapshot_check
    test rax, rax
    js .Lesj_step_error
    jmp .Lesj_read_next
.Lesj_read_unexpected:
    mov rax, -5
    jmp .Lesj_step_error
.Lesj_read_eof:
    cmp r14, 2
    jne 23f
    cmp qword ptr [rbx + ESJ_native + 120], 0
    je 23f
    cmp qword ptr [rbx + ESJ_native + 120], 4
    jne .Lesj_step_exit
    movsxd rax, dword ptr [rbx + ESJ_native + 112]
    test rax, rax
    jns .Lesj_step_exit
    cmp rax, -4095
    jl .Lesj_step_exit
    jmp .Lesj_step_error
23: mov ecx, r14d
    mov eax, 1
    shl eax, cl
    or [rbx + ESJ_eof], rax
    mov rdi, [rbx + ESJ_stdout + r14*8]
    mov qword ptr [rbx + ESJ_stdout + r14*8], -1
    call ext_store_job_native_close
    test rax, rax
    js .Lesj_step_error
.Lesj_read_next:
    inc r14
    cmp r14, 3
    jb .Lesj_read_loop
    xor r14d, r14d
    # Each active stream gets at least one observation before a second pass.
    cmp qword ptr [rbx + ESJ_eof], 7
    jne .Lesj_read_loop
.Lesj_step_poll:
    mov rdi, rbx
    call ext_store_job_native_poll
    test rax, rax
    js .Lesj_step_error_after_poll
    cmp qword ptr [rbx + ESJ_error], 0
    jne .Lesj_step_failure_done
    cmp qword ptr [rbx + ESJ_authority], ESJ_REAPED
    jne .Lesj_step_running
    cmp qword ptr [rbx + ESJ_eof], 7
    jne .Lesj_step_running
    cmp qword ptr [rbx + ESJ_exit], 0
    jne .Lesj_step_exit
    mov rdi, rbx
    call esj_current
    test rax, rax
    js .Lesj_step_error_after_poll
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SNAPSHOT
    jne .Lesj_step_receipt
    mov rdi, [rbx + ESJ_wire]
    mov rsi, [rbx + ESJ_used]
    lea rdx, [rbx + ESJ_tag]
    lea rcx, [rbx + ESJ_result]
    call ext_store_snapshot_unpack_owned_try
    test rax, rax
    jz .Lesj_step_unpack_error
    mov [rbx + ESJ_result], rax
    mov rdi, rax
    mov rsi, [rbx + ESJ_guard]
    mov rdx, [rbx + ESJ_tag + EST_epoch]
    call ext_store_snapshot_bind
    test rax, rax
    js .Lesj_step_error_after_poll
    jmp .Lesj_step_done
.Lesj_step_receipt:
    cmp qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    je .Lesj_step_legacy_snapshot
    cmp qword ptr [rbx + ESJ_used], 192
    jne .Lesj_step_exit
    mov r12, [rbx + ESJ_wire]
    mov rax, 0x00314c4156454852
    cmp qword ptr [rbx + ESJ_purpose], ESJ_LEGACY_VALIDATOR
    jne 34f
    mov rax, 0x00314347454c4852
    mov rcx, [r12 + 80]
    or rcx, [r12 + 88]
    or rcx, [r12 + 96]
    or rcx, [r12 + 104]
    jnz .Lesj_step_exit
    mov rcx, [r12 + 112]
    or rcx, [r12 + 120]
    or rcx, [r12 + 128]
    or rcx, [r12 + 136]
    jz .Lesj_step_exit
34: cmp [r12], rax
    jne .Lesj_step_exit
    cmp dword ptr [r12 + 8], 1
    jne .Lesj_step_exit
    cmp dword ptr [r12 + 12], 192
    jne .Lesj_step_exit
    lea rdi, [r12 + 16]
    lea rsi, [rbx + ESJ_tag]
    mov edx, 64
    call memeq
    test eax, eax
    jz .Lesj_step_exit
    mov rsi, [rbx + ESJ_source]
    test rsi, rsi
    jz 24f
    lea rdi, [r12 + 112]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Lesj_step_exit
24: mov rax, [r12 + 144]
    or rax, [r12 + 152]
    or rax, [r12 + 160]
    or rax, [r12 + 168]
    or rax, [r12 + 176]
    or rax, [r12 + 184]
    jnz .Lesj_step_exit
    mov [rbx + ESJ_result], r12
    mov qword ptr [rbx + ESJ_wire], 0
    jmp .Lesj_step_done
.Lesj_step_legacy_snapshot:
    cmp qword ptr [rbx + ESJ_used], 192
    jb .Lesj_step_exit
    mov rdi, rbx
    call ext_store_job_legacy_snapshot_check
    test rax, rax
    js .Lesj_step_error_after_poll
    mov rax, [rbx + ESJ_wire]
    mov rcx, [rax + 16]
    cmp rcx, [rbx + ESJ_used]
    jne .Lesj_step_exit
    mov [rbx + ESJ_result], rax
    mov qword ptr [rbx + ESJ_wire], 0
.Lesj_step_done:
    mov qword ptr [rbx + ESJ_cancel], 0
    mov qword ptr [rbx + ESJ_user], 0
    mov qword ptr [rbx + ESJ_terminal], 1
.Lesj_step_terminal:
    mov eax, 1
    EPILOGUE
.Lesj_step_unpack_error:
    mov rax, rdx
    mov [rsp], rcx
    mov rdi, rbx
    mov rsi, rax
    mov rdx, [rsp]
    call esj_error
    jmp .Lesj_step_abort_after_poll
.Lesj_step_bad:
    mov rax, -22
    jmp .Lesj_step_error
.Lesj_step_timeout:
    mov rax, -110
    jmp .Lesj_step_error
.Lesj_step_large:
    mov rax, -7
    jmp .Lesj_step_error
.Lesj_step_exit:
    mov rax, -5
.Lesj_step_error_after_poll:
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call esj_error
.Lesj_step_abort_after_poll:
    mov rdi, rbx
    call esj_abort
    jmp .Lesj_step_failure_done
.Lesj_step_error:
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call esj_error
.Lesj_step_abort:
    mov rdi, rbx
    call esj_abort
    jmp .Lesj_step_poll
.Lesj_step_failure_done:
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    jne .Lesj_step_done
.Lesj_step_running:
    xor eax, eax
    EPILOGUE

FN ext_store_job_timeout
    test rdi, rdi
    jz 2f
    cmp qword ptr [rdi + ESJ_terminal], 0
    jne 2f
    mov eax, 16
    cmp qword ptr [rdi + ESJ_purpose], ESJ_LEGACY_SNAPSHOT
    jne 4f
    mov eax, 1
4:  cmp qword ptr [rdi + ESJ_error], 0
    jne 3f
    mov rcx, [rdi + ESJ_deadline]
    sub rcx, rsi
    jbe 1f
    cmp rcx, rax
    jae 3f
    mov rax, rcx
    ret
1:  mov eax, 1
3:  ret
2:  mov rax, -1
    ret

FN ext_store_job_take_snapshot
    xor esi, esi
    jmp esj_take_snapshot
FN ext_store_job_take_snapshot_bound
    mov esi, 1
esj_take_snapshot:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Lesj_take_bad
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SNAPSHOT
    jne .Lesj_take_bad
    call esj_take_check
    test rax, rax
    js .Lesj_take_error
    mov rax, [rbx + ESJ_result]
    test rax, rax
    jz .Lesj_take_empty
    test r12, r12
    jnz 1f
    mov qword ptr [rax + ESS_proof_guard], 0
    mov qword ptr [rax + ESS_proof_epoch], 0
1:  mov qword ptr [rbx + ESJ_result], 0
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lesj_take_empty:
    mov rax, -2
    jmp .Lesj_take_error
.Lesj_take_bad:
    mov rax, -22
.Lesj_take_error:
    mov rdx, rax
    xor ecx, ecx
    test rbx, rbx
    jz 2f
    mov rcx, [rbx + ESJ_secondary]
2:  xor eax, eax
    EPILOGUE

esj_take_check:
    cmp qword ptr [rdi + ESJ_terminal], 0
    je 1f
    mov rax, [rdi + ESJ_error]
    test rax, rax
    js 2f
    jmp esj_current
1:  mov rax, -11
2:  ret

FN ext_store_job_take_receipt
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lesj_take_bad
    cmp qword ptr [rbx + ESJ_purpose], ESJ_VALIDATOR
    jne .Lesj_take_bad
    call esj_take_check
    test rax, rax
    js .Lesj_take_error
    mov rax, [rbx + ESJ_result]
    test rax, rax
    jz .Lesj_take_empty
    mov qword ptr [rbx + ESJ_result], 0
    mov edx, 192
    xor ecx, ecx
    EPILOGUE

# Distinct result types never pass through the managed receipt accessor.
FN ext_store_job_take_legacy_receipt
    mov eax, ESJ_LEGACY_VALIDATOR
    jmp esj_take_legacy
FN ext_store_job_take_legacy_snapshot
    mov eax, ESJ_LEGACY_SNAPSHOT
esj_take_legacy:
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz .Lesj_take_bad
    cmp [rbx + ESJ_purpose], rax
    jne .Lesj_take_bad
    call esj_take_check
    test rax, rax
    js .Lesj_take_error
    mov rax, [rbx + ESJ_result]
    test rax, rax
    jz .Lesj_take_empty
    mov qword ptr [rbx + ESJ_result], 0
    mov rdx, [rbx + ESJ_used]
    xor ecx, ecx
    EPILOGUE

FN ext_store_job_free
    PROLOGUE 16
    mov rbx, rdi
    test rbx, rbx
    jz .Lesj_free_consumed
    cmp qword ptr [rbx + ESJ_authority], ESJ_OWNED
    je .Lesj_free_busy
    cmp qword ptr [rbx + ESJ_error], 0
    jne 8f
    mov qword ptr [rbx + ESJ_error], -125
8:  mov qword ptr [rbx + ESJ_cancel], 0
    mov qword ptr [rbx + ESJ_user], 0
    mov qword ptr [rsp + 8], 1
    mov r12, ESJ_stdout
1:  mov rdi, [rbx + r12]
    mov qword ptr [rbx + r12], -1
    test rdi, rdi
    js 3f
    call ext_store_job_native_close
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
3:  add r12, 8
    cmp r12, ESJ_launch
    jbe 1b
    mov rdi, [rbx + ESJ_anchor]
    mov qword ptr [rbx + ESJ_anchor], -1
    test rdi, rdi
    js 4f
    call ext_root_close
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
4:  mov rdi, rbx
    call ext_store_job_native_free
    mov [rsp + 8], rdx
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
    mov rdi, [rbx + ESJ_result]
    cmp qword ptr [rbx + ESJ_purpose], ESJ_SNAPSHOT
    jne 5f
    call ext_store_snapshot_free_try
    jmp 6f
5:  call prep_cleanup_free
6:  test rdx, rdx
    jz 61f
    mov qword ptr [rbx + ESJ_result], 0
    jmp 62f
61: mov qword ptr [rsp + 8], 0
62: mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
    mov rdi, [rbx + ESJ_wire]
    call prep_cleanup_free
    test rdx, rdx
    jz 63f
    mov qword ptr [rbx + ESJ_wire], 0
    jmp 64f
63: mov qword ptr [rsp + 8], 0
64: mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
    cmp qword ptr [rsp + 8], 0
    je .Lesj_free_retained
    # ELC supplies borrowed cwd until consumed. Dispose only after other memory drains.
    mov rdi, [rbx + ESJ_legacy]
    call prep_cleanup_free
    test rdx, rdx
    jz .Lesj_free_note_retained
    mov qword ptr [rbx + ESJ_legacy], 0
    # ESJ_SIZE fits the infallible small allocator class after final ELC disposal.
.if ESJ_SIZE > 65520
.error "ESJ must remain small to preserve ELC lifetime through consumed free"
.endif
    mov rax, [rbx + ESJ_secondary]
    mov [rsp], rax
    mov rdi, rbx
    call prep_cleanup_free
    mov qword ptr [rip + esj_active], 0
    mov rax, [rsp]
    mov edx, 1
    EPILOGUE
.Lesj_free_note_retained:
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call esj_error
.Lesj_free_retained:
    mov rax, [rbx + ESJ_secondary]
    test rax, rax
    js 7f
    mov rax, -16
7:  xor edx, edx
    EPILOGUE
.Lesj_free_consumed:
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lesj_free_busy:
    mov rax, -16
    xor edx, edx
    EPILOGUE

FN ext_store_jobs_shutdown_begin
    mov qword ptr [rip + esj_closing], 1
    mov rdi, [rip + esj_active]
    cmp rdi, 1
    jbe 1f
    jmp ext_store_job_cancel
1:  xor eax, eax
    ret
FN ext_store_jobs_shutdown_step
    mov rsi, rdi
    mov rdi, [rip + esj_active]
    cmp rdi, 1
    jbe 1f
    mov edx, 65536
    jmp ext_store_job_step
1:  mov eax, 1
    ret

# Optional normal-loop hooks. They only progress collection and never adopt a result.
FN ext_store_jobs_step
    jmp ext_store_jobs_shutdown_step
FN ext_store_jobs_timeout
    mov rsi, rdi
    mov rdi, [rip + esj_active]
    cmp rdi, 1
    jbe 1f
    jmp ext_store_job_timeout
1:  mov rax, -1
    ret
