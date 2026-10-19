.macro XFER_TOGGLE_QUERY
    movzx ecx, byte ptr [r12]
    or ecx, 0x20
    sub ecx, 'a'
    cmp ecx, 25
    ja 993f
    xor byte ptr [r12], 0x20
993:
.endm
.equ W_ptr, 0
.equ W_len, 8
.equ W_class, 12
.equ XFER_TOKEN_LENGTH, 155

.include "gpc-input.inc"
.include "app/extdiscoverygp.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygpxfer.inc"
.include "app/extdiscoveryalloc.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
dia: .skip DIA_SIZE
gpc: .skip GPC_SIZE
.globl pgi
pgi: .skip PGI_SIZE
pge: .skip PGE_SIZE
req: .skip 48
token: .skip 16
scratch: .skip 80
output_guard_before: .skip 32
output: .skip 65536
output_guard_after: .skip 32
position: .skip 8
context_copy: .skip PGI_SIZE
.globl xfer_active,xfer_byte_actual,xfer_unit_actual,xfer_forbidden_actual
xfer_active: .skip 8
xfer_byte_actual: .skip 8
xfer_unit_actual: .skip 8
xfer_forbidden_actual: .skip 8
xfer_budget: .skip 8
xfer_measure_budget: .skip 8
xfer_capacity: .skip 8
.globl xfer_fault,xfer_inject_actual
xfer_fault: .skip 8
xfer_inject_actual: .skip 8
xfer_dia_snapshot: .skip DIA_SIZE
xfer_savedptr: .skip 8
xfer_savedlen: .skip 8
xfer_savedcap: .skip 8
.globl xfer_unmap_actual,xfer_fail_unmap
xfer_unmap_actual: .skip 8
xfer_fail_unmap: .skip 8
xfer_retained_seen: .skip 8
xfer_now: .skip 8
xfer_baseline_live: .skip 8
xfer_saved_gp: .skip 8
xfer_generation_counter: .skip 8
xfer_exhausted_issuer: .skip 8
xfer_queries: .skip 512
xfer_query_pool: .skip 2097168
xfer_query_count: .skip 8
xfer_query_used: .skip 8
xfer_expected_name_len: .skip 8
xfer_expected_rules: .skip 8
xfer_tokens_expected: .skip 1024
xfer_tokens_actual: .skip 1024
xfer_token_state: .skip 16
xfer_lifetime: .skip 8
xfer_stage: .skip 8
xfer_payload: .skip 8
xfer_unknown_raw: .skip 8
xfer_unknown_close_calls: .skip 8
xfer_unknown_eo: .skip 8
xfer_input: .skip 8
xfer_doc_gp: .skip 8
xfer_l_release_raw: .skip 8
xfer_l_omitted_close_count: .skip 8
.globl xfer_output_actual,xfer_fail_eo,xfer_fail_raw,xfer_fail_charge,xfer_fail_next,xfer_fail_aocharge,xfer_fail_total,xfer_fail_used,xfer_fail_live
xfer_output_actual: .skip 8
xfer_fail_eo: .skip 8
xfer_fail_raw: .skip 8
xfer_fail_charge: .skip 8
xfer_fail_next: .skip 8
xfer_fail_aocharge: .skip 8
xfer_fail_total: .skip 8
xfer_fail_used: .skip 8
xfer_fail_live: .skip 8
.text
FN main
    PROLOGUE 16
    mov rax, [rip + g_mem_live]
    mov [rip + xfer_baseline_live], rax
    mov qword ptr [rip + xfer_exhausted_issuer], -2
    lea rdi, [rip + xfer_exhausted_issuer]
    call xfer_issue_generation
    cmp rax, -1
    jne .Lip_fail
    test rdx, rdx
    jne .Lip_fail
    lea rdi, [rip + xfer_exhausted_issuer]
    call xfer_issue_generation
    test rax, rax
    jne .Lip_fail
    cmp rdx, -EV_RESOURCE
    jne .Lip_fail
    cmp qword ptr [rip + xfer_exhausted_issuer], -1
    jne .Lip_fail
    mov qword ptr [rip + xfer_capacity], 65536
    mov r13d, 65536
    mov qword ptr [rip + xfer_fault], -1
    cmp qword ptr [rip + g_argc], 3
    jne 8f
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    cmp byte ptr [rax], 'P'
    jne 7f
    call xfer_lease_probe
    EPILOGUE
7:  cmp byte ptr [rax], 'Q'
    jne 6f
    mov qword ptr [rip + xfer_lifetime], 2
    jmp .Lip_args_ready
6:  cmp byte ptr [rax], 'L'
    jne 8f
    mov qword ptr [rip + xfer_lifetime], 1
    jmp .Lip_args_ready
8:  cmp qword ptr [rip + g_argc], 2
    jb 1f
    mov rax, [rip + g_argv]
    mov rax, [rax + 8]
    movzx eax, byte ptr [rax]
    sub eax, '0'
    cmp eax, 4
    ja .Lip_fail
    cmp eax, 4
    jne 9f
    mov r13d, 2
    mov qword ptr [rip + xfer_measure_budget], 1
    jmp 1f
9:  lea rcx, [rip + xfer_budgets]
    mov r13, [rcx + rax*8]
1:  cmp qword ptr [rip + g_argc], 3
    jb 2f
    mov rax, [rip + g_argv]
    mov rax, [rax + 16]
    movzx eax, byte ptr [rax]
    sub eax, '0'
    cmp eax, 3
    ja .Lip_fail
    lea rcx, [rip + xfer_capacities]
    mov rax, [rcx + rax*8]
    mov [rip + xfer_capacity], rax
2:  mov qword ptr [rip + xfer_fault], -1
    cmp qword ptr [rip + g_argc], 4
    jb 3f
    mov rax, [rip + g_argv]
    mov rax, [rax + 24]
    movzx eax, byte ptr [rax]
    mov [rip + xfer_fault], rax
3:
.Lip_args_ready:
    mov [rip + xfer_budget], r13
    cmp qword ptr [rip + xfer_measure_budget], 0
    jne 9f
    mov [rip + xfer_measure_budget], r13
9:  xor r12d,r12d
    cmp qword ptr [rip + xfer_fault], 'X'
    je 4f
    cmp qword ptr [rip + xfer_fault], 'Z'
    jne .Lip_case
