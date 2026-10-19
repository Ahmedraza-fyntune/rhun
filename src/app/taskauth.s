# Native extension authorization contains copied bytes, never callbacks or native addresses.
.include "rhun.inc"
.include "app/taskproc.inc"
.include "app/taskauth.inc"
.include "app/extstore.inc"
.data
.p2align 3
ka_epoch: .quad 1
.bss
.p2align 3
ka_parsed: .zero AX_SIZE
ka_path: .zero 4096
.section .rodata
ka_empty: .asciz ""
.text
FN ext_activation_epoch_get
    mov rax, [rip + ka_epoch]
    ret

# Overflow permanently invalidates pending activations rather than reusing an epoch.
FN ext_activation_invalidate
    mov rax, [rip + ka_epoch]
    test rax, rax
    jz 9f
    mov rcx, 0x7fffffffffffffff
    cmp rax, rcx
    jae 1f
    inc rax
    mov [rip + ka_epoch], rax
9:  ret
1:  mov qword ptr [rip + ka_epoch], 0
    xor eax, eax
    ret

# keeper_extension_auth(plan) -> owned bytes/0, rdx length or negative errno.
FN keeper_extension_auth
    PROLOGUE 32
    mov r12, rdi
    test r12, r12
    jz .Lka_build_bad
    mov rax, [r12 + KE_context]
    test rax, rax
    jle .Lka_build_bad
    cmp rax, [rip + ka_epoch]
    jne .Lka_build_stale
    mov edi, KA_MAX
    call mem_alloc_try
    test rax, rax
    jz .Lka_build_nomem
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, KA_HEADER
    call memset
    mov rax, KA_MAGIC
    mov [rbx], rax
    mov dword ptr [rbx + 8], 1
    mov eax, [r12 + KE_kind]
    mov [rbx + 12], eax
    mov eax, [r12 + KE_needs]
    mov [rbx + 16], eax
    mov eax, [r12 + KE_fallback]
    mov [rbx + 20], eax
    mov rax, [r12 + KE_context]
    mov [rbx + 24], rax
    mov rsi, [r12 + KE_expected]
    test rsi, rsi
    jz 1f
    lea rdi, [rbx + 32]
    mov edx, EXI_SIZE
    call memcpy
1:  mov rsi, [r12 + KE_id]
    test rsi, rsi
    jz 2f
    mov rdi, rsi
    mov esi, 64
    call ext_root_length
    cmp rax, 64
    jne .Lka_build_owned_bad
    lea rdi, [rbx + 192]
    mov rsi, [r12 + KE_id]
    mov edx, 64
    call memcpy
2:  lea r13, [rbx + KA_HEADER]
    xor r14d, r14d
.Lka_build_string:
    cmp r14, 10
    jae .Lka_build_reserved
    mov r15, [r12 + r14*8]
    test r15, r15
    jnz 3f
    lea r15, [rip + ka_empty]
3:  mov rdi, r15
    mov esi, 4095
    call ext_root_length
    test rax, rax
    js .Lka_build_owned_error
    inc rax
    mov [rbx + r14*4 + 276], eax
    mov [rsp], rax
    lea rcx, [r13 + rax]
    sub rcx, rbx
    cmp rcx, KA_MAX
    ja .Lka_build_owned_big
    mov rdi, r13
    mov rsi, r15
    mov rdx, rax
    call memcpy
    add r13, [rsp]
    inc r14
    jmp .Lka_build_string
.Lka_build_reserved:
    mov dword ptr [rbx + 316], 1
    mov byte ptr [r13], 0
    inc r13
    sub r13, rbx
    mov rdi, rbx
    mov rsi, r13
    call kp_auth_parse
    test rax, rax
    js .Lka_build_owned_error
    mov rax, rbx
    mov rdx, r13
    EPILOGUE
.Lka_build_owned_bad:
    mov rax, -22
    jmp .Lka_build_owned_error
.Lka_build_owned_big:
    mov rax, -7
.Lka_build_owned_error:
    mov r12, rax
    mov rdi, rbx
    call mem_free
    xor eax, eax
    mov rdx, r12
    EPILOGUE
.Lka_build_stale:
    mov rdx, -116
    xor eax, eax
    EPILOGUE
.Lka_build_nomem:
    mov rdx, -12
    xor eax, eax
    EPILOGUE
.Lka_build_bad:
    mov rdx, -22
    xor eax, eax
    EPILOGUE

ka_zero:
    xor eax, eax
