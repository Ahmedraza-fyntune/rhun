.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extdiscoveryalloc.inc"
.bss
.p2align 3
da_context: .skip DIA_SIZE
da_status: .skip 64
da_view: .skip 32
da_dest: .quad 0
da_gp: .quad 0
da_baseline: .quad 0
da_mode: .quad 0
da_raw: .quad 0
da_snapshot: .skip 40
.globl da_fail_unmap, da_unmap_calls, da_fail_map, da_map_calls
da_fail_unmap: .quad 0
da_unmap_calls: .quad 0
da_fail_map: .quad 0
da_map_calls: .quad 0
.globl da_fail_alloc
da_fail_alloc: .quad 0
da_action_calls: .quad 0
.section .rodata
da_data: .ascii "123456789\0"
.text
FN prep_cleanup_free
    inc qword ptr [rip + da_action_calls]
    jmp da_cleanup_free_real
FN ext_prepare_release_deferred
    inc qword ptr [rip + da_action_calls]
    jmp da_release_ep_real
FN grammar_prepare_release_deferred
    inc qword ptr [rip + da_action_calls]
    jmp da_release_gp_real
FN ext_prepare_owner_release_deferred
    inc qword ptr [rip + da_action_calls]
    jmp da_release_eo_real
FN mem_alloc_uninit_try
    cmp qword ptr [rip + da_fail_alloc], 0
    je da_alloc_real
    xor eax, eax
    ret
FN os_map_try
    inc qword ptr [rip + da_map_calls]
    cmp qword ptr [rip + da_fail_map], 0
    je da_map_real
    xor eax, eax
    ret
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 2
    jne .Lda_fail
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    cmp byte ptr [rax + 1], 0
    jne .Lda_fail
    movzx eax, byte ptr [rax]
    sub eax, '0'
    cmp eax, 9
    ja .Lda_fail
    mov [rip + da_mode], rax
    mov rax, [rip + g_mem_live]
    mov [rip + da_baseline], rax
    lea rdi, [rip + da_context]
    call pd_alloc_init
    test rax, rax
    jne .Lda_fail
    mov rax, [rip + da_mode]
    cmp eax, 8
    je .Lda_mixed
    cmp eax, 9
    je .Lda_kinds
    cmp eax, 1
    je .Lda_slots
    cmp eax, 2
    je .Lda_objects
    cmp eax, 3
    je .Lda_retained
    cmp eax, 4
    je .Lda_map_failure
    cmp eax, 5
    je .Lda_quarantine
    cmp eax, 6
    je .Lda_value
    cmp eax, 7
    je .Lda_large
    mov edi, 1
    call pd_extra_block_charge
    cmp rax, 32
    jne .Lda_fail
    mov edi, 65520
    call pd_extra_block_charge
    cmp rax, 65536
    jne .Lda_fail
    mov edi, 65521
    call pd_extra_block_charge
    cmp rax, 69632
    jne .Lda_fail
    mov edi, 64 * 1024 * 1024
    call pd_extra_block_charge
    cmp rax, 64 * 1024 * 1024 + 4096
    jne .Lda_fail
    mov edi, PD_EXTRA_CAP - 16
    call pd_extra_block_charge
    cmp rax, PD_EXTRA_CAP
    jne .Lda_fail
    mov edi, PD_EXTRA_CAP - 15
    call pd_extra_block_charge
    test rax, rax
    jne .Lda_fail
    mov qword ptr [rip + discovery_foreign_charge], PD_FOREIGN_CAP
    mov qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    mov edi, PD_EXTRA_CAP
    call pd_extra_admit
    test rax, rax
    jne .Lda_fail
    mov qword ptr [rip + discovery_extra_charge], 1
    mov edi, PD_EXTRA_CAP
    call pd_extra_admit
    test rax, rax
    jns .Lda_fail
    mov qword ptr [rip + discovery_foreign_charge], 0
    mov qword ptr [rip + prep_total_charge], 0
    mov qword ptr [rip + discovery_extra_charge], 0
    mov esi, PD_EXTRA
    mov edx, 33
    call da_begin
    mov r12, rax
    mov rdi, [rip + da_context + DIA_slots + DTS_raw]
    mov esi, 0xa5
    mov edx, 33
    call memset
    xor ebx, ebx
