.include "rhun.inc"
.section .rodata
# Offset,width,value mutations of the independently authored valid wire below.
cw_mutations:
    .quad 0,8,0
    .quad 8,4,0
    .quad 8,4,2
    .quad 12,4,2
    .quad 12,4,-1
    .quad 16,8,513
    .quad 16,8,-1
    .quad 24,8,6
    .quad 24,8,8
    .quad 24,8,-1
    .quad 32,8,1
    .quad 32,8,-1
    .quad 40,8,1
    .quad 40,8,-1
    .quad 48,8,1
    .quad 48,8,4
    .quad 48,8,8
    .quad 56,8,2
    .quad 56,8,-1
    .quad 64,1,0xff
    .quad -1,0,0
# text,len,line,metadata. Empty pieces, gaps and adjacent pieces are valid.
cw_vectors:
    .quad 0,0,0,0
    .quad 0,0,1,0
    .quad cw_text,7,0,0
    .quad cw_text,7,1,0
    .quad cw_text,7,0,cw_meta
    .quad cw_text,7,1,cw_meta
    .quad cw_text,7,0,cw_gap
    .quad 0,0,0,cw_empty
    .quad -1,0,0,0
cw_encode_bad:
    .quad 0,1,0,0
    .quad 0,67108865,0,0
    .quad cw_text,7,2,0
    .quad cw_text,7,-1,0
    .quad cw_invalid,1,0,0
    .quad cw_text,7,0,cw_count_zero
    .quad cw_text,7,0,cw_count_large
    .quad cw_text,7,0,cw_total_wrong
    .quad cw_text,7,0,cw_overlap
    .quad cw_text,7,0,cw_wrap
    .quad cw_text,7,0,cw_boundary
    .quad -1,0,0,0
cw_golden:
    .ascii "RHUNCLP\0"
    .long 1,0
    .quad 2,7,0,2,3,4
    .byte 0xc3,0xa9,10,0xe6,0xb0,0xb4,0
cw_text: .byte 0xc3,0xa9,10,0xe6,0xb0,0xb4,0
cw_invalid: .byte 0xff
cw_meta: .quad 2,7,0,2,3,4
cw_gap: .quad 3,7,0,0,2,0,6,1
cw_empty: .quad 2,0,0,0,0,0
cw_count_zero: .quad 0,7
cw_count_large: .quad 513,7
cw_total_wrong: .quad 1,8,0,2
cw_overlap: .quad 2,7,0,3,2,1
cw_wrap: .quad 1,7,3,-1
cw_boundary: .quad 1,7,0,1
cw_pairs: .quad 2,0,7,3
cw_ok: .ascii "ok native clipboard wire codec\n"
.bss
.p2align 3
cw_stage: .quad 0
cw_live: .quad 0
cw_wire: .quad 0
cw_len: .quad 0
cw_source: .quad 0
cw_plan: .quad 0
cw_doc: .quad 0
cw_view: .zero CWB_SIZE
cw_zero: .zero CWB_SIZE
cw_buffer: .zero 80
cw_meta_max: .zero ECM_SIZE
.text
cw_fail:
    mov edi, [rip + cw_stage]
    test edi, edi
    jnz 1f
    inc edi
1:  call sys_exit
cw_begin:
    inc qword ptr [rip + cw_stage]
    mov rax, [rip + g_mem_live]
    mov [rip + cw_live], rax
    ret
cw_balanced:
    mov rax, [rip + cw_live]
    cmp rax, [rip + g_mem_live]
    jne cw_fail
    ret
cw_reject_decode:
    PROLOGUE
    lea rdx, [rip + cw_view]
    call clip_wire_decode
    test eax, eax
    jnz cw_fail
    lea rdi, [rip + cw_view]
    lea rsi, [rip + cw_zero]
    mov edx, CWB_SIZE
    call memeq
    test eax, eax
    jz cw_fail
    call cw_balanced
    EPILOGUE
cw_decode:
    PROLOGUE
    mov rdi, [rip + cw_wire]
    mov rsi, [rip + cw_len]
    lea rdx, [rip + cw_view]
    mov rbx, [rip + g_mem_live]
    call clip_wire_decode
    cmp eax, 1
    jne cw_fail
    cmp rbx, [rip + g_mem_live]
    jne cw_fail
    EPILOGUE
cw_free:
    PROLOGUE
    mov rdi, [rip + cw_wire]
    call mem_free
    call cw_balanced
    EPILOGUE
FN main
    PROLOGUE
    # Exact bytes verify an independent format, not just encoder/decoder agreement.
    call cw_begin
    lea rdi, [rip + cw_text]
    mov esi, 7
    xor edx, edx
    lea rcx, [rip + cw_meta]
    call clip_wire_encode
    test rax, rax
    jz cw_fail
    cmp rdx, 71
    jne cw_fail
    mov [rip + cw_wire], rax
    mov [rip + cw_len], rdx
    mov rdi, rax
    lea rsi, [rip + cw_golden]
    call memeq
    test eax, eax
    jz cw_fail
    call cw_decode
    mov rax, [rip + cw_wire]
    lea rcx, [rax + 64]
    cmp rcx, [rip + cw_view + CWB_text]
    jne cw_fail
    add rax, 16
    cmp rax, [rip + cw_view + CWB_metadata]
    jne cw_fail
    call cw_free

    lea r15, [rip + cw_vectors]
.Lcw_vectors:
    cmp qword ptr [r15], -1
    je .Lcw_encode_bad
    call cw_begin
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    mov rcx, [r15 + 24]
    call clip_wire_encode
    test rax, rax
    jz cw_fail
    mov [rip + cw_wire], rax
    mov [rip + cw_len], rdx
    call cw_decode
    mov rax, [r15 + 8]
    cmp rax, [rip + cw_view + CWB_len]
    jne cw_fail
    mov rax, [r15 + 16]
    cmp rax, [rip + cw_view + CWB_line]
    jne cw_fail
    mov rdi, [rip + cw_view + CWB_text]
    mov rsi, [r15]
    mov rdx, [r15 + 8]
    call memeq
    test eax, eax
    jz cw_fail
    mov rsi, [r15 + 24]
    mov rdi, [rip + cw_view + CWB_metadata]
    test rsi, rsi
    jz 1f
    test rdi, rdi
    jz cw_fail
    mov rdx, [rsi + ECM_count]
    shl rdx, 4
    add rdx, ECM_segments
    call memeq
    test eax, eax
    jz cw_fail
    jmp 2f
1:  test rdi, rdi
    jnz cw_fail
2:  call cw_free
    add r15, 32
    jmp .Lcw_vectors
.Lcw_encode_bad:
    lea r15, [rip + cw_encode_bad]
3:  cmp qword ptr [r15], -1
    je .Lcw_mutations
    call cw_begin
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    mov rcx, [r15 + 24]
    call clip_wire_encode
    test rax, rax
    jnz cw_fail
    test rdx, rdx
    jnz cw_fail
    call cw_balanced
    add r15, 32
    jmp 3b
.Lcw_mutations:
    lea r15, [rip + cw_mutations]
4:  cmp qword ptr [r15], -1
    je .Lcw_truncated
    call cw_begin
    lea rdi, [rip + cw_buffer]
    lea rsi, [rip + cw_golden]
    mov edx, 71
    call memcpy
    mov rax, [r15]
    lea rdi, [rip + cw_buffer]
    add rax, rdi
    mov rcx, [r15 + 16]
    cmp qword ptr [r15 + 8], 8
    je 5f
    cmp qword ptr [r15 + 8], 4
    je 6f
    mov [rax], cl
    jmp 7f
5:  mov [rax], rcx
    jmp 7f
6:  mov [rax], ecx
7:  mov esi, 71
    call cw_reject_decode
    add r15, 24
    jmp 4b
.Lcw_truncated:
    xor r15d, r15d
