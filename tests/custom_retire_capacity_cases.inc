.bss
.p2align 3
rtcap_stage: .quad 0
rtcap_arrays: .zero RD_CUSTOM_COUNT * 16
rtcap_fake: .zero RD_SIZE + 32
rtcap_report: .zero 32
rtcap_live: .quad 0
rtcap_charge: .quad 0
rtcap_object: .quad 0
rtcap_owner: .quad 0
rtcap_child: .quad 0
rtcap_map: .quad 0
rtcap_header: .quad 0
rtcap_fault: .quad 0
rtcap_calls: .quad 0
rtcap_callback_calls: .quad 0
rtcap_drop_fault: .quad 0
.globl rtcap_alloc_fault
rtcap_alloc_fault: .quad 0
.text
rtcap_fail:
    mov rdi, [rip + rtcap_stage]
    add rdi, 40
    call sys_exit
    ud2
FN rtcap_native_unmap
    cmp rdi, [rip + rtcap_map]
    jne 1f
    inc qword ptr [rip + rtcap_calls]
    cmp qword ptr [rip + rtcap_fault], 0
    je 1f
    mov rax, -5
    ret
1:  SYS SYS_munmap
    ret
rtcap_trap:
    jmp rtcap_fail
rtcap_simple_step:
    inc qword ptr [rip + rtcap_callback_calls]
    cmp qword ptr [rdi + 8], 0x12345678
    jne rtcap_fail
    jmp ext_prepare_retire_free_custom
rtcap_po_step:
    PROLOGUE
    inc qword ptr [rip + rtcap_callback_calls]
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + PO_SIZE]
    test rdi, rdi
    jz 1f
    cmp qword ptr [rip + rtcap_drop_fault], 0
    jne 2f
    call grammar_prepare_release_deferred
    cmp rdx, 1
    jne 2f
    mov qword ptr [rbx + PO_SIZE], 0
    mov eax, 1
    EPILOGUE
1:  mov rdi, r12
    call ext_prepare_retire_handoff_ledger
    test rax, rax
    jnz rtcap_fail
    mov eax, 1
    EPILOGUE
2:  mov rax, -5
    xor edx, edx
    EPILOGUE
rtcap_snapshot:
    PROLOGUE
    lea rdi, [rip + rtcap_arrays]
    lea rsi, [rip + prep_retire_handlers]
    mov edx, RD_CUSTOM_COUNT * 16
    call memcpy
    EPILOGUE
rtcap_compare:
    PROLOGUE
    lea rdi, [rip + rtcap_arrays]
    lea rsi, [rip + prep_retire_handlers]
    mov edx, RD_CUSTOM_COUNT * 16
    call memeq
    test eax, eax
    jz rtcap_fail
    EPILOGUE
rtcap_step:
    PROLOGUE
    mov r12, [rip + rtcap_callback_calls]
    mov edi, 1
    lea rsi, [rip + rtcap_report]
    call ext_prepare_retire_step
    test rax, rax
    js rtcap_fail
    cmp qword ptr [rip + rtcap_report], 1
    ja rtcap_fail
    mov rcx, [rip + rtcap_callback_calls]
    sub rcx, r12
    cmp rcx, 1
    ja rtcap_fail
    EPILOGUE
rtcap_drain:
    PROLOGUE
    mov r15d, 200000
1:  call rtcap_step
    cmp qword ptr [rip + rtcap_report + 16], 0
    jne rtcap_fail
    test rax, rax
    jz 2f
    dec r15
    jnz 1b
    jmp rtcap_fail
