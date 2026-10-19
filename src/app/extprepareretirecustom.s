# Statically registered native owners share the same charged prefix and work budget.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.globl prep_retire_handlers, prep_retire_modes
.p2align 3
prep_retire_handlers: .zero RD_CUSTOM_COUNT * 8
prep_retire_modes: .zero RD_CUSTOM_COUNT * 8
.text
FN ext_prepare_retire_register_kind
    lea rax, [rdi - RD_CUSTOM_FIRST]
    cmp rax, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrc_bad
    test rsi, rsi
    jz .Lrc_bad
    cmp rdx, 1
    ja .Lrc_bad
    lea r8, [rip + prep_retire_handlers]
    lea r9, [rip + prep_retire_modes]
    cmp qword ptr [r8 + rdi*8], 0
    je 1f
    cmp [r8 + rdi*8], rsi
    jne 2f
    cmp [r9 + rdi*8], rdx
    jne 2f
    xor eax, eax
    ret
1:  mov [r8 + rdi*8], rsi
    mov [r9 + rdi*8], rdx
    xor eax, eax
    ret
2:  mov rax, -17
    ret
.Lrc_bad:
    mov rax, -22
    ret

FN ext_prepare_retire_alloc_custom
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Lrca_bad
    cmp rbx, PREP_CAP
    ja .Lrca_resource
    lea rax, [r12 - RD_CUSTOM_FIRST]
    cmp rax, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrca_bad
    lea rax, [rip + prep_retire_handlers]
    cmp qword ptr [rax + r12*8], 0
    je .Lrca_bad
    lea rax, [rip + prep_retire_modes]
    cmp qword ptr [rax + r12*8], 0
    jne .Lrca_bad
    lea rdi, [rbx + RD_SIZE]
    cmp rdi, rbx
    jb .Lrca_resource
    call prep_alloc_charge
    test rax, rax
    jz .Lrca_resource
    mov r13, rax
    mov rdi, rax
    call prep_global_admit
    test rax, rax
    js .Lrca_resource
    lea rdi, [rbx + RD_SIZE]
    call mem_alloc_try
    test rax, rax
    jz .Lrca_oom
    lea rdx, [rax + RD_SIZE]
    mov [rax + RD_object], rdx
    mov [rax + RD_kind], r12
    add [rip + prep_total_charge], r13
    mov rax, rdx
    xor edx, edx
    EPILOGUE
.Lrca_bad:
    mov rdx, -22
    jmp .Lrca_failed
.Lrca_resource:
    mov rdx, -EV_RESOURCE
    jmp .Lrca_failed
.Lrca_oom:
    mov rdx, -12
.Lrca_failed:
    xor eax, eax
    EPILOGUE

