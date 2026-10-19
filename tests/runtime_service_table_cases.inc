.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntimeservice.inc"
.bss
.p2align 3
rtf_out: .zero RTC_SIZE
rtf_report: .zero 32
rtf_live: .quad 0
rtf_charge: .quad 0
rtf_stage: .quad 0
rtf_owner: .quad 0
rtf_calls: .quad 0
rtf_armed: .quad 0
rtf_drop_fault: .quad 0
rtf_unmap_fault: .quad 0
rtf_unmap_calls: .quad 0
rtf_failed_map: .quad 0
rtf_map_header: .quad 0
rtf_native: .zero EXT_SIZE
.text
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + rtf_live], rax
    mov rax, [rip + prep_total_charge]
    mov [rip + rtf_charge], rax
    mov qword ptr [rip + rtf_stage], 1
    lea rdi, [rip + rtf_out]
    mov qword ptr [rdi + RTC_cleanup], 7
    call rt_table_create
    cmp rax, -22
    jne rtf_fail
    cmp qword ptr [rip + rtf_out + RTC_cleanup], 7
    jne rtf_fail
    cmp qword ptr [rip + rtf_out + RTC_owner], 0
    jne rtf_fail
    mov qword ptr [rip + rtf_out + RTC_cleanup], 0
    mov qword ptr [rip + rtf_armed], 1
.if RTF_SCENARIO == 8
    mov qword ptr [rip + rtf_drop_fault], 1
.endif
    mov qword ptr [rip + rtf_stage], 2
    lea rdi, [rip + rtf_out]
    call rt_table_create
    test rax, rax
    jnz rtf_fail
.if RTF_SCENARIO == 1 || RTF_SCENARIO == 2
    cmp qword ptr [rip + rtf_out + RTC_owner], 0
    jne rtf_fail
    cmp qword ptr [rip + rtf_out + RTC_primary], -12
    jne rtf_fail
    jmp rtf_cleanup_result
.endif
    mov rbx, [rip + rtf_out + RTC_owner]
    test rbx, rbx
    jz rtf_fail
    mov [rip + rtf_owner], rbx
.if RTF_SCENARIO == 7
    cmp qword ptr [rip + rtf_out + RTC_primary], -22
    jne rtf_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    jne rtf_fail
    jmp rtf_cleanup_result
.else
    cmp qword ptr [rip + rtf_out + RTC_primary], 0
    jne rtf_fail
.endif
.if RTF_SCENARIO == 8
    cmp qword ptr [rip + rtf_out + RTC_cleanup], -5
    jne rtf_fail
    cmp qword ptr [rip + rtf_out + RTC_orphanEO], 0
    je rtf_fail
    jmp rtf_cleanup_result
.else
    cmp qword ptr [rip + rtf_out + RTC_cleanup], 0
    jne rtf_fail
    cmp qword ptr [rip + rtf_out + RTC_orphanEO], 0
    jne rtf_fail
.endif
    mov qword ptr [rip + rtf_stage], 3
    mov rdi, rbx
    xor esi, esi
    call rt_table_init_step
    cmp rax, -22
    jne rtf_fail
    test rdx, rdx
    jnz rtf_fail
    cmp qword ptr [rbx + RT_initCursor], 0
    jne rtf_fail
    mov qword ptr [rip + rtf_stage], 4
    mov r15d, 1000
rtf_initialize:
    mov r13, [rbx + RT_initCursor]
    mov rdi, rbx
    mov esi, 1
    call rt_table_init_step
    cmp rdx, 1
    ja rtf_fail
.if RTF_SCENARIO >= 3 && RTF_SCENARIO <= 6
    test rax, rax
    js rtf_allocation_failed
.else
    test rax, rax
    js rtf_fail
.endif
    mov r14, [rbx + RT_initCursor]
    sub r14, r13
    cmp r14, 16
    ja rtf_fail
    cmp rax, 1
    je rtf_initialized
    dec r15
    jnz rtf_initialize
    jmp rtf_fail
