.equ CFD_OK_LEN, 59
# Real retained suppliers and exact immutable fallback routes. No live bridge is claimed.
.bss
.p2align 3
cfd_case: .quad 0
cfd_cg: .quad 0
cfd_ros: .zero 24
cfd_route: .zero 40
cfd_saved_route: .zero 40
cfd_ordinal: .quad 0
cfd_session: .quad 0
.text
cfd_ro:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rdi, rsi
    call strlen
    lea rdi, [rip + cgbt_roc]
    lea rcx, [rip + cgbt_exts + 7 * EXT_SIZE]
    mov [rdi + ROC_target], rcx
    mov rcx, [rip + cfd_session]
    mov [rdi + ROC_session], rcx
    lea rcx, [rip + cfd_owner]
    mov [rdi + ROC_owner], rcx
    lea rcx, [rip + cfd_name]
    mov [rdi + ROC_name], rcx
    mov [rdi + ROC_key], r12
    lea rcx, [rip + cfd_title]
    mov [rdi + ROC_title], rcx
    mov [rdi + ROC_keys], r13
    mov [rdi + ROC_keyslen], rax
    call ext_runtime_new
    test rax, rax
    jz cgbt_fail
    EPILOGUE
cfd_prepare:
    PROLOGUE
    call cgbt_new
    mov rbx, rax
    mov [rip + cfd_cg], rax
    # Getter refuses an unready owner without touching output.
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + cfd_route]
    call command_generation_binding_route
    cmp rax, -22
    jne cgbt_fail
    lea rdi, [rip + cfd_owner]
    lea rsi, [rip + cfd_name]
    lea rdx, [rip + cfd_title]
    call cgbt_ep
    mov r12, rax
    mov rdi, rax
    lea rsi, [rip + cfd_base]
    lea rdx, [rip + cfd_base_value]
    call cgbt_command
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + cgbt_exts + 7 * EXT_SIZE]
    mov ecx, 7
    call command_generation_add_extension
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    cmp qword ptr [rip + cfd_case], 5
    je .Lcfd_build
    xor r14d, r14d
1:  lea rax, [rip + cfd_keys]
    mov rdi, [rax + r14 * 8]
    lea rax, [rip + cfd_specs]
    mov rsi, [rax + r14 * 8]
    call cfd_ro
    lea rcx, [rip + cfd_ros]
    mov [rcx + r14 * 8], rax
    mov r12, rax
    mov rdi, rbx
    mov rsi, rax
    call command_generation_add_runtime
    test rax, rax
    jnz cgbt_fail
    mov rdi, r12
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgbt_fail
    inc r14
    cmp r14, 3
    jb 1b
    mov rax, [rip + cfd_case]
    test rax, rax
    jz .Lcfd_build
    lea rsi, [rip + cfd_combo9]
    lea rdx, [rip + cfd_first_query]
    cmp rax, 1
    je 2f
    lea rdx, [rip + cfd_second_query]
    cmp rax, 2
    je 2f
    lea rdx, [rip + cfd_unknown_query]
    cmp rax, 3
    je 2f
    lea rsi, [rip + cfd_combo7]
    lea rdx, [rip + cfd_third_query]
2:  mov rdi, rbx
    call cgbt_line
    cmp qword ptr [rip + cfd_case], 3
    jne .Lcfd_build
    mov rdi, rbx
    lea rsi, [rip + cfd_combo9]
    lea rdx, [rip + cfd_none]
    call cgbt_line
.Lcfd_build:
    # Dropping caller references must not leave any supplier queued for destruction.
    lea rdi, [rip + cgbt_retire]
    call ext_prepare_retire_status
    mov rax, [rip + cgbt_retire + 8]
    or rax, [rip + cgbt_retire + 16]
    jnz cgbt_fail
    mov rdi, rbx
    call cgbt_build
    EPILOGUE
# Independent search of the legacy-compatible final KB table, by literal key/mods.
cfd_find:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + cfd_cg]
    xor r14d, r14d
