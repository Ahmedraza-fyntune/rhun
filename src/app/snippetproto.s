# Prepared snippet metadata is shared by explicit insertion and completion.
.include "rhun.inc"
.text

# snippet_decode_fields(text, len, extra, extra len, strict, features) -> validated owned SN or 0.
# Preserve the completion parser's current position for the caller.
FN snippet_decode_fields
    PROLOGUE 656
    mov [rsp + 624], r9
    mov qword ptr [rsp + 632], 0
    mov qword ptr [rsp + 640], 0
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov rax, [rip + ps_ptr]
    mov [rsp], rax
    mov rax, [rip + ps_end]
    mov [rsp + 8], rax
    mov rax, [rip + ps_lend]
    mov [rsp + 16], rax
    call snippet_new
    mov rbx, rax
    lea rdi, [rsp + 64]
    xor esi, esi
    mov edx, SB_SIZE
    call memset
    lea rdi, [rsp + 112]
    xor esi, esi
    mov edx, 512
    call memset
    mov [rip + ps_ptr], r12
    add r12, r13
    mov [rip + ps_end], r12
.Lsdf_record:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    je .Lsdf_validate
    mov r15, rax
    call ps_line
    test eax, eax
    jz .Lsdf_bad
    call ps_word
    mov [rsp + 24], rax
    mov [rsp + 32], rdx
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lfield]
    call str_eq_cstr
    test eax, eax
    jz .Lsdf_other
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 24], rax
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 32], rax
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 40], rax
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 48], rax
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    test rax, rax
    jnz .Lsdf_bad
    call ps_eol
    test eax, eax
    jz .Lsdf_bad
    mov rdi, rbx
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 32]
    mov rcx, [rsp + 40]
    mov r8, [rsp + 48]
    call snippet_add
    test eax, eax
    jz .Lsdf_bad
    jmp .Lsdf_record
.Lsdf_other:
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    lea rdx, [rip + .Lchoice]
    call str_eq_cstr
    test eax, eax
    jnz .Lsdf_choice
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    lea rdx, [rip + .Lvariant]
    call str_eq_cstr
    test eax, eax
    jnz .Lsdf_variant
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    lea rdx, [rip + .Ltransforms]
    call str_eq_cstr
    test eax, eax
    jnz .Lsdf_transforms
    test r14, r14
    jnz .Lsdf_bad
    # Unknown completion extras retain their existing length framing.
    mov qword ptr [rsp + 56], 0
1:  call ps_word
    test rdx, rdx
    jz 2f
    mov [rsp + 48], rax
    mov [rsp + 56], rdx
    jmp 1b
2:  mov rsi, [rsp + 56]
    test rsi, rsi
    jz .Lsdf_bad
    mov rdi, [rsp + 48]
    call parse_u64
    cmp rdx, [rsp + 56]
    jne .Lsdf_bad
    mov rcx, [rip + ps_lend]
    inc rcx
    add rcx, rax
    jc .Lsdf_bad
    cmp rcx, [rip + ps_end]
    ja .Lsdf_bad
    mov [rip + ps_ptr], rcx
    jmp .Lsdf_record
.Lsdf_transforms:
    mov rax, [rsp + 624]
    and eax, (1 << FEAT_SNIPPETS) | (1 << FEAT_SNIPPET_TRANSFORMS)
    cmp eax, (1 << FEAT_SNIPPETS) | (1 << FEAT_SNIPPET_TRANSFORMS)
    jne .Lsdf_bad
    cmp qword ptr [rsp + 632], 0
    jne .Lsdf_bad
    call ps_word
    cmp rdx, 1
    jne .Lsdf_bad
    cmp byte ptr [rax], '0'
    jne .Lsdf_bad
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 24], rax
    call ps_eol
    test eax, eax
    jz .Lsdf_bad
    mov rax, [rip + ps_end]
    sub rax, [rip + ps_ptr]
    cmp [rsp + 24], rax
    ja .Lsdf_bad
    mov rdi, [rip + ps_ptr]
    mov rsi, [rsp + 24]
    call snippet_base64_decode
    test ecx, ecx
    jz .Lsdf_bad
    # Empty Base64 cannot contain the mandatory SNTX header. Reject now so
    # the owned pointer also marks presence for duplicate-record detection.
    test rax, rax
    jz .Lsdf_bad
    mov [rsp + 632], rax
    mov [rsp + 640], rdx
    mov rax, [rip + ps_ptr]
    add rax, [rsp + 24]
    mov [rip + ps_ptr], rax
    jmp .Lsdf_record
.Lsdf_variant:
    mov rax, [rsp + 624]
    and eax, (1 << FEAT_SNIPPETS) | (1 << FEAT_SNIPPET_VARIANTS)
    cmp eax, (1 << FEAT_SNIPPETS) | (1 << FEAT_SNIPPET_VARIANTS)
    jne .Lsdf_bad
    call ps_word
    test rdx, rdx
    jz .Lsdf_bad
    # Saturating bounded decimal parser, including arbitrary leading zeroes.
    xor ecx, ecx
1:  movzx esi, byte ptr [rax]
    sub esi, '0'
    cmp esi, 9
    ja .Lsdf_bad
    imul rcx, rcx, 10
    add rcx, rsi
    cmp rcx, SN_FIELDS_MAX
    ja .Lsdf_bad
    inc rax
    dec rdx
    jnz 1b
    test rcx, rcx
    jz .Lsdf_bad
    dec rcx
    cmp byte ptr [rsp + rcx + 112], 0
    jne .Lsdf_bad
    mov byte ptr [rsp + rcx + 112], 1
    call ps_word
    cmp rdx, 1
    jne .Lsdf_bad
    cmp byte ptr [rax], '0'
    jne .Lsdf_bad
    call ps_eol
    test eax, eax
    jz .Lsdf_bad
    jmp .Lsdf_record
