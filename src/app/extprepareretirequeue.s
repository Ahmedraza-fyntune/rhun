# Allocation-free final-reference transfer and bounded retirement scheduling.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.globl prep_retire_ready_head, prep_retire_ready_tail, prep_retire_ready_count
.globl prep_retire_blocked_head, prep_retire_blocked_tail, prep_retire_blocked_count
.globl prep_retire_first_diagnostic
.p2align 3
prep_retire_ready_head: .quad 0
prep_retire_ready_tail: .quad 0
prep_retire_ready_count: .quad 0
prep_retire_blocked_head: .quad 0
prep_retire_blocked_tail: .quad 0
prep_retire_blocked_count: .quad 0
prep_retire_first_diagnostic: .quad 0
.text
FN prep_retire_set_state
    and qword ptr [rdi + RD_state], -256
    or [rdi + RD_state], rsi
    ret

FN ext_prepare_retire_note_error
    test rsi, rsi
    jns 9f
    cmp qword ptr [rdi + RD_diagnostic], 0
    jne 1f
    mov [rdi + RD_diagnostic], rsi
1:  cmp qword ptr [rip + prep_retire_first_diagnostic], 0
    jne 2f
    mov [rip + prep_retire_first_diagnostic], rsi
2:  test qword ptr [rdi + RD_state], RDF_PO
    jz 9f
    mov rax, [rdi + RD_object]
    mov rax, [rax + PO_eo]
    cmp qword ptr [rax - RD_SIZE + RD_diagnostic], 0
    jne 9f
    mov [rax - RD_SIZE + RD_diagnostic], rsi
9:  ret

FN prep_retire_init_diagnostic
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rdi + RD_kind], RD_EP
    jne 1f
    mov rax, [rdi + RD_object]
    mov rsi, [rax + EP_cleanup]
    call ext_prepare_retire_note_error
1:  test qword ptr [rbx + RD_state], RDF_PO
    jz 2f
    mov rax, [rbx + RD_object]
    mov rax, [rax + PO_eo]
    mov rsi, [rax - RD_SIZE + RD_diagnostic]
    mov rdi, rbx
    call ext_prepare_retire_note_error
2:  EPILOGUE

FN prep_retire_enqueue_ready
    mov qword ptr [rdi + RD_next], 0
    and qword ptr [rdi + RD_state], -256
    or qword ptr [rdi + RD_state], RD_READY
    mov rax, [rip + prep_retire_ready_tail]
    test rax, rax
    jz 1f
    mov [rax + RD_next], rdi
    jmp 2f
1:  mov [rip + prep_retire_ready_head], rdi
2:  mov [rip + prep_retire_ready_tail], rdi
    inc qword ptr [rip + prep_retire_ready_count]
    ret

# Record remains live. RDX0 known-unconsumed or2 unknown.
FN prep_retire_enqueue_blocked
    PROLOGUE
    call ext_prepare_retire_note_error
    mov qword ptr [rdi + RD_next], 0
    and qword ptr [rdi + RD_state], -256
    mov eax, RD_BLOCKED_KNOWN
    cmp edx, 2
    jne 1f
    mov eax, RD_BLOCKED_UNKNOWN
1:  or [rdi + RD_state], rax
    mov rax, [rip + prep_retire_blocked_tail]
    test rax, rax
    jz 2f
    mov [rax + RD_next], rdi
    jmp 3f
2:  mov [rip + prep_retire_blocked_head], rdi
3:  mov [rip + prep_retire_blocked_tail], rdi
    inc qword ptr [rip + prep_retire_blocked_count]
    EPILOGUE

FN ext_prepare_release_deferred
    mov esi, RD_EP
    xor edx, edx
    jmp prep_retire_drop_po
FN prep_object_release_deferred
FN grammar_prepare_release_deferred
    mov esi, RD_LEDGER
    xor edx, edx
    jmp prep_retire_drop_po
FN ext_prepare_retire_release_custom_po
    xor esi, esi
    xor edx, edx
    jmp prep_retire_drop_po

# Synchronous helper entry, except an explicitly deferred preparation owner.
FN prep_retire_po_release_sync
    test rdi, rdi
    jz .Lrd_bad
    mov rax, [rdi + PO_eo]
    mov edx, 1
    cmp qword ptr [rax + EO_deferred], 0
    je prep_retire_drop_po
    xor edx, edx