2:  EPILOGUE
rtcap_bad_budgets:
    PROLOGUE
    mov r12, [rip + rtcap_callback_calls]
    mov r13, [rip + prep_retire_ready_count]
    mov r14, [rip + prep_retire_blocked_count]
    lea rdi, [rip + rtcap_report]
    mov esi, 0xa5
    mov edx, 32
    call memset
    xor edi, edi
    lea rsi, [rip + rtcap_report]
    call ext_prepare_retire_step
    cmp rax, -22
    jne rtcap_fail
    mov edi, 65
    lea rsi, [rip + rtcap_report]
    call ext_prepare_retire_step
    cmp rax, -22
    jne rtcap_fail
    mov edi, 1
    xor esi, esi
    call ext_prepare_retire_step
    cmp rax, -22
    jne rtcap_fail
    cmp [rip + rtcap_callback_calls], r12
    jne rtcap_fail
    cmp [rip + prep_retire_ready_count], r13
    jne rtcap_fail
    cmp [rip + prep_retire_blocked_count], r14
    jne rtcap_fail
    lea rdi, [rip + rtcap_report]
    xor ecx, ecx
1:  cmp byte ptr [rdi + rcx], 0xa5
    jne rtcap_fail
    inc rcx
    cmp rcx, 32
    jb 1b
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + rtcap_stage], 10
    # Run the unchanged original kinds6/7 ownership test first.
    call rtcap_original_main
    test rax, rax
    jnz rtcap_fail
    mov rax, [rip + g_mem_live]
    mov [rip + rtcap_live], rax
    call ext_prepare_retire_charge
    mov [rip + rtcap_charge], rax
    mov edi, 8
.if RTCAP_MODE
    lea rsi, [rip + rtcap_po_step]
.else
    lea rsi, [rip + rtcap_simple_step]
.endif
    mov edx, RTCAP_MODE
    call ext_prepare_retire_register_kind
    test rax, rax
    jnz rtcap_fail
    mov edi, 8
.if RTCAP_MODE
    lea rsi, [rip + rtcap_po_step]
.else
    lea rsi, [rip + rtcap_simple_step]
.endif
    mov edx, RTCAP_MODE
    call ext_prepare_retire_register_kind
    test rax, rax
    jnz rtcap_fail
    call rtcap_snapshot
    mov edi, 8
    lea rsi, [rip + rtcap_trap]
    mov edx, RTCAP_MODE
    call ext_prepare_retire_register_kind
    cmp rax, -17
    jne rtcap_fail
    call rtcap_compare
    mov edi, 8
.if RTCAP_MODE
    lea rsi, [rip + rtcap_po_step]
.else
    lea rsi, [rip + rtcap_simple_step]
.endif
    mov edx, 1 - RTCAP_MODE
    call ext_prepare_retire_register_kind
    cmp rax, -17
    jne rtcap_fail
    call rtcap_compare
    mov edi, 8
    xor esi, esi
    xor edx, edx
    call ext_prepare_retire_register_kind
    cmp rax, -22
    jne rtcap_fail
    call rtcap_compare
    mov edi, 8
    lea rsi, [rip + rtcap_trap]
    mov edx, 2
    call ext_prepare_retire_register_kind
    cmp rax, -22
    jne rtcap_fail
    call rtcap_compare
    # mode[0] occupies handler[9]'s physical location. Invalid9 must not follow it.
    mov qword ptr [rip + rtcap_stage], 11
    lea rax, [rip + rtcap_trap]
    mov [rip + prep_retire_modes], rax
    lea rax, [rip + rtcap_modes_end]
    lea rcx, [rip + prep_retire_modes + RD_CUSTOM_COUNT * 8]
    cmp rax, rcx
    jne rtcap_fail
    mov qword ptr [rax], 0
    call rtcap_snapshot
    xor r13d, r13d
