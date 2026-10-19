.include "rhun.inc"
.bss
.p2align 3
out: .zero SB_SIZE
.text
FN main
    PROLOGUE 16
    mov rax, [rip + g_mem_live]
    mov [rsp], rax
    lea r12, [rip + cases]
    xor r13d, r13d
.Lcase:
    mov rdi, [r12]
    test rdi, rdi
    jz .Lowned
    mov rsi, [r12 + 8]
    mov rdx, [r12 + 16]
    mov rcx, [r12 + 24]
    mov r8d, 1
    mov r9d, FEAT_SNIPPETS | FEAT_SNIPPET_VARIANTS
    call snippet_decode_fields
    mov rbx, rax
    test rax, rax
    setnz al
    movzx eax, al
    cmp rax, [r12 + 32]
    jne .Lfail
    test rbx, rbx
    jz 2f
    xor ecx, ecx
1:  cmp rcx, [rbx + SN_nfields]
    jae 2f
    imul rax, rcx, SF_SIZE
    test qword ptr [rbx + rax + SN_fields + SF_flags], 64
    jnz .Lfail
    inc rcx
    jmp 1b
2:  mov rdi, rbx
    call snippet_free_node
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp]
    jne .Lfail
    inc r13
    add r12, 40
    jmp .Lcase
