# Counted provider grammar matches the existing exact kind/language/owner rules.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.section .rodata
cpp_providers: .ascii "providers"
cpp_format: .ascii "format"
cpp_rename: .ascii "rename"
cpp_symbols: .ascii "symbols"
cpp_signature: .ascii "signature"
.text
FN cp_provider_parse
    PROLOGUE
    mov rbx, rdi
    call cp_provider_fields
    test rax, rax
    jz .Lppp_input_error
    mov r12, rax
    mov [rbx + CP_ppremove], rdx
    mov rax, [rbx + CP_ppphase]
    cmp rax, PPS_SECTION
    je .Lppp_section
    cmp rax, PPS_KEY
    je .Lppp_key
    cmp rax, PPS_LANGUAGE
    je .Lppp_language
    cmp rax, PPS_OWNER
    je .Lppp_owner
    mov rax, -22
    jmp .Lppp_return
.Lppp_section:
    cmp qword ptr [r12 + EC_seclen], 9
    jne .Lppp_skip
    mov r13, [r12 + EC_section]
    lea r14, [rip + cpp_providers]
1:  mov rcx, [rbx + CP_matchpos]
    cmp rcx, 9
    jae 2f
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppp_zero
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp al, [r14 + rcx]
    jne .Lppp_skip
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
2:  mov qword ptr [rbx + CP_ppprefix], -1
    mov qword ptr [rbx + CP_scanpos], 0
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_ppkind], 0
    mov qword ptr [rbx + CP_ppphase], PPS_KEY
    jmp .Lppp_zero
.Lppp_key:
    mov r13, [r12 + EC_key]
    mov r14, [r12 + EC_keylen]
    cmp qword ptr [rbx + CP_ppprefix], -1
    jne .Lppp_kind_match
1:  mov rcx, [rbx + CP_scanpos]
    cmp rcx, r14
    jae .Lppp_skip
    cmp rcx, 10
    jae .Lppp_skip
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppp_zero
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp eax, '.'
    je 2f
    inc qword ptr [rbx + CP_scanpos]
    jmp 1b
2:  mov [rbx + CP_ppprefix], rcx
    mov eax, 6
    cmp rcx, 6
    je 3f
    mov eax, 3
    cmp rcx, 7
    je 3f
    cmp rcx, 9
    jne .Lppp_skip
    mov eax, 7
3:  mov [rbx + CP_ppkind], rax
    mov qword ptr [rbx + CP_matchpos], 0
.Lppp_kind_match:
    lea r15, [rip + cpp_format]
    mov rax, [rbx + CP_ppkind]
    cmp rax, 6
    je 1f
    lea r15, [rip + cpp_rename]
    cmp rax, 5
    je 1f
    lea r15, [rip + cpp_symbols]
    cmp rax, 3
    je 1f
    lea r15, [rip + cpp_signature]
1:  mov rcx, [rbx + CP_matchpos]
    cmp rcx, [rbx + CP_ppprefix]
    jae .Lppp_kind_ready
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppp_zero
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp al, [r15 + rcx]
    jne 2f
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
2:  cmp qword ptr [rbx + CP_ppkind], 6
    jne .Lppp_skip
    mov qword ptr [rbx + CP_ppkind], 5
    mov qword ptr [rbx + CP_matchpos], 0
    jmp .Lppp_zero
.Lppp_kind_ready:
    mov rax, r14
    sub rax, [rbx + CP_ppprefix]
    dec rax
    test rax, rax
    jz .Lppp_bad_key
    cmp rax, 128
    ja .Lppp_bad_key
    mov [rbx + CP_pplanglen], rax
    mov qword ptr [rbx + CP_scanpos], 0
    mov eax, 177573
    xor rax, [rbx + CP_ppkind]
    mov [rbx + CP_hash], rax
    mov qword ptr [rbx + CP_ppphase], PPS_LANGUAGE
    jmp .Lppp_zero
.Lppp_language:
    mov r13, [r12 + EC_key]
    add r13, [rbx + CP_ppprefix]
    inc r13
