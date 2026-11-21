# Gitignore engine unit test
.include "rhun.inc"

.bss
.p2align 3
out: .zero SB_SIZE

.section .rodata
.Lrules_base:
    .ascii "node_modules/\n"
    .ascii "vendor/\n"
    .ascii "dist/\n"
    .ascii ".env\n"
    .ascii "*.log\n"
    .ascii "!important.log\n"
    .ascii "/build\n"
.Lrules_base_end:

.Lnested_rules:
    .ascii "!keep.tmp\n"
.Lnested_rules_end:

.Lstr_empty: .asciz ""
.Lstr_node_modules: .asciz "node_modules"
.Lstr_vendor: .asciz "vendor"
.Lstr_dist: .asciz "dist"
.Lstr_dot_env: .asciz ".env"
.Lstr_dot_env_example: .asciz ".env.example"
.Lstr_sub_dot_env: .asciz "config/.env"
.Lstr_debug_log: .asciz "debug.log"
.Lstr_important_log: .asciz "important.log"
.Lstr_build: .asciz "build"
.Lstr_src_build: .asciz "src/build"
.Lstr_main_rs: .asciz "src/main.rs"
.Lstr_main_name: .asciz "main.rs"
.Lstr_sub_dir: .asciz "docs/"
.Lstr_keep_tmp: .asciz "docs/keep.tmp"
.Lstr_keep_name: .asciz "keep.tmp"
.Lstr_other_tmp: .asciz "other.tmp"

.text

# check_test(expected, rel_path, name, is_dir)
check_test:
    PROLOGUE 32
    mov [rsp], rdi              # expected (0 or 1)
    mov r12, rsi                # rel_path
    mov r13, rdx                # name
    mov r14d, ecx               # is_dir

    mov rdi, r12
    call strlen
    mov r15, rax                # rel_len

    mov rdi, r12
    mov rsi, r15
    mov rdx, r13
    mov ecx, r14d
    call gitignore_is_ignored
    # rax = actual
    cmp rax, [rsp]
    je .Lct_ok

    # Fail: output 'F'
    lea rdi, [rip + out]
    mov esi, 'F'
    call sb_push_byte
    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    EPILOGUE

.Lct_ok:
    lea rdi, [rip + out]
    mov esi, '.'
    call sb_push_byte
    EPILOGUE

FN main
    PROLOGUE
    call gitignore_init

    # Parse base rules at depth 0
    lea rdi, [rip + .Lrules_base]
    mov rsi, .Lrules_base_end - .Lrules_base
    lea rdx, [rip + .Lstr_empty]
    xor ecx, ecx
    xor r8d, r8d                # depth 0
    call gitignore_parse_buf

    # Test 1: node_modules (dir) -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_node_modules]
    lea rdx, [rip + .Lstr_node_modules]
    mov ecx, 1
    call check_test

    # Test 2: node_modules (file) -> NOT ignored (0, because trailing slash)
    mov rdi, 0
    lea rsi, [rip + .Lstr_node_modules]
    lea rdx, [rip + .Lstr_node_modules]
    mov ecx, 0
    call check_test

    # Test 3: vendor (dir) -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_vendor]
    lea rdx, [rip + .Lstr_vendor]
    mov ecx, 1
    call check_test

    # Test 4: dist (dir) -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_dist]
    lea rdx, [rip + .Lstr_dist]
    mov ecx, 1
    call check_test

    # Test 5: .env (file) -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_dot_env]
    lea rdx, [rip + .Lstr_dot_env]
    mov ecx, 0
    call check_test

    # Test 6: config/.env (file, unanchored) -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_sub_dot_env]
    lea rdx, [rip + .Lstr_dot_env]
    mov ecx, 0
    call check_test

    # Test 7: .env.example (file) -> NOT ignored (0)
    mov rdi, 0
    lea rsi, [rip + .Lstr_dot_env_example]
    lea rdx, [rip + .Lstr_dot_env_example]
    mov ecx, 0
    call check_test

    # Test 8: debug.log -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_debug_log]
    lea rdx, [rip + .Lstr_debug_log]
    mov ecx, 0
    call check_test

    # Test 9: important.log (negation !) -> NOT ignored (0)
    mov rdi, 0
    lea rsi, [rip + .Lstr_important_log]
    lea rdx, [rip + .Lstr_important_log]
    mov ecx, 0
    call check_test

    # Test 10: build at root (anchored /build) -> ignored (1)
    mov rdi, 1
    lea rsi, [rip + .Lstr_build]
    lea rdx, [rip + .Lstr_build]
    mov ecx, 1
    call check_test

    # Test 11: src/build (anchored /build) -> NOT ignored (0)
    mov rdi, 0
    lea rsi, [rip + .Lstr_src_build]
    lea rdx, [rip + .Lstr_build]
    mov ecx, 1
    call check_test

    # Test 12: src/main.rs -> NOT ignored (0)
    mov rdi, 0
    lea rsi, [rip + .Lstr_main_rs]
    lea rdx, [rip + .Lstr_main_name]
    mov ecx, 0
    call check_test

    # Test 13: Push nested rule in docs/ (depth 1)
    lea rdi, [rip + .Lnested_rules]
    mov rsi, .Lnested_rules_end - .Lnested_rules
    lea rdx, [rip + .Lstr_sub_dir]
    mov ecx, 5                  # strlen("docs/")
    mov r8d, 1                  # depth 1
    call gitignore_parse_buf

    # docs/keep.tmp matches !keep.tmp at depth 1 -> NOT ignored (0)
    mov rdi, 0
    lea rsi, [rip + .Lstr_keep_tmp]
    lea rdx, [rip + .Lstr_keep_name]
    mov ecx, 0
    call check_test

    # Pop depth 1
    mov edi, 1
    call gitignore_leave_dir

    call gitignore_free

    lea rdi, [rip + out]
    mov esi, 10
    call sb_push_byte
    mov rdi, [rip + out + SB_ptr]
    mov rsi, [rip + out + SB_len]
    call log_write
    xor eax, eax
    EPILOGUE
