.section .rodata
svh_owner: .asciz "survivor"
svh_name: .asciz "live"
.ifdef WINDOWS
svh_state: .asciz "C:/state"
.else
svh_state: .asciz "/state"
.endif
svh_expected: .ascii "[survivor/live]\ndisabled = yes\npinned = yes\n"
.equ SVH_EXPECTED_LEN, 44
.bss
.p2align 3
svh_hosts: .zero 3 * EXT_SIZE
svh_identity: .quad 0
svh_written: .quad 0
.text
# Called immediately after the original real HI take cleared all borrowed identity words.
svh_save:
    PROLOGUE
    lea rdi, [rip + svh_hosts]
    mov rsi, r12
    mov edx, EXT_SIZE
    call memcpy
    lea rbx, [rip + svh_hosts]
    mov dword ptr [rbx + EXT_pinned], 1
    mov dword ptr [rbx + EXT_disabled], 1
    mov dword ptr [rbx + EXT_catalog_state], 2
    # Retained historical HI is equally ineligible despite all strings being valid.
    lea r14, [rbx + 2 * EXT_SIZE]
    mov rax, [rip + hi_out]
    mov [r14 + EXT_identity_owner], rax
    mov rcx, [rax + HI_owner]
    mov [r14 + EXT_owner], rcx
    mov rcx, [rax + HI_name]
    mov [r14 + EXT_name], rcx
    mov rcx, [rax + HI_state]
    mov [r14 + EXT_state], rcx
    mov dword ptr [r14 + EXT_catalog_state], 2
    mov dword ptr [r14 + EXT_pinned], 1
    # A visible diagnostic HI with no metadata must still preserve its flags.
    lea rdi, [rip + svh_owner]
    lea rsi, [rip + svh_name]
    lea rdx, [rip + svh_state]
    xor ecx, ecx
    call ext_host_identity_create
    test rax, rax
    jz svh_fail
    test rdx, rdx
    jnz svh_fail
    mov [rip + svh_identity], rax
    lea r14, [rbx + EXT_SIZE]
    mov [r14 + EXT_identity_owner], rax
    mov rcx, [rax + HI_owner]
    mov [r14 + EXT_owner], rcx
    mov rcx, [rax + HI_name]
    mov [r14 + EXT_name], rcx
    mov rcx, [rax + HI_state]
    mov [r14 + EXT_state], rcx
    mov dword ptr [r14 + EXT_catalog_state], 1
    mov dword ptr [r14 + EXT_disabled], 1
    mov dword ptr [r14 + EXT_pinned], 1
    mov [rip + g_exts + VEC_ptr], rbx
    mov qword ptr [rip + g_exts + VEC_len], 3
    mov qword ptr [rip + g_exts + VEC_cap], 3
    call ext_settings_save
    cmp qword ptr [rip + svh_written], 1
    jne svh_fail
    call svh_free_buffers
    mov qword ptr [rip + g_exts + VEC_ptr], 0
    mov qword ptr [rip + g_exts + VEC_len], 0
    mov qword ptr [rip + g_exts + VEC_cap], 0
    mov rdi, [rip + svh_identity]
    call ext_host_identity_release
    test rax, rax
    jnz svh_fail
    cmp rdx, 1
    jne svh_fail
    mov qword ptr [rip + svh_identity], 0
    # The enclosing HI fixture independently drains and checks exact memory/charge census.
    EPILOGUE
FN ext_full_name
    cmp qword ptr [rdi + EXT_owner], 0
    je svh_missing_identity
    cmp qword ptr [rdi + EXT_name], 0
    je svh_missing_identity
    jmp svh_real_ext_full_name
svh_missing_identity:
    mov edi, 211
    call sys_exit
FN file_write_all
    PROLOGUE
    cmp rdx, SVH_EXPECTED_LEN
    jne svh_fail
    mov rdi, rsi
    lea rsi, [rip + svh_expected]
    mov edx, SVH_EXPECTED_LEN
    call memeq
    test eax, eax
    jz svh_fail
    inc qword ptr [rip + svh_written]
    xor eax, eax
    EPILOGUE
FN config_dir
    lea rax, [rip + svh_state]
    ret
FN mkdir_p
    xor eax, eax
    ret
svh_fail:
    mov edi, 212
    call sys_exit