.Lrtcap_invalid:
    lea rax, [rip + rtcap_bad_kinds]
    mov rdi, [rax + r13*8]
    lea rsi, [rip + rtcap_trap]
    xor edx, edx
    call ext_prepare_retire_register_kind
    cmp rax, -22
    jne rtcap_fail
    call rtcap_compare
    lea rax, [rip + rtcap_bad_kinds]
    mov rsi, [rax + r13*8]
    mov edi, 100000
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jnz rtcap_fail
    cmp rdx, -22
    jne rtcap_fail
    call rtcap_compare
    inc r13
    cmp r13, 4
    jb .Lrtcap_invalid
    lea rdi, [rip + rtcap_fake]
    lea rax, [rdi + RD_SIZE]
    mov [rdi + RD_object], rax
    mov qword ptr [rdi + RD_kind], 9
    mov qword ptr [rdi + RD_state], RD_RUNNING
    call prep_retire_dispatch_custom
    cmp rax, -EV_BAD_PREPARE
    jne rtcap_fail
    cmp rdx, 2
    jne rtcap_fail
    lea rdi, [rip + rtcap_fake]
    xor esi, esi
    call prep_retire_one
    cmp rax, -EV_BAD_PREPARE
    jne rtcap_fail
    cmp rdx, 2
    jne rtcap_fail
    lea rdi, [rip + rtcap_fake]
    mov qword ptr [rdi + RD_state], RD_ACTIVE
    call ext_prepare_retire_enqueue_custom
    cmp rax, -22
    jne rtcap_fail
    call rtcap_compare
    mov qword ptr [rip + prep_retire_modes], 0
    # A real ledger PO refuses invalid/wrong-mode mark before any prefix mutation.
    mov qword ptr [rip + rtcap_stage], 12
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz rtcap_fail
    mov [rip + rtcap_owner], rax
    mov rdi, rax
    call ext_prepare_owner_enable_deferred
    test rax, rax
    jnz rtcap_fail
    mov rdi, [rip + rtcap_owner]
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz rtcap_fail
    mov [rip + rtcap_child], rax
    mov rdi, [rip + rtcap_owner]
    mov esi, 100000
    call prep_object_create
    test rax, rax
    jz rtcap_fail
    mov [rip + rtcap_object], rax
    mov rbx, rax
    mov rdi, rax
    mov esi, 9
    call ext_prepare_retire_mark_custom_po
    cmp rax, -22
    jne rtcap_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    jne rtcap_fail
    mov rdi, rbx
    mov esi, 8
    call ext_prepare_retire_mark_custom_po
.if RTCAP_MODE
    test rax, rax
    jnz rtcap_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], 8
    jne rtcap_fail
    mov rax, [rip + rtcap_child]
    mov [rbx + PO_SIZE], rax
    mov qword ptr [rbx + PO_ready], 1
    mov rdi, rbx
    call prep_object_retain
    test rax, rax
    jnz rtcap_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne rtcap_fail
    mov rdi, rbx
    call ext_prepare_retire_release_custom_po
    test rax, rax
    jnz rtcap_fail
    cmp rdx, 1
    jne rtcap_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne rtcap_fail
    mov qword ptr [rbx - RD_PO_BACK + RD_kind], 9
    mov rdi, rbx
    call ext_prepare_retire_release_custom_po
    cmp rax, -EV_BAD_PREPARE
    jne rtcap_fail
    test rdx, rdx
    jnz rtcap_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne rtcap_fail
    mov qword ptr [rbx - RD_PO_BACK + RD_kind], 8
    mov edi, 100000
    mov esi, 8
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jnz rtcap_fail
    cmp rdx, -22
    jne rtcap_fail
    mov rdi, [rip + rtcap_owner]
    call ext_prepare_owner_release_deferred
    cmp rdx, 1
    jne rtcap_fail
    mov rbx, [rip + rtcap_object]
    lea rax, [rbx - RD_PO_BACK - 16]
.else
    cmp rax, -22
    jne rtcap_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    jne rtcap_fail
    mov rdi, rbx
    call grammar_prepare_release_deferred
    cmp rdx, 1
    jne rtcap_fail
    mov rdi, [rip + rtcap_child]
    call grammar_prepare_release_deferred
    cmp rdx, 1
    jne rtcap_fail
    mov rdi, [rip + rtcap_owner]
    call ext_prepare_owner_release_deferred
    cmp rdx, 1
    jne rtcap_fail
    call rtcap_drain
    mov r13, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov r14, rax
    mov qword ptr [rip + rtcap_alloc_fault], 1
    mov edi, 100000
    mov esi, 8
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jnz rtcap_fail
    cmp rdx, -12
    jne rtcap_fail
    cmp [rip + g_mem_live], r13
    jne rtcap_fail
    call ext_prepare_retire_charge
    cmp rax, r14
    jne rtcap_fail
    mov qword ptr [rip + rtcap_alloc_fault], 0
    mov edi, 100000
    mov esi, 8
    call ext_prepare_retire_alloc_custom
    test rax, rax
    jz rtcap_fail
    test rdx, rdx
    jnz rtcap_fail
    mov [rip + rtcap_object], rax
    mov rbx, rax
    mov qword ptr [rbx + 8], 0x12345678
    lea rax, [rbx - RD_SIZE - 16]