4:  mov r12, GPC_MANAGED_COUNT + 1
.Lip_case:
    cmp r12, GPC_INPUT_COUNT
    jae .Lip_done
    cmp qword ptr [rip + xfer_lifetime], 0
    je 8f
    cmp r12, 1
    jae .Lip_done
8:
    cmp qword ptr [rip + xfer_fault], -1
    je 1f
    cmp qword ptr [rip + xfer_fault], 'X'
    je 2f
    cmp qword ptr [rip + xfer_fault], 'Z'
    jne 3f
2:  cmp r12, GPC_MANAGED_COUNT + 2
    jae .Lip_done
    jmp 1f
3:  cmp r12, 1
    jae .Lip_done
1:
    mov qword ptr [rip + token + 8], 0
    call xfer_native_export
    lea rdi, [rip + dia]
    call pd_alloc_init
    test rax, rax
    jne .Lip_fail
    mov esi, PD_EO
    mov edx, EO_SIZE
    call make_full
    lea rdi, [rip + dia]
    mov rsi, rax
    call pd_alloc_enroll_eo
    test rax, rax
    jz .Lip_fail
    cmp qword ptr [rip + xfer_lifetime], 0
    je 8f
    call xfer_lease_setup
8:
    mov esi, PD_EP
    mov edx, EP_SIZE
    call make_full
    lea rdi, [rip + dia]
    mov rsi, rax
    call pd_alloc_enroll_ep
    test rax, rax
    jz .Lip_fail
    mov esi, PD_MEMBER
    mov edx, 8
    call make_full
    lea rdi, [rip + dia]
    mov rsi, rax
    mov edx, 1
    call pd_alloc_bind_grammars
    test rax, rax
    jz .Lip_fail
    mov rax, r12
    shl rax, 4
    lea rbx, [rip + expected]
    add rbx, rax
    mov rax, [rbx]
    mov [rip + req], rax
    mov rax, [rbx + 8]
    mov [rip + req + 8], rax
    cmp qword ptr [rip + xfer_lifetime], 0
    je 8f
    mov edi, 1048576
    call mem_alloc_uninit_try
    test rax, rax
    jz .Lip_fail
    mov [rip + xfer_input], rax
    mov rdi, rax
    mov rsi, [rbx]
    mov rdx, [rbx + 8]
    call memcpy
    mov rax, [rip + xfer_input]
    mov [rip + req], rax
8:
    mov rax, 1
    cmp r12, GPC_MANAGED_COUNT
    jb 1f
    inc rax
1:  mov [rip + req + 16], rax
    mov [rip + req + 24], r12
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + probe_cases]
    mov rax, [rcx + rax + 8]
    mov [rip + req + 32], rax
    mov qword ptr [rip + req + 40], 0
    mov qword ptr [rip + gpc + GPC_state], GPC_NEW
    lea rdi, [rip + gpc]
    lea rsi, [rip + req]
    call pg_validate_begin
    test rax, rax
    jne .Lip_fail
.Lip_validate:
    lea rdi, [rip + gpc]
    mov esi, 65536
    call pg_validate_step
    test rax, rax
    js .Lip_fail
    jnz .Lip_validate
    lea rdi, [rip + pgi]
    mov esi, 0xa5
    mov edx, PGI_SIZE
    call memset
    mov qword ptr [rip + pgi + PGI_state], PGI_NEW
    lea rdi, [rip + context_copy]
    lea rsi, [rip + pgi]
    mov edx, PGI_SIZE
    call memcpy
    lea rdi, [rip + pgi]
    mov esi, 2
    call pg_import_step
    cmp rax, -22
    jne .Lip_fail
    or rdx, rcx
    jnz .Lip_fail
    lea rdi, [rip + scratch]
    mov esi, 0x5a
    mov edx, 80
    call memset
    lea rdi, [rip + pgi]
    lea rsi, [rip + scratch]
    call pg_import_status
    cmp rax, -22
    jne .Lip_fail
    lea rax, [rip + scratch]
    mov ecx, 10
1:  mov rdx, 0x5a5a5a5a5a5a5a5a
    cmp [rax], rdx
    jne .Lip_fail
    add rax, 8
    dec rcx
    jnz 1b
    lea rdi, [rip + pgi]
    call pg_import_cancel
    cmp rax, -22
    jne .Lip_fail
    lea rdi, [rip + pgi]
    call pg_import_clear
    test rax, rax
    jne .Lip_fail
    lea rdi, [rip + context_copy]
    lea rsi, [rip + pgi]
    mov edx, PGI_SIZE
    call memeq
    test eax, eax
    jz .Lip_fail
    lea rax, [rip + dia]
    mov [rip + req], rax
    lea rax, [rip + gpc]
    mov [rip + req + 8], rax
    lea rax, [rip + token]
    mov [rip + req + 16], rax
    lea rdi, [rip + xfer_generation_counter]
    call xfer_issue_generation
    test rax, rax
    jz .Lip_fail
    mov [rip + token], rax
    mov qword ptr [rip + token + 8], 1
    mov [rip + req + 24], rax
    mov qword ptr [rip + req + 32], 0
    lea rdi, [rip + pgi]
    lea rsi, [rip + req]
    call pg_import_begin
    test rax, rax
    jne .Lip_fail
    lea rdi, [rip + pgi]
    lea rsi, [rip + scratch]
    call pg_import_status
    test rax, rax
    jne .Lip_fail
    cmp qword ptr [rip + scratch], PGI_WORK
    jne .Lip_fail
    mov rax, [rip + scratch + 8]
    or rax, [rip + scratch + 16]
    or rax, [rip + scratch + 24]
    or rax, [rip + scratch + 32]
    or rax, [rip + scratch + 48]
    or rax, [rip + scratch + 56]
    jnz .Lip_fail
    lea rdi, [rip + context_copy]
    lea rsi, [rip + pgi]
    mov edx, PGI_SIZE
    call memcpy
    lea rdi, [rip + pgi]
    mov esi, 1
    call pg_import_step
    cmp rax, -22
    jne .Lip_fail
    or rdx, rcx
    jnz .Lip_fail
    lea rdi, [rip + context_copy]
    lea rsi, [rip + pgi]
    mov edx, PGI_SIZE
    call memeq
    test eax, eax
    jz .Lip_fail