.Lsdf_choice:
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    test rax, rax
    jz .Lsdf_bad
    cmp rax, 2147483647
    ja .Lsdf_bad
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 24], rax
    call ps_num
    test edx, edx
    jz .Lsdf_bad
    mov [rsp + 32], rax
    call ps_eol
    test eax, eax
    jz .Lsdf_bad
    mov rax, [rip + ps_end]
    sub rax, [rip + ps_ptr]
    cmp [rsp + 32], rax
    ja .Lsdf_bad
    mov rdi, [rip + ps_ptr]
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 24]
    call snippet_choice_options
    test eax, eax
    jz .Lsdf_bad
    mov rax, [rip + ps_ptr]
    add rax, [rsp + 32]
    mov [rip + ps_ptr], rax
    sub rax, r15
    mov rdx, rax
    add rax, [rsp + 64 + SB_len]
    jc .Lsdf_bad
    cmp rax, SN_BYTES_MAX
    ja .Lsdf_bad
    lea rdi, [rsp + 64]
    mov rsi, r15
    call sb_push
    jmp .Lsdf_record
.Lsdf_validate:
    xor ecx, ecx
1:  cmp rcx, SN_FIELDS_MAX
    jae 3f
    cmp byte ptr [rsp + rcx + 112], 0
    je 2f
    cmp rcx, [rbx + SN_nfields]
    jae .Lsdf_bad
    imul rax, rcx, SF_SIZE
    or qword ptr [rbx + rax + SN_fields + SF_flags], 64
2:  inc rcx
    jmp 1b
3:  mov rdi, rbx
    call snippet_validate
    test eax, eax
    jz .Lsdf_bad
    mov rdi, rbx
    mov rsi, [rsp + 64 + SB_ptr]
    mov rdx, [rsp + 64 + SB_len]
    call snippet_choices_freeze
    test eax, eax
    jz .Lsdf_bad
    cmp qword ptr [rsp + 632], 0
    je .Lsdf_done
    mov rdi, rbx
    mov rsi, [rsp + 632]
    mov rdx, [rsp + 640]
    call snippet_transforms_freeze
    test eax, eax
    jnz .Lsdf_done
.Lsdf_bad:
    mov rdi, rbx
    call snippet_free_node
    xor ebx, ebx
.Lsdf_done:
    mov rdi, [rsp + 632]
    test rdi, rdi
    jz 1f
    call mem_free
1:  lea rdi, [rsp + 64]
    call sb_free
    mov rax, [rsp]
    mov [rip + ps_ptr], rax
    mov rax, [rsp + 8]
    mov [rip + ps_end], rax
    mov rax, [rsp + 16]
    mov [rip + ps_lend], rax
    mov rax, rbx
    EPILOGUE

# snippet_decode_record(body, len, features) -> validated candidate or 0; no list header, edits or labels.
FN snippet_decode_record
    PROLOGUE 48
    mov [rsp + 24], rdx
    mov rax, [rip + ps_ptr]
    mov [rsp], rax
    mov rax, [rip + ps_end]
    mov [rsp + 8], rax
    mov rax, [rip + ps_lend]
    mov [rsp + 16], rax
    xor ebx, ebx
    cmp rsi, SN_BYTES_MAX
    ja .Lsdr_done
    mov [rip + ps_ptr], rdi
    add rdi, rsi
    mov [rip + ps_end], rdi
    call ps_line
    test eax, eax
    jz .Lsdr_done
    mov r12d, 4
1:  call ps_num
    test edx, edx
    jz .Lsdr_done
    test rax, rax
    jnz .Lsdr_done
    dec r12
    jnz 1b
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + .Lsnippet]
    call str_eq_cstr
    test eax, eax
    jz .Lsdr_done
    call ps_num
    test edx, edx
    jz .Lsdr_done
    test rax, rax
    jnz .Lsdr_done
    call ps_num
    test edx, edx
    jz .Lsdr_done
    mov r12, rax                 # text length
    call ps_num
    test edx, edx
    jz .Lsdr_done
    test rax, rax
    jnz .Lsdr_done
    call ps_num
    test edx, edx
    jz .Lsdr_done
    mov r13, rax                 # extra length
    call ps_eol
    test eax, eax
    jz .Lsdr_done
    mov rax, [rip + ps_end]
    sub rax, [rip + ps_ptr]
    lea rcx, [r12 + r13]
    cmp rax, rcx
    jne .Lsdr_done
    mov rdi, [rip + ps_ptr]
    mov rsi, r12
    lea rdx, [rdi + r12]
    mov rcx, r13
    mov r8d, 1
    mov r9, [rsp + 24]
    call snippet_decode_fields
    mov rbx, rax
.Lsdr_done:
    mov rax, [rsp]
    mov [rip + ps_ptr], rax
    mov rax, [rsp + 8]
    mov [rip + ps_end], rax
    mov rax, [rsp + 16]
    mov [rip + ps_lend], rax
    mov rax, rbx
    EPILOGUE

.section .rodata
.Lfield: .asciz "field"
.Lvariant: .asciz "variant"
.Ltransforms: .asciz "transforms"
.Lchoice: .asciz "choice"
.Lsnippet: .asciz "snippet"
