.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
capture: .zero SB_SIZE
accept: .quad 0
platform_calls: .quad 0
last_ptr: .quad 0
.text
# check(doc, text, len, pairs, count) -> bool, comparing all oriented selections.
check:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    call doc_len
    cmp rax, r13
    jne .Lcheck_bad
    lea rdi, [r13 + 1]
    call mem_alloc
    mov [rsp], rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    mov rcx, rax
    call doc_copy
    mov rdi, [rsp]
    mov rsi, r12
    mov rdx, r13
    call memeq
    mov [rsp + 8], rax
    mov rdi, [rsp]
    call mem_free
    cmp qword ptr [rsp + 8], 0
    je .Lcheck_bad
    mov rdi, rbx
    call doc_selections_count
    cmp rax, r15
    jne .Lcheck_bad
    mov qword ptr [rsp + 16], 0
1:  mov rsi, [rsp + 16]
    cmp rsi, r15
    jae .Lcheck_ok
    mov rdi, rbx
    call doc_selections_get
    test r8d, r8d
    jz .Lcheck_bad
    cmp rax, [r14 + DMP_cur]
    jne .Lcheck_bad
    cmp rdx, [r14 + DMP_anchor]
    jne .Lcheck_bad
    add r14, DMP_SIZE
    inc qword ptr [rsp + 16]
    jmp 1b
.Lcheck_ok:
    mov eax, 1
    EPILOGUE
.Lcheck_bad:
    xor eax, eax
    EPILOGUE


capture_clip:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov [rip + last_ptr], rdi
    inc qword ptr [rip + platform_calls]
    lea rdi, [rip + capture]
    call sb_clear
    lea rdi, [rip + capture]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    mov rax, [rip + accept]
    EPILOGUE
no_clipboard:
    ret

FN main
    PROLOGUE 112
    mov qword ptr [rip + accept], 1
    mov rax, [rip + g_plat + P_clip_set]
    mov [rsp + 64], rax
    lea rax, [rip + capture_clip]
    mov [rip + g_plat + P_clip_set], rax
    lea rdi, [rip + capture]
    mov esi, 2048
    call sb_reserve
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    lea r12, [rip + vectors]
    mov r13d, 1
.Lvector:
    cmp qword ptr [r12], 0
    je .Ldone
    mov r15, [rip + g_mem_live]
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    mov rdx, [r12]
    mov rcx, [r12 + 8]
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    mov rsi, [r12 + 8]
    lea rdx, [rip + letter]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    call doc_undo
    mov rdi, rbx
    mov rsi, [r12 + 16]
    mov rdx, [r12 + 24]
    call doc_selections_set
    cmp eax, 1
    jne failed
    xor edi, edi
    xor esi, esi
    call snippet_new
    mov [rbx + DOC_snippet], rax
    mov rdi, rax
    mov esi, SN_SIZE
    call mem_dup
    mov [rsp + 24], rax
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 8], rax
    mov rdi, rbx
    call doc_selections_snapshot
    mov [rsp + 16], rax
    mov qword ptr [rsp], 0
.Lplan:
    mov rdi, rbx
    mov rsi, [rsp]
    mov rdx, [r12 + 40]
    call editor_clip_plan_new_limited
    test rax, rax
    jz failed
    test edx, edx
    jnz failed
    mov r14, rax
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_selections]
    mov rsi, [rsp + 16]
    mov rdx, [r12 + 24]
    dec rdx
    shl rdx, 4
    test rdx, rdx
    jz 1f
    add rdx, DMS_DATA
    call memeq
    test eax, eax
    jz failed
1:  mov rdi, [rbx + DOC_snippet]
    mov rsi, [rsp + 24]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rax, [r12 + 40]
    cmp rax, [r14 + ECP_text + SB_len]
    jne failed
    mov rdi, [r14 + ECP_text + SB_ptr]
    mov rsi, [r12 + 32]
    mov rdx, rax
    call memeq
    test eax, eax
    jz failed
    mov rax, [r14 + ECP_metadata]
    mov rcx, [r12 + 56]
    cmp [rax + ECM_count], rcx
    jne failed
    mov rdx, [r12 + 40]
    cmp [rax + ECM_total], rdx
    jne failed
    lea rdi, [rax + ECM_segments]
    mov rsi, [r12 + 48]
    mov rdx, rcx
    shl rdx, 4
    call memeq
    test eax, eax
    jz failed
    cmp qword ptr [rsp], 0
    jne .Lapply
    mov rdi, r14
    call editor_clip_plan_free
    # One byte below the measured aggregate must fail during pure preparation.
    mov rdi, rbx
    xor esi, esi
    mov rdx, [r12 + 40]
    dec rdx
    call editor_clip_plan_new_limited
    test rax, rax
    jnz failed
    cmp edx, 2
    jne failed
    mov qword ptr [rsp], 1
    jmp .Lplan