.Lip_import:
    mov rax, [rip + xfer_fault]
    cmp rax, -1
    je .Lip_import_step
    cmp rax, 'd'
    je .Lip_import_step
    cmp rax, 'e'
    je .Lip_import_step
    cmp rax, 'h'
    je .Lip_import_step
    cmp rax, 'i'
    je .Lip_import_step
    cmp rax, 'j'
    je .Lip_import_step
    cmp rax, 'k'
    je .Lip_import_step
    cmp rax, 'm'
    je .Lip_import_step
    mov rdx, [rip + pgi + PGI_phase]
    mov rcx, rax
    sub rcx, '0'
    cmp rcx, 9
    jbe 1f
    mov rcx, rax
    sub rcx, 'A' - 10
1:  cmp rcx, rdx
    je .Lip_cancel_prefix
    cmp rcx, 12
    jbe .Lip_import_step
    cmp rax, 'X'
    je 8f
    cmp rax, 'Z'
    je 9f
    cmp rax, 't'
    jne 2f
8:
    cmp rdx, PGI_COPY_BLOB
    jne .Lip_import_step
    cmp qword ptr [rip + pgi + PGI_cursor], 0
    je .Lip_import_step
    jmp .Lip_cancel_prefix
9:  cmp rdx, PGI_FINAL
    jne .Lip_import_step
    jmp .Lip_cancel_prefix
2:  cmp rax, 'u'
    jne 3f
    cmp rdx, PGI_WORD_RELOC
    jne .Lip_import_step
    cmp qword ptr [rip + pgi + PGI_recordstage], 2
    jne .Lip_import_step
    cmp qword ptr [rip + pgi + PGI_byteindex], 8
    jae .Lip_import_step
    cmp qword ptr [rip + pgi + PGI_byteindex], 0
    je .Lip_import_step
    jmp .Lip_cancel_prefix
3:  cmp rax, 'a'
    jne .Lip_maybe_stale
    cmp rdx, PGI_ARRAYS
    jne .Lip_import_step
    cmp qword ptr [rip + pgi + PGI_cursor], 0
    je .Lip_import_step
    jmp .Lip_cancel_prefix
.Lip_maybe_stale:
    cmp rdx, PGI_INIT
    jne .Lip_import_step
    mov r14, [rip + dia + DIA_ep]
    mov rdx, [r14 + EP_grammars + VEC_ptr]
    mov [rip + xfer_savedptr], rdx
    mov rdx, [r14 + EP_grammars + VEC_len]
    mov [rip + xfer_savedlen], rdx
    mov rdx, [r14 + EP_grammars + VEC_cap]
    mov [rip + xfer_savedcap], rdx
    cmp rax, 'f'
    je .Lip_aba_revalidate
    cmp rax, 'r'
    jne 1f
    mov qword ptr [rip + token + 8], 0
    jmp .Lip_expect_stale
1:  cmp rax, 'g'
    jne 2f
    inc qword ptr [rip + token]
    jmp .Lip_expect_stale
2:  cmp rax, 's'
    jne 3f
    lea rdi, [rip + gpc]
    call pg_validate_cancel
    jmp .Lip_expect_stale
3:  cmp rax, 'v'
    jne 4f
    inc qword ptr [r14 + EP_grammars + VEC_len]
    jmp .Lip_expect_stale
4:  cmp rax, 'p'
    jne 5f
    add qword ptr [r14 + EP_grammars + VEC_ptr], 8
    jmp .Lip_expect_stale
5:  cmp rax, 'c'
    jne .Lip_fail
    inc qword ptr [r14 + EP_grammars + VEC_cap]
    jmp .Lip_expect_stale
.Lip_aba_revalidate:
    mov qword ptr [rip + token + 8], 0
    lea rdi, [rip + gpc]
    call pg_validate_cancel
    mov rax, [rip + pgi + PGI_wire]
    mov [rip + req], rax
    mov rax, [rip + pgi + PGI_length]
    mov [rip + req + 8], rax
    mov rax, [rip + pgi + PGI_mode]
    mov [rip + req + 16], rax
    mov rax, [rip + pgi + PGI_ordinal]
    mov [rip + req + 24], rax
    mov rax, [rip + pgi + PGI_sourcebytes]
    mov [rip + req + 32], rax
    mov qword ptr [rip + req + 40], 0
    lea rdi, [rip + gpc]
    lea rsi, [rip + req]
    call pg_validate_begin
    test rax, rax
    jne .Lip_fail
1:  lea rdi, [rip + gpc]
    mov esi, 65536
    call pg_validate_step
    test rax, rax
    js .Lip_fail
    jnz 1b
    lea rdi, [rip + xfer_generation_counter]
    call xfer_issue_generation
    test rax, rax
    jz .Lip_fail
    mov [rip + token], rax
    mov qword ptr [rip + token + 8], 1
    jmp .Lip_expect_stale
.Lip_expect_stale:
    mov qword ptr [rip + xfer_active], 3
    mov qword ptr [rip + xfer_byte_actual], 0
    mov qword ptr [rip + xfer_unit_actual], 0
    lea rdi, [rip + pgi]
    mov esi, 65536
    call pg_import_step
    mov qword ptr [rip + xfer_active], 0
    cmp rax, -116
    jne .Lip_fail
    mov rax, [rip + xfer_byte_actual]
    or rax, [rip + xfer_unit_actual]
    jnz .Lip_fail
    or rdx, rcx
    jnz .Lip_fail
    mov rax, [rip + xfer_savedptr]
    mov [r14 + EP_grammars + VEC_ptr], rax
    mov rax, [rip + xfer_savedlen]
    mov [r14 + EP_grammars + VEC_len], rax
    mov rax, [rip + xfer_savedcap]
    mov [r14 + EP_grammars + VEC_cap], rax
    mov r13, -116
    jmp .Lip_failed_prefix
.Lip_cancel_prefix:
    cmp qword ptr [rip + xfer_fault], 'X'
    je 1f
    cmp qword ptr [rip + xfer_fault], 'Z'
    jne 2f
1:  mov rax, [rip + pgi + PGI_eo]
    mov [rip + xfer_fail_eo], rax
    mov qword ptr [rip + xfer_fail_unmap], 1
    mov qword ptr [rip + xfer_unmap_actual], 0
    mov qword ptr [rip + xfer_retained_seen], 0
2:  lea rdi, [rip + pgi]
    call pg_import_cancel
    test rax, rax
    jne .Lip_fail
    mov r13, -125
