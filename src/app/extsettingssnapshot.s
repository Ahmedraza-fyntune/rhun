# Immutable complete helper receipt ownership. No file reads or metadata references.
.include "rhun.inc"
.include "app/extsettingssnapshot.inc"
.bss
.p2align 3
esb_retired_head: .quad 0
esb_retired_tail: .quad 0
.text
# begin(owned validated ECJ delivery,positive configContext)->ESB/NULL,RDX error.
# Trusted producer: only ECJ take_frame after complete correlated SHA verification.
# Refusal leaves the frame caller-owned; success transfers it without payload copy.
FN ext_settings_snapshot_begin
    test rdi, rdi
    jz .Lesb_bad
    test rsi, rsi
    jle .Lesb_bad
    cmp qword ptr [rdi + EJF_sealed], 1
    jne .Lesb_bad
    cmp qword ptr [rdi + EJF_tag], 0
    jle .Lesb_bad
    cmp qword ptr [rdi + EJF_tag + 8], 0
    jle .Lesb_bad
    mov eax, 48
    cmp qword ptr [rdi + EJF_kind], EW_SNAPSHOT
    je 1f
    cmp qword ptr [rdi + EJF_kind], EW_COMMITTED
    jne .Lesb_bad
    cmp qword ptr [rdi + EJF_length], 80
    jb .Lesb_bad
    cmp qword ptr [rdi + EJF_body], 3
    jne .Lesb_bad
    cmp qword ptr [rdi + EJF_body + 8], 0
    jne .Lesb_bad
    mov eax, 80
1:  cmp [rdi + EJF_length], rax
    jb .Lesb_bad
    lea rcx, [rdi + EJF_body + rax - 48]
    cmp qword ptr [rcx], 1
    ja .Lesb_bad
    mov rdx, [rcx + 8]
    cmp rdx, 1048576
    ja .Lesb_bad
    cmp qword ptr [rcx], 0
    jne 2f
    test rdx, rdx
    jnz .Lesb_bad
2:  add rdx, rax
    cmp [rdi + EJF_length], rdx
    jne .Lesb_bad
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rcx
    mov r14, rax
    mov edi, ESB_SIZE
    call ext_settings_memory_try
    test rax, rax
    jz 3f
    mov r15, rax
    mov qword ptr [rax + ESB_refs], 1
    mov [rax + ESB_frame], rbx
    mov [rax + ESB_context], r12
    mov rcx, [rbx + EJF_tag]
    mov [rax + ESB_job], rcx
    mov rcx, [rbx + EJF_tag + 8]
    mov [rax + ESB_source_context], rcx
    mov rcx, [rbx + EJF_round]
    mov [rax + ESB_round], rcx
    mov rcx, [r13]
    mov [rax + ESB_exists], rcx
    mov rcx, [r13 + 8]
    mov [rax + ESB_length], rcx
    lea rcx, [rbx + EJF_body + r14]
    mov [rax + ESB_bytes], rcx
    lea rdi, [rax + ESB_digest]
    lea rsi, [r13 + 16]
    mov edx, 32
    call memcpy
    mov qword ptr [r15 + ESB_ready], 1
    mov rax, r15
    xor edx, edx
3:  EPILOGUE
.Lesb_bad:
    xor eax, eax
    mov rdx, -22
    ret
FN ext_settings_snapshot_retain
    test rdi, rdi
    jz 1f
    cmp qword ptr [rdi + ESB_refs], 0
    jle 1f
    mov rax, 0x7fffffffffffffff
    cmp [rdi + ESB_refs], rax
    jae 2f
    inc qword ptr [rdi + ESB_refs]
    xor eax, eax
    ret
1:  mov rax, -22
    ret
2:  mov rax, -75
    ret
# release only links retired ownership. No free or byte scan on a publication path.
FN ext_settings_snapshot_release
    test rdi, rdi
    jz 3f
    cmp qword ptr [rdi + ESB_refs], 0
    jle 4f
    dec qword ptr [rdi + ESB_refs]
    jnz 3f
    mov qword ptr [rdi + ESB_next], 0
    mov rax, [rip + esb_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + ESB_next], rdi
    jmp 2f
1:  mov [rip + esb_retired_head], rdi
2:  mov [rip + esb_retired_tail], rdi
3:  xor eax, eax
    ret
4:  mov rax, -22
    ret
# gc(maxUnits1..64)->ownership units retired,RDX first cleanup.
# Frame transfer and owner transfer are separate units, so budget1 always progresses.
FN ext_settings_snapshot_gc
    test rdi, rdi
    jz .Lesbg_invalid
    cmp rdi, 64
    ja .Lesbg_invalid
    PROLOGUE 16
    mov r12, rdi
    xor r13d, r13d
    mov qword ptr [rsp], 0
.Lesbg_loop:
    test r12, r12
    jz .Lesbg_return
    mov rbx, [rip + esb_retired_head]
    test rbx, rbx
    jz .Lesbg_return
    mov rdi, [rbx + ESB_frame]
    test rdi, rdi
    jz .Lesbg_owner
    call ext_settings_frame_free
    cmp rcx, 1
    jne .Lesbg_refused
    # The owner remains queued for its separate self-release unit.
    mov qword ptr [rbx + ESB_frame], 0
    jmp .Lesbg_accepted
.Lesbg_owner:
    mov r14, [rbx + ESB_next]
    mov [rip + esb_retired_head], r14
    test r14, r14
    jnz 1f
    mov qword ptr [rip + esb_retired_tail], 0
1:  mov rdi, rbx
    call ext_settings_memory_free
    cmp rcx, 1
    je .Lesbg_accepted
    # Refusal did not consume the accessible owner. Restore exact list ownership.
    mov [rip + esb_retired_head], rbx
    test r14, r14
    jnz .Lesbg_refused
    mov [rip + esb_retired_tail], rbx
.Lesbg_refused:
    cmp qword ptr [rsp], 0
    jne .Lesbg_return
    mov [rsp], rax
    jmp .Lesbg_return
.Lesbg_accepted:
    test rdx, rdx
    jns 2f
    cmp qword ptr [rsp], 0
    jne 2f
    mov [rsp], rdx
2:  dec r12
    inc r13
    jmp .Lesbg_loop
.Lesbg_return:
    mov rax, r13
    mov rdx, [rsp]
    EPILOGUE
.Lesbg_invalid:
    mov rax, -22
    xor edx, edx
    ret
