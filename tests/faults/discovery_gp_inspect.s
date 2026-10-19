.include "gpc-input.inc"

.bss
.p2align 3
image_header: .skip 64
image_base: .quad 0
.text
FN main
    PROLOGUE 64
    mov rax, [rip + g_mem_live]
    mov [rip + image_base], rax
    xor r12d, r12d
.Limg_case:
    cmp r12, GPC_INPUT_COUNT
    jae .Limg_done
    lea rax, [rip + probe_cases]
    mov rcx, r12
    shl rcx, 4
    add rax, rcx
    mov [rsp], rax
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Limg_bad
    mov r15, rax
    mov rcx, [rsp]
    mov rdi, [rcx]
    mov rsi, [rcx + 8]
    mov rdx, r15
    cmp r12, GPC_MANAGED_COUNT
    jae 1f
    call grammar_parse_prepare
    jmp 2f
1:  call grammar_parse_prepare_legacy
2:  test rax, rax
    jz .Limg_bad
    mov r14, rax
    lea rbx, [rax + GP_gr]
    mov rax, [rsp]
    mov rax, [rax + 8]
    mov [rip + image_header], rax
    mov eax, 1
    cmp r12, GPC_MANAGED_COUNT
    jb 3f
    mov eax, 2
3:  mov [rip + image_header + 8], rax
    mov rax, [rbx + GR_flags]
    mov [rip + image_header + 16], rax
    mov rax, [r14 + GP_warnings]
    mov [rip + image_header + 24], rax
    mov rax, [rbx + GR_wcap]
    mov [rip + image_header + 32], rax
    mov rax, [rbx + GR_wn]
    mov [rip + image_header + 40], rax
    mov rax, [rbx + GR_regions + VEC_len]
    mov [rip + image_header + 48], rax
    mov rax, [rbx + GR_lines + VEC_len]
    mov [rip + image_header + 56], rax
    lea rdi, [rip + image_header]
    mov esi, 64
    call image_write
    xor r13d, r13d
.Limg_field:
    lea rax, [rip + probe_fields]
    mov rax, [rax + r13*8]
    mov rax, [rbx + rax]
    mov [rsp + 8], rax
    mov qword ptr [rsp + 16], -1
    test rax, rax
    jz 1f
    mov rdi, rax
    call strlen
    mov [rsp + 16], rax
1:  lea rdi, [rsp + 16]
    mov esi, 8
    call image_write
    mov rsi, [rsp + 16]
    cmp rsi, -1
    je 2f
    mov rdi, [rsp + 8]
    call image_write
2:  inc r13
    cmp r13, 5
    jb .Limg_field
    mov rdi, [rbx + GR_regions + VEC_ptr]
    mov rsi, [rbx + GR_regions + VEC_len]
    imul rsi, 40
    call image_write
    mov rdi, [rbx + GR_lines + VEC_ptr]
    mov rsi, [rbx + GR_lines + VEC_len]
    imul rsi, 24
    call image_write
    lea rdi, [rbx + GR_identx]
    mov esi, 576
    call image_write
    xor r13d, r13d
.Limg_word:
    cmp r13, [rbx + GR_wcap]
    jae .Limg_release
    mov rax, r13
    shl rax, 4
    add rax, [rbx + GR_words]
    mov rcx, [rax]
    mov [rsp + 8], rcx
    mov qword ptr [rsp + 16], -1
    mov qword ptr [rsp + 24], 0
    test rcx, rcx
    jz 1f
    mov ecx, [rax + 8]
    mov [rsp + 16], rcx
    mov ecx, [rax + 12]
    mov [rsp + 24], rcx
1:  lea rdi, [rsp + 16]
    mov esi, 16
    call image_write
    mov rsi, [rsp + 16]
    cmp rsi, -1
    je 2f
    mov rdi, [rsp + 8]
    call image_write
2:  inc r13
    jmp .Limg_word
.Limg_release:
    mov rdi, r14
    call grammar_prepare_release
    mov rdi, r15
    call ext_prepare_owner_release
    inc r12
    jmp .Limg_case
.Limg_done:
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + image_base]
    jne .Limg_bad
    xor eax, eax
    EPILOGUE
.Limg_bad:
    mov eax, 73
    EPILOGUE
FN image_write
    PROLOGUE
    mov rdx, rsi
    mov rsi, rdi
    mov edi, 1
    call write_all
    test rax, rax
    js 1f
    EPILOGUE
1:  mov edi, 73
    SYS SYS_exit_group