1:  cmp r14, [rbx + CG_bindings + VEC_len]
    jae cgbt_fail
    mov rax, r14
    shl rax, 4
    add rax, [rbx + CG_bindings + VEC_ptr]
    cmp [rax + KB_key], r12d
    jne 2f
    cmp [rax + KB_mods], r13d
    je 3f
2:  inc r14
    jmp 1b
3:  mov [rip + cfd_ordinal], r14
    mov rdi, rbx
    mov rsi, r14
    lea rdx, [rip + cfd_route]
    mov r15, [rip + cgbt_all_alloc_calls]
    call command_generation_binding_route
    cmp [rip + cgbt_all_alloc_calls], r15
    jne cgbt_fail
    test rax, rax
    jnz cgbt_fail
    EPILOGUE
# Validate chain topology against an independent literal row-index list, not current KB winner.
cfd_chain:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov rbx, [rip + cfd_cg]
    mov r14, [rip + cfd_route + 16]
    xor r15d, r15d
1:  cmp r15, r13
    jae 3f
    test r14, r14
    jz cgbt_fail
    cmp r14, [rip + cfd_route + 24]
    ja cgbt_fail
    dec r14
    shl r14, 4
    add r14, [rip + cfd_route + 8]
    mov rax, [r12 + r15 * 8]
    shl rax, 5
    add rax, [rbx + CG_commands + VEC_ptr]
    cmp [r14], rax
    jne cgbt_fail
    mov r14, [r14 + 8]
    inc r15
    jmp 1b
3:  test r14, r14
    jnz cgbt_fail
    EPILOGUE
# Minimal simulated native authority. Production bridge is separately required.
cfd_resolve:
    mov r8, [rip + cfd_cg]
    mov rax, [rip + cfd_route]
    cmp qword ptr [rip + cfd_route + 32], 0
    jne 4f
    mov rcx, [rip + cfd_route + 16]
    test rcx, rcx
    jz 4f
    mov r9d, 8192
1:  test rcx, rcx
    jz 8f
    cmp rcx, [rip + cfd_route + 24]
    ja cgbt_fail
    dec rcx
    shl rcx, 4
    add rcx, [rip + cfd_route + 8]
    mov rax, [rcx]
    mov r10, [rcx + 8]
    call cfd_live
    test eax, eax
    jnz 6f
    mov rcx, r10
    dec r9
    jnz 1b
    jmp cgbt_fail
4:  mov r10, rax
    call cfd_live
    test eax, eax
    jz 8f
    mov rax, r10
    ret
6:  mov rax, [rcx]
    ret
8:  call keys_none_command
    ret
# RAX current command, R8 CG. Leaves RCX/R9/R10 available to traversal.
cfd_live:
    sub rax, [r8 + CG_commands + VEC_ptr]
    test rax, 31
    jnz 2f
    shr rax, 5
    cmp rax, [r8 + CG_ncommands]
    jae 2f
    shl rax, 6
    add rax, [r8 + CG_authority + VEC_ptr]
    cmp qword ptr [rax], 1
    jne 2f
    mov rdx, [rax + 8]
    cmp qword ptr [rdx + RO_live], 1
    jne 3f
    mov rax, [rdx + RO_session]
    cmp rax, [rip + cfd_session]
    jne 3f
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret
FN main
    PROLOGUE
    mov qword ptr [rip + cgbt_context], 11
    mov qword ptr [rip + cgbt_context + 8], 12
    mov qword ptr [rip + cgbt_context + 16], 13
    mov qword ptr [rip + cfd_session], 99
    mov rax, [rip + g_mem_live]
    mov [rip + cgbt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgbt_charge], rax
    mov qword ptr [rip + cfd_case], 0
.Lcfd_case:
    mov rax, [rip + cfd_case]
    mov [rip + cgbt_stage], rax
    call cfd_prepare
    cmp qword ptr [rip + cfd_case], 5
    je .Lcfd_no_runtime
    mov edi, '9'
    mov esi, MOD_CTRL | MOD_ALT
    call cfd_find
    lea rdi, [rip + cfd_expected3]
    mov esi, 3
    call cfd_chain
    mov rax, [rip + cfd_case]
    xor edx, edx
    test rax, rax
    jz 1f
    cmp rax, 4
    je 1f
    inc edx
