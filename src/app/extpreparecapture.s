# Bind all executable parser decision bytes and bounds to committed payload bytes.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
.globl g_ext_image_capture
g_ext_image_capture: .quad 0
.text
# Managed POSIX native image policy, one full stat supplies both eligibility and metadata.
FN prep_owned_exec_stat
.ifdef WINDOWS
    jmp ext_root_stat
.else
    PROLOGUE 144
    mov rbx, rdi
    mov r12, rsi
    mov r13d, 128
1:  mov rdi, rbx
    mov rsi, rsp
    SYS SYS_fstat
    cmp rax, -EINTR
    jne 2f
    dec r13
    jnz 1b
2:  test rax, rax
    js 9f
.ifdef MACOS
    call mac_prep_effective_uid
.else
    SYS 107                   # geteuid, local adapter only
.endif
    cmp eax, [rsp + 28]
    jne 8f
    mov eax, [rsp + 24]
    mov ecx, eax
    and ecx, 0xf000
    cmp ecx, 0x8000
    jne 8f
    test eax, 0x40             # owner-execute0100
    jz 8f
    and eax, 0x49
    mov [r12 + ER_exec], rax
    mov rax, [rsp + 48]
    test rax, rax
    js 8f
    mov [r12 + ER_size], rax
    mov qword ptr [r12 + ER_kind], ER_FILE
    mov qword ptr [r12 + 24], 0
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -EV_BAD_EXEC
    EPILOGUE
.endif

FN prep_payload_stat
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    test rax, rax
    jz 1f
    cmp qword ptr [rax + EP_native], 1
    je prep_owned_exec_stat
1:  jmp ext_root_stat

# Saved/restored synchronous context, exact still-live payload handle only.
FN prep_capture_image
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rip + g_ext_image_capture]
    mov [rbx + EP_capture_handle], rsi
    mov rax, [rcx]
    mov [rbx + EP_capture_size], rax
    mov rax, [rcx + 8]
    mov [rbx + EP_capture_exec], rax
    mov [rip + g_ext_image_capture], rbx
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    call ext_validate_image_owned
    mov [rip + g_ext_image_capture], r14
    EPILOGUE

FN prep_image_stat
    mov rax, [rip + g_ext_image_capture]
    test rax, rax
    jz ext_root_stat
    cmp [rax + EP_capture_handle], rdi
    jne ext_root_stat
    PROLOGUE
    mov rbx, rax
    mov r12, rsi
    call prep_owned_exec_stat
    test rax, rax
    js 8f
    mov rax, [r12 + ER_size]
    cmp rax, [rbx + EP_capture_size]
    jne 7f
    mov rax, [r12 + ER_exec]
    cmp rax, [rbx + EP_capture_exec]
    jne 7f
    xor eax, eax
8:  EPILOGUE
7:  mov rax, -EV_CHANGED
    EPILOGUE

FN prep_image_read
    mov rax, [rip + g_ext_image_capture]
    test rax, rax
    jz ext_root_read
    cmp [rax + EP_capture_handle], rdi
    jne ext_root_read
    PROLOGUE 32
    mov rbx, rax
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 1024
    cmp r14, 512
    ja .Lepir_resource
    cmp r15, [rbx + EP_capture_size]
    ja .Lepir_changed
    mov rax, [rbx + EP_capture_size]
    sub rax, r15
    cmp r14, rax
    cmova r14, rax
1:  mov rax, [rsp]
    cmp rax, r14
    jae 3f
    dec qword ptr [rsp + 8]
    js .Lepir_io
    mov rdi, r12
    lea rsi, [r13 + rax]
    mov rdx, r14
    sub rdx, rax
    lea rcx, [r15 + rax]
    call ext_root_read_once
    cmp rax, -EINTR
    je 1b
    test rax, rax
    js .Lepir_done
    jz .Lepir_changed
    add rax, [rsp]
    jc .Lepir_changed
    cmp rax, r14
    ja .Lepir_changed
    mov [rsp], rax
    jmp 1b
3:  cmp qword ptr [rbx + EP_capture_ranges + VEC_len], 68
    jae .Lepir_resource
    mov rdi, rbx
    lea rsi, [rbx + EP_capture_ranges]
    mov edx, CR_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz .Lepir_alloc_error
    mov [rax + CR_offset], r15
    mov [rax + CR_len], r14
    lea rdi, [rax + CR_bytes]
    mov rsi, r13
    mov rdx, r14
    call memcpy
    mov rax, r14
.Lepir_done:
    EPILOGUE
.Lepir_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lepir_alloc_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lepir_changed:
    mov rax, -EV_CHANGED
    EPILOGUE
.Lepir_io:
    mov rax, -EV_IO
    EPILOGUE

# Compare each overlap against the same exact chunk supplied to streaming SHA256.
FN prep_capture_compare
    test rdi, rdi
    jz .Lepcc_empty
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx
    add rcx, rdx
    jc .Lepcc_changed
    mov [rsp + 8], rcx
    xor r14d, r14d
1:  cmp r14, [rbx + EP_capture_ranges + VEC_len]
    jae .Lepcc_ok
    imul r15, r14, CR_SIZE
    add r15, [rbx + EP_capture_ranges + VEC_ptr]
    mov rax, [r15 + CR_offset]
    mov rdx, [r15 + CR_len]
    add rdx, rax
    jc .Lepcc_changed
    cmp r13, rdx
    jae 3f
    cmp rax, [rsp + 8]
    jae 3f
    cmp rax, r13
    cmovb rax, r13             # overlap start
    cmp rdx, [rsp + 8]
    cmova rdx, [rsp + 8]       # overlap end
    sub rdx, rax
    mov rcx, rax
    sub rcx, r13
    lea rdi, [r12 + rcx]
    sub rax, [r15 + CR_offset]
    lea rsi, [r15 + CR_bytes + rax]
    call memeq
    test eax, eax
    jz .Lepcc_changed
3:  inc r14
    jmp 1b
.Lepcc_ok:
    xor eax, eax
    EPILOGUE
.Lepcc_changed:
    mov rax, -EV_CHANGED
    EPILOGUE
.Lepcc_empty:
    xor eax, eax
    ret

FN prep_capture_reset
    PROLOGUE
    mov rbx, rdi
    mov rsi, [rbx + EP_capture_ranges + VEC_ptr]
    call prep_owned_free
    test rax, rax
    jnz 1f
    mov qword ptr [rbx + EP_capture_ranges + VEC_ptr], 0
    mov qword ptr [rbx + EP_capture_ranges + VEC_len], 0
    mov qword ptr [rbx + EP_capture_ranges + VEC_cap], 0
    mov qword ptr [rbx + EP_capture_handle], -1
1:  EPILOGUE