8:  call cw_begin
    lea rdi, [rip + cw_golden]
    mov rsi, r15
    call cw_reject_decode
    inc r15
    cmp r15, 71
    jb 8b
    call cw_begin
    lea rdi, [rip + cw_buffer]
    lea rsi, [rip + cw_golden]
    mov edx, 71
    call memcpy
    lea rdi, [rip + cw_buffer]
    mov esi, 72
    call cw_reject_decode
    xor edi, edi
    mov esi, 32
    call cw_reject_decode
    lea rdi, [rip + cw_golden]
    mov rsi, -1
    call cw_reject_decode
    lea rdi, [rip + cw_golden]
    mov esi, 71
    xor edx, edx
    call clip_wire_decode
    test eax, eax
    jnz cw_fail
    call cw_balanced
    call cw_real_plan
    call cw_maximum
    mov edi, 1
    lea rsi, [rip + cw_ok]
    mov edx, 31
    call write_all
    xor edi, edi
    call sys_exit

cw_real_plan:
    PROLOGUE
    call cw_begin
    call doc_new
    mov [rip + cw_doc], rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + cw_text]
    mov ecx, 7
    xor r8d, r8d
    call doc_insert
    mov rdi, [rip + cw_doc]
    lea rsi, [rip + cw_pairs]
    mov edx, 2
    call doc_selections_set
    cmp eax, 1
    jne cw_fail
    mov rdi, [rip + cw_doc]
    xor esi, esi
    call editor_clip_plan_new
    test rax, rax
    jz cw_fail
    mov [rip + cw_plan], rax
    mov rdi, [rax + ECP_text + SB_ptr]
    mov rsi, [rax + ECP_text + SB_len]
    mov rdx, [rax + ECP_line]
    mov rcx, [rax + ECP_metadata]
    call clip_wire_encode
    test rax, rax
    jz cw_fail
    cmp rdx, 71
    jne cw_fail
    mov [rip + cw_wire], rax
    mov [rip + cw_len], rdx
    mov rdi, rax
    lea rsi, [rip + cw_golden]
    call memeq
    test eax, eax
    jz cw_fail
    # Source plans may be freed before the encoded payload is consumed.
    mov rdi, [rip + cw_plan]
    call editor_clip_plan_free
    mov rdi, [rip + cw_doc]
    call doc_free
    call cw_decode
    mov rdi, [rip + cw_view + CWB_text]
    lea rsi, [rip + cw_text]
    mov edx, 7
    call memeq
    test eax, eax
    jz cw_fail
    call cw_free
    EPILOGUE

cw_maximum:
    PROLOGUE
    call cw_begin
    # 512 empty pieces are valid even with a nil empty source.
    lea rcx, [rip + cw_meta_max]
    mov qword ptr [rcx + ECM_count], DOC_SELECTIONS_MAX
    xor edi, edi
    xor esi, esi
    xor edx, edx
    call clip_wire_encode
    test rax, rax
    jz cw_fail
    cmp rdx, 8224
    jne cw_fail
    mov [rip + cw_wire], rax
    mov [rip + cw_len], rdx
    call cw_decode
    call cw_free
    # Exact wire maximum combines the complete segment table and 64MiB text.
    call cw_begin
    mov edi, DOC_MULTI_BYTES_MAX
    call mem_alloc
    mov [rip + cw_source], rax
    mov rdi, rax
    mov esi, 'a'
    mov edx, DOC_MULTI_BYTES_MAX
    call memset
    lea rcx, [rip + cw_meta_max]
    mov qword ptr [rcx + ECM_total], DOC_MULTI_BYTES_MAX
    mov qword ptr [rcx + ECM_segments + (DOC_SELECTIONS_MAX-1)*ECS_SIZE + ECS_len], DOC_MULTI_BYTES_MAX
    mov rdi, [rip + cw_source]
    mov esi, DOC_MULTI_BYTES_MAX
    mov edx, 1
    call clip_wire_encode
    test rax, rax
    jz cw_fail
    cmp rdx, CLW_MAX
    jne cw_fail
    mov [rip + cw_wire], rax
    mov [rip + cw_len], rdx
    call cw_decode
    cmp qword ptr [rip + cw_view + CWB_len], DOC_MULTI_BYTES_MAX
    jne cw_fail
    cmp qword ptr [rip + cw_view + CWB_line], 1
    jne cw_fail
    mov rdi, [rip + cw_view + CWB_text]
    mov rsi, [rip + cw_source]
    mov edx, DOC_MULTI_BYTES_MAX
    call memeq
    test eax, eax
    jz cw_fail
    mov rdi, [rip + cw_source]
    call mem_free
    call cw_free
    EPILOGUE