FN ext_prepare_retire_mark_custom_po
    test rdi, rdi
    jz .Lrc_bad
    lea rax, [rsi - RD_CUSTOM_FIRST]
    cmp rax, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrc_bad
    lea r8, [rdi - RD_PO_BACK]
    mov rax, [r8 + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lrc_bad
    test eax, RDF_PO
    jz .Lrc_bad
    cmp qword ptr [r8 + RD_kind], RD_LEDGER
    jne .Lrc_bad
    cmp qword ptr [rdi + PO_refs], 0
    je .Lrc_bad
    lea rax, [rip + prep_retire_handlers]
    cmp qword ptr [rax + rsi*8], 0
    je .Lrc_bad
    lea rax, [rip + prep_retire_modes]
    cmp qword ptr [rax + rsi*8], 1
    jne .Lrc_bad
    mov [r8 + RD_kind], rsi
    xor eax, eax
    ret

FN ext_prepare_retire_enqueue_custom
    test rdi, rdi
    jz .Lrc_bad
    mov rax, [rdi + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lrc_bad
    mov r8, [rdi + RD_kind]
    lea rcx, [r8 - RD_CUSTOM_FIRST]
    cmp rcx, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrc_bad
    lea rcx, [rip + prep_retire_handlers]
    cmp qword ptr [rcx + r8*8], 0
    je .Lrc_bad
    lea rcx, [rip + prep_retire_modes]
    mov r9, [rdi + RD_object]
    test r9, r9
    jz .Lrc_bad
    test eax, RDF_PO
    jz 1f
    cmp qword ptr [rcx + r8*8], 1
    jne .Lrc_bad
    cmp qword ptr [r9 + PO_refs], 0
    jne .Lrc_bad
    mov qword ptr [r9 + PO_ready], 0
    jmp 2f
1:  cmp qword ptr [rcx + r8*8], 0
    jne .Lrc_bad
2:  PROLOGUE
    call prep_retire_enqueue_ready
    xor eax, eax
    EPILOGUE

FN ext_prepare_retire_free_custom
    test rdi, rdi
    jz .Lrcf_bad
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi - RD_SIZE]
    cmp [r12 + RD_object], rdi
    jne .Lrcf_invalid
    mov rax, [r12 + RD_state]
    test eax, RDF_PO
    jnz .Lrcf_invalid
    and eax, RDF_STATE_MASK
    cmp eax, RD_RUNNING
    jne .Lrcf_invalid
    mov rax, [r12 + RD_kind]
    lea rcx, [rax - RD_CUSTOM_FIRST]
    cmp rcx, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrcf_invalid
    lea rcx, [rip + prep_retire_modes]
    cmp qword ptr [rcx + rax*8], 0
    jne .Lrcf_invalid
    lea rcx, [rip + prep_retire_handlers]
    cmp qword ptr [rcx + rax*8], 0
    je .Lrcf_invalid
    mov rdi, r12
    call prep_pointer_charge
    mov r13, rax
    mov rdi, r12
    call prep_cleanup_free
    test rax, rax
    js 1f
    sub [rip + prep_total_charge], r13
1:  EPILOGUE
.Lrcf_invalid:
    mov rax, -22
    xor edx, edx
    EPILOGUE
.Lrcf_bad:
    mov rax, -22
    xor edx, edx
    ret

FN ext_prepare_retire_handoff_ledger
    test rdi, rdi
    jz .Lrc_bad
    mov rax, [rdi + RD_state]
    test eax, RDF_PO
    jz .Lrc_bad
    test eax, RDF_NATIVE_MASK
    jnz .Lrc_bad
    and eax, RDF_STATE_MASK
    cmp eax, RD_RUNNING
    jne .Lrc_bad
    mov rax, [rdi + RD_kind]
    lea rcx, [rax - RD_CUSTOM_FIRST]
    cmp rcx, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrc_bad
    lea rcx, [rip + prep_retire_modes]
    cmp qword ptr [rcx + rax*8], 1
    jne .Lrc_bad
    mov qword ptr [rdi + RD_kind], RD_LEDGER
    mov qword ptr [rdi + RD_phase], 0
    mov qword ptr [rdi + RD_index], 0
    xor eax, eax
    ret

FN prep_retire_dispatch_custom
    PROLOGUE
    mov rbx, rdi
    mov rax, [rdi + RD_kind]
    lea rcx, [rax - RD_CUSTOM_FIRST]
    cmp rcx, RD_CUSTOM_LAST - RD_CUSTOM_FIRST
    ja .Lrcd_bad
    lea rcx, [rip + prep_retire_handlers]
    mov r12, [rcx + rax*8]
    test r12, r12
    jz .Lrcd_bad
    lea rcx, [rip + prep_retire_modes]
    mov rdx, [rcx + rax*8]
    mov rax, [rbx + RD_state]
    shr rax, 8
    and eax, 1
    cmp rax, rdx
    jne .Lrcd_bad
    mov rdi, [rbx + RD_object]
    mov rsi, rbx
    call r12
    test rax, rax
    jz .Lrcd_done          # Record may already be unmapped.
    js 1f
    cmp rax, 1
    jne .Lrcd_bad
    mov rcx, [rbx + RD_state]
    and ecx, RDF_STATE_MASK
    cmp ecx, RD_RUNNING
    jne .Lrcd_bad
    jmp .Lrcd_done
1:  test rdx, rdx
    jz .Lrcd_done
    cmp rdx, 2
    je .Lrcd_done
    mov edx, 2
.Lrcd_done:
    EPILOGUE
.Lrcd_bad:
    mov rax, -EV_BAD_PREPARE
    mov edx, 2
    EPILOGUE
