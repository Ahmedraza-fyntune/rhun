# Helper-only legacy link-following opens. Never used by pure import or managed validation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.text
# Actual classification and checked ownership after a successful native open.
# Internal(handle,kind)->owned handle/-primary,secondary cleanup.
prep_legacy_classify:
    PROLOGUE ER_STAT_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov rsi, rsp
    call ext_root_stat
    test rax, rax
    js .Leplc_close
    cmp r12, ER_ANY
    je .Leplc_good
    cmp [rsp + ER_kind], r12
    je .Leplc_good
    mov rax, -20
    cmp r12, ER_DIR
    je .Leplc_close
    mov rax, -21
.Leplc_close:
    mov r12, rax
    mov rdi, rbx
    call ext_root_close
    mov rdx, rax
    mov rax, r12
    EPILOGUE
.Leplc_good:
    mov rax, rbx
    xor edx, edx
    EPILOGUE

# Bounded ordinary final link-following basename open, anchored to actual parent.
FN prep_legacy_open_at
.ifdef WINDOWS
    jmp win_prep_legacy_open_at
.else
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsi
    call ext_root_name
    test rax, rax
    js .Leplo_error
    mov r14d, 128
.Leplo_retry:
    mov rdi, rbx
    mov rsi, r12
    mov edx, 0x80800          # O_CLOEXEC|O_NONBLOCK, final links deliberately followed
    cmp r13, ER_DIR
    jne 1f
    or edx, 0x10000
1:  xor r10d, r10d
    SYS SYS_openat
    cmp rax, -EINTR
    jne 2f
    dec r14
    jnz .Leplo_retry
2:  test rax, rax
    js .Leplo_error
    mov rdi, rax
    mov rsi, r13
    call prep_legacy_classify
    EPILOGUE
.Leplo_error:
    xor edx, edx
    EPILOGUE
.endif

# Ordinary absolute legacy pathname; native lookup may block, helper process only.
FN prep_legacy_open_absolute
.ifdef WINDOWS
    jmp win_prep_legacy_open_absolute
.else
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Leploa_bad
    cmp byte ptr [rbx], '/'
    jne .Leploa_bad
    mov rsi, rax
    mov rdi, rbx
    call ext_validate_text
    test eax, eax
    jz .Leploa_bad
    mov r13d, 128
.Leploa_retry:
    mov rdi, rbx
    mov esi, 0x80800
    cmp r12, ER_DIR
    jne 1f
    or esi, 0x10000
1:  xor edx, edx
    SYS SYS_open
    cmp rax, -EINTR
    jne 2f
    dec r13
    jnz .Leploa_retry
2:  test rax, rax
    js .Leploa_error
    mov rdi, rax
    mov rsi, r12
    call prep_legacy_classify
    EPILOGUE
.Leploa_bad:
    mov rax, -EV_BAD_PATH
.Leploa_error:
    xor edx, edx
    EPILOGUE
.endif

# Only canonical manifest or flat asset relative paths. Final components may follow links.
FN prep_legacy_open_relative
    PROLOGUE 4128
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rdx, rdx
    jz .Leplor_bad
    cmp rdx, 4095
    ja .Leplor_bad
    mov rdi, rsp
    call memcpy
    mov byte ptr [rsp + r13], 0
    xor r14d, r14d
1:  cmp r14, r13
    jae .Leplor_flat
    cmp byte ptr [rsp + r14], '/'
    je 2f
    inc r14
    jmp 1b
2:  mov byte ptr [rsp + r14], 0
    mov rdi, rbx
    mov rsi, rsp
    mov edx, ER_DIR
    call prep_legacy_open_at
    test rax, rax
    js .Leplor_done
    mov r15, rax
    mov rdi, rax
    lea rsi, [rsp + r14 + 1]
    mov edx, ER_FILE
    call prep_legacy_open_at
    mov [rsp + 4096], rax
    mov [rsp + 4104], rdx
    mov rdi, r15
    call ext_root_close
    mov rdx, [rsp + 4104]
    test rax, rax
    jns 3f
    test rdx, rdx
    jnz 3f
    mov rdx, rax
3:  mov rax, [rsp + 4096]
    test rax, rax
    js .Leplor_done
    test rdx, rdx
    jz .Leplor_done
    mov [rsp + 4104], rdx
    mov rdi, rax
    call ext_root_close
    mov rdx, rax
    mov rax, [rsp + 4104]
    EPILOGUE
