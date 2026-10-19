# Final view release queues preowned retirement; GC owns each field until transfer.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsview.inc"
.bss
.p2align 3
esv_retired_head: .quad 0
esv_retired_tail: .quad 0
esv_retired_count: .quad 0
.text
FN ext_settings_view_retain
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + EV_refs], 0
    jle 1f
    mov rax, 0x7fffffffffffffff
    cmp [rdi + EV_refs], rax
    jae 2f
    inc qword ptr [rdi + EV_refs]
    xor eax, eax
    ret
1:  mov rax, -22
    ret
2:  mov rax, -75
    ret
FN ext_settings_view_release
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + EV_refs], 0
    jle 4f
    dec qword ptr [rdi + EV_refs]
    jnz 3f
    mov qword ptr [rdi + EV_next], 0
    mov rax, [rip + esv_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + EV_next], rdi
    jmp 2f
1:  mov [rip + esv_retired_head], rdi
2:  mov [rip + esv_retired_tail], rdi
    inc qword ptr [rip + esv_retired_count]
3:  xor eax, eax
    ret
4:  mov rax, -22
    ret
FN ext_settings_view_pending
    mov rax, [rip + esv_retired_count]
    ret
# gc(maxUnits1..64)->logical ownership units,RDX first cleanup.
# At most one free/release per unit. Native failed frees transfer to ESM backoff.
FN ext_settings_view_gc
    test rdi, rdi
    jz .Lesvg_invalid
    cmp rdi, 64
    ja .Lesvg_invalid
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
    xor r15d, r15d
.Lesvg_loop:
    test r12, r12
    jz .Lesvg_return
    mov rbx, [rip + esv_retired_head]
    test rbx, rbx
    jz .Lesvg_return
    mov rax, [rbx + EV_gcindex]
    cmp rax, [rbx + EV_count]
    jae .Lesvg_extra
    imul rax, EVR_SIZE
    lea r14, [rbx + rax + EV_rows]
    mov rax, [rbx + EV_gcphase]
    test rax, rax
    jz .Lesvg_value
    cmp rax, 1
    je .Lesvg_base
    lea r14, [r14 + EVR_key]
    jmp .Lesvg_owned
.Lesvg_value:
    test qword ptr [r14 + EVR_flags], EVR_ALIAS_BASE
    jz 1f
    mov qword ptr [r14 + EVR_value], 0
    jmp .Lesvg_advance
1:  lea r14, [r14 + EVR_value]
    jmp .Lesvg_owned
.Lesvg_base:
    lea r14, [r14 + EVR_base]
    jmp .Lesvg_owned
.Lesvg_extra:
    mov rax, [rbx + EV_gcphase]
    cmp rax, 3
    jae 1f
    mov qword ptr [rbx + EV_gcphase], 3
    mov eax, 3
1:  cmp rax, 3
    je .Lesvg_work
    cmp rax, 4
    je .Lesvg_section
    cmp rax, 5
    je .Lesvg_cursor
    cmp rax, 6
    je .Lesvg_previous
    cmp rax, 7
    je .Lesvg_model
    cmp rax, 8
    je .Lesvg_source
    cmp rax, 9
    je .Lesvg_ep
    # Detach only after self ownership has actually transferred.
    mov r14, [rbx + EV_next]
    mov rdi, rbx
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lesvg_blocked
    mov [rip + esv_retired_head], r14
    test r14, r14
    jnz 2f
    mov qword ptr [rip + esv_retired_tail], 0
2:  dec qword ptr [rip + esv_retired_count]
    jmp .Lesvg_self_done
.Lesvg_work:
    lea r14, [rbx + EV_work]
    jmp .Lesvg_owned
.Lesvg_section:
    lea r14, [rbx + EV_section]
    jmp .Lesvg_owned
.Lesvg_cursor:
    lea r14, [rbx + EV_cursor]
    mov rdi, [r14]
    test rdi, rdi
    jz .Lesvg_advance
    call ext_settings_ini_free
    cmp rcx, 1
    jne .Lesvg_blocked
    mov qword ptr [r14], 0
    jmp .Lesvg_note
.Lesvg_previous:
    lea r14, [rbx + EV_previous]
    mov rdi, [r14]
    call ext_settings_view_release
    jmp .Lesvg_reference
.Lesvg_model:
    lea r14, [rbx + EV_oldmodel]
    mov rdi, [r14]
    call ext_settings_model_release
    jmp .Lesvg_reference
.Lesvg_source:
    lea r14, [rbx + EV_source]
    mov rdi, [r14]
    call ext_settings_snapshot_release
    jmp .Lesvg_reference
.Lesvg_ep:
    lea r14, [rbx + EV_ep]
    mov rdi, [r14]
    test rdi, rdi
    jz .Lesvg_advance
    call ext_prepare_release_deferred
.Lesvg_reference:
    test rax, rax
    jnz .Lesvg_blocked
    mov qword ptr [r14], 0
    jmp .Lesvg_advance
.Lesvg_owned:
    mov rdi, [r14]
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lesvg_blocked
    mov qword ptr [r14], 0
.Lesvg_note:
    test rdx, rdx
    jns .Lesvg_advance
    test r15, r15
    jnz .Lesvg_advance
    mov r15, rdx
.Lesvg_advance:
    inc qword ptr [rbx + EV_gcphase]
    cmp qword ptr [rbx + EV_gcphase], 3
    jne .Lesvg_unit
    inc qword ptr [rbx + EV_gcindex]
    mov qword ptr [rbx + EV_gcphase], 0
.Lesvg_unit:
    inc r13
    dec r12
    jmp .Lesvg_loop
.Lesvg_self_done:
    test rdx, rdx
    jns .Lesvg_unit
    test r15, r15
    jnz .Lesvg_unit
    mov r15, rdx
    jmp .Lesvg_unit
.Lesvg_blocked:
    test r15, r15
    jnz .Lesvg_return
    test rax, rax
    js 1f
    mov rax, -22
1:  mov r15, rax
.Lesvg_return:
    mov rax, r13
    mov rdx, r15
    EPILOGUE
.Lesvg_invalid:
    mov rax, -22
    xor edx, edx
    ret