.Lapply:
    mov rax, [r12 + 88]
    cmp rax, [r14 + ECP_ncuts]
    jne failed
    # Accepted Copy changes no DOC/SN/history state and publishes exact piece metadata.
    mov rdi, rbx
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne failed
    test edx, edx
    jnz failed
    mov rax, [rip + capture + SB_len]
    cmp rax, [r12 + 40]
    jne failed
    mov rdi, [rip + capture + SB_ptr]
    mov rsi, [r12 + 32]
    mov rdx, rax
    call memeq
    test eax, eax
    jz failed
    mov rdi, [r12 + 32]
    mov rsi, [r12 + 40]
    call editor_clip_segments_get
    test rax, rax
    jz failed
    mov [rsp + 40], rax
    mov rcx, [r12 + 56]
    cmp [rax + ECM_count], rcx
    jne failed
    lea rdi, [rax + ECM_segments]
    mov rsi, [r12 + 48]
    mov rdx, rcx
    shl rdx, 4
    call memeq
    test eax, eax
    jz failed
    mov rax, [r14 + ECP_line]
    cmp eax, [rip + g_clip_line]
    jne failed
    # A rejected Cut must retain the existing cache, metadata, redo, and live snippet.
    mov qword ptr [rip + accept], 0
    mov rdi, rbx
    mov esi, 1
    call editor_multi_copy
    test eax, eax
    jnz failed
    cmp edx, 5
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_snippet]
    mov rsi, [rsp + 24]
    mov edx, SN_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rbx + DOC_selections]
    mov rsi, [rsp + 16]
    mov rdx, [r12 + 24]
    dec rdx
    shl rdx, 4
    test rdx, rdx
    jz 20f
    add rdx, DMS_DATA
    call memeq
    test eax, eax
    jz failed
20: mov rdi, [r12 + 32]
    mov rsi, [r12 + 40]
    call editor_clip_segments_get
    cmp rax, [rsp + 40]
    jne failed
    mov rax, [r14 + ECP_line]
    cmp eax, [rip + g_clip_line]
    jne failed
    mov qword ptr [rip + accept], 1
    call cmd_cut
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 64]
    mov rdx, [r12 + 72]
    mov rcx, [r12 + 80]
    mov r8, [r12 + 88]
    call check
    test eax, eax
    jz failed
    cmp qword ptr [r14 + ECP_nedits], 0
    je .Lfree
    mov qword ptr [rsp + 32], 3
.Lreplay:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12]
    mov rdx, [r12 + 8]
    mov rcx, [r12 + 16]
    mov r8, [r12 + 24]
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    mov rsi, [r12 + 64]
    mov rdx, [r12 + 72]
    mov rcx, [r12 + 80]
    mov r8, [r12 + 88]
    call check
    test eax, eax
    jz failed
    dec qword ptr [rsp + 32]
    jnz .Lreplay
.Lfree:
    mov rdi, r14
    call editor_clip_plan_free
    mov rdi, [rsp + 8]
    call mem_free
    mov rdi, [rsp + 16]
    call mem_free
    mov rdi, [rsp + 24]
    call mem_free
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    # A successful generic write clears segment metadata and returns to the warmed cache size.
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    xor edi, edi
    xor esi, esi
    call editor_clip_segments_get
    test rax, rax
    jnz failed
    cmp r15, [rip + g_mem_live]
    jne failed
    add r12, 96
    inc r13
    jmp .Lvector
.Ldone:
    # Cache invalidation is observable even through empty and non-editor delivery paths.
    mov r13d, 100
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + clip_fixture_s0]
    mov ecx, 5
    xor r8d, r8d
    call doc_insert
    mov r14d, 0
.Lobserve_case:
    mov rdi, rbx
    lea rsi, [rip + clip_fixture_p0]
    mov edx, 2
    call doc_selections_set
    mov rdi, rbx
    xor esi, esi
    call editor_multi_copy
    cmp eax, 1
    jne failed
    lea rdi, [rip + clip_fixture_c0]
    mov esi, 5
    call editor_clip_segments_get
    test rax, rax
    jz failed
    mov [rsp + 40], rax
    mov rax, [rip + last_ptr]
    mov [rsp + 48], rax
    cmp r14d, 0
    jne 1f
    # Failed generic replacement preserves metadata for the accepted text.
    mov qword ptr [rip + accept], 0
    lea rdi, [rip + external_text]
    mov esi, 1
    xor edx, edx
    call ed_clip_set
    test eax, eax
    jnz failed
    lea rdi, [rip + clip_fixture_c0]
    mov esi, 5
    call editor_clip_segments_get
    cmp rax, [rsp + 40]
    jne failed
    mov qword ptr [rip + accept], 1
    # The input aliases the current owned cache, which must be copied before it is replaced.
    mov rdi, [rsp + 48]
    mov esi, 5
    xor edx, edx
    call ed_clip_set
    cmp eax, 1
    jne failed
    jmp .Linvalidated
1:  cmp r14d, 1
    jne 2f
    mov dword ptr [rip + g_focus], FOCUS_FIND
    lea rdi, [rip + external_text]
    mov esi, 1
    call app_on_paste
    jmp .Linvalidated
2:  cmp r14d, 2
    jne 3f
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    xor edi, edi
    xor esi, esi
    call app_on_paste
    jmp .Linvalidated
3:  cmp r14d, 3
    jne 4f
    # Direct editor entry must observe before readonly/empty early returns.
    or dword ptr [rbx + DOC_flags], DF_READONLY
    xor edi, edi
    xor esi, esi
    call ed_paste
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    jmp .Linvalidated
4:  cmp r14d, 4
    jne 5f
    mov qword ptr [rip + g_doc], 0
    xor edi, edi
    xor esi, esi
    call ed_paste
    mov [rip + g_doc], rbx
    jmp .Linvalidated
