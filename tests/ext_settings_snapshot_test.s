.include "rhun.inc"
.include "app/extsettingsini.inc"
.include "app/extsettingsmemory.inc"
.section .rodata
ests_tag: .quad 17,29,0,0
ests_corpus: .ascii "outside = base\r\n # quiet\n; hidden\n[ owner/tool ]\n pinned = yes\nsetting.text = snow 雪 = still\n[providers]\ncomplete.py=other/tool\n[ ]\nempty =\n[owner/tool]\npinned=no"
.equ ESTS_LEN, 164
ests_malformed: .ascii "missing-equal\n"
ests_ok: .ascii "ok immutable snapshot spans and bounded INI cursor\n"
.equ ESTS_OK_LEN, 51
.text
ests_fail:
    mov edi, 76
    call sys_exit
# Build owned helper-validated source for a fixture span, return ESB with ref1.
ests_snapshot:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + ests_tag]
    mov esi, EW_SNAPSHOT
    lea rdx, [r12 + 48]
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz ests_fail
    mov r13, rax
    mov qword ptr [rax + EJF_body], 1
    mov [rax + EJF_body + 8], r12
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rax + EJF_body + 16]
    call sha256_hash
    cmp eax, 1
    jne ests_fail
    lea rdi, [r13 + EJF_body + 48]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov qword ptr [r13 + EJF_sealed], 1
    mov rdi, r13
    mov esi, 29
    call ext_settings_snapshot_begin
    test rax, rax
    jz ests_fail
    EPILOGUE
# Compare every row with the established grammar. Input ESB remains caller-owned.
# rsi budget. Exact text comparisons only in this test, never product step.
ests_compare:
    mov edx, 1024
    jmp .Lests_compare_enter
ests_compare_one_phase:
    mov edx, 1
.Lests_compare_enter:
    PROLOGUE 128
    mov [rsp + 112], rdx
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rsp]
    mov rsi, [rbx + ESB_bytes]
    mov rdx, [rbx + ESB_length]
    call ini_init
    mov rdi, rbx
    call ext_settings_ini_begin
    test rax, rax
    jz ests_fail
    mov r13, rax
1:  mov rdi, r13
    mov rsi, r12
    mov rdx, [rsp + 112]
    call ext_settings_ini_step_budget
    cmp rdx, r12
    ja ests_fail
    cmp rcx, [rsp + 112]
    ja ests_fail
    test rax, rax
    jz 1b
    cmp rax, 2
    je 4f
    cmp rax, 1
    jne ests_fail
    mov rdi, r13
    lea rsi, [rsp + 64]
    call ext_settings_ini_row
    test rax, rax
    jnz ests_fail
    lea rdi, [rsp]
    call ini_next
    cmp eax, 1
    jne ests_fail
    # INI struct includes position/end then section,key,value counted spans.
    xor r14d, r14d
2:  lea rax, [rsp + 64]
    lea rdx, [rsp + INI_sec]
    mov rsi, [rax + r14]
    mov rdi, [rdx + r14]
    mov rdx, [rdx + r14 + 8]
    cmp [rax + r14 + 8], rdx
    jne ests_fail
    call memeq
    test eax, eax
    jz ests_fail
    add r14, 16
    cmp r14, 48
    jb 2b
    # A ready row is stable without any more input work.
    mov rdi, r13
    mov esi, 1
    call ext_settings_ini_step
    cmp rax, 1
    jne ests_fail
    test rdx, rdx
    jnz ests_fail
    test rcx, rcx
    jnz ests_fail
    mov rdi, r13
    call ext_settings_ini_advance
    test rax, rax
    jnz ests_fail
    jmp 1b
4:  lea rdi, [rsp]
    call ini_next
    test eax, eax
    jnz ests_fail
    mov rdi, r13
    call ext_settings_ini_free
    test rax, rax
    jnz ests_fail
    EPILOGUE
