# Real legacy open/accept/setter plus cancelled intent at the exact reused row address.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/exthostidentity.inc"
.section .rodata
pb_key: .asciz "greeting"
pb_other: .asciz "replacement"
pb_old: .asciz "old"
pb_new: .asciz "new"
pb_yes: .asciz "yes"
.bss
.p2align 3
.globl pi_guard, pb_saves
pi_guard: .quad 0
pb_saves: .quad 0
pb_host: .zero EXT_SIZE
pb_rows: .zero 2 * SD_SIZE
pb_live: .quad 0
.text
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + pb_live], rax
    mov r15d, 1
    lea rbx, [rip + pb_host]
    lea r12, [rip + pb_rows + SD_SIZE]
    lea rax, [rip + pb_rows]
    mov [rbx + EXT_sdefs + VEC_ptr], rax
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 2
    mov qword ptr [rbx + EXT_sdefs + VEC_cap], 2
    mov [rip + g_exts + VEC_ptr], rbx
    mov qword ptr [rip + g_exts + VEC_len], 1
    mov qword ptr [rip + g_exts + VEC_cap], 1
    mov [rip + g_xp_detail], rbx
    mov rdi, rbx
    call pb_shape
    lea rdi, [rip + pb_old]
    call dup_cstr
    mov [r12 + SD_value], rax
    call pb_open
    # Actual acceptance goes through the palette's TF and ordinary prompt completion.
    lea rdi, [rip + pi_pal_tf]
    lea rsi, [rip + pb_new]
    mov edx, 3
    call tf_set
    call pi_palette_accept
    cmp qword ptr [rip + pi_xp_prompt_sd], 0
    jne pb_bad
    cmp qword ptr [rip + pb_saves], 1
    jne pb_bad
    call pb_value
    inc r15d
    # Escape/close cancels the original intent, even if its row address returns unchanged.
    call pb_open
    call palette_close
    call pb_reuse
    call pb_late
    inc r15d
    call pb_shape
    call pb_open
    # Replacing it by an ordinary prompt clears the extension association.
    lea rdi, [rip + pb_key]
    mov esi, PROMPT_RENAME
    lea rdx, [rip + pb_old]
    mov ecx, 3
    call palette_ext_prompt_open
    call pb_reuse
    call pb_late
    inc r15d
    call pb_shape
    call pb_open
    call palette_close_extensions_pure
    call pb_reuse
    call pb_late
    inc r15d
    call pb_shape
    call pb_open
    # The catalog-only cancellation path also clears any prior delayed association.
    mov dword ptr [rip + pi_pal_mode], 2
    call palette_close_catalogs_pure
    call pb_reuse
    call pb_late
    inc r15d
    call pb_shape
    call pb_open
    # Fault cutpoints return immediately after the real entry invalidation, before IO.
    call ext_init
    call pb_reuse
    call pb_late
    inc r15d
    call pb_shape
    call pb_open
    mov edi, 1
    mov esi, 1
    mov edx, 1
    call ext_load
    call pb_reuse
    call pb_late
    inc r15d
    # Real successful and refused HI/EP take paths are checked by the source wrappers.
    call pp_hi_main
    test eax, eax
    jnz pb_bad
    mov rdi, [r12 + SD_value]
    call mem_free
    mov qword ptr [r12 + SD_value], 0
    lea rdi, [rip + pi_xp_line]
    call sb_free
    lea rdi, [rip + pi_pal_tf + TF_sb]
    call sb_free
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + pb_live]
    jne pb_bad
    xor eax, eax
    EPILOGUE

pb_shape:
    lea rax, [rip + pb_rows]
    mov [rbx + EXT_sdefs + VEC_ptr], rax
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 2
    lea rax, [rip + pb_key]
    mov [r12 + SD_key], rax
    mov dword ptr [r12 + SD_type], SDT_STRING
    ret
pb_open:
    PROLOGUE
    mov rdi, rbx
    mov rsi, r12
    call extpage_setting_prompt_open
    test rax, rax
    jnz pb_bad
    cmp [rip + pi_xp_prompt_sd], r12
    jne pb_bad
    cmp dword ptr [rip + pi_pal_mode], 6
    jne pb_bad
    cmp dword ptr [rip + pi_pal_prompt], PROMPT_EXT_SETTING
    jne pb_bad
    EPILOGUE
pb_reuse:
    # The identical address is now a different type, key and schema ordinal.
    mov [rbx + EXT_sdefs + VEC_ptr], r12
    mov qword ptr [rbx + EXT_sdefs + VEC_len], 1
    lea rax, [rip + pb_other]
    mov [r12 + SD_key], rax
    mov dword ptr [r12 + SD_type], SDT_BOOL
    ret
pb_late:
    PROLOGUE
    lea rdi, [rip + pb_yes]
    mov esi, 3
    call extpage_prompt_done
    cmp qword ptr [rip + pi_xp_prompt_sd], 0
    jne pb_bad
    cmp qword ptr [rip + pb_saves], 1
    jne pb_bad
    call pb_value
    EPILOGUE
pb_value:
    PROLOGUE
    mov rdi, [r12 + SD_value]
    lea rsi, [rip + pb_new]
    call strcmp_eq
    test eax, eax
    jz pb_bad
    EPILOGUE
.globl pi_forbidden
FN pi_forbidden
    mov edi, 199
    SYS SYS_exit_group
pb_bad:
    mov edi, r15d
    add edi, 100
    SYS SYS_exit_group