rtf_allocation_failed:
    cmp rax, -12
    jne rtf_fail
    cmp qword ptr [rbx + PO_ready], 0
    jne rtf_fail
    jmp rtf_cleanup_result
rtf_initialized:
.if RTF_SCENARIO >= 3 && RTF_SCENARIO <= 6
    jmp rtf_fail
.endif
    cmp qword ptr [rbx + PO_ready], 1
    jne rtf_fail
    cmp qword ptr [rbx + RT_initCursor], RT_ROW_COUNT
    jne rtf_fail
    mov qword ptr [rip + rtf_stage], 5
    mov qword ptr [rbx + RT_role], RT_TICKET_ROLE
    mov rdi, rbx
    call rt_table_is_owned
    test eax, eax
    jnz rtf_fail
    mov qword ptr [rbx + RT_role], RT_TABLE_ROLE
    mov rdi, rbx
    call rt_table_is_owned
    cmp eax, 1
    jne rtf_fail
    mov qword ptr [rip + rtf_stage], 6
    mov r13, [rbx + RT_freeHead]
    mov r14d, 1
1:  cmp r13, r14
    jne rtf_fail
    dec r13
    imul r13, r13, RT_ROW_SIZE
    lea r13, [rbx + r13 + RT_rows]
    cmp qword ptr [r13 + RTR_ro], 0
    jne rtf_fail
    mov r13, [r13 + RTR_next]
    inc r14
    cmp r14, RT_ROW_COUNT + 1
    jb 1b
    test r13, r13
    jnz rtf_fail
    mov qword ptr [rip + rtf_stage], 7
    mov rdi, rbx
    call rt_table_release
    cmp rax, -16
    jne rtf_fail
    test rdx, rdx
    jnz rtf_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne rtf_fail
    mov qword ptr [rip + rtf_stage], 8
    mov rdi, rbx
    call rt_table_retain
    test rax, rax
    jnz rtf_fail
    mov [rip + g_closingRT], rbx
    mov qword ptr [rip + rtf_out + RTC_owner], 0
    lea r13, [rip + rtf_native]
    mov dword ptr [r13 + EXT_in], -1
    mov dword ptr [r13 + EXT_out], -1
    mov dword ptr [r13 + EXT_log], -1
    mov dword ptr [r13 + EXT_host_child_in], -1
    mov dword ptr [r13 + EXT_host_child_out], -1
    mov [rbx + RT_stableExtBase], r13
    mov [rip + g_exts + VEC_ptr], r13
    mov qword ptr [rip + g_exts + VEC_cap], 1
    mov qword ptr [rbx + RT_stableExtCount], 1
    mov dword ptr [r13 + EXT_pid], 123
    mov qword ptr [rip + rtf_stage], 9
    call rt_closing_finish
    cmp rax, -16
    jne rtf_fail
    test rdx, rdx
    jnz rtf_fail
    cmp [rip + g_closingRT], rbx
    jne rtf_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne rtf_fail
    test qword ptr [rbx + RT_flags], RTF_MEMORY_ONLY
    jnz rtf_fail
    mov dword ptr [r13 + EXT_pid], 0
    mov qword ptr [rip + rtf_stage], 10
    call rt_closing_finish
    test rax, rax
    jnz rtf_fail
    cmp rdx, 1
    jne rtf_fail
    cmp qword ptr [rip + g_closingRT], 0
    jne rtf_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne rtf_fail
    test qword ptr [rbx + RT_flags], RTF_MEMORY_ONLY
    jz rtf_fail
    cmp qword ptr [rbx + RT_stableExtBase], 0
    jne rtf_fail
    mov qword ptr [rip + rtf_stage], 11
.if RTF_SCENARIO == 9
    mov qword ptr [rip + rtf_unmap_fault], 1
.endif
    mov rdi, rbx
    call rt_table_release
    test rax, rax
    jnz rtf_fail
    cmp rdx, 1
    jne rtf_fail
    jmp rtf_drain
