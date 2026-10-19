# Private grammar lifetime, boundary reads, all built-in parity and bounded file probes.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.bss
.p2align 3
gpt_result: .zero 64
gpt_a: .zero 4096
gpt_b: .zero 4096
.equ gpt_guard_len, 40
.text
# same nullable C strings.
gpt_same:
    test rdi, rdi
    jnz 1f
    xor eax, eax
    test rsi, rsi
    sete al
    ret
1:  test rsi, rsi
    jz 2f
    jmp strcmp_eq
2:  xor eax, eax
    ret
# compare(legacyGR, preparedGR), includes every semantic field and each tokenized word.
gpt_compare:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, 4
    jae 2f
    mov rdi, [rbx + r13*8]
    mov rsi, [r12 + r13*8]
    call gpt_same
    test eax, eax
    jz .Lgpt_different
    inc r13
    jmp 1b
2:  mov rdi, [rbx + GR_comment]
    mov rsi, [r12 + GR_comment]
    call gpt_same
    test eax, eax
    jz .Lgpt_different
    mov rax, [rbx + GR_commentlen]
    cmp rax, [r12 + GR_commentlen]
    jne .Lgpt_different
    lea rdi, [rbx + GR_flags]
    lea rsi, [r12 + GR_flags]
    mov edx, GR_src - GR_flags
    call memeq
    test eax, eax
    jz .Lgpt_different
    mov rax, [rbx + GR_wn]
    cmp rax, [r12 + GR_wn]
    jne .Lgpt_different
    mov rax, [rbx + GR_regions + VEC_len]
    cmp rax, [r12 + GR_regions + VEC_len]
    jne .Lgpt_different
    imul rdx, rax, REG_SIZE
    mov rdi, [rbx + GR_regions + VEC_ptr]
    mov rsi, [r12 + GR_regions + VEC_ptr]
    call memeq
    test eax, eax
    jz .Lgpt_different
    mov rax, [rbx + GR_lines + VEC_len]
    cmp rax, [r12 + GR_lines + VEC_len]
    jne .Lgpt_different
    imul rdx, rax, 24
    mov rdi, [rbx + GR_lines + VEC_ptr]
    mov rsi, [r12 + GR_lines + VEC_ptr]
    call memeq
    test eax, eax
    jz .Lgpt_different
    xor r13d, r13d
3:  cmp r13, [rbx + GR_wcap]
    jae .Lgpt_same
    mov rax, r13
    shl rax, 4
    add rax, [rbx + GR_words]
    inc r13
    mov r14, [rax]
    test r14, r14
    jz 3b
    mov r15d, [rax + 8]
    cmp r15, 4096
    ja .Lgpt_different
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    xor ecx, ecx
    lea r8, [rip + gpt_a]
    call tokenize
    mov [rsp], eax
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    xor ecx, ecx
    lea r8, [rip + gpt_b]
    call tokenize
    cmp eax, [rsp]
    jne .Lgpt_different
    lea rdi, [rip + gpt_a]
    lea rsi, [rip + gpt_b]
    mov rdx, r15
    call memeq
    test eax, eax
    jz .Lgpt_different
    jmp 3b
.Lgpt_same:
    xor eax, eax
    EPILOGUE
.Lgpt_different:
    mov eax, 1
    EPILOGUE

gpt_all:
    PROLOGUE 32
    xor ebx, ebx
1:  cmp rbx, [rip + syntax_count]
    jae .Lgpta_ok
    imul r12, rbx, 56
    lea rax, [rip + syntax_table]
    add r12, rax
    mov rdi, [r12 + 8]
    mov rsi, [r12 + 16]
    sub rsi, rdi
    call grammar_parse
    mov [rsp], rax
    mov rax, [rip + g_mem_live]
    mov [rsp + 8], rax
    mov rax, [rip + g_grammar_warnings]
    mov [rsp + 16], rax
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lgpta_bad
    mov r13, rax
    mov rdi, [r12 + 8]
    mov rsi, [r12 + 16]
    sub rsi, rdi
    mov rdx, r13
    call grammar_parse_prepare
    test rax, rax
    jz .Lgpta_bad
    mov r14, rax
    mov rdi, rax
    call grammar_prepare_gr
    mov rsi, rax
    mov rdi, [rsp]
    call gpt_compare
    test eax, eax
    jnz .Lgpta_bad
    mov rax, [rip + g_grammar_warnings]
    cmp rax, [rsp + 16]
    jne .Lgpta_bad
    mov rdi, r14
    call grammar_prepare_retain
    test rax, rax
    jnz .Lgpta_bad
    mov rdi, r14
    call grammar_prepare_release
    test rax, rax
    jnz .Lgpta_bad
    mov rdi, r13
    call ext_prepare_owner_release
    test rax, rax
    jnz .Lgpta_bad
    # GP is now the only reference keeping its owner alive.
    mov rdi, r14
    call grammar_prepare_gr
    test rax, rax
    jz .Lgpta_bad
    mov rdi, r14
    call grammar_prepare_release
    test rax, rax
    jnz .Lgpta_bad
    mov rax, [rip + g_mem_live]
    cmp rax, [rsp + 8]
    jne .Lgpta_bad
    inc rbx
    jmp 1b