1:  mov rcx, [rbx + CP_scanpos]
    cmp rcx, [rbx + CP_pplanglen]
    jae 2f
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppp_zero
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp eax, 32
    jb .Lppp_bad_key
    cmp eax, '='
    je .Lppp_bad_key
    cmp eax, '['
    je .Lppp_bad_key
    cmp eax, ']'
    je .Lppp_bad_key
    mov rdx, [rbx + CP_hash]
    mov r8, rdx
    shl rdx, 5
    add rdx, r8
    xor rdx, rax
    mov [rbx + CP_hash], rdx
    inc qword ptr [rbx + CP_scanpos]
    jmp 1b
2:  mov rax, [r12 + EC_vallen]
    mov [rbx + CP_ppownerlen], rax
    mov qword ptr [rbx + CP_matchpos], 0
    mov qword ptr [rbx + CP_ppoldrow], 0
    mov qword ptr [rbx + CP_ppexpectedhash], 0
    mov qword ptr [rbx + CP_ppphase], PPS_OWNER
    jmp .Lppp_zero
.Lppp_owner:
    cmp qword ptr [rbx + CP_ppremove], 0
    jne .Lppp_owner_ready
    cmp qword ptr [rbx + CP_ppownerlen], 0
    je .Lppp_bad_owner
    cmp qword ptr [rbx + CP_ppownerlen], 201
    ja .Lppp_bad_owner
    mov r13, [r12 + EC_value]
1:  mov rcx, [rbx + CP_matchpos]
    cmp rcx, [rbx + CP_ppownerlen]
    jae 4f
    cmp qword ptr [rbx + CP_bytesleft], 0
    je .Lppp_zero
    movzx eax, byte ptr [r13 + rcx]
    dec qword ptr [rbx + CP_bytesleft]
    cmp eax, '/'
    je 3f
    cmp eax, '-'
    je 2f
    cmp eax, '_'
    je 2f
    cmp eax, '.'
    je 2f
    cmp eax, '0'
    jb .Lppp_bad_owner
    cmp eax, '9'
    jbe 2f
    or eax, 32
    sub eax, 'a'
    cmp eax, 26
    jae .Lppp_bad_owner
2:  inc qword ptr [rbx + CP_ppoldrow]
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
3:  cmp qword ptr [rbx + CP_ppoldrow], 0
    je .Lppp_bad_owner
    inc qword ptr [rbx + CP_ppexpectedhash]
    cmp qword ptr [rbx + CP_ppexpectedhash], 1
    ja .Lppp_bad_owner
    mov qword ptr [rbx + CP_ppoldrow], 0
    inc qword ptr [rbx + CP_matchpos]
    jmp 1b
4:  cmp qword ptr [rbx + CP_ppoldrow], 0
    je .Lppp_bad_owner
    cmp qword ptr [rbx + CP_ppexpectedhash], 1
    jne .Lppp_bad_owner
.Lppp_owner_ready:
    mov rdi, rbx
    call cp_provider_begin_lookup
    jmp .Lppp_return
.Lppp_bad_owner:
    test qword ptr [rbx + CP_workflags], PPF_DIRTY
    jnz .Lppp_dirty_invalid
    or qword ptr [rbx + CP_workflags], PPF_BAD
    mov rdi, rbx
    call cp_provider_target
    inc qword ptr [rax + PB_invalid]
    inc qword ptr [rbx + CP_ppinvalid]
    mov rdi, rbx
    call cp_provider_begin_lookup
    jmp .Lppp_return
.Lppp_bad_key:
    mov rdi, rbx
    call cp_provider_target
    inc qword ptr [rax + PB_invalid]
    inc qword ptr [rbx + CP_ppinvalid]
.Lppp_skip:
    mov rdi, rbx
    call cp_provider_advance
    jmp .Lppp_return
.Lppp_zero:
    xor eax, eax
.Lppp_return:
    EPILOGUE
.Lppp_input_error:
    mov rax, rdx
    EPILOGUE
.Lppp_dirty_invalid:
    mov rax, -22
    EPILOGUE
FN cp_provider_begin_lookup
    mov rax, [rdi + CP_hash]
    and eax, 1023
    mov [rdi + CP_probe], rax
    mov qword ptr [rdi + CP_matchpos], 0
    mov qword ptr [rdi + CP_ppphase], PPS_LOOKUP
    xor eax, eax
    ret