1:  cmp byte ptr [rdi], 0
    jne 9f
    inc rdi
    dec rsi
    jnz 1b
    mov eax, 1
9:  ret

ka_hex_id:
    xor ecx, ecx
1:  movzx eax, byte ptr [rdi + rcx]
    cmp eax, '0'
    jb 8f
    cmp eax, '9'
    jbe 2f
    sub eax, 'a'
    cmp eax, 5
    ja 8f
2:  inc rcx
    cmp rcx, 64
    jb 1b
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# Exact bounded record or all-zero absence. Returns pointer/NULL or -EINVAL.
FN kp_auth_expected
    PROLOGUE
    mov rbx, rdi
    mov esi, EXI_SIZE
    call ka_zero
    test eax, eax
    jnz 1f
    mov rdi, rbx
    mov esi, EXI_SIZE
    mov rdx, [rbx + EXI_generation]
    call ext_index_check
    test eax, eax
    jz 8f
    mov rax, rbx
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
8:  mov rax, -22
    EPILOGUE

# Validate every copied byte before any store or process operation. One helper owns this context.
FN kp_auth_parse
    PROLOGUE 32
    mov rbx, rdi
    cmp rsi, KA_HEADER + 11
    jb .Lka_parse_bad
    cmp rsi, KA_MAX
    ja .Lka_parse_bad
    lea r12, [rdi + rsi]
    mov rax, KA_MAGIC
    cmp [rbx], rax
    jne .Lka_parse_bad
    cmp dword ptr [rbx + 8], 1
    jne .Lka_parse_bad
    mov eax, [rbx + 12]
    sub eax, 1
    cmp eax, 2
    ja .Lka_parse_bad
    mov eax, [rbx + 16]
    test eax, -128
    jnz .Lka_parse_bad
    cmp dword ptr [rbx + 20], 1
    ja .Lka_parse_bad
    cmp qword ptr [rbx + 24], 0
    jle .Lka_parse_bad
    lea rdi, [rbx + 256]
    mov esi, 20
    call ka_zero
    test eax, eax
    jz .Lka_parse_bad
    lea r15, [rip + ka_parsed]
    mov rdi, r15
    xor esi, esi
    mov edx, AX_SIZE
    call memset
    mov eax, [rbx + 12]
    mov [r15 + AX_kind], rax
    mov eax, [rbx + 16]
    mov [r15 + AX_needs], rax
    mov eax, [rbx + 20]
    mov [r15 + AX_fallback], rax
    mov rax, [rbx + 24]
    mov [r15 + AX_context], rax
    lea rdi, [rbx + 32]
    call kp_auth_expected
    test rax, rax
    js .Lka_parse_bad
    mov [r15 + AX_expected], rax
    lea rax, [rbx + 192]
    mov [r15 + AX_id], rax
    cmp qword ptr [r15 + AX_kind], KA_LEGACY
    jne 1f
    cmp qword ptr [r15 + AX_expected], 0
    jne .Lka_parse_bad
    mov rdi, rax
    mov esi, 64
    call ka_zero
    test eax, eax
    jz .Lka_parse_bad
    mov qword ptr [r15 + AX_id], 0
    jmp 2f
1:  mov rdi, rax
    call ka_hex_id
    test eax, eax
    jz .Lka_parse_bad
    cmp qword ptr [r15 + AX_kind], KA_SELECTED
    jne 2f
    mov rdi, [r15 + AX_expected]
    test rdi, rdi
    jz .Lka_parse_bad
    cmp dword ptr [rdi + EXI_flags], EXI_ACTIVE
    jne .Lka_parse_bad
    add rdi, EXI_active
    mov rsi, [r15 + AX_id]
    mov edx, 64
    call memeq
    test eax, eax
    jz .Lka_parse_bad
2:  lea r13, [rbx + KA_HEADER]
    xor r14d, r14d
.Lka_parse_string:
    mov eax, [rbx + r14*4 + 276]
    test eax, eax
    jz .Lka_parse_bad
    cmp eax, 4096
    ja .Lka_parse_bad
    lea rcx, [r13 + rax]
    cmp rcx, r12
    ja .Lka_parse_bad
    mov [rsp], rcx
    cmp byte ptr [rcx - 1], 0
    jne .Lka_parse_bad
    dec rax
    mov [rsp + 8], rax
    xor ecx, ecx
3:  cmp rcx, rax
    jae 4f
    cmp byte ptr [r13 + rcx], 0
    je .Lka_parse_bad
    inc rcx
    jmp 3b
4:  mov rdi, r13
    mov rsi, rax
    call snippet_utf8_valid
    test eax, eax
    jz .Lka_parse_bad
    cmp r14, 11
    jae .Lka_parse_bad
    mov [r15 + r14*8 + AX_strings], r13
    mov r13, [rsp]
    inc r14
    cmp r14, 11
    jb .Lka_parse_string
    cmp r13, r12
    jne .Lka_parse_bad
    cmp qword ptr [rsp + 8], 0
    jne .Lka_parse_bad
    # root/payload/state/program are nonempty absolute native paths.
    xor r14d, r14d
5:  mov rdi, [r15 + r14*8 + AX_strings]
    cmp byte ptr [rdi], 0
    je .Lka_parse_bad
.ifdef WINDOWS
    call kp_path_absolute
    test eax, eax
    jz .Lka_parse_bad
.else
    cmp byte ptr [rdi], '/'
    jne .Lka_parse_bad
.endif
    cmp r14, 0
    jne 51f
    mov r14d, 3
    jmp 5b
51: inc r14
    cmp r14, 6
    jb 5b
    mov rdi, [r15 + AX_strings + 8]
    call ext_store_identity_len
    test eax, eax
    jz .Lka_parse_bad
    mov rdi, [r15 + AX_strings + 16]
    call ext_store_identity_len
    test eax, eax
    jz .Lka_parse_bad
    # Authoritative native store path formatter uses exact encoded logical spelling.
    cmp qword ptr [r15 + AX_kind], KA_LEGACY
    je .Lka_parse_legacy_path
    lea rdi, [rip + ka_path]
    mov rsi, [r15 + AX_strings]
    mov rdx, [r15 + AX_strings + 8]
    mov rcx, [r15 + AX_strings + 16]
    mov r8, [r15 + AX_id]
    call ext_store_payload_path
    test rax, rax
    js .Lka_parse_bad
    jmp .Lka_parse_path_compare
.Lka_parse_legacy_path:
    lea rdi, [rip + ka_path]
    mov rsi, [r15 + AX_strings]
    call cstr_copy
    mov r12, rax
    lea rdi, [rip + ka_path]
    call strlen
    cmp rax, 3892
    ja .Lka_parse_bad
    mov byte ptr [r12], '/'
    lea rdi, [r12 + 1]
    mov rsi, [r15 + AX_strings + 8]
    call cstr_copy
    mov byte ptr [rax], '/'
    lea rdi, [rax + 1]
    mov rsi, [r15 + AX_strings + 16]
    call cstr_copy
.Lka_parse_path_compare:
    lea rdi, [rip + ka_path]
    mov rsi, [r15 + AX_strings + 24]
    call strcmp_eq
    test eax, eax
    jz .Lka_parse_bad
    mov rax, r15
    EPILOGUE
.Lka_parse_bad:
    mov rax, -22
    EPILOGUE

# kp_parent_auth_attach(slot,spec,copiedAuth) ->0/-errno. All inputs already copied.
FN kp_parent_auth_attach
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r13
    mov rsi, [r12 + KP_auth_len]
    call kp_auth_parse
    test rax, rax
    js 9f
    mov r14, rax
    mov rax, [r14 + AX_context]
    cmp rax, [rip + ka_epoch]
    jne 8f
    mov [rbx + KX_context], rax
    mov rdi, [r14 + AX_strings + 24]
    mov rsi, [r12 + KP_cwd]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [r14 + AX_strings + 40]
    mov rax, [r12 + KP_argv]
    mov rsi, [rax]
    call strcmp_eq
    test eax, eax
    jz 7f
    mov rdi, [r12 + KP_parentlease]
.ifdef WINDOWS
    test rdi, rdi
    jz 7f
.else
    test rdi, rdi
    js 7f
.endif
    call kp_lease_duplicate
    test rax, rax
    js 9f
    mov [rbx + KX_lease], rax
    mov [rbx + KX_auth], r13
    mov rax, [r12 + KP_auth_len]
    mov [rbx + KX_auth_len], rax
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -116
    EPILOGUE
7:  mov rax, -22
    EPILOGUE

# Local-only cancellation callback supplied to store APIs. No callback is serialized.
kp_auth_cancel:
    jmp kp_helper_alive

