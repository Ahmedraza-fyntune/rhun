# A replacement loads its own saved choices while the old identity remains live.
.include "rhun.inc"
.equ EST_NDEF, 6
.bss
.p2align 3
est_records: .zero EXT_SIZE * 4
est_defs: .zero SD_SIZE * EST_NDEF * 4
est_records_before: .zero EXT_SIZE * 4
est_defs_before: .zero SD_SIZE * EST_NDEF * 4
est_live: .quad 0
est_stage: .quad 0
.text
FN main
    PROLOGUE
    lea rax, [rip + est_records]
    mov [rip + g_exts + VEC_ptr], rax
    mov qword ptr [rip + g_exts + VEC_len], 4
    mov qword ptr [rip + g_exts + VEC_cap], 4
    xor r12d, r12d
1:  imul rbx, r12, EXT_SIZE
    lea rax, [rip + est_records]
    add rbx, rax
    lea rax, [rip + est_alice]
    cmp r12d, 2
    jne 2f
    lea rax, [rip + est_bob]
2:  mov [rbx + EXT_owner], rax
    lea rax, [rip + est_demo]
    cmp r12d, 3
    jne 3f
    lea rax, [rip + est_absent]
3:  mov [rbx + EXT_name], rax
    mov dword ptr [rbx + EXT_status], ES_IDLE
    imul r13, r12, SD_SIZE * EST_NDEF
    lea rax, [rip + est_defs]
    add r13, rax
    mov [rbx + EXT_sdefs + VEC_ptr], r13
    mov qword ptr [rbx + EXT_sdefs + VEC_len], EST_NDEF
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], EST_NDEF
    xor r14d, r14d
4:  imul r15, r14, SD_SIZE
    add r15, r13
    lea rax, [rip + est_keys]
    mov rax, [rax + r14*8]
    mov [r15 + SD_key], rax
    lea rax, [rip + est_defaults]
    mov rdi, [rax + r14*8]
    mov [r15 + SD_default], rdi
    call dup_cstr
    mov [r15 + SD_value], rax
    lea rax, [rip + est_types]
    mov eax, [rax + r14*4]
    mov [r15 + SD_type], eax
    mov dword ptr [r15 + SD_min], 1
    mov dword ptr [r15 + SD_max], 8
    lea rax, [rip + est_options]
    mov [r15 + SD_opts], rax
    inc r14d
    cmp r14d, EST_NDEF
    jb 4b
    inc r12d
    cmp r12d, 4
    jb 1b
    lea rdi, [rip + est_records_before]
    lea rsi, [rip + est_records]
    mov edx, EXT_SIZE * 4
    call memcpy
    lea rdi, [rip + est_defs_before]
    lea rsi, [rip + est_defs]
    mov edx, SD_SIZE * EST_NDEF * 4
    call memcpy
    mov qword ptr [rip + est_stage], 1
    lea rdi, [rip + est_records + EXT_SIZE]
    call ext_settings_load_one
    call est_check_candidate
    test eax, eax
    jz est_fail
    mov qword ptr [rip + est_stage], 2
    call est_check_others
    test eax, eax
    jz est_fail
    mov rax, [rip + g_mem_live]
    mov [rip + est_live], rax
    mov r12d, 64
5:  lea rdi, [rip + est_records + EXT_SIZE]
    call ext_settings_load_one
    lea rdi, [rip + est_records + EXT_SIZE * 3]
    call ext_settings_load_one
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + est_live]
    jne est_fail
    dec r12d
    jnz 5b
    mov qword ptr [rip + est_stage], 3
    call est_check_candidate
    test eax, eax
    jz est_fail
    call est_check_others
    test eax, eax
    jz est_fail
    # Targeted loading must not depend on discovery visibility at all.
    mov qword ptr [rip + g_exts + VEC_len], 0
    lea rdi, [rip + est_records + EXT_SIZE]
    call ext_settings_load_one
    call est_check_candidate
    test eax, eax
    jz est_fail
    call est_check_others
    test eax, eax
    jz est_fail
    lea rdi, [rip + est_ok]
    call log_cstr
    xor eax, eax
    EPILOGUE
est_fail:
    lea rdi, [rip + est_bad]
    call log_cstr
    mov rdi, [rip + est_stage]
    call log_u64
    call log_nl
    mov eax, 1
    EPILOGUE

est_check_candidate:
    PROLOGUE
    lea rbx, [rip + est_records + EXT_SIZE]
    cmp dword ptr [rbx + EXT_disabled], 1
    jne 8f
    cmp dword ptr [rbx + EXT_pinned], 1
    jne 8f
    cmp dword ptr [rbx + EXT_status], ES_DISABLED
    jne 8f
    xor r12d, r12d
1:  imul rax, r12, SD_SIZE
    lea rcx, [rip + est_defs + SD_SIZE * EST_NDEF]
    add rax, rcx
    mov rdi, [rax + SD_value]
    lea rax, [rip + est_expected]
    mov rsi, [rax + r12*8]
    call strcmp_eq
    test eax, eax
    jz 8f
    inc r12d
    cmp r12d, EST_NDEF
    jb 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

est_check_others:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12d, 1
    je 3f
    imul rbx, r12, EXT_SIZE
    lea rdi, [rip + est_records]
    add rdi, rbx
    lea rsi, [rip + est_records_before]
    add rsi, rbx
    mov edx, EXT_SIZE
    call memeq
    test eax, eax
    jz 8f
    imul rbx, r12, SD_SIZE * EST_NDEF
    lea rdi, [rip + est_defs]
    add rdi, rbx
    lea rsi, [rip + est_defs_before]
    add rsi, rbx
    mov edx, SD_SIZE * EST_NDEF
    call memeq
    test eax, eax
    jz 8f
3:  inc r12d
    cmp r12d, 4
    jb 1b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.section .rodata
.p2align 3
est_keys: .quad est_word, est_width, est_loud, est_style, est_badbool, est_badchoice
est_defaults: .quad est_hi, est_four, est_no, est_plain, est_no, est_plain
est_expected: .quad est_saved, est_eight, est_yes, est_bright, est_no, est_plain
est_types: .long SDT_STRING, SDT_INT, SDT_BOOL, SDT_CHOICE, SDT_BOOL, SDT_CHOICE
est_alice: .asciz "alice"
est_bob: .asciz "bob"
est_demo: .asciz "demo"
est_absent: .asciz "absent"
est_word: .asciz "word"
est_width: .asciz "width"
est_loud: .asciz "loud"
est_style: .asciz "style"
est_badbool: .asciz "badbool"
est_badchoice: .asciz "badchoice"
est_hi: .asciz "hi"
est_four: .asciz "4"
est_no: .asciz "no"
est_plain: .asciz "plain"
est_saved: .asciz "saved value"
est_eight: .asciz "8"
est_yes: .asciz "yes"
est_bright: .asciz "bright"
est_options: .asciz "plain bright"
est_ok: .asciz "ok exact extension replacement settings\n"
est_bad: .asciz "FAIL extension replacement settings "
