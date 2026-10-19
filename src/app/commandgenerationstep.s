.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/commandgeneration.inc"
.text
# CG -> valid active marked ownership. No supplier bytes are read.
FN cg_active
    test rdi, rdi
    jz 8f
    cmp qword ptr [rdi + PO_refs], 0
    je 8f
    cmp qword ptr [rdi - RD_PO_BACK + RD_kind], 4
    jne 8f
    test qword ptr [rdi - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz 8f
    xor eax, eax
    ret
8:  mov rax, -22
    ret
# CG,current positive context24 ->0/-ESTALE. Borrowed for this call only.
FN cg_context
    test rsi, rsi
    jz 8f
    xor ecx, ecx
1:  mov rax, [rsi + rcx*8]
    test rax, rax
    jle 8f
    cmp [rdi + rcx*8 + CG_intent], rax
    jne 8f
    inc rcx
    cmp rcx, 3
    jb 1b
    xor eax, eax
    ret
8:  mov rax, -116
    ret

# CG,current context24,budget1..16 ->1pending/0ready/-errno, RDXactual work.
FN command_generation_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    lea rax, [rdx - 1]
    cmp rax, 15
    ja .Lcgstep_invalid
    call cg_active
    test rax, rax
    jnz .Lcgstep_return
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz .Lcgstep_return
    mov rdi, rbx
    mov rsi, r12
    call cg_context
    test rax, rax
    jnz .Lcgstep_fail
    cmp qword ptr [rbx + PO_ready], 1
    je .Lcgstep_ready
    cmp qword ptr [rbx + CG_phase], CG_ALLOC
    jb .Lcgstep_badphase
.Lcgstep_loop:
    mov rdi, rbx
    call cg_build_one
    inc r14
    test rax, rax
    js .Lcgstep_fail
    cmp qword ptr [rbx + CG_phase], CG_READY
    je .Lcgstep_finish
    test rax, rax
    jnz .Lcgstep_pending
    cmp r14, r13
    jb .Lcgstep_loop
.Lcgstep_pending:
    mov eax, 1
    jmp .Lcgstep_return
.Lcgstep_finish:
    mov rdi, rbx
    mov rsi, r12
    call cg_context
    test rax, rax
    jnz .Lcgstep_fail
    mov qword ptr [rbx + PO_ready], 1
.Lcgstep_ready:
    xor eax, eax
    jmp .Lcgstep_return
.Lcgstep_badphase:
    mov rax, -22
.Lcgstep_fail:
    mov rdi, rbx
    call cg_fail
    jmp .Lcgstep_return
.Lcgstep_invalid:
    mov rax, -22
.Lcgstep_return:
    mov rdx, r14
    EPILOGUE

FN command_generation_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call cg_active
    test rax, rax
    jnz 9f
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz 9f
    cmp qword ptr [rbx + PO_ready], 1
    jne 8f
    mov rdi, rbx
    mov rsi, r12
    call cg_context
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE

# Getter validation is independent of epoch checking; caller checks actual epochs before use.
FN cg_getter
    PROLOGUE
    mov rbx, rdi
    call cg_active
    test rax, rax
    jnz 9f
    mov rax, [rbx + PO_error]
    test rax, rax
    jnz 9f
    cmp qword ptr [rbx + PO_ready], 1
    jne 8f
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
FN command_generation_views
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 8f
    call cg_getter
    test rax, rax
    jnz 9f
    mov rdi, r12
    lea rsi, [rbx + CG_commands]
    mov edx, 96
    call memcpy
    xor eax, eax
9:  EPILOGUE
8:  mov rax, -22
    EPILOGUE
FN command_generation_manifest_count
    PROLOGUE
    mov rbx, rdi
    call cg_getter
    test rax, rax
    jnz 9f
    mov rax, [rbx + CG_nmanifest]
9:  EPILOGUE
# CG,sparse ordinal,out16 ->0/-errno. Fixed<=128 row preflight lookup.
FN command_generation_slot
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz 8f
    cmp r12, 128
    jae 8f
    call cg_getter
    test rax, rax
    jnz 9f
    xor ecx, ecx
1:  cmp rcx, [rbx + CG_nslots]
    jae 7f
    imul rax, rcx, CS_SIZE
    lea rax, [rbx + rax + CG_slots]
    inc rcx
    cmp [rax + CS_ordinal], r12
    jne 1b
    mov rdx, [rax + CS_first]
    mov [r13], rdx
    mov rdx, [rax + CS_count]
    mov [r13 + 8], rdx
    xor eax, eax
9:  EPILOGUE
7:  mov rax, -2
    EPILOGUE
8:  mov rax, -22
    EPILOGUE