1:  cmp [rip + cfd_route + 32], rdx
    jne cgbt_fail
    # The getter's direct winner must be exact even when a default chain exists.
    cmp rax, 3
    je .Lcfd_initial_none
    mov rbx, [rip + cfd_cg]
    mov rdx, [rbx + CG_commands + VEC_ptr]
    add rdx, 32
    cmp rax, 2
    jne .Lcfd_initial_compare
    add rdx, 32
    jmp .Lcfd_initial_compare
.Lcfd_initial_none:
    call keys_none_command
    mov rdx, rax
.Lcfd_initial_compare:
    cmp [rip + cfd_route], rdx
    jne cgbt_fail
    mov rax, [rip + cfd_case]
    test rax, rax
    jnz .Lcfd_other_cases
    call cfd_resolve
    mov rbx, [rip + cfd_cg]
    mov rdx, [rbx + CG_commands + VEC_ptr]
    add rdx, 32
    cmp rax, rdx
    jne cgbt_fail
    mov rdi, [rip + cfd_ros]
    call ext_runtime_revoke
    call cfd_resolve
    mov rdx, [rbx + CG_commands + VEC_ptr]
    add rdx, 64
    cmp rax, rdx
    jne cgbt_fail
    mov qword ptr [rip + cfd_session], 100
    lea rdi, [rip + cfd_first]
    lea rsi, [rip + cfd_spec3]
    call cfd_ro
    mov r12, rax
    call cfd_resolve
    mov r13, rax
    call keys_none_command
    cmp rax, r13
    jne cgbt_fail
    mov rdi, r12
    call ext_runtime_release_deferred
    mov qword ptr [rip + cfd_session], 99
    mov rdi, [rip + cfd_ros + 8]
    call ext_runtime_revoke
    mov rdi, [rip + cfd_ros + 16]
    call ext_runtime_revoke
    call cfd_resolve
    mov r13, rax
    call keys_none_command
    cmp rax, r13
    jne cgbt_fail
.Lcfd_other_cases:
    mov rax, [rip + cfd_case]
    cmp rax, 1
    je .Lcfd_user_live
    cmp rax, 2
    jne .Lcfd_after_user_live
.Lcfd_user_live:
    call cfd_resolve
    cmp rax, [rip + cfd_route]
    jne cgbt_fail
.Lcfd_after_user_live:
    cmp qword ptr [rip + cfd_case], 1
    jne 2f
    mov rdi, [rip + cfd_ros]
    call ext_runtime_revoke
    call cfd_resolve
    mov r13, rax
    call keys_none_command
    cmp rax, r13
    jne cgbt_fail
2:  mov edi, '8'
    mov esi, MOD_CTRL | MOD_ALT
    call cfd_find
    lea rdi, [rip + cfd_expected2]
    mov esi, 2
    call cfd_chain
    cmp qword ptr [rip + cfd_route + 32], 0
    jne cgbt_fail
    mov edi, 'm'
    mov esi, MOD_CTRL | MOD_ALT
    call cfd_find
    cmp qword ptr [rip + cfd_route + 16], 0
    jne cgbt_fail
    mov rbx, [rip + cfd_cg]
    mov rax, [rbx + CG_commands + VEC_ptr]
    cmp rax, [rip + cfd_route]
    jne cgbt_fail
    mov edi, 'p'
    mov esi, MOD_CTRL
    call cfd_find
    cmp qword ptr [rip + cfd_route + 16], 0
    jne cgbt_fail
    lea rax, [rip + g_commands]
    cmp rax, [rip + cfd_route]
    jne cgbt_fail
    cmp qword ptr [rip + cfd_case], 4
    jne .Lcfd_getter_checks
    mov edi, '7'
    mov esi, MOD_CTRL | MOD_ALT
    call cfd_find
    cmp qword ptr [rip + cfd_route + 16], 0
    jne cgbt_fail
    cmp qword ptr [rip + cfd_route + 32], 1
    jne cgbt_fail
    mov rax, [rbx + CG_commands + VEC_ptr]
    add rax, 96
    cmp [rip + cfd_route], rax
    jne cgbt_fail
    call cfd_resolve
    cmp rax, [rip + cfd_route]
    jne cgbt_fail
    jmp .Lcfd_getter_checks