.Lip_failed_prefix:
    lea rdi, [rip + pgi]
    lea rsi, [rip + scratch]
    call pg_import_status
    test rax, rax
    jne .Lip_fail
    cmp qword ptr [rip + scratch], PGI_FAILED
    jne .Lip_fail
    cmp [rip + scratch + 8], r13
    jne .Lip_fail
    cmp qword ptr [rip + scratch + 16], PGI_INIT
    jne 1f
    mov rax, [rip + scratch + 24]
    or rax, [rip + scratch + 32]
    or rax, [rip + scratch + 48]
    or rax, [rip + scratch + 56]
    jnz .Lip_fail
1:  lea rdi, [rip + pgi]
    call pg_import_clear
    cmp rax, -16
    jne .Lip_fail
    lea rdi, [rip + pgi]
    call pg_import_cancel
    test rax, rax
    jne .Lip_fail
    lea rdi, [rip + pgi]
    mov esi, 65536
    call pg_import_step
    cmp rax, r13
    jne .Lip_fail
    or rdx, rcx
    jnz .Lip_fail
    jmp .Lip_retire
.Lip_operation_error:
    cmp qword ptr [rip + xfer_inject_actual], 1
    jne .Lip_fail
    mov r13, -5
    cmp qword ptr [rip + xfer_fault], 'd'
    je 1f
    cmp qword ptr [rip + xfer_fault], 'e'
    jne 2f
1:  mov r13, -12
2:  cmp rax, r13
    jne .Lip_fail
    cmp [rip + dia + DIA_primary], r13
    jne .Lip_fail
    cmp qword ptr [rip + dia + DIA_state], DIA_ABORT
    jne .Lip_fail
    lea rdi, [rip + dia + 24]
    lea rsi, [rip + xfer_dia_snapshot + 24]
    mov edx, DIA_SIZE - 24
    call memeq
    test eax, eax
    jz .Lip_fail
    jmp .Lip_failed_prefix
.Lip_import_step:
    cmp qword ptr [rip + xfer_fault], -1
    je 8f
    lea rdi, [rip + xfer_dia_snapshot]
    lea rsi, [rip + dia]
    mov edx, DIA_SIZE
    call memcpy
8:  lea rdi, [rip + pgi]
    mov esi, 65536
    mov rsi, [rip + xfer_budget]
    mov qword ptr [rip + xfer_active], 3
    mov qword ptr [rip + xfer_byte_actual], 0
    mov qword ptr [rip + xfer_unit_actual], 0
    call pg_import_step
    mov qword ptr [rip + xfer_active], 0
    cmp rdx, [rip + xfer_byte_actual]
    jne .Lip_fail
    cmp rcx, [rip + xfer_unit_actual]
    jne .Lip_fail
    cmp qword ptr [rip + xfer_forbidden_actual], 0
    jne .Lip_fail
    cmp rdx, [rip + xfer_budget]
    ja .Lip_fail
    cmp rcx, 16
    ja .Lip_fail
    test rax, rax
    js .Lip_operation_error
    jnz .Lip_import
    cmp qword ptr [rip + xfer_fault], -1
    jne .Lip_fail
    mov qword ptr [rip + token + 8], 0
    lea rdi, [rip + gpc]
    call pg_validate_cancel
    mov qword ptr [rip + gpc + GPC_wire], 1
    cmp qword ptr [rip + xfer_lifetime], 0
    je 8f
    mov rdi, [rip + xfer_input]
    mov esi, 0xa5
    mov rdx, [rbx + 8]
    call memset
    mov rdi, [rip + xfer_input]
    call mem_free
    test rax, rax
    js .Lip_fail
    mov qword ptr [rip + xfer_input], 0
    mov rdi, [rip + xfer_payload]
    call ext_root_close
    test rax, rax
    jne .Lip_fail
    cmp rdx, 1
    jne .Lip_fail
    mov qword ptr [rip + xfer_payload], -1
8:  lea rdi, [rip + pgi]
    mov esi, 2
    call pg_import_step
    test rax, rax
    jne .Lip_fail
    or rdx, rcx
    jnz .Lip_fail
    lea rdi, [rip + pgi]
    call pg_import_cancel
    cmp rax, -16
    jne .Lip_fail
    cmp qword ptr [rip + dia + DIA_gp], 0
    jne .Lip_fail
    mov rax, [rip + dia + DIA_ep]
    cmp qword ptr [rax + EP_grammars + VEC_len], 1
    jne .Lip_fail
    mov rax, [rax + EP_grammars + VEC_ptr]
    mov r14, [rax]
    test r14, r14
    jz .Lip_fail
    cmp qword ptr [r14 + PO_ready], 1
    jne .Lip_fail
    cmp [r14 + GP_gr + GR_owner], r14
    jne .Lip_fail
    call xfer_assert_native_fields
    call xfer_compare_queries
    call xfer_compare_tokens
    call xfer_export_check
    cmp qword ptr [rip + xfer_lifetime], 0
    je 8f
    mov rdi, r14
    call grammar_prepare_retain
    test rax, rax
    jne .Lip_fail
    mov [rip + xfer_doc_gp], r14
8:  lea rdi, [rip + pgi]
    call pg_import_clear
    test rax, rax
    jne .Lip_fail
    lea rdi, [rip + dia]
    mov rsi, -125
    call pd_alloc_abort
.Lip_retire:
    lea rdi, [rip + dia]
    add qword ptr [rip + xfer_now], 1000
    mov rsi, [rip + xfer_now]
    call pd_alloc_retire_step
    test rax, rax
    js .Lip_fail
    mov r13, rax
    cmp qword ptr [rip + xfer_fault], 'X'
    jne 1f
    cmp qword ptr [rip + xfer_retained_seen], 0
    jne 1f
    cmp qword ptr [rip + xfer_unmap_actual], 1
    jne 1f
    cmp qword ptr [rip + xfer_fail_unmap], 0
    jne .Lip_fail
    cmp qword ptr [rip + discovery_extra_charge], 0
    je .Lip_fail
    lea rdi, [rip + pgi]
    call pg_import_clear
    cmp rax, -16
    jne .Lip_fail
    lea rdi, [rip + dia]
    mov rsi, [rip + xfer_now]
    call pd_alloc_retire_step
    cmp qword ptr [rip + xfer_unmap_actual], 1
    jne .Lip_fail
    mov qword ptr [rip + xfer_retained_seen], 1
1:  test r13, r13
    jnz .Lip_retire
.Lip_common:
    mov edi, 1
    lea rsi, [rip + scratch]
    call ext_prepare_retire_step
    test rax, rax
    js .Lip_fail
    jz .Lip_common_done
    cmp qword ptr [rip + xfer_lifetime], 2
    jne 8f
    cmp qword ptr [rip + xfer_unknown_close_calls], 0
    je .Lip_common
    call xfer_unknown_proof
    jmp .Lip_done