5:  # Empty queued Vim delivery leaves the accepted clipboard metadata untouched.
    mov rax, [rip + g_plat + P_clip_get]
    mov [rsp + 56], rax
    lea rax, [rip + no_clipboard]
    mov [rip + g_plat + P_clip_get], rax
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + cfg_vim], 1
    call vim_sync
    mov edi, 'p'
    mov esi, 'p'
    xor edx, edx
    call vim_key
    mov rdi, [rip + app_clip_active_token]
    test rdi, rdi
    jz failed
    xor esi, esi
    xor edx, edx
    mov ecx, 1
    call app_clip_complete
    cmp qword ptr [rip + app_clip_active_token], 0
    jne failed
    lea rdi, [rip + clip_fixture_c0]
    mov esi, 5
    call editor_clip_segments_get
    cmp rax, [rsp + 40]
    jne failed
    call editor_clip_segments_clear
    mov dword ptr [rip + cfg_vim], 0
    call vim_sync
    mov rax, [rsp + 56]
    mov [rip + g_plat + P_clip_get], rax
.Linvalidated:
    lea rdi, [rip + clip_fixture_c0]
    mov esi, 5
    call editor_clip_segments_get
    test rax, rax
    jnz failed
    cmp dword ptr [rip + g_clip_line], 0
    jne failed
    inc r14d
    inc r13d
    cmp r14d, 6
    jb .Lobserve_case
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov r14d, 0
.Linvalid_action:
    mov r13d, 110
    add r13d, r14d
    mov rdi, rbx
    lea rsi, [rip + clip_fixture_p0]
    mov edx, 2
    call doc_selections_set
    mov qword ptr [rsp + 80], 1
    mov qword ptr [rsp + 88], 0
    cmp r14d, 2
    jae 1f
    or dword ptr [rbx + DOC_flags], DF_READONLY
    mov qword ptr [rsp + 80], 3
    mov qword ptr [rsp + 88], 1
    test r14d, r14d
    jz 5f
    mov qword ptr [rsp + 80], 0
    mov qword ptr [rsp + 88], 0
    jmp 5f
1:  cmp r14d, 4
    jae 2f
    mov qword ptr [rbx + DOC_selectionbatch], 1
    mov qword ptr [rsp + 80], 4
    cmp r14d, 3
    jne 5f
    mov qword ptr [rsp + 88], 1
    jmp 5f
2:  cmp r14d, 4
    jne 3f
    mov qword ptr [rbx + DOC_cur], 6
3:  cmp r14d, 5
    jne 4f
    mov qword ptr [rip + g_doc], 0
4:  cmp r14d, 6
    jne 6f
    mov qword ptr [rsp + 88], 2
6:  cmp r14d, 7
    jne 5f
    mov qword ptr [rbx + DOC_cur], -1
5:  mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 72], rax
    mov qword ptr [rip + platform_calls], 0
    mov rdi, rbx
    mov rsi, [rsp + 88]
    call editor_multi_copy
    cmp rdx, [rsp + 80]
    jne failed
    test rdx, rdx
    jnz 7f
    cmp eax, 1
    jne failed
    cmp qword ptr [rip + platform_calls], 1
    jne failed
    jmp 8f
7:  test eax, eax
    jnz failed
    cmp qword ptr [rip + platform_calls], 0
    jne failed
8:  mov rdi, rbx
    mov rsi, [rsp + 72]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp + 72]
    call mem_free
    mov [rip + g_doc], rbx
    and dword ptr [rbx + DOC_flags], ~DF_READONLY
    mov qword ptr [rbx + DOC_selectionbatch], 0
    inc r14d
    cmp r14d, 8
    jb .Linvalid_action
    mov r13d, 119
    mov qword ptr [rip + platform_calls], 0
    mov rdi, rbx
    xor esi, esi
    mov edx, DOC_MULTI_BYTES_MAX + 1
    call editor_clip_plan_new_limited
    test rax, rax
    jnz failed
    cmp edx, 2
    jne failed
    cmp qword ptr [rip + platform_calls], 0
    jne failed
    # Whole-line status also stays invalid after an observed mismatch and text restoration.
    mov r13d, 120
    lea rdi, [rip + whole_line]
    mov esi, 2
    mov edx, 1
    call ed_clip_set
    lea rdi, [rip + external_text]
    mov esi, 1
    call ed_clip_observe
    lea rdi, [rip + whole_line]
    mov esi, 2
    call ed_clip_linewise
    test eax, eax
    jnz failed
    mov rdi, rbx
    call doc_free
    mov r13d, 121
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + invalid_utf8]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + invalid_pairs]
    mov edx, 2
    call doc_selections_set
    mov rdi, rbx
    mov esi, DOC_SIZE
    call mem_dup
    mov [rsp + 72], rax
    mov qword ptr [rip + platform_calls], 0
    mov rdi, rbx
    mov esi, 1
    call editor_multi_copy
    test eax, eax
    jnz failed
    cmp edx, 5
    jne failed
    cmp qword ptr [rip + platform_calls], 0
    jne failed
    mov rdi, rbx
    mov rsi, [rsp + 72]
    mov edx, DOC_SIZE
    call memeq
    test eax, eax
    jz failed
    mov rdi, [rsp + 72]
    call mem_free
    mov rdi, rbx
    call doc_free
    # The owner of an outer undo group may edit and finalize selections after Cut.
    mov r13d, 130
    call doc_new
    mov rbx, rax
    mov [rip + g_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + clip_fixture_s0]
    mov ecx, 5
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + clip_fixture_p0]
    mov edx, 2
    call doc_selections_set
    mov rax, [rbx + DOC_undo + VEC_len]
    mov [rsp + 80], rax
    mov rdi, rbx
    call doc_begin_group
    call cmd_cut
    test dword ptr [rbx + DOC_flags], DF_GROUP
    jz failed
    mov rdi, rbx
    mov esi, 1
    lea rdx, [rip + bang]
    mov ecx, 1
    xor r8d, r8d
    call doc_insert
    mov rdi, rbx
    lea rsi, [rip + outer_pairs]
    mov edx, 2
    call doc_selections_set
    mov rdi, rbx
    mov rsi, [rsp + 80]
    call doc_selections_record_after
    mov rdi, rbx
    call doc_end_group
    mov r14d, 3
.Louter_replay:
    mov rdi, rbx
    call doc_undo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + clip_fixture_s0]
    mov edx, 5
    lea rcx, [rip + clip_fixture_p0]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    mov rdi, rbx
    call doc_redo
    cmp eax, 1
    jne failed
    mov rdi, rbx
    lea rsi, [rip + outer_result]
    mov edx, 2
    lea rcx, [rip + outer_pairs]
    mov r8d, 2
    call check
    test eax, eax
    jz failed
    dec r14
    jnz .Louter_replay
    mov rdi, rbx
    call doc_free
    mov qword ptr [rip + g_doc], 0
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call ed_clip_set
    mov rax, [rsp + 64]
    mov [rip + g_plat + P_clip_set], rax
    lea rdi, [rip + capture]
    call sb_free
    lea rdi, [rip + success]
    call log_cstr
    xor eax, eax
    EPILOGUE
failed:
    lea rdi, [rip + failure]
    call log_cstr
    lea rdi, [rip + out]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    mov eax, 1
    EPILOGUE
.section .rodata
success: .asciz "ok editor clipboard planning and actions\n"
failure: .asciz "failed editor clipboard case "
letter: .ascii "x"
external_text: .ascii "B"
whole_line: .ascii "A\n"
invalid_utf8: .byte 0xff
invalid_pairs: .quad 1,0,1,1
outer_pairs: .quad 2,2,0,0
outer_result: .ascii " !"
bang: .ascii "!"
.section .rodata
.p2align 3
vectors:
    .quad clip_fixture_s0,5,clip_fixture_p0,2,clip_fixture_c0,5,clip_fixture_m0,2,clip_fixture_a0,1,clip_fixture_o0,2
    .quad clip_fixture_s1,5,clip_fixture_p1,2,clip_fixture_c1,5,clip_fixture_m1,2,clip_fixture_a1,1,clip_fixture_o1,2
    .quad clip_fixture_s2,5,clip_fixture_p2,2,clip_fixture_c2,5,clip_fixture_m2,2,clip_fixture_a2,1,clip_fixture_o2,2
    .quad clip_fixture_s3,6,clip_fixture_p3,2,clip_fixture_c3,5,clip_fixture_m3,1,clip_fixture_a3,1,clip_fixture_o3,1
    .quad clip_fixture_s4,5,clip_fixture_p4,2,clip_fixture_c4,2,clip_fixture_m4,1,clip_fixture_a4,3,clip_fixture_o4,1
    .quad clip_fixture_s5,4,clip_fixture_p5,2,clip_fixture_c5,5,clip_fixture_m5,2,clip_fixture_a5,0,clip_fixture_o5,1
    .quad clip_fixture_s6,5,clip_fixture_p6,2,clip_fixture_c6,5,clip_fixture_m6,2,clip_fixture_a6,1,clip_fixture_o6,2
    .quad clip_fixture_s7,7,clip_fixture_p7,2,clip_fixture_c7,7,clip_fixture_m7,2,clip_fixture_a7,1,clip_fixture_o7,2
    .quad clip_fixture_s8,8,clip_fixture_p8,2,clip_fixture_c8,7,clip_fixture_m8,2,clip_fixture_a8,2,clip_fixture_o8,1
    .quad clip_fixture_s9,7,clip_fixture_p9,2,clip_fixture_c9,5,clip_fixture_m9,1,clip_fixture_a9,2,clip_fixture_o9,1
    .quad clip_fixture_s10,6,clip_fixture_p10,2,clip_fixture_c10,10,clip_fixture_m10,2,clip_fixture_a10,0,clip_fixture_o10,1
    .quad clip_fixture_s11,6,clip_fixture_p11,2,clip_fixture_c11,10,clip_fixture_m11,2,clip_fixture_a11,0,clip_fixture_o11,1
    .quad clip_fixture_s12,5,clip_fixture_p12,2,clip_fixture_c12,7,clip_fixture_m12,2,clip_fixture_a12,0,clip_fixture_o12,1
    .quad clip_fixture_s13,7,clip_fixture_p13,2,clip_fixture_c13,6,clip_fixture_m13,2,clip_fixture_a13,2,clip_fixture_o13,2
    .quad clip_fixture_s14,3,clip_fixture_p14,2,clip_fixture_c14,5,clip_fixture_m14,2,clip_fixture_a14,0,clip_fixture_o14,1
    .quad clip_fixture_s15,0,clip_fixture_p15,2,clip_fixture_c15,1,clip_fixture_m15,1,clip_fixture_a15,0,clip_fixture_o15,1
    .quad clip_fixture_s16,7,clip_fixture_p16,2,clip_fixture_c16,9,clip_fixture_m16,2,clip_fixture_a16,1,clip_fixture_o16,1
    .quad clip_fixture_s17,1024,clip_fixture_p17,512,clip_fixture_c17,1023,clip_fixture_m17,512,clip_fixture_a17,512,clip_fixture_o17,512
    .quad 0