.Lcfd_no_runtime:
    mov edi, 'm'
    mov esi, MOD_CTRL | MOD_ALT
    call cfd_find
    mov rax, [rip + cfd_route + 8]
    or rax, [rip + cfd_route + 16]
    or rax, [rip + cfd_route + 24]
    or rax, [rip + cfd_route + 32]
    jnz cgbt_fail
.Lcfd_getter_checks:
    # Pending intent changes cannot invalidate owned immutable getters.
    inc qword ptr [rip + cgbt_context]
    mov rdi, [rip + cfd_cg]
    lea rsi, [rip + cgbt_context]
    call command_generation_check
    cmp rax, -116
    jne cgbt_fail
    mov rdi, [rip + cfd_cg]
    mov rsi, [rip + cfd_ordinal]
    lea rdx, [rip + cfd_route]
    call command_generation_binding_route
    test rax, rax
    jnz cgbt_fail
    mov rdi, [rip + cfd_cg]
    xor esi, esi
    xor edx, edx
    call command_generation_binding_route
    cmp rax, -22
    jne cgbt_fail
    mov rbx, [rip + cfd_cg]
    lea rdi, [rip + cfd_saved_route]
    lea rsi, [rip + cfd_route]
    mov edx, 40
    call memcpy
    mov rsi, [rbx + CG_bindings + VEC_len]
    mov rdi, rbx
    lea rdx, [rip + cfd_route]
    call command_generation_binding_route
    cmp rax, -22
    jne cgbt_fail
    lea rdi, [rip + cfd_saved_route]
    lea rsi, [rip + cfd_route]
    mov edx, 40
    call memeq
    test eax, eax
    jz cgbt_fail
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + cfd_route]
    call command_generation_binding_route
    cmp rax, -22
    jne cgbt_fail
    lea rdi, [rip + cfd_saved_route]
    lea rsi, [rip + cfd_route]
    mov edx, 40
    call memeq
    test eax, eax
    jz cgbt_fail
    mov rdi, rbx
    call cgbt_abort
    inc qword ptr [rip + cfd_case]
    cmp qword ptr [rip + cfd_case], 5
    jbe .Lcfd_case
    mov edi, 1
    lea rsi, [rip + cfd_ok]
    mov edx, CFD_OK_LEN
    call write_all
    xor eax, eax
    EPILOGUE
.section .rodata
cfd_owner: .asciz "owner"
cfd_name: .asciz "tool"
cfd_title: .asciz "Dynamic"
cfd_base: .asciz "base"
cfd_base_value: .asciz "Base | ctrl+alt+m"
cfd_first: .asciz "first"
cfd_second: .asciz "second"
cfd_third: .asciz "third"
cfd_spec1: .asciz "ctrl+alt+9 ctrl+alt+8 ctrl+alt+9 ctrl+alt+m ctrl+p"
cfd_spec2: .asciz "ctrl+alt+9 ctrl+alt+8"
cfd_spec3: .asciz "ctrl+alt+9"
cfd_combo9: .asciz "ctrl+alt+9"
cfd_combo7: .asciz "ctrl+alt+7"
cfd_first_query: .asciz "owner/tool.first"
cfd_second_query: .asciz "owner/tool.second"
cfd_third_query: .asciz "owner/tool.third"
cfd_unknown_query: .asciz "owner/tool.missing"
cfd_none: .asciz "none"
.p2align 3
cfd_keys: .quad cfd_first,cfd_second,cfd_third
cfd_specs: .quad cfd_spec1,cfd_spec2,cfd_spec3
cfd_expected3: .quad 1,2,3
cfd_expected2: .quad 1,2
cfd_ok: .ascii "ok immutable runtime default chains and override authority\n"
cfd_ok_end:

.text
FN cfd_getter_alloc_noise
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov edi, 8
    call mem_alloc_try
    test rax, rax
    jz cgbt_fail
    mov rdi, rax
    call mem_free
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    EPILOGUE