8:  cmp qword ptr [rip + xfer_fault], 'Z'
    jne .Lip_common
    cmp qword ptr [rip + xfer_unmap_actual], 1
    jne .Lip_common
    mov rax, [rip + prep_total_charge]
    cmp rax, [rip + xfer_fail_total]
    jne .Lip_fail
    mov rax, [rip + xfer_fail_eo]
    mov rax, [rax + EO_used]
    cmp rax, [rip + xfer_fail_used]
    jne .Lip_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + xfer_fail_live]
    jne .Lip_fail
    mov rax, [rip + pgi + PGI_gp]
    mov rax, [rax + PO_allocs]
    cmp rax, [rip + xfer_fail_raw]
    jne .Lip_fail
    mov rcx, [rax + AO_charge]
    cmp rcx, [rip + xfer_fail_charge]
    jne .Lip_fail
    cmp rcx, [rip + xfer_fail_aocharge]
    jne .Lip_fail
    mov rcx, [rax + AO_next]
    cmp rcx, [rip + xfer_fail_next]
    jne .Lip_fail
    mov rcx, [rax - 16]
    cmp rcx, [rip + xfer_fail_charge]
    jne .Lip_fail
    cmp qword ptr [rip + xfer_fail_unmap], 0
    jne .Lip_fail
    mov edi, 1
    call ext_prepare_retire_retry_known
    jmp .Lip_common
.Lip_common_done:
    cmp qword ptr [rip + xfer_lifetime], 0
    je 8f
    cmp qword ptr [rip + xfer_doc_gp], 0
    je 8f
    call xfer_doc_lifetime
    jmp .Lip_common
8:  mov rax, [rip + g_mem_live]
    cmp rax, [rip + xfer_baseline_live]
    jne .Lip_fail
    cmp qword ptr [rip + prep_total_charge], 0
    jne .Lip_fail
    cmp qword ptr [rip + discovery_extra_charge], 0
    jne .Lip_fail
    cmp qword ptr [rip + xfer_fault], -1
    je 1f
    lea rdi, [rip + pgi]
    call pg_import_clear
    test rax, rax
    jne .Lip_fail
1:  cmp qword ptr [rip + xfer_fault], 'X'
    jne 2f
    cmp qword ptr [rip + xfer_retained_seen], 1
    jne .Lip_fail
2:  cmp qword ptr [rip + xfer_fault], 'X'
    je 3f
    cmp qword ptr [rip + xfer_fault], 'Z'
    jne 4f
3:  cmp qword ptr [rip + xfer_unmap_actual], 2
    jne .Lip_fail
    cmp qword ptr [rip + xfer_fail_unmap], 0
    jne .Lip_fail
4:  cmp qword ptr [rip + xfer_lifetime], 1
    jne 5f
    call xfer_l_success_wait
5:  inc r12
    jmp .Lip_case
.Lip_done:
    xor eax, eax
    EPILOGUE
.Lip_fail:
    mov [rip + scratch], r12
    mov [rip + scratch + 8], rax
    mov rax, [rip + pgi + PGI_phase]
    mov [rip + scratch + 16], rax
    mov rax, [rip + pgi + PGI_error]
    mov [rip + scratch + 24], rax
    mov rax, [rip + dia + DIA_primary]
    mov [rip + scratch + 32], rax
    mov rax, [rip + pgi + PGI_cursor]
    mov [rip + scratch + 40], rax
    mov edi, 2
    lea rsi, [rip + scratch]
    mov edx, 48
    call write_all
    mov eax, 73
    EPILOGUE
FN make_full
    PROLOGUE
    lea rdi, [rip + dia]
    call pd_alloc_begin
    test rax, rax
    js .Lip_make_fail
    mov rbx, rax
1:  lea rdi, [rip + dia]
    mov rsi, rbx
    mov edx, 65536
    call pd_alloc_zero
    test rax, rax
    js .Lip_make_fail
    lea rdi, [rip + dia]
    mov rsi, rbx
    call pd_alloc_slot
    cmp qword ptr [rax + DTS_state], DTS_INITIALIZED
    jne 1b
    mov rax, rbx
    EPILOGUE
.Lip_make_fail:
    mov edi, 73
    SYS SYS_exit_group

.section .rodata
xfer_budgets: .quad 2,3,4096,65536
xfer_capacities: .quad 1,3,4096,65536

.text
# Actual parser setup precedes all bounded transfer calls and is helper-only.
FN xfer_native_export
    mov qword ptr [rip + xfer_stage], 1
    PROLOGUE 16
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lxpe_fail
    mov r15, rax
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + probe_cases]
    add rax, rcx
    mov rdi, [rax]
    mov rsi, [rax + 8]
    mov rdx, r15
    cmp r12, GPC_MANAGED_COUNT
    jb 1f
    call grammar_parse_prepare_legacy
    jmp 2f
1:  call grammar_parse_prepare
2:  test rax, rax
    jz .Lxpe_fail
    mov r14, rax
    # Capture scalar expectations from the actual native parser before it dies.
    mov rax, [r14 + GP_name_len]
    mov [rip + xfer_expected_name_len], rax
    mov rax, [r14 + GP_rules]
    mov [rip + xfer_expected_rules], rax
    call xfer_assert_native_fields
    test r12, r12
    jnz 9f
    call xfer_export_api_matrix
9:  call xfer_capture_queries
    call xfer_capture_tokens
    call xfer_export_check
    mov rdi, r14
    call grammar_prepare_release
    mov rdi, r15
    call ext_prepare_owner_release
    EPILOGUE
FN xfer_export_check
    mov qword ptr [rip + xfer_stage], 2
    PROLOGUE
    mov rax, r12
    shl rax, 4
    lea rbx, [rip + expected]
    add rbx, rax
    mov [rip + req], r14
    mov rax, [r14 + GP_legacy]
    inc rax
    mov [rip + req + 8], rax
    mov [rip + req + 16], r12
    mov rax, r12
    shl rax, 4
    lea rcx, [rip + probe_cases]
    mov rax, [rcx + rax + 8]
    mov [rip + req + 24], rax
    mov qword ptr [rip + req + 32], 0
    lea rdi, [rip + pge]
    mov esi, 0xa5
    mov edx, PGE_SIZE
    call memset
    mov qword ptr [rip + pge + PGE_state], PGE_NEW
    lea rdi, [rip + pge]
    lea rsi, [rip + req]
    call pg_export_begin
    test rax, rax
    jne .Lxpe_fail