clip_fixture_s0: .byte 97,98,32,99,100,0
clip_fixture_c0: .byte 97,98,10,99,100,0
clip_fixture_a0: .byte 32,0
clip_fixture_p0: .quad 2,0,5,3
clip_fixture_m0: .quad 0,2,3,2
clip_fixture_o0: .quad 0,0,1,1
clip_fixture_s1: .byte 97,98,32,99,100,0
clip_fixture_c1: .byte 97,98,10,99,100,0
clip_fixture_a1: .byte 32,0
clip_fixture_p1: .quad 5,3,2,0
clip_fixture_m1: .quad 0,2,3,2
clip_fixture_o1: .quad 1,1,0,0
clip_fixture_s2: .byte 97,98,32,99,100,0
clip_fixture_c2: .byte 97,98,10,99,100,0
clip_fixture_a2: .byte 32,0
clip_fixture_p2: .quad 0,2,3,5
clip_fixture_m2: .quad 0,2,3,2
clip_fixture_o2: .quad 0,0,1,1
clip_fixture_s3: .byte 97,98,99,100,101,102,0
clip_fixture_c3: .byte 97,98,99,100,101,0
clip_fixture_a3: .byte 102,0
clip_fixture_p3: .quad 3,0,5,2
clip_fixture_m3: .quad 0,5
clip_fixture_o3: .quad 0,0
clip_fixture_s4: .byte 97,98,32,99,100,0
clip_fixture_c4: .byte 97,98,0
clip_fixture_a4: .byte 32,99,100,0
clip_fixture_p4: .quad 2,0,2,0
clip_fixture_m4: .quad 0,2
clip_fixture_o4: .quad 0,0
clip_fixture_s5: .byte 97,98,99,100,0
clip_fixture_c5: .byte 97,98,10,99,100,0
clip_fixture_a5: .byte 0
clip_fixture_p5: .quad 2,0,4,2
clip_fixture_m5: .quad 0,2,3,2
clip_fixture_o5: .quad 0,0
clip_fixture_s6: .byte 195,169,32,206,169,0
clip_fixture_c6: .byte 195,169,10,206,169,0
clip_fixture_a6: .byte 32,0
clip_fixture_p6: .quad 2,0,5,3
clip_fixture_m6: .quad 0,2,3,2
clip_fixture_o6: .quad 0,0,1,1
clip_fixture_s7: .byte 97,10,98,10,99,10,100,0
clip_fixture_c7: .byte 97,10,98,10,99,10,100,0
clip_fixture_a7: .byte 10,0
clip_fixture_p7: .quad 3,0,7,4
clip_fixture_m7: .quad 0,3,4,3
clip_fixture_o7: .quad 0,0,1,1
clip_fixture_s8: .byte 97,97,10,98,98,10,99,99,0
clip_fixture_c8: .byte 97,97,10,10,98,98,10,0
clip_fixture_a8: .byte 99,99,0
clip_fixture_p8: .quad 1,1,4,4
clip_fixture_m8: .quad 0,3,4,3
clip_fixture_o8: .quad 0,0
clip_fixture_s9: .byte 97,98,99,100,10,101,102,0
clip_fixture_c9: .byte 97,98,99,100,10,0
clip_fixture_a9: .byte 101,102,0
clip_fixture_p9: .quad 1,1,2,2
clip_fixture_m9: .quad 0,5
clip_fixture_o9: .quad 0,0
clip_fixture_s10: .byte 97,98,99,100,101,102,0
clip_fixture_c10: .byte 97,98,10,97,98,99,100,101,102,10,0
clip_fixture_a10: .byte 0
clip_fixture_p10: .quad 2,0,4,4
clip_fixture_m10: .quad 0,2,3,7
clip_fixture_o10: .quad 0,0
clip_fixture_s11: .byte 97,98,99,100,101,102,0
clip_fixture_c11: .byte 97,98,99,100,101,102,10,10,100,101,0
clip_fixture_a11: .byte 0
clip_fixture_p11: .quad 1,1,5,3
clip_fixture_m11: .quad 0,7,8,2
clip_fixture_o11: .quad 0,0
clip_fixture_s12: .byte 97,97,10,98,98,0
clip_fixture_c12: .byte 97,97,10,10,98,98,10,0
clip_fixture_a12: .byte 0
clip_fixture_p12: .quad 1,1,4,4
clip_fixture_m12: .quad 0,3,4,3
clip_fixture_o12: .quad 0,0
clip_fixture_s13: .byte 97,98,99,10,100,101,102,0
clip_fixture_c13: .byte 97,10,100,101,102,10,0
clip_fixture_a13: .byte 98,99,0
clip_fixture_p13: .quad 5,5,1,0
clip_fixture_m13: .quad 0,1,2,4
clip_fixture_o13: .quad 2,2,0,0
clip_fixture_s14: .byte 97,97,10,0
clip_fixture_c14: .byte 97,97,10,10,10,0
clip_fixture_a14: .byte 0
clip_fixture_p14: .quad 1,1,3,3
clip_fixture_m14: .quad 0,3,4,1
clip_fixture_o14: .quad 0,0
clip_fixture_s15: .byte 0
clip_fixture_c15: .byte 10,0
clip_fixture_a15: .byte 0
clip_fixture_p15: .quad 0,0,0,0
clip_fixture_m15: .quad 0,1
clip_fixture_o15: .quad 0,0
clip_fixture_s16: .byte 97,98,99,10,100,101,102,0
clip_fixture_c16: .byte 97,98,99,10,10,99,10,100,101,0
clip_fixture_a16: .byte 102,0
clip_fixture_p16: .quad 1,1,6,2
clip_fixture_m16: .quad 0,4,5,4
clip_fixture_o16: .quad 0,0
clip_fixture_s17: .byte 120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,120,32,0
clip_fixture_c17: .byte 120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,10,120,0
clip_fixture_a17: .byte 32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,32,0
clip_fixture_p17: .quad 1023,1022,1021,1020,1019,1018,1017,1016,1015,1014,1013,1012,1011,1010,1009,1008,1007,1006,1005,1004,1003,1002,1001,1000,999,998,997,996,995,994,993,992,991,990,989,988,987,986,985,984,983,982,981,980,979,978,977,976,975,974,973,972,971,970,969,968,967,966,965,964,963,962,961,960,959,958,957,956,955,954,953,952,951,950,949,948,947,946,945,944,943,942,941,940,939,938,937,936,935,934,933,932,931,930,929,928,927,926,925,924,923,922,921,920,919,918,917,916,915,914,913,912,911,910,909,908,907,906,905,904,903,902,901,900,899,898,897,896,895,894,893,892,891,890,889,888,887,886,885,884,883,882,881,880,879,878,877,876,875,874,873,872,871,870,869,868,867,866,865,864,863,862,861,860,859,858,857,856,855,854,853,852,851,850,849,848,847,846,845,844,843,842,841,840,839,838,837,836,835,834,833,832,831,830,829,828,827,826,825,824,823,822,821,820,819,818,817,816,815,814,813,812,811,810,809,808,807,806,805,804,803,802,801,800,799,798,797,796,795,794,793,792,791,790,789,788,787,786,785,784,783,782,781,780,779,778,777,776,775,774,773,772,771,770,769,768,767,766,765,764,763,762,761,760,759,758,757,756,755,754,753,752,751,750,749,748,747,746,745,744,743,742,741,740,739,738,737,736,735,734,733,732,731,730,729,728,727,726,725,724,723,722,721,720,719,718,717,716,715,714,713,712,711,710,709,708,707,706,705,704,703,702,701,700,699,698,697,696,695,694,693,692,691,690,689,688,687,686,685,684,683,682,681,680,679,678,677,676,675,674,673,672,671,670,669,668,667,666,665,664,663,662,661,660,659,658,657,656,655,654,653,652,651,650,649,648,647,646,645,644,643,642,641,640,639,638,637,636,635,634,633,632,631,630,629,628,627,626,625,624,623,622,621,620,619,618,617,616,615,614,613,612,611,610,609,608,607,606,605,604,603,602,601,600,599,598,597,596,595,594,593,592,591,590,589,588,587,586,585,584,583,582,581,580,579,578,577,576,575,574,573,572,571,570,569,568,567,566,565,564,563,562,561,560,559,558,557,556,555,554,553,552,551,550,549,548,547,546,545,544,543,542,541,540,539,538,537,536,535,534,533,532,531,530,529,528,527,526,525,524,523,522,521,520,519,518,517,516,515,514,513,512,511,510,509,508,507,506,505,504,503,502,501,500,499,498,497,496,495,494,493,492,491,490,489,488,487,486,485,484,483,482,481,480,479,478,477,476,475,474,473,472,471,470,469,468,467,466,465,464,463,462,461,460,459,458,457,456,455,454,453,452,451,450,449,448,447,446,445,444,443,442,441,440,439,438,437,436,435,434,433,432,431,430,429,428,427,426,425,424,423,422,421,420,419,418,417,416,415,414,413,412,411,410,409,408,407,406,405,404,403,402,401,400,399,398,397,396,395,394,393,392,391,390,389,388,387,386,385,384,383,382,381,380,379,378,377,376,375,374,373,372,371,370,369,368,367,366,365,364,363,362,361,360,359,358,357,356,355,354,353,352,351,350,349,348,347,346,345,344,343,342,341,340,339,338,337,336,335,334,333,332,331,330,329,328,327,326,325,324,323,322,321,320,319,318,317,316,315,314,313,312,311,310,309,308,307,306,305,304,303,302,301,300,299,298,297,296,295,294,293,292,291,290,289,288,287,286,285,284,283,282,281,280,279,278,277,276,275,274,273,272,271,270,269,268,267,266,265,264,263,262,261,260,259,258,257,256,255,254,253,252,251,250,249,248,247,246,245,244,243,242,241,240,239,238,237,236,235,234,233,232,231,230,229,228,227,226,225,224,223,222,221,220,219,218,217,216,215,214,213,212,211,210,209,208,207,206,205,204,203,202,201,200,199,198,197,196,195,194,193,192,191,190,189,188,187,186,185,184,183,182,181,180,179,178,177,176,175,174,173,172,171,170,169,168,167,166,165,164,163,162,161,160,159,158,157,156,155,154,153,152,151,150,149,148,147,146,145,144,143,142,141,140,139,138,137,136,135,134,133,132,131,130,129,128,127,126,125,124,123,122,121,120,119,118,117,116,115,114,113,112,111,110,109,108,107,106,105,104,103,102,101,100,99,98,97,96,95,94,93,92,91,90,89,88,87,86,85,84,83,82,81,80,79,78,77,76,75,74,73,72,71,70,69,68,67,66,65,64,63,62,61,60,59,58,57,56,55,54,53,52,51,50,49,48,47,46,45,44,43,42,41,40,39,38,37,36,35,34,33,32,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
clip_fixture_m17: .quad 0,1,2,1,4,1,6,1,8,1,10,1,12,1,14,1,16,1,18,1,20,1,22,1,24,1,26,1,28,1,30,1,32,1,34,1,36,1,38,1,40,1,42,1,44,1,46,1,48,1,50,1,52,1,54,1,56,1,58,1,60,1,62,1,64,1,66,1,68,1,70,1,72,1,74,1,76,1,78,1,80,1,82,1,84,1,86,1,88,1,90,1,92,1,94,1,96,1,98,1,100,1,102,1,104,1,106,1,108,1,110,1,112,1,114,1,116,1,118,1,120,1,122,1,124,1,126,1,128,1,130,1,132,1,134,1,136,1,138,1,140,1,142,1,144,1,146,1,148,1,150,1,152,1,154,1,156,1,158,1,160,1,162,1,164,1,166,1,168,1,170,1,172,1,174,1,176,1,178,1,180,1,182,1,184,1,186,1,188,1,190,1,192,1,194,1,196,1,198,1,200,1,202,1,204,1,206,1,208,1,210,1,212,1,214,1,216,1,218,1,220,1,222,1,224,1,226,1,228,1,230,1,232,1,234,1,236,1,238,1,240,1,242,1,244,1,246,1,248,1,250,1,252,1,254,1,256,1,258,1,260,1,262,1,264,1,266,1,268,1,270,1,272,1,274,1,276,1,278,1,280,1,282,1,284,1,286,1,288,1,290,1,292,1,294,1,296,1,298,1,300,1,302,1,304,1,306,1,308,1,310,1,312,1,314,1,316,1,318,1,320,1,322,1,324,1,326,1,328,1,330,1,332,1,334,1,336,1,338,1,340,1,342,1,344,1,346,1,348,1,350,1,352,1,354,1,356,1,358,1,360,1,362,1,364,1,366,1,368,1,370,1,372,1,374,1,376,1,378,1,380,1,382,1,384,1,386,1,388,1,390,1,392,1,394,1,396,1,398,1,400,1,402,1,404,1,406,1,408,1,410,1,412,1,414,1,416,1,418,1,420,1,422,1,424,1,426,1,428,1,430,1,432,1,434,1,436,1,438,1,440,1,442,1,444,1,446,1,448,1,450,1,452,1,454,1,456,1,458,1,460,1,462,1,464,1,466,1,468,1,470,1,472,1,474,1,476,1,478,1,480,1,482,1,484,1,486,1,488,1,490,1,492,1,494,1,496,1,498,1,500,1,502,1,504,1,506,1,508,1,510,1,512,1,514,1,516,1,518,1,520,1,522,1,524,1,526,1,528,1,530,1,532,1,534,1,536,1,538,1,540,1,542,1,544,1,546,1,548,1,550,1,552,1,554,1,556,1,558,1,560,1,562,1,564,1,566,1,568,1,570,1,572,1,574,1,576,1,578,1,580,1,582,1,584,1,586,1,588,1,590,1,592,1,594,1,596,1,598,1,600,1,602,1,604,1,606,1,608,1,610,1,612,1,614,1,616,1,618,1,620,1,622,1,624,1,626,1,628,1,630,1,632,1,634,1,636,1,638,1,640,1,642,1,644,1,646,1,648,1,650,1,652,1,654,1,656,1,658,1,660,1,662,1,664,1,666,1,668,1,670,1,672,1,674,1,676,1,678,1,680,1,682,1,684,1,686,1,688,1,690,1,692,1,694,1,696,1,698,1,700,1,702,1,704,1,706,1,708,1,710,1,712,1,714,1,716,1,718,1,720,1,722,1,724,1,726,1,728,1,730,1,732,1,734,1,736,1,738,1,740,1,742,1,744,1,746,1,748,1,750,1,752,1,754,1,756,1,758,1,760,1,762,1,764,1,766,1,768,1,770,1,772,1,774,1,776,1,778,1,780,1,782,1,784,1,786,1,788,1,790,1,792,1,794,1,796,1,798,1,800,1,802,1,804,1,806,1,808,1,810,1,812,1,814,1,816,1,818,1,820,1,822,1,824,1,826,1,828,1,830,1,832,1,834,1,836,1,838,1,840,1,842,1,844,1,846,1,848,1,850,1,852,1,854,1,856,1,858,1,860,1,862,1,864,1,866,1,868,1,870,1,872,1,874,1,876,1,878,1,880,1,882,1,884,1,886,1,888,1,890,1,892,1,894,1,896,1,898,1,900,1,902,1,904,1,906,1,908,1,910,1,912,1,914,1,916,1,918,1,920,1,922,1,924,1,926,1,928,1,930,1,932,1,934,1,936,1,938,1,940,1,942,1,944,1,946,1,948,1,950,1,952,1,954,1,956,1,958,1,960,1,962,1,964,1,966,1,968,1,970,1,972,1,974,1,976,1,978,1,980,1,982,1,984,1,986,1,988,1,990,1,992,1,994,1,996,1,998,1,1000,1,1002,1,1004,1,1006,1,1008,1,1010,1,1012,1,1014,1,1016,1,1018,1,1020,1,1022,1
clip_fixture_o17: .quad 511,511,510,510,509,509,508,508,507,507,506,506,505,505,504,504,503,503,502,502,501,501,500,500,499,499,498,498,497,497,496,496,495,495,494,494,493,493,492,492,491,491,490,490,489,489,488,488,487,487,486,486,485,485,484,484,483,483,482,482,481,481,480,480,479,479,478,478,477,477,476,476,475,475,474,474,473,473,472,472,471,471,470,470,469,469,468,468,467,467,466,466,465,465,464,464,463,463,462,462,461,461,460,460,459,459,458,458,457,457,456,456,455,455,454,454,453,453,452,452,451,451,450,450,449,449,448,448,447,447,446,446,445,445,444,444,443,443,442,442,441,441,440,440,439,439,438,438,437,437,436,436,435,435,434,434,433,433,432,432,431,431,430,430,429,429,428,428,427,427,426,426,425,425,424,424,423,423,422,422,421,421,420,420,419,419,418,418,417,417,416,416,415,415,414,414,413,413,412,412,411,411,410,410,409,409,408,408,407,407,406,406,405,405,404,404,403,403,402,402,401,401,400,400,399,399,398,398,397,397,396,396,395,395,394,394,393,393,392,392,391,391,390,390,389,389,388,388,387,387,386,386,385,385,384,384,383,383,382,382,381,381,380,380,379,379,378,378,377,377,376,376,375,375,374,374,373,373,372,372,371,371,370,370,369,369,368,368,367,367,366,366,365,365,364,364,363,363,362,362,361,361,360,360,359,359,358,358,357,357,356,356,355,355,354,354,353,353,352,352,351,351,350,350,349,349,348,348,347,347,346,346,345,345,344,344,343,343,342,342,341,341,340,340,339,339,338,338,337,337,336,336,335,335,334,334,333,333,332,332,331,331,330,330,329,329,328,328,327,327,326,326,325,325,324,324,323,323,322,322,321,321,320,320,319,319,318,318,317,317,316,316,315,315,314,314,313,313,312,312,311,311,310,310,309,309,308,308,307,307,306,306,305,305,304,304,303,303,302,302,301,301,300,300,299,299,298,298,297,297,296,296,295,295,294,294,293,293,292,292,291,291,290,290,289,289,288,288,287,287,286,286,285,285,284,284,283,283,282,282,281,281,280,280,279,279,278,278,277,277,276,276,275,275,274,274,273,273,272,272,271,271,270,270,269,269,268,268,267,267,266,266,265,265,264,264,263,263,262,262,261,261,260,260,259,259,258,258,257,257,256,256,255,255,254,254,253,253,252,252,251,251,250,250,249,249,248,248,247,247,246,246,245,245,244,244,243,243,242,242,241,241,240,240,239,239,238,238,237,237,236,236,235,235,234,234,233,233,232,232,231,231,230,230,229,229,228,228,227,227,226,226,225,225,224,224,223,223,222,222,221,221,220,220,219,219,218,218,217,217,216,216,215,215,214,214,213,213,212,212,211,211,210,210,209,209,208,208,207,207,206,206,205,205,204,204,203,203,202,202,201,201,200,200,199,199,198,198,197,197,196,196,195,195,194,194,193,193,192,192,191,191,190,190,189,189,188,188,187,187,186,186,185,185,184,184,183,183,182,182,181,181,180,180,179,179,178,178,177,177,176,176,175,175,174,174,173,173,172,172,171,171,170,170,169,169,168,168,167,167,166,166,165,165,164,164,163,163,162,162,161,161,160,160,159,159,158,158,157,157,156,156,155,155,154,154,153,153,152,152,151,151,150,150,149,149,148,148,147,147,146,146,145,145,144,144,143,143,142,142,141,141,140,140,139,139,138,138,137,137,136,136,135,135,134,134,133,133,132,132,131,131,130,130,129,129,128,128,127,127,126,126,125,125,124,124,123,123,122,122,121,121,120,120,119,119,118,118,117,117,116,116,115,115,114,114,113,113,112,112,111,111,110,110,109,109,108,108,107,107,106,106,105,105,104,104,103,103,102,102,101,101,100,100,99,99,98,98,97,97,96,96,95,95,94,94,93,93,92,92,91,91,90,90,89,89,88,88,87,87,86,86,85,85,84,84,83,83,82,82,81,81,80,80,79,79,78,78,77,77,76,76,75,75,74,74,73,73,72,72,71,71,70,70,69,69,68,68,67,67,66,66,65,65,64,64,63,63,62,62,61,61,60,60,59,59,58,58,57,57,56,56,55,55,54,54,53,53,52,52,51,51,50,50,49,49,48,48,47,47,46,46,45,45,44,44,43,43,42,42,41,41,40,40,39,39,38,38,37,37,36,36,35,35,34,34,33,33,32,32,31,31,30,30,29,29,28,28,27,27,26,26,25,25,24,24,23,23,22,22,21,21,20,20,19,19,18,18,17,17,16,16,15,15,14,14,13,13,12,12,11,11,10,10,9,9,8,8,7,7,6,6,5,5,4,4,3,3,2,2,1,1,0,0