FN main
    PROLOGUE 32
    mov r15, [rip + g_mem_live]
    call ests_refusals
    lea rdi, [rip + ests_corpus]
    mov esi, ESTS_LEN
    call ests_snapshot
    mov rbx, rax
    mov rdi, rbx
    mov esi, 1
    call ests_compare
    mov rdi, rbx
    mov esi, 7
    call ests_compare
    mov rdi, rbx
    mov esi, 65536
    call ests_compare
    # Composition with a single remaining phase action still reaches every row.
    mov rdi, rbx
    mov esi, 65536
    call ests_compare_one_phase
    # Cursor ownership outlives the producer's snapshot reference.
    mov rdi, rbx
    call ext_settings_ini_begin
    test rax, rax
    jz ests_fail
    mov r12, rax
    mov rdi, rbx
    call ext_settings_snapshot_release
    mov edi, 64
    call ext_settings_snapshot_gc
    test rax, rax
    jnz ests_fail
    mov rdi, r12
    mov esi, 65536
    call ext_settings_ini_step
    cmp rax, 1
    jne ests_fail
    mov rdi, r12
    call ext_settings_ini_free
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    jne ests_fail
    mov edi, 1
    call ext_settings_snapshot_gc
    cmp rax, 1
    jne ests_fail
    # A maximal comment exercises one huge line without a whole-span parser call.
    mov edi, 1048576
    call ext_settings_memory_try
    test rax, rax
    jz ests_fail
    mov rbx, rax
    mov rdi, rax
    mov esi, 'x'
    mov edx, 1048576
    call memset
    mov byte ptr [rbx], ';'
    mov byte ptr [rbx + 1048575], 10
    mov rdi, rbx
    mov esi, 1048576
    call ests_snapshot
    mov r12, rax
    mov rdi, rbx
    call ext_settings_memory_free
    # A single long scan must charge exactly every inspected byte.
    mov rdi, r12
    call ext_settings_ini_begin
    mov r13, rax
    mov rdi, r13
    mov esi, 7
    call ext_settings_ini_step
    test rax, rax
    jnz ests_fail
    cmp rdx, 7
    jne ests_fail
    cmp rcx, 1
    jne ests_fail
    mov rdi, r13
    call ext_settings_ini_free
    mov rdi, r12
    mov esi, 7
    call ests_compare
    mov rdi, r12
    mov esi, 65536
    call ests_compare
    mov rdi, r12
    call ext_settings_snapshot_release
    mov edi, 64
    call ext_settings_snapshot_gc
    cmp rax, 2
    jne ests_fail
    # Blank/whitespace/comment/short-row storms exercise transition yielding.
    mov edi, 65536
    call ext_settings_memory_try
    mov rbx, rax
    test rax, rax
    jz ests_fail
    mov rdi, rbx
    mov esi, 10
    mov edx, 65536
    call memset
    mov rdi, rbx
    mov esi, 65536
    call ests_snapshot
    mov r12, rax
    mov rdi, r12
    call ext_settings_ini_begin
    mov r13, rax
    mov rdi, r13
    mov esi, 65536
    call ext_settings_ini_step
    test rax, rax
    jnz ests_fail
    cmp rdx, 256
    jne ests_fail
    cmp rcx, 1024
    jne ests_fail
    cmp qword ptr [r13 + ESI_pos], 256
    jne ests_fail
    mov rdi, r13
    call ext_settings_ini_free
    mov rdi, r12
    mov esi, 65536
    call ests_compare
    mov rdi, r12
    call ext_settings_snapshot_release
    mov edi, 64
    call ext_settings_snapshot_gc
    # Repeat whitespace, comment and short duplicate fields in the same allocation.
    mov r14d, 1
.Lests_storm:
    xor ecx, ecx
1:  mov dword ptr [rbx + rcx], 0x0a0d0920
    cmp r14, 1
    je 2f
    mov dword ptr [rbx + rcx], 0x0a787823
    cmp r14, 2
    je 2f
    mov dword ptr [rbx + rcx], 0x0a763d6b
2:  add rcx, 4
    cmp rcx, 65536
    jb 1b
    mov rdi, rbx
    mov esi, 65536
    call ests_snapshot
    mov r12, rax
    mov rdi, r12
    mov esi, 65536
    call ests_compare
    mov rdi, r12
    call ext_settings_snapshot_release
    mov edi, 64
    call ext_settings_snapshot_gc
    inc r14
    cmp r14, 3
    jbe .Lests_storm
    mov rdi, rbx
    call ext_settings_memory_free
    lea rdi, [rip + ests_malformed]
    mov esi, 14
    call ests_snapshot
    mov r12, rax
    mov rdi, r12
    call ext_settings_ini_begin
    mov r13, rax
    mov rdi, r12
    call ext_settings_snapshot_release
    mov rdi, r13
    mov esi, 65536
    call ext_settings_ini_step
    cmp rax, -22
    jne ests_fail
    mov rdi, r13
    call ext_settings_ini_free
    mov edi, 64
    call ext_settings_snapshot_gc
    call ext_settings_memory_total
    test rax, rax
    jnz ests_fail
    cmp [rip + g_mem_live], r15
    jne ests_fail
    mov edi, 1
    lea rsi, [rip + ests_ok]
    mov edx, ESTS_OK_LEN
    call write_all
    xor eax, eax
    EPILOGUE

