# Immutable default chains preserve immediate runtime revocation without rebuilding keys.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/commandgeneration.inc"
.text
# One allocation per call, before source rows and final binding pointers are built.
FN cg_defaults_allocate
    PROLOGUE
    mov rbx, rdi
    lea r12, [rbx + CG_defaultmeta]
    mov esi, CG_BINDING_CAP * 16
    cmp qword ptr [rbx + CG_phase], CG_DEFAULT_ALLOC_META
    je 1f
    lea r12, [rbx + CG_defaultnodes]
    mov rsi, [rbx + CG_defaultcapacity]
    test rsi, rsi
    jz .Lcgda_invalid
    cmp rsi, CG_DEFAULT_NODE_CAP
    ja .Lcgda_invalid
    shl rsi, 4
1:  call prep_owned_alloc
    test rax, rax
    jz .Lcgda_error
    mov [r12], rax
    cmp qword ptr [rbx + CG_phase], CG_DEFAULT_ALLOC_META
    jne 2f
    mov qword ptr [rbx + CG_phase], CG_DEFAULT_ALLOC_NODES
    jmp 3f
2:  mov qword ptr [rbx + CG_phase], 9
3:  mov eax, 1
    EPILOGUE
.Lcgda_error:
    mov rax, [rbx + PO_error]
    EPILOGUE
.Lcgda_invalid:
    mov rax, -EV_RESOURCE
    EPILOGUE

# CG, final binding ordinal. Fixed scalar work, no source reads or allocation.
FN cg_defaults_note
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + CG_defaultmeta]
    test r12, r12
    jz .Lcgd_note_ok
    cmp rsi, [rbx + CG_bindings + VEC_len]
    jae .Lcgd_note_bad
    cmp rsi, CG_BINDING_CAP
    jae .Lcgd_note_bad
    mov r13, rsi
    shl r13, 4
    add r12, r13
    cmp qword ptr [rbx + CG_wordmode], 2
    je .Lcgd_note_user
    cmp qword ptr [rbx + CG_wordmode], 1
    jne .Lcgd_note_ok
    mov rax, [rbx + CG_row]
    cmp rax, [rbx + CG_nmanifest]
    jb .Lcgd_note_ok
    # Earlier builtin/manifest defaults cannot be displaced by runtime revocation.
    add r13, [rbx + CG_bindings + VEC_ptr]
    mov r13, [r13 + KB_cmd]
    mov rax, [rbx + CG_nmanifest]
    shl rax, 5
    add rax, [rbx + CG_commands + VEC_ptr]
    cmp r13, rax
    jb .Lcgd_note_ok
    mov rdx, [rbx + CG_ncommands]
    sub rdx, [rbx + CG_nmanifest]
    shl rdx, 5
    sub r13, rax
    cmp r13, rdx
    jae .Lcgd_note_ok
    test r13, 31
    jnz .Lcgd_note_bad
    mov r13, [rbx + CG_bindingcmd]
    mov r14, [r12 + 8]
    test r14, r14
    jz .Lcgd_note_append
    cmp r14, [rbx + CG_defaultcount]
    ja .Lcgd_note_bad
    dec r14
    shl r14, 4
    add r14, [rbx + CG_defaultnodes]
    cmp [r14], r13
    je .Lcgd_note_ok
.Lcgd_note_append:
    mov r15, [rbx + CG_defaultcount]
    cmp r15, [rbx + CG_defaultcapacity]
    jae .Lcgd_note_bad
    mov rax, r15
    shl rax, 4
    add rax, [rbx + CG_defaultnodes]
    mov [rax], r13
    mov qword ptr [rax + 8], 0
    inc r15
    test r14, r14
    jz 1f
    mov [r14 + 8], r15
    jmp 2f
1:  mov [r12], r15
2:  mov [r12 + 8], r15
    mov [rbx + CG_defaultcount], r15
.Lcgd_note_ok:
    xor eax, eax
    EPILOGUE
.Lcgd_note_user:
    bts qword ptr [r12], CG_DEFAULT_USER_BIT
    jmp .Lcgd_note_ok
.Lcgd_note_bad:
    mov rax, -EV_RESOURCE
    EPILOGUE

# Retained ready CG, binding ordinal, disjoint writable out40. No epoch authority grant.
FN command_generation_binding_route
    PROLOGUE 48
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .Lcgdr_invalid
    call cg_getter
    test rax, rax
    jnz .Lcgdr_return
    cmp r12, [rbx + CG_bindings + VEC_len]
    jae .Lcgdr_invalid
    mov r14, r12
    shl r14, 4
    mov rax, r14
    add rax, [rbx + CG_bindings + VEC_ptr]
    mov rax, [rax + KB_cmd]
    mov [rsp], rax
    mov rax, [rbx + CG_defaultnodes]
    mov [rsp + 8], rax
    mov qword ptr [rsp + 16], 0
    mov rax, [rbx + CG_defaultcount]
    mov [rsp + 24], rax
    mov qword ptr [rsp + 32], 0
    mov rax, [rbx + CG_defaultmeta]
    test rax, rax
    jz 1f
    mov rax, [rax + r14]
    mov rcx, rax
    shr rcx, CG_DEFAULT_USER_BIT
    mov [rsp + 32], rcx
    btr rax, CG_DEFAULT_USER_BIT
    mov [rsp + 16], rax
1:  mov rdi, r13
    mov rsi, rsp
    mov edx, 40
    call memcpy
    xor eax, eax
.Lcgdr_return:
    EPILOGUE
.Lcgdr_invalid:
    mov rax, -22
    EPILOGUE
