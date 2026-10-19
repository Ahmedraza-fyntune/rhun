# Charged raw construction. Never follows a partially initialized payload.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extdiscoveryalloc.inc"
.bss
.p2align 3
.globl discovery_extra_charge, discovery_foreign_charge
discovery_extra_charge: .quad 0
discovery_foreign_charge: .quad 0
.text
# Constructor-only fixed allowance. Caller owns and charges DIA backing.
FN pd_alloc_init
    test rdi, rdi
    jz .Lpda_invalid
    PROLOGUE
    mov edx, DIA_SIZE
    xor esi, esi
    call memset
    xor eax, eax
    EPILOGUE

FN pd_extra_block_charge
    mov rax, rdi
    add rax, 16
    jc 8f
    cmp rax, PD_EXTRA_CAP
    ja 8f
    cmp rax, 65536
    ja 2f
    mov edx, 32
1:  cmp rdx, rax
    jae 3f
    add rdx, rdx
    jmp 1b
2:  add rax, 4095
    and rax, -4096
    cmp rax, PD_EXTRA_CAP
    ja 8f
    ret
3:  mov rax, rdx
    ret
8:  xor eax, eax
    ret

# Admit only. Acquisition and charge commit occur with no yield or callback.
FN pd_extra_admit
    test rdi, rdi
    jz 8f
    mov rax, [rip + discovery_extra_charge]
    add rax, rdi
    jc 8f
    cmp rax, PD_EXTRA_CAP
    ja 8f
    mov rcx, [rip + prep_total_charge]
    cmp rcx, PREP_TOTAL_CAP
    ja 8f
    add rax, rcx
    jc 8f
    mov rcx, [rip + discovery_foreign_charge]
    test rcx, rcx
    jz 1f
    cmp rcx, PD_FOREIGN_CAP
    jne 8f
1:
    add rax, rcx
    jc 8f
    cmp rax, PD_COMBINED_CAP
    ja 8f
    xor eax, eax
    ret
8:  mov rax, -EV_RESOURCE
    ret

# Trusted local slot record, borrowed. No payload inspection.
FN pd_alloc_slot
    test rdi, rdi
    jz .Lpda_invalid
    cmp qword ptr [rdi + DIA_state], DIA_EMPTY
    ja .Lpda_invalid
    cmp rsi, 16
    jae .Lpda_invalid
    mov rax, rsi
    shl rax, 6
    lea rax, [rdi + rax + DIA_slots]
    cmp qword ptr [rax + DTS_raw], 0
    je .Lpda_invalid
    ret

FN pd_alloc_begin
    test rdi, rdi
    jz .Lpda_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpda_invalid
    cmp qword ptr [rdi + DIA_ep], 0
    je 11f
    cmp qword ptr [rdi + DIA_eo], 0
    je .Lpda_invalid
11:
    lea rax, [rsi - 1]
    cmp rax, 5
    ja .Lpda_invalid
    test rdx, rdx
    jle .Lpda_invalid
    cmp rsi, PD_EO
    jne 1f
    cmp rdx, EO_SIZE
    jne .Lpda_invalid
1:  cmp rsi, PD_EP
    jne 2f
    cmp rdx, EP_SIZE
    jne .Lpda_invalid
2:  cmp rsi, PD_GP
    jne 3f
    cmp rdx, GP_SIZE
    jne .Lpda_invalid
3:  PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rdx
    cmp r12, PD_EO
    jne 4f
    add r14, RD_SIZE
    jmp 6f
4:  cmp r12, PD_EP
    je 5f
    cmp r12, PD_GP
    jne 7f
5:  add r14, RD_SIZE + AO_SIZE
    jmp 6f
7:  cmp r12, PD_MEMBER
    jne 6f
    add r14, AO_SIZE
6:  xor r15d, r15d
8:  mov rax, r15
    shl rax, 6
    cmp qword ptr [rbx + rax + DIA_slots + DTS_state], DTS_EMPTY
    je 9f
    inc r15
    cmp r15, 16
    jb 8b
    jmp .Lpda_begin_resource
9:  mov rdi, r14
    call pd_extra_block_charge
    test rax, rax
    jz .Lpda_begin_resource
    mov [rsp], rax
    mov rdi, rax
    call pd_extra_admit
    test rax, rax
    js .Lpda_begin_error
    mov rdi, r14
    call mem_alloc_uninit_try
    test rax, rax
    jz .Lpda_begin_nomem
    mov rcx, r15
    shl rcx, 6
    lea rcx, [rbx + rcx + DIA_slots]
    mov [rcx + DTS_raw], rax
    mov [rcx + DTS_request], r14
    mov rdx, [rsp]
    mov [rcx + DTS_charge], rdx
    mov qword ptr [rcx + DTS_initialized], 0
    mov [rcx + DTS_kind], r12
    mov qword ptr [rcx + DTS_state], DTS_RAW
    mov [rcx + DTS_logical], r13
    mov qword ptr [rcx + DTS_due], 0
    add [rip + discovery_extra_charge], rdx
    inc qword ptr [rbx + DIA_active]
    mov rax, r15
    EPILOGUE