.Lxpe_measure:
    lea rdi, [rip + pge]
    mov esi, 65536
    mov rsi, [rip + xfer_measure_budget]
    mov qword ptr [rip + xfer_active], 1
    mov qword ptr [rip + xfer_byte_actual], 0
    mov qword ptr [rip + xfer_unit_actual], 0
    call pg_export_measure_step
    mov qword ptr [rip + xfer_active], 0
    cmp rdx, [rip + xfer_byte_actual]
    jne .Lxpe_fail
    cmp rcx, [rip + xfer_unit_actual]
    jne .Lxpe_fail
    cmp rdx, [rip + xfer_measure_budget]
    ja .Lxpe_fail
    cmp rcx, 16
    ja .Lxpe_fail
    test rax, rax
    js .Lxpe_fail
    jnz .Lxpe_measure
    mov qword ptr [rip + position], 0
.Lxpe_export:
    lea rdi, [rip + output_guard_before]
    mov esi, 0xa5
    mov edx, 32
    call memset
    lea rdi, [rip + output]
    add rdi, [rip + xfer_capacity]
    mov esi, 0xa5
    mov edx, 32
    call memset
    mov qword ptr [rip + xfer_output_actual], 0
    lea rdi, [rip + pge]
    lea rsi, [rip + output]
    mov rdx, [rip + xfer_capacity]
    mov ecx, 65536
    mov rcx, [rip + xfer_budget]
    mov qword ptr [rip + xfer_active], 2
    mov qword ptr [rip + xfer_byte_actual], 0
    mov qword ptr [rip + xfer_unit_actual], 0
    call pg_export_emit_step
    mov qword ptr [rip + xfer_active], 0
    cmp rdx, [rip + xfer_capacity]
    ja .Lxpe_fail
    cmp rdx, [rip + xfer_output_actual]
    jne .Lxpe_fail
    cmp rcx, [rip + xfer_byte_actual]
    jne .Lxpe_fail
    cmp r8, [rip + xfer_unit_actual]
    jne .Lxpe_fail
    cmp rcx, [rip + xfer_budget]
    ja .Lxpe_fail
    cmp r8, 16
    ja .Lxpe_fail
    test rax, rax
    js .Lxpe_fail
    mov r13, rax
    lea rdi, [rip + output]
    mov rsi, rdx
    mov rcx, rdx
    mov rdx, [rbx]
    add rdx, [rip + position]
    add [rip + position], rcx
    call str_eq
    test eax, eax
    jz .Lxpe_fail
    lea rax, [rip + output_guard_before]
    mov r9d, 2
.Lxpe_guards:
    mov ecx, 4
1:  mov rdx, 0xa5a5a5a5a5a5a5a5
    cmp [rax], rdx
    jne .Lxpe_fail
    add rax, 8
    dec rcx
    jnz 1b
    dec r9
    jz 2f
    lea rax, [rip + output]
    add rax, [rip + xfer_capacity]
    jmp .Lxpe_guards
2:  test r13, r13
    jnz .Lxpe_export
    mov rax, [rip + position]
    cmp rax, [rbx + 8]
    jne .Lxpe_fail
    mov rax, [rip + pge + PGE_gp]
    mov [rip + xfer_saved_gp], rax
    mov qword ptr [rip + pge + PGE_gp], 1
    lea rdi, [rip + pge]
    mov esi, 1
    call pg_export_measure_step
    test rax, rax
    jne .Lxpe_fail
    or rdx, rcx
    jnz .Lxpe_fail
    lea rdi, [rip + pge]
    lea rsi, [rip + output]
    mov edx, 1
    mov ecx, 2
    call pg_export_emit_step
    test rax, rax
    jne .Lxpe_fail
    or rdx, rcx
    or rdx, r8
    jnz .Lxpe_fail
    mov rax, [rip + xfer_saved_gp]
    mov [rip + pge + PGE_gp], rax
    EPILOGUE
.Lxpe_fail:
    mov [rip + scratch], rax
    mov [rip + scratch + 8], r12
    mov [rip + scratch + 16], r13
    mov [rip + scratch + 24], r14
    mov rax, [rip + xfer_stage]
    mov [rip + scratch + 32], rax
    mov rax, [rip + pgi + PGI_phase]
    mov [rip + scratch + 40], rax
    mov edi, 2
    lea rsi, [rip + scratch]
    mov edx, 48
    call write_all
    mov edi, 73
    SYS SYS_exit_group

.text
# All native lease values below are actual checked handles, never wire fields.
FN xfer_lease_open
    mov qword ptr [rip + xfer_stage], 3
    PROLOGUE
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    call ext_root_open
    test rax, rax
    js .Lxpe_fail
    test rdx, rdx
    jne .Lxpe_fail
    mov [rip + xfer_payload], rax
    mov rdi, rax
    lea rsi, [rip + xfer_lease_name]
    mov edx, ER_FILE
    xor ecx, ecx
    xor r8d, r8d
    call ext_root_open_at
    test rax, rax
    js .Lxpe_fail
    test rdx, rdx
    jne .Lxpe_fail
    EPILOGUE
FN xfer_lease_setup
    mov qword ptr [rip + xfer_stage], 4
    PROLOGUE
    call xfer_lease_open
    mov r12, rax
    mov rdi, rax
    xor esi, esi
    call ext_store_raw_lock
    test rax, rax
    jne .Lxpe_fail
    mov rax, [rip + dia + DIA_eo]
    cmp qword ptr [rax + EO_lease], -1
    jne .Lxpe_fail
    mov [rax + EO_lease], r12
    EPILOGUE
FN xfer_lease_probe
    mov qword ptr [rip + xfer_stage], 5
    PROLOGUE
    call xfer_lease_open
    mov r12, rax
    mov rdi, rax
    mov esi, 1
    call ext_store_raw_lock
    mov r13, rax
    mov rdi, r12
    call ext_root_close
    test rax, rax
    jne .Lxpe_fail
    cmp rdx, 1
    jne .Lxpe_fail
    mov rdi, [rip + xfer_payload]
    call ext_root_close
    test rax, rax
    jne .Lxpe_fail
    cmp rdx, 1
    jne .Lxpe_fail
    xor eax, eax
    test r13, r13
    jz 1f
    cmp r13, -11
    jne .Lxpe_fail
    mov eax, 75