1:  lea rdi, [rip + da_context]
    mov rsi, r12
    mov edx, 1
    call pd_alloc_zero
    cmp rax, 1
    jne .Lda_fail
    inc rbx
    mov rax, [rip + da_context + DIA_slots + DTS_raw]
    cmp byte ptr [rax + rbx - 1], 0
    jne .Lda_fail
    cmp rbx, 33
    je 2f
    cmp byte ptr [rax + rbx], 0xa5
    jne .Lda_fail
    jmp 1b
2:  cmp qword ptr [rip + da_context + DIA_slots + DTS_state], DTS_INITIALIZED
    jne .Lda_fail
    mov qword ptr [rip + da_view], -1
    lea rdi, [rip + da_context]
    mov rsi, r12
    lea rdx, [rip + da_view]
    call pd_alloc_extra_take_check
    cmp rax, -22
    jne .Lda_fail
    cmp qword ptr [rip + da_view], -1
    jne .Lda_fail
    mov qword ptr [rip + da_view], 0
    lea rdi, [rip + da_context]
    mov rsi, r12
    lea rdx, [rip + da_view]
    call pd_alloc_extra_take_check
    test rax, rax
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov rsi, r12
    lea rdx, [rip + da_view]
    call pd_alloc_extra_take_VOID
    cmp qword ptr [rip + da_view + 8], 33
    jne .Lda_fail
    cmp qword ptr [rip + da_view + 16], 64
    jne .Lda_fail
    cmp qword ptr [rip + da_view + 24], PD_EXTRA
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_active], 0
    jne .Lda_fail
    cmp qword ptr [rip + discovery_extra_charge], 64
    jne .Lda_fail
    mov rdi, [rip + da_view]
    call prep_cleanup_free
    cmp rdx, 1
    jne .Lda_fail
    sub qword ptr [rip + discovery_extra_charge], 64
    mov qword ptr [rip + da_view], 0
    # MEMBER copy is refused until its AO prefix is initialized.
    mov esi, PD_MEMBER
    mov edx, 10
    call da_begin
    mov r12, rax
    lea rdi, [rip + da_context]
    mov rsi, r12
    lea rdx, [rip + da_data]
    mov ecx, 1
    call pd_alloc_copy
    cmp rax, -22
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov rsi, r12
    mov edx, AO_SIZE
    call pd_alloc_zero
    cmp rax, AO_SIZE
    jne .Lda_fail
    xor r13d, r13d
3:  lea rdi, [rip + da_context]
    mov rsi, r12
    lea rdx, [rip + da_data]
    add rdx, r13
    mov ecx, 1
    call pd_alloc_copy
    cmp rax, 1
    jne .Lda_fail
    inc r13
    cmp r13, 10
    jb 3b
    mov rax, [rip + da_context + DIA_slots + DTS_raw]
    xor ecx, ecx
    lea rdx, [rip + da_data]
4:  movzx esi, byte ptr [rdx + rcx]
    cmp [rax + rcx + AO_SIZE], sil
    jne .Lda_fail
    inc rcx
    cmp rcx, 10
    jb 4b
    jmp .Lda_cleanup
.Lda_slots:
    xor r12d, r12d
1:  mov esi, PD_EXTRA
    mov edx, 1
    call da_begin
    cmp rax, r12
    jne .Lda_fail
    inc r12
    cmp r12, 16
    jb 1b
    lea rdi, [rip + da_context]
    mov esi, PD_EXTRA
    mov edx, 1
    call pd_alloc_begin
    test rax, rax
    jns .Lda_fail
    cmp qword ptr [rip + da_context + DIA_active], 16
    jne .Lda_fail
    cmp qword ptr [rip + discovery_extra_charge], 512
    jne .Lda_fail
    jmp .Lda_cleanup