.Leplor_flat:
    mov rdi, rbx
    mov rsi, rsp
    mov edx, ER_FILE
    call prep_legacy_open_at
.Leplor_done:
    EPILOGUE
.Leplor_bad:
    mov rax, -EV_BAD_PATH
    xor edx, edx
    EPILOGUE

# Bounded ordinary legacy availability policy. Actual handles establish type/bytes separately.
FN prep_legacy_access
.ifdef WINDOWS
    xor eax, eax              # Windows' old X_OK/R_OK mean existence; held open already proves it.
    ret
.else
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, 128
1:  mov rdi, rbx
    mov rsi, r12
    SYS SYS_access
    cmp rax, -EINTR
    jne 2f
    dec r13
    jnz 1b
2:  EPILOGUE
.endif

# Legacy runtime accepts slash-containing paths, otherwise existing bounded PATH/python search.
FN prep_legacy_runtime_resolve
    PROLOGUE 4128
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    mov esi, 4095
    call ext_root_length
    test rax, rax
    jle .Leplr_bad
    mov r13, rax
    xor r14d, r14d
1:  cmp r14, r13
    jae .Leplr_basename
    mov al, [r12 + r14]
    cmp al, '/'
    je .Leplr_path
.ifdef WINDOWS
    cmp al, 92
    je .Leplr_path
.endif
    inc r14
    jmp 1b
.Leplr_basename:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call prep_runtime_resolve
.ifndef WINDOWS
    test rax, rax
    jz .Leplr_done
    mov rdi, rbx
    mov rsi, rax
    call prep_legacy_runtime_absolute
.endif
    EPILOGUE
.Leplr_path:
.ifdef WINDOWS
    mov rsi, [rbx + EP_legacy_cwd]
    test rsi, rsi
    jz .Leplr_bad
.else
    mov rdi, rsp
    mov esi, 4096
    SYS SYS_getcwd
    test rax, rax
    js .Leplr_error
    mov rsi, rsp
.endif
    mov rdi, rbx
    mov rdx, r12
    mov rcx, r13
    call prep_owned_join
    xor edx, edx
    test rax, rax
    jnz .Leplr_done
    mov rdx, [rbx + PO_error]
.Leplr_done:
    EPILOGUE
.Leplr_bad:
    mov rax, -EV_BAD_RUNTIME
.Leplr_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE

# Legacy search preserves relative/empty components. Only selected POSIX paths need UTF8.
FN prep_legacy_path_env
    PROLOGUE
    lea rdi, [rip + epl_path]
    call getenv
    test rax, rax
    jz 1f
    mov rbx, rax
    mov rdi, rax
    mov esi, 65536
    call ext_root_length
    test rax, rax
    js 2f
 .ifdef WINDOWS
    mov rsi, rax
    mov rdi, rbx
    call snippet_utf8_valid
    test eax, eax
    jz 2f
.endif
1:  xor eax, eax
    EPILOGUE
2:  mov rax, -EV_BAD_RUNTIME
    EPILOGUE

.ifndef WINDOWS
# Convert selected relative PATH spelling to owned absolute helper-context spelling.
# The input is already owned by EP and is retired on every replacement/failure path.
FN prep_legacy_runtime_absolute
    PROLOGUE 4112
    mov rbx, rdi
    mov r12, rsi
    cmp byte ptr [rsi], '/'
    jne 1f
    mov rax, rsi
    xor edx, edx
    EPILOGUE
1:  mov rdi, rsp
    mov esi, 4096
    SYS SYS_getcwd
    test rax, rax
    js .Leplra_cwd_error
    mov rdi, r12
    call strlen
    mov rcx, rax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, r12
    call prep_owned_join
    mov r14, rax
    xor r15d, r15d
    test rax, rax
    jnz .Leplra_release
    mov r15, [rbx + PO_error]
    jmp .Leplra_release
.Leplra_cwd_error:
    mov r15, rax
    xor r14d, r14d
.Leplra_release:
    mov rdi, rbx
    mov rsi, r12
    call prep_owned_free
    test rax, rax
    jns 2f
    test r15, r15
    jnz 2f
    mov r15, rax
2:  mov rax, r14
    mov rdx, r15
    test rdx, rdx
    jz 3f
    xor eax, eax
3:  EPILOGUE
.endif
.section .rodata
epl_path: .asciz "PATH"