rtf_cleanup_result:
    mov rdi, [rip + rtf_out + RTC_orphanEO]
    test rdi, rdi
    jz 2f
    call ext_prepare_owner_release_deferred
    test rax, rax
    jnz rtf_fail
    cmp rdx, 1
    jne rtf_fail
    mov qword ptr [rip + rtf_out + RTC_orphanEO], 0
2:  mov rdi, [rip + rtf_out + RTC_owner]
    test rdi, rdi
    jz rtf_drain
    call rt_table_release
    test rax, rax
    jnz rtf_fail
    cmp rdx, 1
    jne rtf_fail
    mov qword ptr [rip + rtf_out + RTC_owner], 0
rtf_drain:
    mov qword ptr [rip + rtf_armed], 0
    mov qword ptr [rip + rtf_stage], 12
    mov r15d, 1000
3:  mov r13, [rip + g_mem_live]
    mov r14, [rip + prep_total_charge]
    mov edi, 1
    lea rsi, [rip + rtf_report]
    call ext_prepare_retire_step
.if RTF_SCENARIO == 9
    cmp qword ptr [rip + rtf_unmap_fault], 0
    je 4f
    cmp qword ptr [rip + rtf_unmap_calls], 0
    je 4f
    cmp qword ptr [rip + rtf_unmap_calls], 1
    jne rtf_fail
    cmp [rip + g_mem_live], r13
    jne rtf_fail
    cmp [rip + prep_total_charge], r14
    jne rtf_fail
    mov rax, [rip + rtf_failed_map]
    mov rcx, [rip + rtf_map_header]
    cmp [rax], rcx
    jne rtf_fail
    cmp qword ptr [rip + rtf_report + 16], 1
    jne rtf_fail
    mov qword ptr [rip + rtf_unmap_fault], 0
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne rtf_fail
4:
.endif
    mov edi, 1
    lea rsi, [rip + rtf_report]
    call ext_prepare_retire_step
    cmp qword ptr [rip + rtf_report], 1
    ja rtf_fail
    test rax, rax
    jz rtf_finished
    dec r15
    jnz 3b
    jmp rtf_fail
rtf_finished:
    mov qword ptr [rip + rtf_stage], 13
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + rtf_live]
    jne rtf_fail
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + rtf_charge]
    jne rtf_fail
.if RTF_SCENARIO == 9
    cmp qword ptr [rip + rtf_unmap_calls], 0
    je rtf_fail
.endif
    xor eax, eax
    EPILOGUE
rtf_fail:
    mov rdi, [rip + rtf_stage]
    add rdi, 160
    call sys_exit
FN mem_alloc_try
    cmp qword ptr [rip + rtf_armed], 0
    je rtf_real_mem_alloc_try
    inc qword ptr [rip + rtf_calls]
.if RTF_SCENARIO >= 1 && RTF_SCENARIO <= 6
    cmp qword ptr [rip + rtf_calls], RTF_SCENARIO
    jne rtf_real_mem_alloc_try
    xor eax, eax
    ret
.else
    jmp rtf_real_mem_alloc_try
.endif
FN ext_prepare_retire_mark_custom_po
.if RTF_SCENARIO == 7
    mov rax, -22
    ret
.else
    jmp rtf_real_mark
.endif
FN ext_prepare_owner_release_deferred
    cmp qword ptr [rip + rtf_drop_fault], 0
    je rtf_real_owner_drop
    mov qword ptr [rip + rtf_drop_fault], 0
    mov rax, -5
    xor edx, edx
    ret
FN rtf_unmap
    cmp qword ptr [rip + rtf_unmap_fault], 0
    je 5f
    inc qword ptr [rip + rtf_unmap_calls]
    mov [rip + rtf_failed_map], rdi
    mov rax, [rdi]
    mov [rip + rtf_map_header], rax
    mov rax, -5
    ret
5:  SYS SYS_munmap
    ret
