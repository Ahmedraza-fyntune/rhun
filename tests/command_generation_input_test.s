# Owned suppliers, partial constructors and chunk boundaries for private command generations.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/extruntime.inc"
.include "app/commandgeneration.inc"
.include "app/keycombo.inc"
.bss
.p2align 3
cgt_stage: .quad 0
cgt_live: .quad 0
cgt_charge: .quad 0
cgt_fail_mark: .quad 0
cgt_fail_alloc: .quad 0
cgt_alloc_count: .quad 0
cgt_retire: .zero 32
cgt_ini: .zero INI_SIZE
cgt_input: .zero 32
cgt_expected: .zero 32
cgt_identity_owner: .zero 16
cgt_identity_name: .zero 16
cgt_bytes: .zero 4097
cgt_namebuf: .zero 8
.text
cgt_fail:
    mov rdi, [rip + cgt_stage]
    add rdi, 80
    call sys_exit
    ud2
FN cgt_mark
    cmp qword ptr [rip + cgt_fail_mark], 0
    je ext_prepare_retire_mark_custom_po
    mov rax, -5
    ret
.ifndef CGT_INSTRUMENTED
FN cgt_real_alloc
    jmp mem_alloc_try
.endif
FN cgt_alloc
    cmp qword ptr [rip + cgt_fail_alloc], 0
    je cgt_real_alloc
    inc qword ptr [rip + cgt_alloc_count]
    mov rax, [rip + cgt_alloc_count]
    cmp rax, [rip + cgt_fail_alloc]
    jne cgt_real_alloc
    xor eax, eax
    ret
cgt_new:
    PROLOGUE
    lea rdi, [rip + cgt_context]
    call command_generation_begin
    test rcx, rcx
    jnz cgt_fail
    test rax, rax
    jz cgt_fail
    test rdx, rdx
    jnz cgt_fail
    test rcx, rcx
    jnz cgt_fail
    EPILOGUE
cgt_drain:
    PROLOGUE
    mov ebx, 65536
1:  mov edi, 1
    lea rsi, [rip + cgt_retire]
    call ext_prepare_retire_step
    test rax, rax
    js cgt_fail
    cmp qword ptr [rip + cgt_retire], 1
    ja cgt_fail
    cmp qword ptr [rip + cgt_retire + 16], 0
    jne cgt_fail
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp cgt_fail
2:  call ext_prepare_retire_charge
    cmp rax, [rip + cgt_charge]
    jne cgt_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + cgt_live]
    jne cgt_fail
    EPILOGUE
cgt_abort:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + g_mem_live]
    call command_generation_release_deferred
    test rax, rax
    jnz cgt_fail
    cmp rdx, 1
    jne cgt_fail
    cmp [rip + g_mem_live], r12
    jne cgt_fail
    cmp qword ptr [rbx + PO_refs], 0
    jne cgt_fail
    call cgt_drain
    EPILOGUE

FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + cgt_live], rax
    call ext_prepare_retire_charge
    mov [rip + cgt_charge], rax
    mov qword ptr [rip + cgt_stage], 1
    call cgt_new
    mov rbx, rax
    cmp qword ptr [rbx + PO_refs], 1
    jne cgt_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_kind], 4
    jne cgt_fail
    cmp qword ptr [rbx + CG_intent], 11
    jne cgt_fail
    cmp qword ptr [rbx + CG_keyepoch], 12
    jne cgt_fail
    cmp qword ptr [rbx + CG_visibility], 13
    jne cgt_fail
    # Actual prepared command callback supplies a ready product, without native source handles.
    mov rdi, -1
    lea rsi, [rip + cgt_path]
    lea rdx, [rip + cgt_owner]
    lea rcx, [rip + cgt_name]
    call ext_prepare_alloc
    test rax, rax
    jz cgt_fail
    mov r12, rax
    mov rdi, rax
    call ext_prepare_enable_deferred
    lea rax, [rip + cgt_key]
    mov [rip + cgt_ini + INI_key], rax
    mov qword ptr [rip + cgt_ini + INI_keylen], 3
    lea rax, [rip + cgt_value]
    mov [rip + cgt_ini + INI_val], rax
    mov qword ptr [rip + cgt_ini + INI_vallen], 12
    mov rdi, r12
    lea rsi, [rip + cgt_ini]
    call ext_prepare_command_add
    test rax, rax
    jnz cgt_fail
    mov qword ptr [r12 + PO_ready], 1
    mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    mov ecx, 17
    call command_generation_add_extension
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [r12 + PO_refs], 2
    jne cgt_fail
    mov rdi, r12
    call ext_prepare_release_deferred
    cmp rdx, 1
    jne cgt_fail
    cmp qword ptr [r12 + PO_refs], 1
    jne cgt_fail
    cmp qword ptr [rbx + CG_nmanifest], 1
    jne cgt_fail
    cmp qword ptr [rbx + CG_slots + CS_ordinal], 17
    jne cgt_fail
    cmp [rbx + CG_slots + CS_ep], r12
    jne cgt_fail
    # Failed/disabled identities still own names independently and affect later alias resolution.
    lea rdi, [rip + cgt_identity_owner]
    lea rsi, [rip + cgt_other]
    mov edx, 6
    call memcpy
    lea rdi, [rip + cgt_identity_name]
    lea rsi, [rip + cgt_name]
    mov edx, 5
    call memcpy
    mov rdi, rbx
    mov esi, 2
    mov edx, 91
    lea rcx, [rip + cgt_identity_owner]
    lea r8, [rip + cgt_identity_name]
    call command_generation_add_identity
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [rbx + CG_nslots], 2
    jne cgt_fail
    cmp qword ptr [rbx + CG_slots + CS_SIZE + CS_ep], 0
    jne cgt_fail
    mov byte ptr [rip + cgt_identity_owner], '!'
    mov byte ptr [rip + cgt_identity_owner + 5], '!'
    mov byte ptr [rip + cgt_identity_name], '!'
    mov byte ptr [rip + cgt_identity_name + 4], '!'
    mov rdi, [rbx + CG_slots + CS_SIZE + CS_name]
    lea rsi, [rip + cgt_name]
    call strcmp_eq
    test eax, eax
    jz cgt_fail
    mov rdi, [rbx + CG_slots + CS_SIZE + CS_owner]
    lea rsi, [rip + cgt_other]
    cmp rdi, rsi
    je cgt_fail
    call strcmp_eq
    test eax, eax
    jz cgt_fail
    lea rdi, [rip + cgt_runtime]
    call ext_runtime_new
    test rax, rax
    jz cgt_fail
    mov r13, rax
    mov rdi, rbx
    mov rsi, r13
    call command_generation_add_runtime
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [r13 + RO_refs], 2
    jne cgt_fail
    mov rdi, r13
    call ext_runtime_release_deferred
    cmp rdx, 1
    jne cgt_fail
    cmp qword ptr [r13 + RO_refs], 1
    jne cgt_fail
    cmp qword ptr [rbx + CG_nruntimes], 1
    jne cgt_fail
    cmp qword ptr [rbx + CG_ncommands], 2
    jne cgt_fail
    # A chunk may cross the separately terminated combo/command boundary.
    lea rdi, [rip + cgt_input]
    lea rsi, [rip + cgt_line]
    mov edx, 20
    call memcpy
    mov rdi, rbx
    mov esi, 6
    mov edx, 14
    call command_generation_key_begin
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    lea rsi, [rip + cgt_input]
    mov edx, 3
    call command_generation_key_append
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    lea rsi, [rip + cgt_input + 3]
    mov edx, 17
    call command_generation_key_append
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    call command_generation_key_finish
    test rax, rax
    jnz cgt_fail
    lea rdi, [rip + cgt_input]
    mov ecx, 20
    mov al, '!'
    rep stosb
    mov rdi, [rbx + CG_keylines]
    lea rsi, [rip + cgt_combo]
    call strcmp_eq
    test eax, eax
    jz cgt_fail
    mov rdi, [rbx + CG_keylines + 16]
    lea rsi, [rip + cgt_command]
    call strcmp_eq
    test eax, eax
    jz cgt_fail
    cmp qword ptr [rbx + CG_keybytes], 20
    jne cgt_fail
    # Empty spans also get independent owned terminators.
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call command_generation_key_begin
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    call command_generation_key_finish
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [rbx + CG_nkeys], 2
    jne cgt_fail
    mov rdi, rbx
    call command_generation_seal
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [rbx + CG_phase], CG_ALLOC
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    # No partially admitted owner is hidden by a failed constructor result.
    mov qword ptr [rip + cgt_stage], 2
    mov qword ptr [rip + cgt_fail_mark], 1
    lea rdi, [rip + cgt_context]
    call command_generation_begin
    test rcx, rcx
    jnz cgt_fail
    test rax, rax
    jz cgt_fail
    cmp rdx, -5
    jne cgt_fail
    cmp qword ptr [rax + PO_error], -5
    jne cgt_fail
    cmp qword ptr [rax - RD_PO_BACK + RD_kind], RD_LEDGER
    jne cgt_fail
    mov rdi, rax
    call cgt_abort
    mov qword ptr [rip + cgt_fail_mark], 0
    mov qword ptr [rip + cgt_stage], 3
    mov r12d, 1