.Lda_objects:
    call da_make_ep
    call da_add_members
    mov rax, [rip + da_context + DIA_gp]
    mov [rip + da_gp], rax
    mov qword ptr [rax + PO_ready], 1
    mov rdi, rax
    call grammar_prepare_retain
    test rax, rax
    jne .Lda_fail
    mov rax, [rip + da_context + DIA_gp]
    mov qword ptr [rax + PO_ready], 1
    lea rdi, [rip + da_context]
    call pd_alloc_attach_gp
    test rax, rax
    jne .Lda_fail
    call da_take_ep
    mov rdi, [rip + da_dest]
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne .Lda_fail
    mov qword ptr [rip + da_dest], 0
    call da_drain_common
    mov rax, [rip + da_gp]
    cmp qword ptr [rax + PO_refs], 1
    jne .Lda_fail
    mov rcx, [rax + PO_eo]
    cmp qword ptr [rcx + EO_deferred], 1
    jne .Lda_fail
    cmp qword ptr [rip + prep_total_charge], 0
    je .Lda_fail
    # A second candidate binds new vectors, without reinitializing the context.
    call da_make_ep
    call da_add_members
    mov rax, [rip + da_context + DIA_gp]
    mov qword ptr [rax + PO_ready], 1
    lea rdi, [rip + da_context]
    call pd_alloc_attach_gp
    test rax, rax
    jne .Lda_fail
    call da_take_ep
    mov rdi, [rip + da_dest]
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne .Lda_fail
    mov qword ptr [rip + da_dest], 0
    call da_drain_common
    mov rdi, [rip + da_gp]
    call grammar_prepare_release_deferred
    cmp rdx, 1
    jne .Lda_fail
    mov qword ptr [rip + da_gp], 0
    call da_drain_common
    jmp .Lda_cleanup
.Lda_retained:
    mov esi, PD_EXTRA
    mov edx, 70000
    call da_begin
    mov r12, rax
    mov rax, [rip + da_context + DIA_slots + DTS_raw]
    mov [rip + da_raw], rax
    mov qword ptr [rip + da_fail_unmap], 1
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_retire_step
    cmp rax, 1
    jne .Lda_fail
    cmp rdx, -5
    jne .Lda_fail
    cmp rcx, 1
    jne .Lda_fail
    mov rax, [rip + da_raw]
    cmp [rip + da_context + DIA_slots + DTS_raw], rax
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_slots + DTS_due], 16
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_slots + DTS_logical], 16
    jne .Lda_fail
    cmp qword ptr [rip + discovery_extra_charge], 73728
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 15
    call pd_alloc_timeout
    cmp rax, 1
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 15
    call pd_alloc_retire_step
    cmp qword ptr [rip + da_unmap_calls], 1
    jne .Lda_fail
    mov qword ptr [rip + da_fail_unmap], 8
    mov r12d, 8
    mov r13d, 16
1:  mov r14, [rip + da_context + DIA_slots + DTS_due]
    lea rdi, [rip + da_context]
    mov rsi, r14
    call pd_alloc_retire_step
    cmp rax, 1
    jne .Lda_fail
    add r13, r13
    cmp r13, 1000
    jbe 2f
    mov r13d, 1000
2:  cmp [rip + da_context + DIA_slots + DTS_logical], r13
    jne .Lda_fail
    lea rdi, [rip + da_context]
    lea rsi, [rip + da_status]
    mov rdx, r14
    call pd_alloc_status
    test rax, rax
    jne .Lda_fail
    cmp qword ptr [rip + da_status + 56], 1
    jne .Lda_fail
    cmp [rip + da_status + 48], r13
    jne .Lda_fail
    mov rax, r14
    add rax, r13
    cmp [rip + da_status + 40], rax
    jne .Lda_fail
    dec r12
    jnz 1b
    lea rdi, [rip + da_context]
    mov rsi, [rip + da_context + DIA_slots + DTS_due]
    call pd_alloc_retire_step
    test rax, rax
    jne .Lda_fail
    cmp qword ptr [rip + da_unmap_calls], 10
    jne .Lda_fail
    jmp .Lda_pass