1:  EPILOGUE
FN xfer_doc_lifetime
    mov qword ptr [rip + xfer_stage], 6
    PROLOGUE
    mov r14, [rip + xfer_doc_gp]
    cmp qword ptr [r14 + PO_refs], 1
    jne .Lxpe_fail
    mov rax, [r14 + PO_eo]
    cmp qword ptr [rax + EO_refs], 1
    jne .Lxpe_fail
    cmp qword ptr [rax + EO_lease], 0
    jl .Lxpe_fail
    cmp qword ptr [rip + dia + DIA_state], DIA_EMPTY
    jne .Lxpe_fail
    cmp qword ptr [rip + prep_total_charge], 0
    je .Lxpe_fail
    mov byte ptr [rip + scratch], 'R'
    mov edi, 1
    lea rsi, [rip + scratch]
    mov edx, 1
    call write_all
    xor edi, edi
    lea rsi, [rip + scratch]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lxpe_fail
    cmp byte ptr [rip + scratch], 'G'
    jne .Lxpe_fail
    call xfer_compare_queries
    call xfer_compare_tokens
    call xfer_export_check
    mov byte ptr [rip + scratch], 'V'
    mov edi, 1
    lea rsi, [rip + scratch]
    mov edx, 1
    call write_all
    xor edi, edi
    lea rsi, [rip + scratch]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lxpe_fail
    cmp byte ptr [rip + scratch], 'D'
    jne .Lxpe_fail
    cmp qword ptr [rip + xfer_lifetime], 1
    jne 3f
    mov rax, [r14 + PO_eo]
    mov rax, [rax + EO_lease]
    mov [rip + xfer_l_release_raw], rax
3:  cmp qword ptr [rip + xfer_lifetime], 2
    jne 2f
    mov rax, [r14 + PO_eo]
    mov [rip + xfer_unknown_eo], rax
    mov rax, [rax + EO_lease]
    mov [rip + xfer_unknown_raw], rax
2:  mov rdi, r14
    call grammar_prepare_release_deferred
    test rax, rax
    jne .Lxpe_fail
    cmp rdx, 1
    jne .Lxpe_fail
    mov qword ptr [rip + xfer_doc_gp], 0
    EPILOGUE
.section .rodata
xfer_lease_name: .asciz "lease"

.text
FN xfer_capture_tokens
    PROLOGUE
    lea rdi, [r14 + GP_gr]
    lea rsi, [rip + xfer_token_line]
    mov edx, XFER_TOKEN_LENGTH
    xor ecx, ecx
    lea r8, [rip + xfer_tokens_expected]
    call tokenize
    mov [rip + xfer_token_state], rax
    lea rdi, [r14 + GP_gr]
    lea rsi, [rip + xfer_token_line]
    mov edx, XFER_TOKEN_LENGTH
    xor ecx, ecx
    cmp qword ptr [r14 + GP_gr + GR_regions + VEC_len], 0
    je 1f
    inc ecx
1:  lea r8, [rip + xfer_tokens_expected + 512]
    call tokenize
    mov [rip + xfer_token_state + 8], rax
    EPILOGUE
FN xfer_compare_tokens
    PROLOGUE
    lea rdi, [r14 + GP_gr]
    lea rsi, [rip + xfer_token_line]
    mov edx, XFER_TOKEN_LENGTH
    xor ecx, ecx
    lea r8, [rip + xfer_tokens_actual]
    call tokenize
    cmp rax, [rip + xfer_token_state]
    jne .Lxpe_fail
    lea rdi, [r14 + GP_gr]
    lea rsi, [rip + xfer_token_line]
    mov edx, XFER_TOKEN_LENGTH
    xor ecx, ecx
    cmp qword ptr [r14 + GP_gr + GR_regions + VEC_len], 0
    je 1f
    inc ecx
1:  lea r8, [rip + xfer_tokens_actual + 512]
    call tokenize
    cmp rax, [rip + xfer_token_state + 8]
    jne .Lxpe_fail
    lea rdi, [rip + xfer_tokens_expected]
    lea rsi, [rip + xfer_tokens_actual]
    mov edx, XFER_TOKEN_LENGTH
    call memeq
    test eax, eax
    jz .Lxpe_fail
    lea rdi, [rip + xfer_tokens_expected + 512]
    lea rsi, [rip + xfer_tokens_actual + 512]
    mov edx, XFER_TOKEN_LENGTH
    call memeq
    test eax, eax
    jz .Lxpe_fail
    EPILOGUE
.section .rodata
xfer_token_line:
    .asciz "Alpha beta Gamma Abc abc foo BAR if return class std printf 123 0xff $value @var # // comment /* block */ \"string\" 'c' + -= []{}() <> ; é É Σ σ Б б\n"
xfer_token_line_end:
.if XFER_TOKEN_LENGTH > 512
.error "token fixture exceeds fixed output"
.endif

.text
# One injected unobserved close result retains the exact live native lease.
FN ext_root_close
    cmp qword ptr [rip + xfer_lifetime], 2
    jne xfer_close_real
    cmp rdi, [rip + xfer_unknown_raw]
    jne xfer_close_real
    cmp qword ptr [rip + xfer_unknown_close_calls], 0
    jne .Lxpe_fail
    inc qword ptr [rip + xfer_unknown_close_calls]
    mov rax, -5
    mov edx, 2
    ret
FN xfer_unknown_proof
    PROLOGUE
    mov r12, [rip + xfer_unknown_eo]
    mov rax, [r12 + EO_lease]
    cmp rax, [rip + xfer_unknown_raw]
    jne .Lxpe_fail
    cmp qword ptr [r12 - RD_SIZE + RD_state], RD_BLOCKED_UNKNOWN + (1 << RDF_UNKNOWN_BASE)
    jne .Lxpe_fail
    cmp qword ptr [r12 - RD_SIZE + RD_diagnostic], -5
    jne .Lxpe_fail
    mov rdi, r12
    sub rdi, RD_SIZE
    call prep_pointer_charge
    cmp rax, [r12 + EO_used]
    jne .Lxpe_fail
    cmp rax, [rip + prep_total_charge]
    jne .Lxpe_fail
    mov rcx, [rip + xfer_baseline_live]
    inc rcx
    cmp [rip + g_mem_live], rcx
    jne .Lxpe_fail
    mov edi, 4
    lea rsi, [rip + scratch]
    call ext_prepare_retire_step
    test rax, rax
    jz .Lxpe_fail
    mov edi, 4
    call ext_prepare_retire_retry_known
    cmp qword ptr [rip + xfer_unknown_close_calls], 1
    jne .Lxpe_fail
    mov byte ptr [rip + scratch], 'Q'
    mov edi, 1
    lea rsi, [rip + scratch]
    mov edx, 1
    call write_all
    xor edi, edi
    lea rsi, [rip + scratch]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lxpe_fail
    cmp byte ptr [rip + scratch], 'U'
    jne .Lxpe_fail
    cmp qword ptr [rip + xfer_unknown_close_calls], 1
    jne .Lxpe_fail
    EPILOGUE