1:  mov [rip + cgt_fail_alloc], r12
    mov qword ptr [rip + cgt_alloc_count], 0
    lea rdi, [rip + cgt_context]
    call command_generation_begin
    test rcx, rcx
    jnz cgt_fail
    test rax, rax
    jnz cgt_fail
    cmp rdx, -12
    jne cgt_fail
    mov qword ptr [rip + cgt_fail_alloc], 0
    call cgt_drain
    inc r12
    cmp r12, 3
    jb 1b
    # Invalid chunks cannot partially overwrite the owned line.
    mov qword ptr [rip + cgt_stage], 4
    call cgt_new
    mov rbx, rax
    mov rdi, rbx
    mov esi, 6
    mov edx, 14
    call command_generation_key_begin
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    lea rsi, [rip + cgt_line]
    mov edx, 3
    call command_generation_key_append
    # Poison all unwritten bytes and compare the WHOLE admitted span after refusal.
    mov rdi, [rbx + CG_openkey]
    add rdi, 3
    mov ecx, 19
    mov al, 165
    rep stosb
    lea rdi, [rip + cgt_expected]
    mov rsi, [rbx + CG_openkey]
    mov edx, 22
    call memcpy
    mov rdi, rbx
    lea rsi, [rip + cgt_bad]
    mov edx, 3
    call command_generation_key_append
    cmp rax, -22
    jne cgt_fail
    cmp qword ptr [rbx + CG_keycursor], 3
    jne cgt_fail
    mov rdi, [rbx + CG_openkey]
    lea rsi, [rip + cgt_expected]
    mov edx, 22
    call memeq
    test eax, eax
    jz cgt_fail
    mov rdi, rbx
    call cgt_abort
    call cgt_input_boundaries
.ifdef CGT_INSTRUMENTED
    call cgt_input_faults
.endif
    lea rdi, [rip + cgt_ok]
    call strlen
    mov rdx, rax
    mov edi, 1
    lea rsi, [rip + cgt_ok]
    call write_all
    xor eax, eax
    EPILOGUE
# Fixture-only repeated span capture uses actual public input APIs and reusable caller bytes.
cgt_capture:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rsi + rdx]
    call command_generation_key_begin
    test rax, rax
    jnz 3f
1:  test r12, r12
    jz 2f
    mov r13d, 4096
    cmp r13, r12
    cmova r13, r12
    mov rdi, rbx
    lea rsi, [rip + cgt_bytes]
    mov rdx, r13
    call command_generation_key_append
    test rax, rax
    jnz 3f
    sub r12, r13
    jmp 1b
2:  mov rdi, rbx
    call command_generation_key_finish
3:  EPILOGUE
# index -> unique short ASCII name; caller buffer is overwritten on every call.
cgt_make_name:
    lea r8, [rip + cgt_hex]
    lea r9, [rip + cgt_namebuf]
    mov byte ptr [r9], 'n'
    mov rcx, rdi
    shr rcx, 4
    and ecx, 15
    movzx eax, byte ptr [r8 + rcx]
    mov [r9 + 1], al
    and edi, 15
    movzx eax, byte ptr [r8 + rdi]
    mov [r9 + 2], al
    mov byte ptr [r9 + 3], 0
    mov rax, r9
    ret
cgt_input_boundaries:
    PROLOGUE
    lea rdi, [rip + cgt_bytes]
    mov ecx, 4096
    mov al, 'a'
    rep stosb
    mov qword ptr [rip + cgt_stage], 5
    # All128 sparse ordinals, owned repeated caller names, then explicit capacity refusal.
    call cgt_new
    mov rbx, rax
    xor r12d, r12d