.Lda_map_failure:
    mov qword ptr [rip + da_fail_map], 1
    lea rdi, [rip + da_context]
    mov esi, PD_EXTRA
    mov edx, 70000
    call pd_alloc_begin
    cmp rax, -12
    jne .Lda_fail
    cmp qword ptr [rip + discovery_extra_charge], 0
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_active], 0
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_primary], -12
    jne .Lda_fail
    jmp .Lda_cleanup
.Lda_quarantine:
    call da_make_ep
    mov rax, [rip + da_context + DIA_ep]
    # Deliberate trusted native invalidity, no counterfeit scalar release stub.
    mov qword ptr [rax - RD_PO_BACK + RD_kind], RD_LEDGER
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_retire_step
    cmp rax, 1
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_blocked], 2
    jne .Lda_fail
    mov rax, [rip + da_context + DIA_ep]
    mov qword ptr [rax - RD_PO_BACK + RD_kind], RD_EP
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_retire_step
    cmp qword ptr [rip + da_context + DIA_eo], 0
    jne .Lda_fail
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_timeout
    cmp rax, -1
    jne .Lda_fail
    mov rax, [rip + da_context + DIA_ep]
    cmp qword ptr [rax + PO_refs], 1
    jne .Lda_fail
    # Fixture restores rejected metadata and takes its retained ref for teardown.
    mov qword ptr [rax - RD_PO_BACK + RD_kind], RD_EP
    mov rdi, rax
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne .Lda_fail
    mov qword ptr [rip + da_context + DIA_ep], 0
    mov qword ptr [rip + da_context + DIA_blocked], 0
    call da_drain_common
    jmp .Lda_cleanup
.Lda_value:
    call da_make_ep
    mov esi, PD_MEMBER
    mov edx, 2 * SD_SIZE
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    mov edx, 2
    call pd_alloc_bind_settings
    test rax, rax
    jz .Lda_fail
    mov esi, PD_VALUE
    mov edx, 10
    call da_begin
    mov r12, rax
    lea rdi, [rip + da_context]
    mov rsi, r12
    lea rdx, [rip + da_data]
    mov ecx, 10
    call pd_alloc_copy
    cmp rax, 10
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_slots + DTS_initialized], 10
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_slots + DTS_state], DTS_INITIALIZED
    jne .Lda_fail
    mov r14, [rip + discovery_extra_charge]
    lea rdi, [rip + da_context]
    mov rsi, r12
    xor edx, edx
    call pd_alloc_enroll_value
    test rax, rax
    jne .Lda_fail
    cmp rdx, -22
    jne .Lda_fail
    cmp [rip + discovery_extra_charge], r14
    jne .Lda_fail
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_publish_setting
    test rax, rax
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov rsi, r12
    xor edx, edx
    call pd_alloc_enroll_value
    test rax, rax
    jz .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 1
    call pd_alloc_publish_setting
    test rax, rax
    jne .Lda_fail
    mov esi, PD_VALUE
    mov edx, 1
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    mov edx, 1
    call pd_alloc_enroll_value
    test rax, rax
    jz .Lda_fail
    cmp byte ptr [rax], 0
    jne .Lda_fail
    mov rcx, [rip + da_context + DIA_ep]
    cmp qword ptr [rcx + EP_valuecharge], 64
    jne .Lda_fail
    mov r13, [rcx + PO_eo]
    mov rax, [r13 + EO_used]
    mov [r13 + EO_cap], rax
    mov esi, PD_MEMBER
    mov edx, 1
    call da_full
    mov r12, rax
    mov r14, [rip + prep_total_charge]
    mov r15, [rip + discovery_extra_charge]
    lea rdi, [rip + da_context]
    mov rsi, r12
    mov edx, 1
    call pd_alloc_enroll_member
    test rax, rax
    jne .Lda_fail
    cmp rdx, -EV_RESOURCE
    jne .Lda_fail
    cmp [rip + prep_total_charge], r14
    jne .Lda_fail
    cmp [rip + discovery_extra_charge], r15
    jne .Lda_fail
    jmp .Lda_cleanup