# Initial selection and lease acquisition, before any native target exists.
FN kp_extension_authorize
    PROLOGUE 16
    mov rbx, rdi
    cmp qword ptr [rbx + KH_lease], -1
    jne .Lka_authorized
    mov r14, [rbx + KH_authctx]
    test r14, r14
    jnz 1f
    mov rdi, [rbx + KH_auth]
    mov rsi, [rbx + KH_auth_len]
    call kp_auth_parse
    test rax, rax
    js .Lka_authorize_return
    mov r14, rax
    mov [rbx + KH_authctx], rax
    mov rax, [r14 + AX_context]
    mov [rbx + KH_context], rax
    mov rdi, [r14 + AX_strings + 24]
    mov rsi, [rbx + KH_cwd]
    call strcmp_eq
    test eax, eax
    jz .Lka_authorize_invalid
    mov rdi, [r14 + AX_strings + 40]
    mov rax, [rbx + KH_argv]
    mov rsi, [rax]
    call strcmp_eq
    test eax, eax
    jz .Lka_authorize_invalid
1:  mov rdi, [r14 + AX_strings]
    xor esi, esi
    xor edx, edx
    lea rcx, [rip + kp_auth_cancel]
    mov r8, rbx
    call ext_store_guard_try
    mov r12, rax
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rcx
    call kh_note_cleanup
    test r12, r12
    jz .Lka_authorize_guard_error
    mov [rbx + KH_guard], r12
    cmp qword ptr [rbx + KH_cleanup], 0
    jne .Lka_authorize_cleanup_error
    mov rdi, r12
    mov rsi, [r14 + AX_strings + 8]
    mov rdx, [r14 + AX_strings + 16]
    mov rcx, [r14 + AX_expected]
    call ext_store_selection_matches
    mov rdi, rbx
    mov rsi, rax
    call kh_merge_status
    test rax, rax
    js .Lka_authorize_release
    mov rdi, r12
    mov rsi, [r14 + AX_strings + 8]
    mov rdx, [r14 + AX_strings + 16]
    mov rcx, [r14 + AX_id]
    xor r8d, r8d
    xor r9d, r9d
    call ext_store_lease_try
    test rax, rax
    js 11f
    mov [rbx + KH_lease], rax
    xor eax, eax
11: mov rdi, rbx
    mov rsi, rax
    call kh_merge_status
.Lka_authorize_release:
    mov [rsp], rax
    mov rdi, rbx
    call kh_guard_release
    cmp qword ptr [rsp], 0
    je .Lka_authorize_return
    mov rax, [rsp]
.Lka_authorize_return:
    EPILOGUE
.Lka_authorized:
    xor eax, eax
    EPILOGUE
.Lka_authorize_cleanup_error:
    mov rax, [rbx + KH_cleanup]
    jmp .Lka_authorize_release
.Lka_authorize_guard_error:
    mov rax, r15
    test rax, rax
    js .Lka_authorize_return
    mov rax, -5
    EPILOGUE
.Lka_authorize_invalid:
    mov rax, -22
    EPILOGUE

# Validate START against the exact leased identity and copied preparation context.
FN kp_extension_check_start
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r13, [rbx + AX_context]
    jne 8f
    mov rdi, r12
    call kp_auth_expected
    test rax, rax
    js 9f
    cmp qword ptr [rbx + AX_kind], KA_LEGACY
    jne 1f
    test rax, rax
    jnz 8f
    xor eax, eax
    EPILOGUE
1:  test rax, rax
    jz 8f
    cmp dword ptr [rax + EXI_flags], EXI_ACTIVE
    jne 8f
    lea rdi, [rax + EXI_active]
    mov rsi, [rbx + AX_id]
    mov edx, 64
    call memeq
    test eax, eax
    jz 8f
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -116
    EPILOGUE

# Actual native gate operation is serialized inside the keeper's read-only root guard.
FN kp_extension_start
    PROLOGUE 16
    mov rbx, rdi
    mov r14, [rbx + KH_authctx]
    mov rdi, r14
    mov rsi, [rbx + KH_start_expected]
    mov rdx, [rbx + KH_context]
    call kp_extension_check_start
    test rax, rax
    js .Lka_start_return
    mov rdi, [r14 + AX_strings]
    xor esi, esi
    xor edx, edx
    lea rcx, [rip + kp_auth_cancel]
    mov r8, rbx
    call ext_store_guard_try
    mov r12, rax
    mov r15, rdx
    mov rdi, rbx
    mov rsi, rcx
    call kh_note_cleanup
    test r12, r12
    jz .Lka_start_guard_error
    mov [rbx + KH_guard], r12
    cmp qword ptr [rbx + KH_cleanup], 0
    jne .Lka_start_cleanup_error
    mov rdi, [rbx + KH_start_expected]
    call kp_auth_expected
    mov rcx, rax
    mov rdi, r12
    mov rsi, [r14 + AX_strings + 8]
    mov rdx, [r14 + AX_strings + 16]
    call ext_store_selection_matches
    mov rdi, rbx
    mov rsi, rax
    call kh_merge_status
    test rax, rax
    js .Lka_start_release
    mov rdi, rbx
    call kp_target_start
    test rax, rax
    js .Lka_start_release
    or dword ptr [rbx + KH_flags], KP_STARTED
    mov qword ptr [rbx + KH_dirty], 1