1:  mov rdi, r12
    call cgt_make_name
    mov r8, rax
    lea rcx, [rip + cgt_owner]
    mov rdx, r12
    lea rsi, [r12 + 1]
    mov rdi, rbx
    call command_generation_add_identity
    test rax, rax
    jnz cgt_fail
    inc r12
    cmp r12, 128
    jb 1b
    cmp qword ptr [rbx + CG_nslots], 128
    jne cgt_fail
    mov rdi, rbx
    mov esi, 129
    xor edx, edx
    lea rcx, [rip + cgt_other]
    lea r8, [rip + cgt_name]
    call command_generation_add_identity
    cmp rax, -EV_RESOURCE
    jne cgt_fail
    cmp qword ptr [rbx + CG_nslots], 128
    jne cgt_fail
    mov rdi, rbx
    call command_generation_seal
    cmp rax, -EV_RESOURCE
    jne cgt_fail
    cmp qword ptr [rbx + CG_phase], CG_INPUT
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    mov qword ptr [rip + cgt_stage], 6
    # Empty combinations still count toward the exact4096-line resource boundary.
    call cgt_new
    mov rbx, rax
    mov r12d, 4096
2:  mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call cgt_capture
    test rax, rax
    jnz cgt_fail
    dec r12
    jnz 2b
    cmp qword ptr [rbx + CG_nkeys], 4096
    jne cgt_fail
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call command_generation_key_begin
    cmp rax, -EV_RESOURCE
    jne cgt_fail
    cmp qword ptr [rbx + CG_nkeys], 4096
    jne cgt_fail
    cmp qword ptr [rbx + CG_openkey], 0
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    mov qword ptr [rip + cgt_stage], 7
    # Exact1MiB total, including max-sized individual spans and the final smaller span.
    call cgt_new
    mov rbx, rax
    mov r12d, 5
3:  mov rdi, rbx
    mov esi, KC_CAP
    xor edx, edx
    call cgt_capture
    test rax, rax
    jnz cgt_fail
    dec r12
    jnz 3b
    mov rdi, rbx
    mov esi, CG_KEY_BYTES_CAP - 5 * KC_CAP
    xor edx, edx
    call cgt_capture
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [rbx + CG_keybytes], CG_KEY_BYTES_CAP
    jne cgt_fail
    mov rdi, rbx
    mov esi, 1
    xor edx, edx
    call command_generation_key_begin
    cmp rax, -EV_RESOURCE
    jne cgt_fail
    cmp qword ptr [rbx + CG_nkeys], 6
    jne cgt_fail
    cmp qword ptr [rbx + CG_keybytes], CG_KEY_BYTES_CAP
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    mov qword ptr [rip + cgt_stage], 8
    call cgt_new
    mov rbx, rax
    mov rdi, rbx
    mov esi, KC_CAP + 1
    xor edx, edx
    call command_generation_key_begin
    cmp rax, -EV_RESOURCE
    jne cgt_fail
    cmp qword ptr [rbx + CG_openkey], 0
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    # Empty/nonempty halves and exact4096-byte append all preserve complete copied spans.
    call cgt_new
    mov rbx, rax
    mov rdi, rbx
    xor esi, esi
    mov edx, 5
    call cgt_capture
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    mov esi, 5
    xor edx, edx
    call cgt_capture
    test rax, rax
    jnz cgt_fail
    mov rdi, rbx
    mov esi, 4096
    xor edx, edx
    call cgt_capture
    test rax, rax
    jnz cgt_fail
    cmp qword ptr [rbx + CG_nkeys], 3
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    # Full-width span refusal precedes any unreadable caller pointer access.
    call cgt_new
    mov rbx, rax
    mov rdi, rbx
    mov rsi, -1
    xor edx, edx
    call command_generation_key_begin
    cmp rax, -EV_RESOURCE
    jne cgt_fail
    mov rdi, rbx
    call cgt_abort
    EPILOGUE
.section .rodata
.p2align 3
cgt_hex: .ascii "0123456789abcdef"
cgt_context: .quad 11,12,13
cgt_runtime: .quad 1,7,cgt_owner,cgt_name,cgt_runtime_key,cgt_runtime_title,cgt_runtime_keys,6
cgt_path: .asciz "/fixture"
cgt_owner: .asciz "owner"
cgt_other: .asciz "other"
cgt_name: .asciz "name"
cgt_key: .asciz "run"
cgt_value: .asciz "Run | ctrl+x"
cgt_runtime_key: .asciz "rt"
cgt_runtime_title: .asciz "Runtime"
cgt_runtime_keys: .asciz "ctrl+r"
cgt_line: .ascii "ctrl+xowner/name.run"
cgt_combo: .asciz "ctrl+x"
cgt_command: .asciz "owner/name.run"
cgt_bad: .byte 'a',0,'b'
cgt_ok: .asciz "ok command generation owned inputs and deferred suppliers\n"