.Lda_large:
    mov esi, PD_EXTRA
    mov edx, 64 * 1024 * 1024
    call da_full
    cmp qword ptr [rip + discovery_extra_charge], 64 * 1024 * 1024 + 4096
    jne .Lda_fail
    jmp .Lda_cleanup
# Retained raw slots cannot hide other raw or enrolled owners.
.Lda_mixed:
    mov esi, PD_EXTRA
    mov edx, 70000
    call da_begin
    mov esi, PD_EXTRA
    mov edx, 70000
    call da_begin
    mov esi, PD_EXTRA
    mov edx, 1
    call da_begin
    call da_make_ep
    mov qword ptr [rip + da_fail_unmap], 2
    mov r12d, 5
1:  mov r14, [rip + da_action_calls]
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_retire_step
    cmp rax, 1
    jne .Lda_fail
    inc r14
    cmp [rip + da_action_calls], r14
    jne .Lda_fail
    dec r12
    jnz 1b
    cmp qword ptr [rip + da_unmap_calls], 2
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_active], 2
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_ep], 0
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_eo], 0
    jne .Lda_fail
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_timeout
    cmp rax, 16
    jne .Lda_fail
    mov qword ptr [rip + da_fail_unmap], 1
    lea rdi, [rip + da_context]
    mov esi, 16
    call pd_alloc_retire_step
    cmp qword ptr [rip + da_context + DIA_slots + DTS_due], 48
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_slots + DTS_logical], 32
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 16
    call pd_alloc_timeout
    test rax, rax
    jne .Lda_fail
    lea rdi, [rip + da_context]
    lea rsi, [rip + da_status]
    mov edx, 16
    call pd_alloc_status
    test rax, rax
    jne .Lda_fail
    cmp qword ptr [rip + da_status + 40], 16
    jne .Lda_fail
    cmp qword ptr [rip + da_status + 56], 0
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 16
    call pd_alloc_retire_step
    cmp qword ptr [rip + da_context + DIA_active], 1
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 16
    call pd_alloc_timeout
    cmp rax, 32
    jne .Lda_fail
    lea rdi, [rip + da_context]
    mov esi, 48
    call pd_alloc_retire_step
    test rax, rax
    jne .Lda_fail
    call da_drain_common
    jmp .Lda_pass
.Lda_kinds:
    # Every acquisition kind crosses a refused allocator boundary, then retries
    # in a fresh EMPTY caller-owned context after exact owner/census checks.
    mov r12d, 1
1:  mov qword ptr [rip + da_fail_alloc], 1
    lea rdi, [rip + da_context]
    mov rsi, r12
    mov edx, 2
    cmp r12, PD_EO
    jne 2f
    mov edx, EO_SIZE
2:  cmp r12, PD_EP
    jne 3f
    mov edx, EP_SIZE
3:  cmp r12, PD_GP
    jne 4f
    mov edx, GP_SIZE
4:  mov r13, rdx
    call pd_alloc_begin
    cmp rax, -12
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_primary], -12
    jne .Lda_fail
    cmp qword ptr [rip + discovery_extra_charge], 0
    jne .Lda_fail
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_retire_step
    test rax, rax
    jne .Lda_fail
    lea rdi, [rip + da_context]
    call pd_alloc_init
    mov qword ptr [rip + da_fail_alloc], 0
    mov rsi, r12
    mov rdx, r13
    call da_begin
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_enroll_eo
    test rax, rax
    jne .Lda_fail
    cmp rdx, -22
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_eo], 0
    jne .Lda_fail
    mov rdi, [rip + da_context + DIA_slots + DTS_raw]
    mov rdx, [rip + da_context + DIA_slots + DTS_request]
    mov esi, 0xa5
    call memset
    lea rdi, [rip + da_context]
    xor esi, esi
    mov edx, 1
    call pd_alloc_zero
    cmp rax, 1
    jne .Lda_fail
    lea rdi, [rip + da_context]
    xor esi, esi
    lea rdx, [rip + da_data]
    mov ecx, 1
    call pd_alloc_copy
    cmp r12, PD_EXTRA
    je 5f
    cmp r12, PD_VALUE
    je 5f
    cmp rax, -22
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_slots + DTS_initialized], 1
    jne .Lda_fail
    jmp 6f