# Constructor failures, reference exhaustion, invalid budgets, absent and committed sources.
ests_refusals:
    PROLOGUE 16
    lea rdi, [rip + ests_tag]
    mov esi, EW_SNAPSHOT
    mov edx, 48
    xor ecx, ecx
    call ext_settings_frame_new
    test rax, rax
    jz ests_fail
    mov r13, rax
    mov qword ptr [rax + EJF_sealed], 1
    xor edi, edi
    xor esi, esi
    lea rdx, [rax + EJF_body + 16]
    call sha256_hash
    call ext_settings_memory_total
    mov r14d, ESM_CAP
    sub r14, rax
    mov rdi, r14
    call ext_settings_memory_reserve
    test rax, rax
    jnz ests_fail
    mov rdi, r13
    mov esi, 29
    call ext_settings_snapshot_begin
    test rax, rax
    jnz ests_fail
    cmp rdx, -12
    jne ests_fail
    cmp qword ptr [r13 + EJF_sealed], 1
    jne ests_fail
    mov rdi, r14
    call ext_settings_memory_release
    mov rdi, r13
    mov esi, 29
    call ext_settings_snapshot_begin
    test rax, rax
    jz ests_fail
    mov rbx, rax
    cmp qword ptr [rbx + ESB_exists], 0
    jne ests_fail
    mov rax, 0x7fffffffffffffff
    mov [rbx + ESB_refs], rax
    mov rdi, rbx
    call ext_settings_snapshot_retain
    cmp rax, -75
    jne ests_fail
    mov rdi, rbx
    call ext_settings_ini_begin
    test rax, rax
    jnz ests_fail
    cmp rdx, -75
    jne ests_fail
    mov qword ptr [rbx + ESB_refs], 1
    call ext_settings_memory_total
    mov r14d, ESM_CAP
    sub r14, rax
    mov rdi, r14
    call ext_settings_memory_reserve
    mov rdi, rbx
    call ext_settings_ini_begin
    test rax, rax
    jnz ests_fail
    cmp rdx, -12
    jne ests_fail
    cmp qword ptr [rbx + ESB_refs], 1
    jne ests_fail
    mov rdi, r14
    call ext_settings_memory_release
    mov rdi, rbx
    call ext_settings_ini_begin
    mov r12, rax
    test rax, rax
    jz ests_fail
    # Invalid composition budgets perform no work or state mutation.
    mov rdi, r12
    mov esi, 1
    xor edx, edx
    call ext_settings_ini_step_budget
    cmp rax, -22
    jne ests_fail
    or rdx, rcx
    jnz ests_fail
    cmp qword ptr [r12 + ESI_phase], ESIP_SCAN
    jne ests_fail
    mov rdi, r12
    mov esi, 1
    mov edx, 1025
    call ext_settings_ini_step_budget
    cmp rax, -22
    jne ests_fail
    or rdx, rcx
    jnz ests_fail
    cmp qword ptr [r12 + ESI_phase], ESIP_SCAN
    jne ests_fail
    mov rdi, r12
    xor esi, esi
    call ext_settings_ini_step
    cmp rax, -22
    jne ests_fail
    test rdx, rdx
    jnz ests_fail
    test rcx, rcx
    jnz ests_fail
    cmp qword ptr [r12 + ESI_phase], ESIP_SCAN
    jne ests_fail
    mov rdi, r12
    mov esi, 65537
    call ext_settings_ini_step
    cmp rax, -22
    jne ests_fail
    test rdx, rdx
    jnz ests_fail
    test rcx, rcx
    jnz ests_fail
    mov rdi, r12
    mov esi, 1
    mov edx, 1
    call ext_settings_ini_step_budget
    cmp rax, 2
    jne ests_fail
    test rdx, rdx
    jnz ests_fail
    cmp rcx, 1
    jne ests_fail
    mov rdi, r12
    call ext_settings_ini_free
    mov rdi, rbx
    call ext_settings_snapshot_release
    mov edi, 64
    call ext_settings_snapshot_gc
    cmp rax, 2
    jne ests_fail
    # Fully validated committed receipt of an existing empty file.
    lea rdi, [rip + ests_tag]
    mov esi, EW_COMMITTED
    mov edx, 80
    mov ecx, 1
    call ext_settings_frame_new
    test rax, rax
    jz ests_fail
    mov r13, rax
    mov qword ptr [rax + EJF_body], 3
    mov qword ptr [rax + EJF_body + 16], -5
    mov qword ptr [rax + EJF_body + 24], -6
    mov qword ptr [rax + EJF_body + 32], 1
    mov qword ptr [rax + EJF_sealed], 1
    xor edi, edi
    xor esi, esi
    lea rdx, [rax + EJF_body + 48]
    call sha256_hash
    mov rdi, r13
    mov esi, 29
    call ext_settings_snapshot_begin
    test rax, rax
    jz ests_fail
    mov rbx, rax
    cmp qword ptr [rbx + ESB_exists], 1
    jne ests_fail
    cmp qword ptr [rbx + ESB_length], 0
    jne ests_fail
    cmp qword ptr [rbx + ESB_round], 1
    jne ests_fail
    mov rdi, rbx
    mov esi, 1
    call ests_compare
    mov rdi, rbx
    call ext_settings_snapshot_release
    mov edi, 64
    call ext_settings_snapshot_gc
    cmp rax, 2
    jne ests_fail
    EPILOGUE