.Lka_start_release:
    mov [rsp], rax
    mov rdi, rbx
    call kh_guard_release
    cmp qword ptr [rsp], 0
    je .Lka_start_return
    mov rax, [rsp]
.Lka_start_return:
    EPILOGUE
.Lka_start_cleanup_error:
    mov rax, [rbx + KH_cleanup]
    jmp .Lka_start_release
.Lka_start_guard_error:
    mov rax, r15
    test rax, rax
    js .Lka_start_return
    mov rax, -5
    EPILOGUE

# Exactly one <=PIPE_BUF frame. The activation owner rechecks its own epochs before each call.
FN keeper_start_selected
    PROLOGUE 208
    mov [rsp + 192], rsi
    mov [rsp + 200], rdx
    call kp_find
    test rax, rax
    jz .Lka_send_missing
    mov rbx, rax
    cmp qword ptr [rbx + KX_mode], KP_EXTENSION
    jne .Lka_send_invalid
    mov rax, [rsp + 200]
    cmp rax, [rbx + KX_context]
    jne .Lka_send_stale
    cmp rax, [rip + ka_epoch]
    jne .Lka_send_stale
    cmp qword ptr [rbx + KX_accepted], 0
    jne .Lka_send_accepted
    test dword ptr [rbx + KX_flags], KP_FAILED | KP_DONE | KP_DEFERRED
    jnz .Lka_send_failed
    test dword ptr [rbx + KX_flags], KP_READY
    jz .Lka_send_again
    cmp qword ptr [rbx + KX_control], -1
    je .Lka_send_failed
    mov rdi, rsp
    xor esi, esi
    mov edx, 192
    call memset
    mov rax, 0x314c5443504b4852
    mov [rsp], rax
    mov rax, [rbx + KX_id]
    mov [rsp + 8], rax
    mov dword ptr [rsp + 16], 2
    mov dword ptr [rsp + 20], 168
    mov rsi, [rsp + 192]
    test rsi, rsi
    jz 1f
    lea rdi, [rsp + 24]
    mov edx, EXI_SIZE
    call memcpy
1:  mov rax, [rsp + 200]
    mov [rsp + 184], rax
    mov rdi, [rbx + KX_auth]
    mov rsi, [rbx + KX_auth_len]
    call kp_auth_parse
    test rax, rax
    js .Lka_send_return
    mov rdi, rax
    lea rsi, [rsp + 24]
    mov rdx, [rsp + 184]
    call kp_extension_check_start
    test rax, rax
    js .Lka_send_return
    mov rdi, [rbx + KX_control]
    mov rsi, rsp
    mov edx, 192
    SYS SYS_write
    cmp rax, 192
    je .Lka_send_success
    cmp rax, -11
    je .Lka_send_again
    cmp rax, -4
    je .Lka_send_again
    test rax, rax
    js 2f
    mov rax, -5
2:  mov r12, rax
    mov [rbx + KX_error], eax
    or dword ptr [rbx + KX_flags], KP_FAILED
    mov rdi, [rbx + KX_id]
    call keeper_stop
    mov rax, r12
.Lka_send_return:
    EPILOGUE
.Lka_send_success:
    mov qword ptr [rbx + KX_accepted], 1
.Lka_send_accepted:
    mov eax, 1
    EPILOGUE
.Lka_send_again:
    xor eax, eax
    EPILOGUE
.Lka_send_stale:
    mov rax, -116
    EPILOGUE
.Lka_send_invalid:
    mov rax, -22
    EPILOGUE
.Lka_send_missing:
    mov rax, -2
    EPILOGUE
.Lka_send_failed:
    movsxd rax, dword ptr [rbx + KX_error]
    test rax, rax
    js .Lka_send_return
    mov rax, -5
    EPILOGUE