.Lowned:
    lea rdi, [rip + record]
    mov esi, record_end - record
    mov edx, FEAT_SNIPPETS | FEAT_SNIPPET_VARIANTS
    call snippet_decode_record
    test rax, rax
    jz .Lfail
    mov rbx, rax
    mov r12, [rbx + SN_choice]
    test r12, r12
    jz .Lfail
    cmp qword ptr [r12 + SC_refs], 1
    jne .Lfail
    cmp qword ptr [rbx + SN_groups + SG_choice], 0
    je .Lfail
    cmp qword ptr [rbx + SN_choicebytes], 27
    jne .Lfail
    mov rdi, rbx
    call snippet_clone_chain
    mov r14, rax
    cmp [r14 + SN_choice], r12
    jne .Lfail
    cmp qword ptr [r12 + SC_refs], 2
    jne .Lfail
    mov rdi, rbx
    call snippet_free_node
    cmp qword ptr [r12 + SC_refs], 1
    jne .Lfail
    # The surviving clone can still decode a literal multiline Unicode option.
    lea rdi, [r12 + SC_DATA + 14]
    lea rsi, [r12 + SC_DATA + 27]
    call snippet_choice_option
    cmp rdx, 1
    jne .Lfail
    cmp byte ptr [rax], 'x'
    jne .Lfail
    mov rdi, rcx
    lea rsi, [r12 + SC_DATA + 27]
    call snippet_choice_option
    test rdx, rdx
    jnz .Lfail
    mov rdi, rcx
    lea rsi, [r12 + SC_DATA + 27]
    call snippet_choice_option
    cmp rdx, 6
    jne .Lfail
    cmp byte ptr [rax + 1], 10
    jne .Lfail
    lea rax, [r12 + SC_DATA + 27]
    cmp rcx, rax
    jne .Lfail
    mov rdi, r14
    call snippet_free_chain
    # Native accepted state owns choices independently of the original wire buffer.
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + text]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    lea rdi, [rip + text]
    mov esi, 3
    lea rdx, [rip + twofields]
    mov ecx, twofields_end - twofields
    mov r8d, 1
    mov r9d, FEAT_SNIPPETS | FEAT_SNIPPET_VARIANTS
    call snippet_decode_fields
    test rax, rax
    jz .Lfail
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call snippet_attach
    cmp qword ptr [r14 + SN_choice_pending], 1
    jne .Lfail
    mov r15, [r14 + SN_activation]
    mov rdi, rbx
    mov esi, 1
    call snippet_step
    cmp qword ptr [r14 + SN_choice_pending], 0
    jne .Lfail
    mov rdi, rbx
    mov esi, -1
    call snippet_step
    cmp qword ptr [r14 + SN_choice_pending], 1
    jne .Lfail
    cmp [r14 + SN_activation], r15
    jbe .Lfail
    # Retained payload totals, not field-local totals, bound nesting.
    lea rdi, [rip + record]
    mov esi, record_end - record
    mov edx, FEAT_SNIPPETS | FEAT_SNIPPET_VARIANTS
    call snippet_decode_record
    mov r12, rax
    mov r15, [r12 + SN_choicebytes]
    mov qword ptr [r12 + SN_choicebytes], SN_BYTES_MAX
    mov rdi, rbx
    mov rsi, r12
    call snippet_can_nest
    test rax, rax
    jnz .Lfail
    mov [r12 + SN_choicebytes], r15
    mov rdi, rbx
    mov rsi, r12
    call snippet_can_nest
    test rax, rax
    jz .Lfail
    mov rdi, r12
    call snippet_free_node
    mov rdi, rbx
    call doc_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp]
    jne .Lfail
    lea rdi, [rip + ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
.Lfail:
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
ok: .asciz "ok snippet choices\n"
failure: .asciz "failed snippet choice case "
text: .ascii "x x"
empty: .ascii ""
choice: .ascii "choice 1 3 13\n"
choice_options: .ascii "1\nx0\n6\na\n😀"
choice_end:
record: .ascii "0 0 0 0 snippet 0 3 0 75\nx xfield 1 0 1 0 0\nfield 1 2 3 0 0\nfield 0 3 3 0 0\nchoice 1 3 13\n1\nx0\n6\na\n😀"
record_end:
valid: .ascii "choice 1 3 13\n1\nx0\n6\na\n😀field 1 0 1 0 0\nfield 1 2 3 0 0\n"
valid_end:
twofields: .ascii "field 1 0 1 0 0\nfield 2 2 3 0 0\nchoice 1 3 13\n1\nx0\n6\na\n😀"
twofields_end:
missing: .ascii "choice 1 1 3\n1\nx"
missing_end:
zero: .ascii "field 1 0 1 0 0\nchoice 0 1 3\n1\nx"
zero_end:
count: .ascii "field 1 0 1 0 0\nchoice 1 0 0\n"
count_end:
excess: .ascii "field 1 0 1 0 0\nchoice 1 257 3\n1\nx"
excess_end:
mismatch: .ascii "field 1 0 1 0 0\nchoice 1 1 3\n1\ny"
mismatch_end:
duplicate: .ascii "field 1 0 1 0 0\nchoice 1 1 3\n1\nxchoice 1 1 3\n1\nx"
duplicate_end:
trailing: .ascii "field 1 0 1 0 0\nchoice 1 1 4\n1\nx!"
trailing_end:
truncated: .ascii "field 1 0 1 0 0\nchoice 1 1 3\n2\nx"
truncated_end:
invalid_utf8: .ascii "field 1 0 1 0 0\nchoice 1 1 3\n1\n\xff"
invalid_utf8_end:
invalid_surrogate: .ascii "field 1 0 1 0 0\nchoice 1 1 5\n3\n\xed\xa0\x80"
invalid_surrogate_end:
no_length: .ascii "field 1 0 1 0 0\nchoice 1 1 2\n\nx"
no_length_end:
overflow: .ascii "field 1 0 1 0 0\nchoice 1 1 13\n4294967297\nx"
overflow_end:
emptyfirst: .ascii "field 1 0 0 0 0\nchoice 1 2 5\n0\n1\nx"
emptyfirst_end:
variant_text: .ascii "x Y"
variant_ok: .ascii "variant 2 0\nfield 1 0 1 0 0\nfield 1 2 3 0 0\n"
variant_ok_end:
variant_primary: .ascii "field 1 0 1 0 0\nvariant 1 0\n"
variant_primary_end:
variant_final: .ascii "field 0 0 1 0 0\nvariant 1 0\n"
variant_final_end:
variant_missing: .ascii "variant 2 0\nfield 1 0 1 0 0\n"
variant_missing_end:
variant_zero: .ascii "variant 0 0\n"
variant_zero_end:
variant_equal: .ascii "field 1 0 1 0 0\nfield 1 2 3 0 0\nvariant 2 0\n"
variant_equal_end:
variant_double: .ascii "field 1 0 1 0 0\nfield 1 2 3 0 0\nvariant 2 0\nvariant 2 0\n"
variant_double_end:
variant_overflow: .ascii "variant 18446744073709551618 0\n"
variant_overflow_end:
variant_zeros: .ascii "variant 00000000000000000000000000000000000000000000000000000000000000002 0\nfield 1 0 1 0 0\nfield 1 2 3 0 0\n"
variant_zeros_end:
.byte 0                       # keep table alignment outside the final record
cases:
.quad text,3,valid,valid_end-valid,1
.quad text,3,missing,missing_end-missing,0
.quad text,3,zero,zero_end-zero,0
.quad text,3,count,count_end-count,0
.quad text,3,excess,excess_end-excess,0
.quad text,3,mismatch,mismatch_end-mismatch,0
.quad text,3,duplicate,duplicate_end-duplicate,0
.quad text,3,trailing,trailing_end-trailing,0
.quad text,3,truncated,truncated_end-truncated,0
.quad text,3,invalid_utf8,invalid_utf8_end-invalid_utf8,0
.quad text,3,invalid_surrogate,invalid_surrogate_end-invalid_surrogate,0
.quad text,3,no_length,no_length_end-no_length,0
.quad text,3,overflow,overflow_end-overflow,0
.quad empty,0,emptyfirst,emptyfirst_end-emptyfirst,1
.quad variant_text,3,variant_ok,variant_ok_end-variant_ok,1
.quad variant_text,3,variant_primary,variant_primary_end-variant_primary,0
.quad variant_text,3,variant_final,variant_final_end-variant_final,0
.quad variant_text,3,variant_missing,variant_missing_end-variant_missing,0
.quad variant_text,3,variant_zero,variant_zero_end-variant_zero,0
.quad text,3,variant_equal,variant_equal_end-variant_equal,0
.quad variant_text,3,variant_double,variant_double_end-variant_double,0
.quad variant_text,3,variant_overflow,variant_overflow_end-variant_overflow,0
.quad variant_text,3,variant_zeros,variant_zeros_end-variant_zeros,1
.quad 0,0,0,0,0
