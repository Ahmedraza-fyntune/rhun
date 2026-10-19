# Plans retire their own input references independently of installed models.
.include "rhun.inc"
.include "app/extsettingscatalog.inc"
.bss
.p2align 3
catalog_retired_head: .quad 0
catalog_retired_tail: .quad 0
catalog_retired_count: .quad 0
.text
FN ext_settings_catalog_retain
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + CP_refs], 0
    jle 1f
    mov rax, 0x7fffffffffffffff
    cmp [rdi + CP_refs], rax
    jae 2f
    inc qword ptr [rdi + CP_refs]
    xor eax, eax
    ret
1:  mov rax, -22
    ret
2:  mov rax, -75
    ret
FN ext_settings_catalog_release
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + CP_refs], 0
    jle 4f
    dec qword ptr [rdi + CP_refs]
    jnz 3f
    mov qword ptr [rdi + CP_next], 0
    mov rax, [rip + catalog_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + CP_next], rdi
    jmp 2f
1:  mov [rip + catalog_retired_head], rdi
2:  mov [rip + catalog_retired_tail], rdi
    inc qword ptr [rip + catalog_retired_count]
3:  xor eax, eax
    ret
4:  mov rax, -22
    ret
FN ext_settings_catalog_pending
    mov rax, [rip + catalog_retired_count]
    ret
# Each reference drop or checked allocation transfer is one resumable unit.
FN ext_settings_catalog_gc
    test rdi, rdi
    jz .Lcpg_invalid
    cmp rdi, 64
    ja .Lcpg_invalid
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
    xor r15d, r15d
.Lcpg_loop:
    test r12, r12
    jz .Lcpg_return
    mov rbx, [rip + catalog_retired_head]
    test rbx, rbx
    jz .Lcpg_return
    mov rcx, [rbx + CP_gcindex]
    cmp rcx, [rbx + CP_count]
    jae .Lcpg_extra
    imul rcx, CPR_SIZE
    lea r14, [rbx + CP_rows + rcx + CPR_view]
    mov rdi, [r14]
    call ext_settings_view_release
    test rax, rax
    jnz .Lcpg_blocked
    mov qword ptr [r14], 0
    inc qword ptr [rbx + CP_gcindex]
    jmp .Lcpg_unit
.Lcpg_extra:
    mov rax, [rbx + CP_gcphase]
    test rax, rax
    jz .Lcpg_cursor
    cmp rax, 1
    je .Lcpg_baseline
    cmp rax, 2
    je .Lcpg_model
    cmp rax, 3
    je .Lcpg_oldmodel
    cmp rax, 4
    je .Lcpg_source
    mov r14, [rbx + CP_next]
    mov rdi, rbx
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lcpg_blocked
    mov [rip + catalog_retired_head], r14
    test r14, r14
    jnz 1f
    mov qword ptr [rip + catalog_retired_tail], 0
1:  dec qword ptr [rip + catalog_retired_count]
    jmp .Lcpg_note
.Lcpg_cursor:
    lea r14, [rbx + CP_cursor]
    mov rdi, [r14]
    test rdi, rdi
    jz .Lcpg_advance
    call ext_settings_ini_free
    cmp rcx, 1
    jne .Lcpg_blocked
    mov qword ptr [r14], 0
    inc qword ptr [rbx + CP_gcphase]
    jmp .Lcpg_note
.Lcpg_baseline:
    lea r14, [rbx + CP_baseline]
    mov rdi, [r14]
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lcpg_blocked
    mov qword ptr [r14], 0
    inc qword ptr [rbx + CP_gcphase]
    jmp .Lcpg_note
.Lcpg_model:
    lea r14, [rbx + CP_model]
    mov rdi, [r14]
    call ext_settings_model_release
    jmp .Lcpg_reference
.Lcpg_oldmodel:
    lea r14, [rbx + CP_oldref]
    mov rdi, [r14]
    call ext_settings_model_release
    jmp .Lcpg_reference
.Lcpg_source:
    lea r14, [rbx + CP_source]
    mov rdi, [r14]
    call ext_settings_snapshot_release
.Lcpg_reference:
    test rax, rax
    jnz .Lcpg_blocked
    mov qword ptr [r14], 0
.Lcpg_advance:
    inc qword ptr [rbx + CP_gcphase]
    jmp .Lcpg_unit
.Lcpg_note:
    test rdx, rdx
    jns .Lcpg_unit
    test r15, r15
    jnz .Lcpg_unit
    mov r15, rdx
.Lcpg_unit:
    inc r13
    dec r12
    jmp .Lcpg_loop
.Lcpg_blocked:
    test r15, r15
    jnz .Lcpg_return
    test rax, rax
    js 1f
    mov rax, -22
1:  mov r15, rax
.Lcpg_return:
    mov rax, r13
    mov rdx, r15
    EPILOGUE
.Lcpg_invalid:
    mov rax, -22
    xor edx, edx
    ret
