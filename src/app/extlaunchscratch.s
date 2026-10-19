# Parent launch inputs remain owned until the synchronous native consumer returns.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
launch_active: .quad 0
launch_eo: .quad 0
launch_po: .quad 0
launch_argv: .quad 0
launch_env: .quad 0
launch_primary: .quad 0
launch_cleanup: .quad 0
launch_due: .quad 0
.data
.p2align 3
launch_delay: .quad 16
.text
# Two process-lifetime vector descriptors. RDX1 requires end even on failure.
FN ext_launch_scratch_begin
    PROLOGUE
    cmp qword ptr [rip + launch_active], 0
    jne .Lls_busy
    cmp qword ptr [rip + launch_eo], 0
    jne .Lls_busy
    cmp qword ptr [rip + launch_po], 0
    jne .Lls_busy
    test rdi, rdi
    jz .Lls_invalid
    test rsi, rsi
    jz .Lls_invalid
    cmp rdi, rsi
    je .Lls_invalid
    mov [rip + launch_argv], rdi
    mov [rip + launch_env], rsi
    mov qword ptr [rdi + VEC_ptr], 0
    mov qword ptr [rdi + VEC_len], 0
    mov qword ptr [rdi + VEC_cap], 0
    mov qword ptr [rsi + VEC_ptr], 0
    mov qword ptr [rsi + VEC_len], 0
    mov qword ptr [rsi + VEC_cap], 0
    mov qword ptr [rip + launch_active], 1
    mov qword ptr [rip + launch_primary], 0
    mov qword ptr [rip + launch_cleanup], 0
    mov qword ptr [rip + launch_due], 0
    mov qword ptr [rip + launch_delay], 16
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    mov [rip + launch_eo], rax
    test rax, rax
    jz .Lls_constructor_error
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    test rax, rax
    js .Lls_begin_error
    mov rdi, [rip + launch_eo]
    mov esi, PO_SIZE
    call prep_object_create
    mov [rip + launch_po], rax
    test rax, rax
    jz .Lls_constructor_error
    xor eax, eax
    mov edx, 1
    EPILOGUE
.Lls_constructor_error:
    mov rax, rdx
.Lls_begin_error:
    mov [rip + launch_primary], rax
    mov edx, 1
    EPILOGUE
.Lls_busy:
    mov rax, -16
    xor edx, edx
    EPILOGUE
.Lls_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE

FN ext_launch_scratch_error
    mov rax, [rip + launch_primary]
    ret

# Sticky builder failure. Never loses a live owner behind an error return.
launch_record_error:
    cmp qword ptr [rip + launch_primary], 0
    jne 9f
    mov rax, [rip + launch_po]
    test rax, rax
    jz 1f
    mov rax, [rax + PO_error]
    test rax, rax
    js 2f
1:  mov rax, -22
2:  mov [rip + launch_primary], rax
9:  xor eax, eax
    ret

FN ext_launch_scratch_push
    cmp qword ptr [rip + launch_active], 1
    jne launch_record_error
    cmp qword ptr [rip + launch_primary], 0
    jne launch_record_error
    cmp rsi, 8
    jne launch_record_error
    cmp rdi, [rip + launch_argv]
    je 1f
    cmp rdi, [rip + launch_env]
    jne launch_record_error
1:  mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rip + launch_po]
    test rdi, rdi
    jz launch_record_error
    PROLOGUE
    call prep_owned_vec_push
    test rax, rax
    jnz 9f
    call launch_record_error
9:  EPILOGUE

FN ext_launch_scratch_dup
    cmp qword ptr [rip + launch_active], 1
    jne launch_record_error
    cmp qword ptr [rip + launch_primary], 0
    jne launch_record_error
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rip + launch_po]
    test rdi, rdi
    jz launch_record_error
    PROLOGUE
    call prep_owned_dup
    test rax, rax
    jnz 9f
    call launch_record_error
9:  EPILOGUE

# Retained refs are retried only by deadline. Consumed refs are never touched again.
FN ext_launch_scratch_end
    cmp qword ptr [rip + launch_active], 0
    je 1f
    mov qword ptr [rip + launch_active], 0
    jmp launch_transfer
1:  jmp launch_result

FN ext_launch_scratch_tick
    cmp qword ptr [rip + launch_active], 0
    jne launch_result
    cmp qword ptr [rip + launch_due], 0
    je launch_result
    cmp rdi, [rip + launch_due]
    jb launch_result
launch_transfer:
    PROLOGUE
    mov rdi, [rip + launch_po]
    test rdi, rdi
    jz 2f
    call prep_owned_dispose
    mov rbx, rdx
    call launch_note_cleanup
    cmp rbx, 1
    jne .Lls_retained
    mov qword ptr [rip + launch_po], 0
2:  mov rdi, [rip + launch_argv]
    test rdi, rdi
    jz 3f
    mov qword ptr [rdi + VEC_ptr], 0
    mov qword ptr [rdi + VEC_len], 0
    mov qword ptr [rdi + VEC_cap], 0
3:  mov rdi, [rip + launch_env]
    test rdi, rdi
    jz 4f
    mov qword ptr [rdi + VEC_ptr], 0
    mov qword ptr [rdi + VEC_len], 0
    mov qword ptr [rdi + VEC_cap], 0
4:  mov rdi, [rip + launch_eo]
    test rdi, rdi
    jz 5f
    call ext_prepare_owner_release_deferred
    mov rbx, rdx
    call launch_note_cleanup
    cmp rbx, 1
    jne .Lls_retained
    mov qword ptr [rip + launch_eo], 0
5:  mov qword ptr [rip + launch_due], 0
    call launch_result
    EPILOGUE
.Lls_retained:
    call time_ms
    add rax, [rip + launch_delay]
    mov [rip + launch_due], rax
    mov rax, [rip + launch_delay]
    add rax, rax
    mov edx, 1000
    cmp rax, rdx
    cmova rax, rdx
    mov [rip + launch_delay], rax
    call launch_result
    EPILOGUE
launch_note_cleanup:
    test rax, rax
    jns 9f
    cmp qword ptr [rip + launch_cleanup], 0
    jne 9f
    mov [rip + launch_cleanup], rax
9:  ret
launch_result:
    mov rax, [rip + launch_cleanup]
    xor edx, edx
    cmp qword ptr [rip + launch_active], 0
    jne 9f
    cmp qword ptr [rip + launch_po], 0
    jne 9f
    cmp qword ptr [rip + launch_eo], 0
    jne 9f
    mov edx, 1
9:  ret

FN ext_launch_scratch_timeout
    mov rax, -1
    cmp qword ptr [rip + launch_active], 0
    jne 9f
    cmp qword ptr [rip + launch_due], 0
    je 9f
    mov rax, [rip + launch_due]
    sub rax, rdi
    ja 9f
    mov eax, 1
9:  ret