.endif
    mov [rip + rtcap_map], rax
    mov rcx, [rax]
    mov [rip + rtcap_header], rcx
    cmp rcx, 65536
    jbe rtcap_fail
    mov qword ptr [rip + rtcap_fault], 1
    mov qword ptr [rip + rtcap_stage], 13
.if RTCAP_MODE
    mov qword ptr [rip + rtcap_drop_fault], 1
    mov rdi, rbx
    call ext_prepare_retire_release_custom_po
    test rax, rax
    jnz rtcap_fail
    cmp rdx, 1
    jne rtcap_fail
    call rtcap_bad_budgets
    call rtcap_step
    cmp qword ptr [rip + rtcap_callback_calls], 1
    jne rtcap_fail
    mov rbx, [rip + rtcap_object]
    mov rax, [rip + rtcap_child]
    cmp [rbx + PO_SIZE], rax
    jne rtcap_fail
    cmp qword ptr [rax + PO_refs], 1
    jne rtcap_fail
    mov r14d, 100
1:  call rtcap_step
    cmp qword ptr [rip + rtcap_callback_calls], 1
    jne rtcap_fail
    dec r14
    jnz 1b
    mov qword ptr [rip + rtcap_drop_fault], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne rtcap_fail
    cmp rdx, 1
    jne rtcap_fail
.else
    lea rdi, [rbx - RD_SIZE]
    call ext_prepare_retire_enqueue_custom
    test rax, rax
    jnz rtcap_fail
    call rtcap_bad_budgets
.endif
    mov qword ptr [rip + rtcap_stage], 14
    mov r15d, 200000
2:  mov r13, [rip + g_mem_live]
    call ext_prepare_retire_charge
    mov r14, rax
    call rtcap_step
    cmp qword ptr [rip + rtcap_calls], 0
    jne 3f
    dec r15
    jnz 2b
    jmp rtcap_fail
3:  cmp qword ptr [rip + rtcap_calls], 1
    jne rtcap_fail
    cmp [rip + g_mem_live], r13
    jne rtcap_fail
    call ext_prepare_retire_charge
    cmp rax, r14
    jne rtcap_fail
    mov rax, [rip + rtcap_map]
    mov rcx, [rip + rtcap_header]
    cmp [rax], rcx
    jne rtcap_fail
    mov r15d, 100
4:  call rtcap_step
    cmp qword ptr [rip + rtcap_calls], 1
    jne rtcap_fail
    dec r15
    jnz 4b
    mov qword ptr [rip + rtcap_fault], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne rtcap_fail
    cmp rdx, 1
    jne rtcap_fail
    call rtcap_drain
    cmp qword ptr [rip + rtcap_calls], 2
    jne rtcap_fail
    call ext_prepare_retire_charge
    cmp rax, [rip + rtcap_charge]
    jne rtcap_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + rtcap_live]
    jne rtcap_fail
    call ext_prepare_retire_ack
    test rax, rax
    jnz rtcap_fail
    lea rdi, [rip + rtcap_ok]
    call strlen
    mov rdx, rax
    lea rsi, [rip + rtcap_ok]
    mov edi, 1
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
rtcap_bad_kinds: .quad 0, 3, 9, -1
.if RTCAP_MODE
rtcap_ok: .asciz "ok custom kind8 po ownership and native retry\n"
.else
rtcap_ok: .asciz "ok custom kind8 simple ownership and native retry\n"
.endif