5:  cmp rax, 1
    jne .Lda_fail
6:  # Partial native bytes must remain raw, never followed by cleanup.
    lea rdi, [rip + da_context]
    xor esi, esi
    call pd_alloc_retire_step
    test rax, rax
    jne .Lda_fail
    lea rdi, [rip + da_context]
    call pd_alloc_init
    inc r12
    cmp r12, 6
    jbe 1b
    call da_make_ep
    mov esi, PD_GP
    mov edx, GP_SIZE
    call da_full
    mov r12, rax
    mov r13, [rip + da_context + DIA_eo]
    mov rax, 0x7fffffffffffffff
    mov [r13 + EO_refs], rax
    mov r14, [rip + prep_total_charge]
    mov r15, [rip + discovery_extra_charge]
    lea rdi, [rip + da_context]
    mov rsi, r12
    call pd_alloc_enroll_gp
    test rax, rax
    jne .Lda_fail
    cmp rdx, -EV_RESOURCE
    jne .Lda_fail
    cmp [rip + prep_total_charge], r14
    jne .Lda_fail
    cmp [rip + discovery_extra_charge], r15
    jne .Lda_fail
    cmp qword ptr [rip + da_context + DIA_gp], 0
    jne .Lda_fail
    mov qword ptr [r13 + EO_refs], 2
    call da_retire_all
    lea rdi, [rip + da_context]
    call pd_alloc_init
    call da_make_ep
    mov esi, PD_MEMBER
    mov edx, 1
    call da_full
    mov r12, rax
    mov rbx, [rip + da_context + DIA_ep]
    mov r13, [rbx + PO_eo]
    mov r14, [rip + prep_total_charge]
    mov r15, [rip + discovery_extra_charge]
    mov rax, [rip + da_context + DIA_slots + DTS_raw]
    mov [rip + da_snapshot], rax
    mov rax, [r13 + EO_used]
    mov [rip + da_snapshot + 8], rax
    mov rax, [rbx + PO_allocs]
    mov [rip + da_snapshot + 16], rax
    mov rax, [r13 + EO_refs]
    mov [rip + da_snapshot + 24], rax
    mov [rip + da_snapshot + 32], rbx
    mov qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    lea rdi, [rip + da_context]
    mov rsi, r12
    mov edx, 1
    call pd_alloc_enroll_member
    test rax, rax
    jne .Lda_fail
    cmp rdx, -EV_RESOURCE
    jne .Lda_fail
    cmp qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    jne .Lda_fail
    cmp [rip + discovery_extra_charge], r15
    jne .Lda_fail
    cmp [rip + da_context + DIA_ep], rbx
    jne .Lda_fail
    mov rax, [rip + da_snapshot]
    cmp [rip + da_context + DIA_slots + DTS_raw], rax
    jne .Lda_fail
    mov rax, [rip + da_snapshot + 8]
    cmp [r13 + EO_used], rax
    jne .Lda_fail
    mov rax, [rip + da_snapshot + 16]
    cmp [rbx + PO_allocs], rax
    jne .Lda_fail
    mov rax, [rip + da_snapshot + 24]
    cmp [r13 + EO_refs], rax
    jne .Lda_fail
    mov [rip + prep_total_charge], r14
    jmp .Lda_cleanup
.Lda_cleanup:
    call da_retire_all
    jmp .Lda_pass
.Lda_pass:
    cmp qword ptr [rip + discovery_extra_charge], 0
    jne .Lda_fail
    cmp qword ptr [rip + prep_total_charge], 0
    jne .Lda_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + da_baseline]
    jne .Lda_fail
    xor eax, eax
    EPILOGUE
