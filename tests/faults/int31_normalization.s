# Exact integer helper prefix ABI and actual legacy immutable default normalization.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
intt_stage: .quad 0
intt_live: .quad 0
intt_charge: .quad 0
intt_report: .zero 32
.text
intt_fail:
    mov rdi, [rip + intt_stage]
    add rdi, 80
    call sys_exit
    ud2
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + intt_live], rax
    call ext_prepare_retire_charge
    mov [rip + intt_charge], rax
    .ifdef INTT_DEFAULT_ONLY
    jmp .Lintt_defaults
    .endif
    lea rbx, [rip + intt_cases]
    mov r12d, 17
    mov qword ptr [rip + intt_stage], 1
1:  mov rdi, [rbx]
    mov rsi, [rbx + 8]
    call ext_prepare_parse_int31
    cmp rax, [rbx + 16]
    jne intt_fail
    cmp rdx, [rbx + 24]
    jne intt_fail
    add rbx, 32
    dec r12
    jnz 1b
    # Declared span, rather than C terminator, stops the scanner.
    lea rdi, [rip + intt_prefix]
    mov esi, 3
    call ext_prepare_parse_int31
    cmp rax, 123
    jne intt_fail
    cmp rdx, 3
    jne intt_fail
    call intt_guard
.Lintt_defaults:
    mov qword ptr [rip + intt_stage], 2
    mov rdi, -1
    lea rsi, [rip + intt_path]
    lea rdx, [rip + intt_owner]
    lea rcx, [rip + intt_name]
    call ext_prepare_alloc
    test rax, rax
    jz intt_fail
    mov rbx, rax
    mov qword ptr [rbx + EP_kind], 2
    mov rdi, rbx
    call ext_prepare_enable_deferred
    test rax, rax
    jnz intt_fail
    mov rdi, rbx
    lea rsi, [rbx + EP_ext + EXT_sdefs]
    mov edx, SD_SIZE
    call prep_owned_vec_push
    test rax, rax
    jz intt_fail
    mov r12, rax
    mov dword ptr [r12 + SD_type], SDT_INT
    mov dword ptr [r12 + SD_min], 10
    mov dword ptr [r12 + SD_max], 100
    mov rdi, rbx
    lea rsi, [rip + intt_huge]
    mov edx, 20
    call prep_owned_dup
    test rax, rax
    jz intt_fail
    mov [r12 + SD_default], rax
    mov rdi, rbx
    call ext_prepare_defaults
    test rax, rax
    jnz intt_fail
    mov rdi, [r12 + SD_default]
    lea rsi, [rip + intt_expected]
    call strcmp_eq
    test eax, eax
    jz intt_fail
    mov rdi, [r12 + SD_value]
    lea rsi, [rip + intt_expected]
    call strcmp_eq
    test eax, eax
    jz intt_fail
    mov rdi, rbx
    call ext_prepare_release_deferred
    test rax, rax
    jnz intt_fail
    cmp rdx, 1
    jne intt_fail
    mov r13d, 4096
2:  mov edi, 1
    lea rsi, [rip + intt_report]
    call ext_prepare_retire_step
    test rax, rax
    js intt_fail
    cmp qword ptr [rip + intt_report + 16], 0
    jne intt_fail
    test rax, rax
    jz 3f
    dec r13
    jnz 2b
    jmp intt_fail
3:  call ext_prepare_retire_charge
    cmp rax, [rip + intt_charge]
    jne intt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + intt_live]
    jne intt_fail
    mov edi, 1
    lea rsi, [rip + intt_ok]
    mov edx, 47
    call write_all
    xor eax, eax
    EPILOGUE
# Inaccessible retained page proves no byte at ptr+len is observed.
intt_guard:
    PROLOGUE 128
    mov edi, 32768
    call os_map_try
    test rax, rax
    jz intt_fail
    mov rbx, rax
.ifdef WINDOWS
    lea rcx, [rbx + 16384]
    mov edx, 16384
    mov r8d, 0x4000
    call [rip + __imp_VirtualFree]
    test eax, eax
    jz intt_fail
.else
    lea r15, [rbx + 16384]
    mov rdi, r15
    mov esi, 16384
    xor edx, edx
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS | 0x10
    mov r8, -1
    xor r9d, r9d
    SYS SYS_mmap
    cmp rax, r15
    jne intt_fail
.endif
    lea r12, [rbx + 16384 - 20]
    mov rdi, r12
    lea rsi, [rip + intt_huge]
    mov edx, 20
    call memcpy
    mov rdi, r12
    mov esi, 20
    call ext_prepare_parse_int31
    cmp rax, 2147483647
    jne intt_fail
    cmp rdx, 20
    jne intt_fail
    # Even zero length may point exactly at the inaccessible page.
    lea rdi, [rbx + 16384]
    xor esi, esi
    call ext_prepare_parse_int31
    test rax, rax
    jnz intt_fail
    test rdx, rdx
    jnz intt_fail
    mov rdi, rbx
    mov esi, 32768
    SYS SYS_munmap
    test rax, rax
    jnz intt_fail
    EPILOGUE

.section .rodata
intt_path: .asciz "/fixture"
intt_owner: .asciz "fixture"
intt_name: .asciz "number"
intt_prefix: .asciz "123456"
intt_huge: .asciz "18446744073709551616"
intt_expected: .asciz "100"
intt_ok: .ascii "ok saturating int31 prefix and legacy defaults\n"
intt_ok_end:
intt_text0: .asciz ""
intt_text1: .asciz "x"
intt_text2: .asciz "0"
intt_text3: .asciz "2147483646"
intt_text4: .asciz "2147483647"
intt_text5: .asciz "2147483648"
intt_text6: .asciz "4294967296"
intt_text7: .asciz "18446744073709551615"
intt_text8: .asciz "18446744073709551616"
intt_text9: .asciz "18446744073709551617"
intt_text10: .asciz "9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
intt_text11: .asciz "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
intt_text12: .asciz "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001"
intt_text13: .asciz "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002147483647"
intt_text14: .asciz "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002147483648"
intt_text15: .asciz "123x9"
intt_text16: .asciz "2147483648x"

.p2align 3
intt_cases:
    .quad intt_text0,0,0,0
    .quad intt_text1,1,0,0
    .quad intt_text2,1,0,1
    .quad intt_text3,10,2147483646,10
    .quad intt_text4,10,2147483647,10
    .quad intt_text5,10,2147483647,10
    .quad intt_text6,10,2147483647,10
    .quad intt_text7,20,2147483647,20
    .quad intt_text8,20,2147483647,20
    .quad intt_text9,20,2147483647,20
    .quad intt_text10,256,2147483647,256
    .quad intt_text11,256,0,256
    .quad intt_text12,257,1,257
    .quad intt_text13,266,2147483647,266
    .quad intt_text14,266,2147483647,266
    .quad intt_text15,5,123,3
    .quad intt_text16,11,2147483647,10