.text
# Normative fixture caller issuer. Exhaustion never resets or restores a generation.
FN xfer_issue_generation
    xor eax, eax
    mov rdx, -EV_RESOURCE
    cmp qword ptr [rdi], -1
    je 1f
    inc qword ptr [rdi]
    mov rax, [rdi]
    xor edx, edx
1:  ret

.include "discovery-gp-transfer-api.inc"

.text
# Runtime lookup through the actual physical native table, including misses.
FN xfer_query_class
    PROLOGUE
    call xfer_native_word_slot
    test rax, rax
    jz .Lxpe_fail
    cmp qword ptr [rax + W_ptr], 0
    je 1f
    mov eax, [rax + W_class]
    EPILOGUE
1:  mov rax, -1
    EPILOGUE
FN xfer_capture_queries
    PROLOGUE 16
    mov qword ptr [rip + xfer_query_count], 0
    mov qword ptr [rip + xfer_query_used], 0
    xor r13d, r13d
    xor r15d, r15d
    mov rbx, [r14 + GP_gr + GR_words]
1:  cmp r13, [r14 + GP_gr + GR_wcap]
    jae 2f
    mov rax, r13
    shl rax, 4
    cmp qword ptr [rbx + rax + W_ptr], 0
    je 9f
    inc r15
9:  inc r13
    jmp 1b
2:  cmp r15, 16
    jbe 3f
    sub r15, 8
    jmp 4f
3:  mov r15d, 8
4:  mov [rsp], r15
    xor r13d, r13d
    mov qword ptr [rsp + 8], 0
.Lxq_scan:
    cmp r13, [r14 + GP_gr + GR_wcap]
    jae .Lxq_capture_done
    mov rax, r13
    shl rax, 4
    add rax, rbx
    cmp qword ptr [rax + W_ptr], 0
    je .Lxq_next
    mov rcx, [rsp + 8]
    inc qword ptr [rsp + 8]
    cmp rcx, 8
    jb .Lxq_take
    cmp rcx, [rsp]
    jb .Lxq_next
.Lxq_take:
    mov rsi, [rax + W_ptr]
    mov edx, [rax + W_len]
    mov r15, [rip + xfer_query_count]
    cmp r15, 16
    jae .Lxpe_fail
    shl r15, 5
    lea rcx, [rip + xfer_queries]
    add r15, rcx
    mov [r15 + 8], rdx
    lea rdi, [rip + xfer_query_pool]
    mov rax, [rip + xfer_query_used]
    mov [r15], rax
    add rax, rdx
    cmp rax, 2097168
    ja .Lxpe_fail
    mov [rip + xfer_query_used], rax
    add rdi, [r15]
    call memcpy
    lea rdi, [r14 + GP_gr]
    lea rsi, [rip + xfer_query_pool]
    add rsi, [r15]
    mov rdx, [r15 + 8]
    call xfer_query_class
    mov [r15 + 16], rax
    lea r12, [rip + xfer_query_pool]
    add r12, [r15]
    XFER_TOGGLE_QUERY
    lea rdi, [r14 + GP_gr]
    mov rsi, r12
    mov rdx, [r15 + 8]
    call xfer_query_class
    mov [r15 + 24], rax
    XFER_TOGGLE_QUERY
    inc qword ptr [rip + xfer_query_count]
.Lxq_next:
    inc r13
    jmp .Lxq_scan
.Lxq_capture_done:
    EPILOGUE
FN xfer_compare_queries
    PROLOGUE
    xor r13d, r13d
.Lxq_compare:
    cmp r13, [rip + xfer_query_count]
    jae .Lxq_compare_done
    mov r15, r13
    shl r15, 5
    lea rcx, [rip + xfer_queries]
    add r15, rcx
    lea r12, [rip + xfer_query_pool]
    add r12, [r15]
    lea rdi, [r14 + GP_gr]
    mov rsi, r12
    mov rdx, [r15 + 8]
    call xfer_query_class
    cmp rax, [r15 + 16]
    jne .Lxpe_fail
    XFER_TOGGLE_QUERY
    lea rdi, [r14 + GP_gr]
    mov rsi, r12
    mov rdx, [r15 + 8]
    call xfer_query_class
    XFER_TOGGLE_QUERY
    cmp rax, [r15 + 24]
    jne .Lxpe_fail
    inc r13
    jmp .Lxq_compare
.Lxq_compare_done:
    EPILOGUE

.text
# These fields are not all serialized. Compare actual native products directly.
FN xfer_assert_native_fields
    mov rax, [r14 + GP_name_len]
    cmp rax, [rip + xfer_expected_name_len]
    jne .Lxpe_fail
    mov rax, [r14 + GP_rules]
    cmp rax, [rip + xfer_expected_rules]
    jne .Lxpe_fail
    cmp qword ptr [r14 + GP_gr + GR_src], 0
    jne .Lxpe_fail
    cmp qword ptr [r14 + GP_gr + GR_srclen], 0
    jne .Lxpe_fail
    cmp qword ptr [r14 + GP_gr + GR_ficon], 0
    jne .Lxpe_fail
    ret

.text
# L only. All ordinary retirement/census checks precede this keepalive gate.
FN xfer_l_success_wait
    PROLOGUE
    mov rax, [rip + xfer_l_omitted_close_count]
    cmp rax, 1
    ja .Lxpe_fail
    mov byte ptr [rip + scratch], 'F'
    mov [rip + scratch + 1], al
    mov edi, 1
    lea rsi, [rip + scratch]
    mov edx, 2
    call write_all
    test rax, rax
    js .Lxpe_fail
    xor edi, edi
    lea rsi, [rip + scratch]
    mov edx, 1
    SYS SYS_read
    cmp rax, 1
    jne .Lxpe_fail
    cmp byte ptr [rip + scratch], 'E'
    jne .Lxpe_fail
    EPILOGUE