.Lda_fail:
    mov eax, 73
    EPILOGUE

FN da_begin
    PROLOGUE
    lea rdi, [rip + da_context]
    call pd_alloc_begin
    test rax, rax
    js .Lda_helper_fail
    EPILOGUE
FN da_full
    PROLOGUE
    call da_begin
    mov rbx, rax
1:  lea rdi, [rip + da_context]
    mov rsi, rbx
    mov edx, 65536
    call pd_alloc_zero
    test rax, rax
    js .Lda_helper_fail
    mov rcx, rbx
    shl rcx, 6
    lea rcx, [rip + da_context + DIA_slots]
    mov rax, rbx
    shl rax, 6
    add rcx, rax
    cmp qword ptr [rcx + DTS_state], DTS_INITIALIZED
    jne 1b
    mov rax, rbx
    EPILOGUE
FN da_make_ep
    PROLOGUE
    mov esi, PD_EO
    mov edx, EO_SIZE
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    call pd_alloc_enroll_eo
    test rax, rax
    jz .Lda_helper_fail
    mov esi, PD_EP
    mov edx, EP_SIZE
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    call pd_alloc_enroll_ep
    test rax, rax
    jz .Lda_helper_fail
    cmp qword ptr [rax + EP_root], -1
    jne .Lda_helper_fail
    cmp dword ptr [rax + EP_ext + EXT_in], -1
    jne .Lda_helper_fail
    cmp qword ptr [rax + EP_ext + EXT_active], -1
    jne .Lda_helper_fail
    EPILOGUE
FN da_add_members
    PROLOGUE
    mov esi, PD_MEMBER
    mov edx, 2 * SD_SIZE
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    mov edx, 2
    call pd_alloc_bind_settings
    test rax, rax
    jz .Lda_helper_fail
    mov esi, PD_MEMBER
    mov edx, 8
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    mov edx, 1
    call pd_alloc_bind_grammars
    test rax, rax
    jz .Lda_helper_fail
    mov esi, PD_GP
    mov edx, GP_SIZE
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    call pd_alloc_enroll_gp
    test rax, rax
    jz .Lda_helper_fail
    mov esi, PD_MEMBER
    mov edx, 128
    call da_full
    lea rdi, [rip + da_context]
    mov rsi, rax
    mov edx, 2
    call pd_alloc_enroll_member
    test rax, rax
    jz .Lda_helper_fail
    EPILOGUE
FN da_take_ep
    PROLOGUE
    mov rax, [rip + da_context + DIA_ep]
    mov qword ptr [rax + PO_ready], 1
    lea rdi, [rip + da_context]
    call pd_alloc_drop_eo_root
    cmp rdx, 1
    jne .Lda_helper_fail
    lea rdi, [rip + da_context]
    lea rsi, [rip + da_dest]
    call pd_alloc_take_ep_check
    test rax, rax
    jne .Lda_helper_fail
    lea rdi, [rip + da_context]
    lea rsi, [rip + da_dest]
    call pd_alloc_take_ep_VOID
    cmp qword ptr [rip + da_context + DIA_settings], 0
    jne .Lda_helper_fail
    cmp qword ptr [rip + da_context + DIA_grammars], 0
    jne .Lda_helper_fail
    EPILOGUE
FN da_drain_common
    PROLOGUE
    sub rsp, 64
    mov r12d, 10000
1:  mov edi, 1
    mov rsi, rsp
    call ext_prepare_retire_step
    test rax, rax
    js .Lda_helper_fail
    jz 2f
    dec r12
    jnz 1b
    jmp .Lda_helper_fail
2:  EPILOGUE
.Lda_helper_fail:
    mov edi, 73
    SYS SYS_exit_group

FN da_retire_all
    PROLOGUE
    mov r12d, 10000
1:  lea rdi, [rip + da_context]
    mov esi, 100000
    call pd_alloc_retire_step
    test rax, rax
    js .Lda_helper_fail
    jz 2f
    dec r12
    jnz 1b
    jmp .Lda_helper_fail
2:  call da_drain_common
    EPILOGUE