.Lpda_begin_resource:
    mov rax, -EV_RESOURCE
    jmp .Lpda_begin_error
.Lpda_begin_nomem:
    mov rax, -12
.Lpda_begin_error:
    mov rdi, rbx
    mov rsi, rax
    call pd_alloc_abort
    mov rax, rsi
    EPILOGUE

FN pd_alloc_abort
    test rdi, rdi
    jz .Lpda_invalid
    cmp qword ptr [rdi + DIA_state], DIA_EMPTY
    jae .Lpda_invalid
    cmp qword ptr [rdi + DIA_primary], 0
    jne 1f
    test rsi, rsi
    jns 1f
    mov [rdi + DIA_primary], rsi
1:  mov qword ptr [rdi + DIA_state], DIA_ABORT
    xor eax, eax
    ret

# Each initialized byte is charged to the caller's explicit payload budget.
FN pd_alloc_zero
    test rdi, rdi
    jz .Lpda_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpda_invalid
    cmp qword ptr [rdi + DIA_ep], 0
    je 11f
    cmp qword ptr [rdi + DIA_eo], 0
    je .Lpda_invalid
11:
    lea rax, [rdx - 1]
    cmp rax, 65535
    ja .Lpda_invalid
    PROLOGUE
    mov r12, rdx
    call pd_alloc_slot
    test rax, rax
    js .Lpda_init_exit
    mov rbx, rax
    cmp qword ptr [rbx + DTS_state], DTS_RETAINED
    jae .Lpda_init_invalid
    mov r13, [rbx + DTS_request]
    sub r13, [rbx + DTS_initialized]
    cmp r13, r12
    cmova r13, r12
    mov rdi, [rbx + DTS_raw]
    add rdi, [rbx + DTS_initialized]
    mov rdx, r13
    xor esi, esi
    call memset
    add [rbx + DTS_initialized], r13
    call pd_alloc_init_state
    mov rax, r13
.Lpda_init_exit:
    EPILOGUE
.Lpda_init_invalid:
    mov rax, -22
    EPILOGUE

# Copy only data regions. Native constructor fields are never a wire image.
FN pd_alloc_copy
    test rdi, rdi
    jz .Lpda_invalid
    cmp qword ptr [rdi + DIA_state], DIA_ACTIVE
    jne .Lpda_invalid
    cmp qword ptr [rdi + DIA_ep], 0
    je 11f
    cmp qword ptr [rdi + DIA_eo], 0
    je .Lpda_invalid
11:
    test rdx, rdx
    jz .Lpda_invalid
    lea rax, [rcx - 1]
    cmp rax, 65535
    ja .Lpda_invalid
    PROLOGUE
    mov r12, rdx
    mov r13, rcx
    call pd_alloc_slot
    test rax, rax
    js .Lpda_init_exit
    mov rbx, rax
    cmp qword ptr [rbx + DTS_state], DTS_RETAINED
    jae .Lpda_init_invalid
    mov rax, [rbx + DTS_kind]
    cmp rax, PD_EXTRA
    je 1f
    cmp rax, PD_VALUE
    je 1f
    cmp rax, PD_MEMBER
    jne .Lpda_init_invalid
    cmp qword ptr [rbx + DTS_initialized], AO_SIZE
    jb .Lpda_init_invalid
1:  mov rax, [rbx + DTS_request]
    sub rax, [rbx + DTS_initialized]
    cmp rax, r13
    jb .Lpda_init_invalid
    mov rdi, [rbx + DTS_raw]
    add rdi, [rbx + DTS_initialized]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    add [rbx + DTS_initialized], r13
    call pd_alloc_init_state
    mov rax, r13
    EPILOGUE

# Internal fixed metadata operation, RBX slot. All payload work already debited.
FN pd_alloc_init_state
    mov rax, [rbx + DTS_initialized]
    cmp rax, [rbx + DTS_request]
    jne 1f
    mov qword ptr [rbx + DTS_state], DTS_INITIALIZED
1:  ret

FN pd_alloc_view
    test rdx, rdx
    jz .Lpda_invalid
    PROLOGUE
    mov rbx, rdx
    call pd_alloc_slot
    test rax, rax
    js 1f
    mov rcx, [rax + DTS_raw]
    mov [rbx], rcx
    mov rcx, [rax + DTS_request]
    mov [rbx + 8], rcx
    mov rcx, [rax + DTS_initialized]
    mov [rbx + 16], rcx
    mov rcx, [rax + DTS_kind]
    mov [rbx + 24], rcx
    xor eax, eax
1:  EPILOGUE

# Fixed slot record removal after another owner or real free consumed its bytes.
FN pd_alloc_clear_slot
    mov qword ptr [rsi], 0
    mov qword ptr [rsi + 8], 0
    mov qword ptr [rsi + 16], 0
    mov qword ptr [rsi + 24], 0
    mov qword ptr [rsi + 32], 0
    mov qword ptr [rsi + 40], 0
    mov qword ptr [rsi + 48], 0
    mov qword ptr [rsi + 56], 0
    dec qword ptr [rdi + DIA_active]
    ret

.Lpda_invalid:
    mov rax, -22
    ret