# keeper_info(handle,out24)->0/-errno. Caller owns output bytes.
FN keeper_info
    PROLOGUE
    mov r12, rsi
    test r12, r12
    jz 8f
    call kp_find
    test rax, rax
    jz 7f
    mov rdx, [rax + KX_target]
    mov [r12], rdx
    mov rdx, [rax + KX_confined]
    mov [r12 + 8], rdx
    mov rdx, [rax + KX_context]
    mov [r12 + 16], rdx
    xor eax, eax
    EPILOGUE
7:  mov rax, -2
    EPILOGUE
8:  mov rax, -22
    EPILOGUE

# Deferred initialization never creates a target until authorization, confinement and phase flush.
FN kp_extension_prepare
    PROLOGUE
    mov rbx, rdi
    call kp_extension_authorize
    test rax, rax
    js 9f
    cmp qword ptr [rbx + KH_no_target_flushed], 0
    jne 11f
    mov qword ptr [rbx + KH_dirty], 1
    mov rdi, rbx
    call kh_flush
    test rax, rax
    js 9f
    jz 8f
    mov qword ptr [rbx + KH_no_target_flushed], 1
11: cmp qword ptr [rbx + KH_creating], 0
    jne 1f
    mov rdi, rbx
    call kp_extension_confinement
    test rax, rax
    js 9f
    mov qword ptr [rbx + KH_creating], 1
    or dword ptr [rbx + KH_flags], KP_CREATING
    mov qword ptr [rbx + KH_dirty], 1
1:  mov rdi, rbx
    call kh_flush
    test rax, rax
    js 9f
    jz 8f
    mov rdi, rbx
    call kp_helper_alive
    test rax, rax
    js 9f
    mov qword ptr [rbx + KH_native_attempted], 1
    mov rdi, rbx
    call kp_target_prepare
    mov r12, rax
    mov qword ptr [rbx + KH_prepare_pending], 0
    mov rdi, rbx
    call kp_extension_confinement_release
    mov rax, r12
    test rax, rax
    js 91f
    mov rax, [rbx + KH_cleanup]
91: test rax, rax
    js 9f
    mov qword ptr [rbx + KH_prepare_pending], 0
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -11
    EPILOGUE

# Release protection only after native DONE, before publishing the terminal status.
FN kp_extension_cleanup
    PROLOGUE
    mov rbx, rdi
    call kp_extension_confinement_release
    mov rdi, rbx
    call kh_guard_release
    mov rdi, rbx
    mov esi, 4
    call kh_close_field
    mov rax, [rbx + KH_cleanup]
    EPILOGUE

# Native raw descriptor/HANDLE duplicate, preserving access and adding noninheritability.
FN kp_raw_duplicate
    jmp kp_lease_duplicate

# Capture a validated prototype into one owned allocation. Lease remains borrowed from metadata owner.
FN keeper_extension_plan_try
    PROLOGUE 16
    mov r12, rdi
    call keeper_extension_auth
    test rax, rax
    jz .Lka_plan_auth_error
    mov r13, rax
    mov r14, rdx
    lea rdi, [rdx + KE_SIZE]
    call mem_alloc_try
    test rax, rax
    jz .Lka_plan_nomem
    mov rbx, rax
    mov rdi, rax
    mov rsi, r12
    mov edx, KE_SIZE
    call memcpy
    lea rdi, [rbx + KE_SIZE]
    mov rsi, r13
    mov rdx, r14
    call memcpy
    mov rdi, r13
    call mem_free
    lea rdi, [rbx + KE_SIZE]
    mov rsi, r14
    call kp_auth_parse
    test rax, rax
    js .Lka_plan_parse_error
    mov r12, rax
    xor ecx, ecx
1:  mov rdx, [r12 + rcx*8 + AX_strings]
    mov [rbx + rcx*8], rdx
    inc rcx
    cmp rcx, 10
    jb 1b
    mov rax, [r12 + AX_expected]
    mov [rbx + KE_expected], rax
    mov rax, [r12 + AX_id]
    mov [rbx + KE_id], rax
    mov rax, rbx
    xor edx, edx
    EPILOGUE
.Lka_plan_parse_error:
    mov r12, rax
    mov rdi, rbx
    call mem_free
    mov rdx, r12
    xor eax, eax
    EPILOGUE
.Lka_plan_nomem:
    mov rdi, r13
    call mem_free
    mov rdx, -12
    xor eax, eax
    EPILOGUE
.Lka_plan_auth_error:
    xor eax, eax
    EPILOGUE

FN keeper_extension_plan_free
    jmp mem_free