prep_retire_drop_po:
    test rdi, rdi
    jz .Lrd_bad
    lea r8, [rdi - RD_PO_BACK]
    mov rax, [r8 + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lrd_bad
    test eax, RDF_PO
    jz .Lrd_bad
    cmp qword ptr [rdi + PO_refs], 0
    je .Lrd_bad
    test rsi, rsi
    jz 1f
    cmp [r8 + RD_kind], rsi
    jne .Lrd_bad
    jmp 2f
1:  cmp qword ptr [r8 + RD_kind], RD_CUSTOM_FIRST
    jb .Lrd_bad
    cmp qword ptr [r8 + RD_kind], RD_CUSTOM_LAST
    ja .Lrd_bad
    mov rax, [r8 + RD_kind]
    lea rcx, [rip + prep_retire_handlers]
    cmp qword ptr [rcx + rax*8], 0
    je .Lrd_bad
    lea rcx, [rip + prep_retire_modes]
    cmp qword ptr [rcx + rax*8], 1
    jne .Lrd_bad
2:  dec qword ptr [rdi + PO_refs]
    jnz .Lrd_consumed
    mov qword ptr [rdi + PO_ready], 0
    mov rdi, r8
    jmp prep_retire_finish_drop
.Lrd_consumed:
    xor eax, eax
    mov edx, 1
    ret
.Lrd_bad:
    mov rax, -EV_BAD_PREPARE
    xor edx, edx
    ret

FN ext_prepare_owner_release_deferred
    xor edx, edx
    jmp prep_retire_drop_eo
FN prep_retire_owner_release_sync
    test rdi, rdi
    jz .Lrd_bad
    mov edx, 1
    cmp qword ptr [rdi + EO_deferred], 0
    je prep_retire_drop_eo
    xor edx, edx
prep_retire_drop_eo:
    test rdi, rdi
    jz .Lrd_bad
    lea r8, [rdi - RD_SIZE]
    mov rax, [r8 + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lrd_bad
    cmp qword ptr [r8 + RD_kind], RD_EO
    jne .Lrd_bad
    cmp qword ptr [rdi + EO_refs], 0
    je .Lrd_bad
    dec qword ptr [rdi + EO_refs]
    jnz .Lrd_consumed
    mov rdi, r8
prep_retire_finish_drop:
    PROLOGUE
    mov rbx, rdi
    mov r12, rdx
    call prep_retire_init_diagnostic
    test r12, r12
    jnz 1f
    mov rdi, rbx
    call prep_retire_enqueue_ready
    xor eax, eax
    mov edx, 1
    EPILOGUE
1:  mov rdi, rbx
    call prep_retire_run_sync
    mov edx, 1
    EPILOGUE

# Private sole-object disposal also accepts1 from a failed parse before publication.
FN prep_retire_dispose
    test rdi, rdi
    jz .Lrd_bad
    lea r8, [rdi - RD_PO_BACK]
    mov rax, [r8 + RD_state]
    test eax, RDF_STATE_MASK
    jnz .Lrd_bad
    test eax, RDF_PO
    jz .Lrd_bad
    cmp qword ptr [rdi + PO_refs], 1
    ja .Lrd_bad
    mov qword ptr [rdi + PO_refs], 0
    mov qword ptr [rdi + PO_ready], 0
    mov rax, [rdi + PO_eo]
    mov edx, 1
    cmp qword ptr [rax + EO_deferred], 0
    je 1f
    xor edx, edx
1:  mov rdi, r8
    jmp prep_retire_finish_drop

FN ext_prepare_owner_enable_deferred
    test rdi, rdi
    jz .Lrd_bad
    cmp qword ptr [rdi + EO_refs], 0
    je .Lrd_bad
    test qword ptr [rdi - RD_SIZE + RD_state], RDF_STATE_MASK
    jnz .Lrd_bad
    mov qword ptr [rdi + EO_deferred], 1
    xor eax, eax
    ret
FN ext_prepare_enable_deferred
    test rdi, rdi
    jz .Lrd_bad
    test qword ptr [rdi - RD_PO_BACK + RD_state], RDF_STATE_MASK
    jnz .Lrd_bad
    cmp qword ptr [rdi + PO_refs], 0
    je .Lrd_bad
    mov rdi, [rdi + PO_eo]
    jmp ext_prepare_owner_enable_deferred

# Off-editor exact cleanup only. Never drains another owner's queue.
FN prep_retire_run_sync
    PROLOGUE
    mov rbx, rdi
    mov r12, [rdi + RD_diagnostic]
    mov esi, RD_RUNNING
    call prep_retire_set_state
1:  mov rdi, rbx
    mov esi, 1
    call prep_retire_one
    test r12, r12
    jnz 2f
    mov r12, rcx
2:  test rax, rax
    jz 4f
    jns 1b
    mov r13, rax
    test r12, r12
    jnz 3f
    mov r12, rax
3:  mov rdi, rbx
    mov rsi, r13
    call prep_retire_enqueue_blocked
4:  mov rax, r12
    EPILOGUE

FN ext_prepare_retire_status
    test rdi, rdi
    jz .Lret_invalid
    mov qword ptr [rdi], 0
    mov rax, [rip + prep_retire_ready_count]
    mov [rdi + 8], rax
    mov rax, [rip + prep_retire_blocked_count]
    mov [rdi + 16], rax
    mov rax, [rip + prep_retire_first_diagnostic]
    mov [rdi + 24], rax
    xor eax, eax
    ret
.Lret_invalid:
    mov rax, -22
    ret

FN ext_prepare_retire_ack
    cmp qword ptr [rip + prep_retire_blocked_count], 0
    jne 1f
    mov qword ptr [rip + prep_retire_first_diagnostic], 0
    xor eax, eax
    ret
1:  mov rax, -16
    ret

FN ext_prepare_retire_step
    test rsi, rsi
    jz .Lret_invalid
    lea rax, [rdi - 1]
    cmp rax, 63
    ja .Lret_invalid
    PROLOGUE
    mov rbx, rsi
    mov r12, rdi
    xor r13d, r13d
1:  cmp r13, r12
    jae 4f
    mov r14, [rip + prep_retire_ready_head]
    test r14, r14
    jz 4f
    mov rax, [r14 + RD_next]
    mov [rip + prep_retire_ready_head], rax
    test rax, rax
    jnz 2f
    mov qword ptr [rip + prep_retire_ready_tail], 0
2:  dec qword ptr [rip + prep_retire_ready_count]
    mov qword ptr [r14 + RD_next], 0
    mov rdi, r14
    mov esi, RD_RUNNING
    call prep_retire_set_state
    mov rdi, r14
    xor esi, esi
    call prep_retire_one
    test rax, rax
    jz 3f
    mov rdi, r14
    js .Lret_step_block
    call prep_retire_enqueue_ready
    jmp 3f
.Lret_step_block:
    mov rsi, rax
    call prep_retire_enqueue_blocked
3:  inc r13
    jmp 1b
4:  mov rdi, rbx
    call ext_prepare_retire_status
    mov [rbx], r13
    mov rax, [rbx + 8]
    or rax, [rbx + 16]
    setnz al
    movzx eax, al
    EPILOGUE

FN ext_prepare_retire_retry_known
    lea rax, [rdi - 1]
    cmp rax, 63
    ja .Lret_invalid
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
    xor r13d, r13d
1:  cmp r13, rbx
    jae 5f
    mov r14, [rip + prep_retire_blocked_head]
    test r14, r14
    jz 5f
    mov rax, [r14 + RD_next]
    mov [rip + prep_retire_blocked_head], rax
    test rax, rax
    jnz 2f
    mov qword ptr [rip + prep_retire_blocked_tail], 0
2:  dec qword ptr [rip + prep_retire_blocked_count]
    mov rax, [r14 + RD_state]
    and eax, RDF_STATE_MASK
    cmp eax, RD_BLOCKED_KNOWN
    jne 3f
    and qword ptr [r14 + RD_state], ~RDF_KNOWN_MASK
    mov rdi, r14
    call prep_retire_enqueue_ready
    inc r12
    jmp 4f
3:  mov rdi, r14
    mov rsi, [r14 + RD_diagnostic]
    mov edx, 2
    call prep_retire_enqueue_blocked
4:  inc r13
    jmp 1b
5:  mov rax, r12
    mov rdx, r13
    EPILOGUE