.Lgpta_ok:
    xor eax, eax
    EPILOGUE
.Lgpta_bad:
    mov eax, 1
    EPILOGUE

gpt_guard:
    PROLOGUE 128
    mov edi, 32768
    call os_map_try
    test rax, rax
    jz .Lgptg_bad
    mov rbx, rax
.ifdef WINDOWS
    lea rcx, [rbx + 16384]
    mov edx, 16384
    mov r8d, 0x4000           # MEM_DECOMMIT, keeps reserved guard inaccessible
    call [rip + __imp_VirtualFree]
    test eax, eax
    jz .Lgptg_bad
.else
    lea r15, [rbx + 16384]
    mov rdi, r15
    mov esi, 16384
    xor edx, edx              # retain an inaccessible mapping, no later allocation can reuse it
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS | 0x10
    mov r8, -1
    xor r9d, r9d
    SYS SYS_mmap
    cmp rax, r15
    jne .Lgptg_bad
.endif
    lea r12, [rbx + 16384 - gpt_guard_len]
    mov rdi, r12
    lea rsi, [rip + gpt_guard_text]
    mov edx, gpt_guard_len
    call memcpy
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lgptg_bad
    mov r13, rax
    mov rdi, r12
    mov esi, gpt_guard_len
    mov rdx, r13
    call grammar_parse_prepare
    test rax, rax
    jz .Lgptg_bad
    mov r14, rax
    mov rax, [rax + GP_gr + GR_regions + VEC_ptr]
    cmp byte ptr [rax + REG_esc], 0
    jne .Lgptg_bad
    mov rdi, r14
    call grammar_prepare_release
    mov rdi, r13
    call ext_prepare_owner_release
    mov rdi, rbx
    mov esi, 32768
    SYS SYS_munmap
    xor eax, eax
    EPILOGUE
.Lgptg_bad:
    mov eax, 1
    EPILOGUE

FN main
    PROLOGUE 32
    mov rbx, [rip + g_argv]
    cmp qword ptr [rip + g_argc], 2
    jne .Lgpt_bad
    mov rdi, [rbx + 8]
    lea rsi, [rip + gpt_all_arg]
    call strcmp_eq
    test eax, eax
    jz 1f
    call gpt_all
    EPILOGUE
1:  mov rdi, [rbx + 8]
    lea rsi, [rip + gpt_guard_arg]
    call strcmp_eq
    test eax, eax
    jz 2f
    call gpt_guard
    EPILOGUE
2:  mov rax, [rip + g_mem_live]
    mov [rsp], rax
    mov rdi, [rbx + 8]
    mov esi, 2 * 1024 * 1024 + 1
    call file_read_limited_try
    test rax, rax
    jz .Lgpt_bad
    mov r12, rax
    mov r13, rdx
    mov edi, PREP_CAP
    call ext_prepare_owner_create
    test rax, rax
    jz .Lgpt_bad
    mov r14, rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call grammar_parse_prepare
    test rax, rax
    jz 3f
    mov r15, rax
    mov rax, [rax + GP_gr + GR_wn]
    mov [rip + gpt_result + 8], rax
    mov rax, [r15 + GP_gr + GR_regions + VEC_len]
    mov [rip + gpt_result + 16], rax
    mov rax, [r15 + GP_gr + GR_lines + VEC_len]
    mov [rip + gpt_result + 24], rax
    mov rdi, r15
    call grammar_prepare_release
    mov rdx, rax
3:  mov [rip + gpt_result], rdx
    mov rax, [r14 + EO_used]
    mov [rip + gpt_result + 32], rax
    mov rdi, r14
    call ext_prepare_owner_release
    mov rdi, r12
    call mem_free
    mov rax, [rip + g_mem_live]
    sub rax, [rsp]
    mov [rip + gpt_result + 40], rax
    mov eax, [rip + g_grammar_warnings]
    mov [rip + gpt_result + 48], rax
    mov rax, [rip + g_grammars + VEC_len]
    mov [rip + gpt_result + 56], rax
    mov edi, 1
    lea rsi, [rip + gpt_result]
    mov edx, 64
    call write_all
    xor eax, eax
    EPILOGUE
.Lgpt_bad:
    mov eax, 1
    EPILOGUE
.section .rodata
gpt_all_arg: .asciz "--all"
gpt_guard_arg: .asciz "--guard"
gpt_guard_text: .ascii "name = Guard\nregion = a b string escape="
