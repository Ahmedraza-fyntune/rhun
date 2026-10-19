# Pure request safety and semantic checks before any constructor acquisition.
.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extactivation.inc"
.include "app/exthostidentity.inc"
.include "app/extruntimeservice.inc"
.include "app/extruntimeticket.inc"
.text
# table,canonicalRequest80,emptyResult32 -> status, DX outputValidated (NOT disposition).
# DX0 forbids any result store. DX1 proves result safety, even on semantic rejection.
FN rt_ticket_request_check
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .Lttc_api
    mov rax, r12
    add rax, RTQ_SIZE
    jc .Lttc_api
    call rt_table_is_owned
    test eax, eax
    jz .Lttc_api
    mov rdi, r13
    mov esi, RTC_SIZE
    mov rdx, rbx
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lttc_api
    mov rdi, r13
    mov esi, RTC_SIZE
    mov rdx, r12
    mov ecx, RTQ_SIZE
    call rt_spans_disjoint
    test rax, rax
    jnz .Lttc_api
    mov rdx, [rbx + RT_stableExtBase]
    test rdx, rdx
    jz 1f
    mov rdi, r13
    mov esi, RTC_SIZE
    mov ecx, RT_SLOT_COUNT * EXT_SIZE
    call rt_spans_disjoint
    test rax, rax
    jnz .Lttc_api
1:  mov rdi, r13
    mov esi, RTC_SIZE
    mov rdx, [r12 + RTQ_key]
    mov rcx, [r12 + RTQ_keyLen]
    call rt_spans_disjoint
    test rax, rax
    jnz .Lttc_api
    mov rdi, r13
    mov esi, RTC_SIZE
    mov rdx, [r12 + RTQ_title]
    mov rcx, [r12 + RTQ_titleLen]
    call rt_spans_disjoint
    test rax, rax
    jnz .Lttc_api
    mov rdi, r13
    mov esi, RTC_SIZE
    mov rdx, [r12 + RTQ_keys]
    mov rcx, [r12 + RTQ_keysLen]
    call rt_spans_disjoint
    test rax, rax
    jnz .Lttc_api
    mov r14, [r12 + RTQ_ordinal]
    cmp r14, RT_SLOT_COUNT
    jae .Lttc_empty
    imul rax, r14, RT_SLOT_SIZE
    lea r15, [rbx + rax + RT_slots]
    mov rdi, [r15 + RTS_ea]
    test rdi, rdi
    jz 2f
    call ea_is_ready
    test eax, eax
    jz .Lttc_api
    mov rdx, [r15 + RTS_ea]
    mov rdi, r13
    mov esi, RTC_SIZE
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lttc_api
2:  mov rdi, [r15 + RTS_hi]
    test rdi, rdi
    jz .Lttc_empty
    call hi_is_ready
    test eax, eax
    jz .Lttc_api
    mov rdx, [r15 + RTS_hi]
    mov rdi, r13
    mov esi, RTC_SIZE
    call rt_output_disjoint_po
    test rax, rax
    jnz .Lttc_api
.Lttc_empty:
    mov rax, [r13 + RTC_owner]
    or rax, [r13 + RTC_orphanEO]
    or rax, [r13 + RTC_primary]
    or rax, [r13 + RTC_cleanup]
    jnz .Lttc_api
    # From here every refusal may be recorded in the validated empty result.
    cmp r14, RT_SLOT_COUNT
    jae .Lttc_semantic
    cmp qword ptr [r12 + RTQ_kind], RTQ_REGISTER
    jne .Lttc_semantic
    mov rax, [r12 + RTQ_id]
    test rax, rax
    jle .Lttc_semantic
    cmp rax, 0x7fffffff
    ja .Lttc_semantic
    mov rax, [r12 + RTQ_keyLen]
    dec rax
    cmp rax, 39
    ja .Lttc_semantic
    cmp qword ptr [r12 + RTQ_titleLen], 80
    ja .Lttc_semantic
    cmp qword ptr [r12 + RTQ_keysLen], 65536
    ja .Lttc_semantic
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [r12 + RTQ_session]
    call rt_session_check
    test rax, rax
    jnz .Lttc_result
    mov rax, [r15 + RTS_ea]
    cmp qword ptr [rax + PO_refs], -1
    je .Lttc_overflow
    mov rdi, [r12 + RTQ_key]
    xor ecx, ecx
3:  movzx eax, byte ptr [rdi + rcx]
    cmp al, '_'
    je 4f
    sub al, '0'
    cmp al, 9
    jbe 4f
    sub al, 'a' - '0'
    cmp al, 25
    ja .Lttc_semantic
4:  inc rcx
    cmp rcx, [r12 + RTQ_keyLen]
    jb 3b
    mov rdi, [r12 + RTQ_title]
    mov rsi, [r12 + RTQ_titleLen]
    call rt_ticket_no_nul
    test eax, eax
    jz .Lttc_semantic
    mov rdi, [r12 + RTQ_title]
    mov rsi, [r12 + RTQ_titleLen]
    call snippet_utf8_valid
    test eax, eax
    jz .Lttc_semantic
    mov rdi, [r12 + RTQ_keys]
    mov rsi, [r12 + RTQ_keysLen]
    call rt_ticket_no_nul
    test eax, eax
    jz .Lttc_semantic
    xor eax, eax
.Lttc_result:
    mov edx, 1
    EPILOGUE
.Lttc_overflow:
    mov rax, -75
    jmp .Lttc_result
.Lttc_semantic:
    mov rax, -22
    jmp .Lttc_result
.Lttc_api:
    mov rax, -22
    xor edx, edx
    EPILOGUE

# Valid bounded span; zero-length NULL is allowed and never read.
FN rt_ticket_no_nul
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 0
    je 3f
    inc rcx
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret
