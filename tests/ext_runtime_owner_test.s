# Immutable runtime records: ownership, exact identity, session revocation and checked failures.
.include "rhun.inc"
.include "app/extruntime.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.ifdef WINDOWS
.equ ROT_UNMAP_ERROR, -5
.else
.equ ROT_UNMAP_ERROR, -22
.endif
.bss
.p2align 3
rot_config: .zero ROC_SIZE
rot_owner: .zero 65538
rot_name: .zero 65538
rot_title: .zero 65538
rot_keys: .zero 65538
rot_key: .zero 42
rot_fail_alloc: .quad 0
rot_live: .quad 0
rot_stage: .quad 0
.globl rot_fail_unmap, rot_unmap_calls
rot_fail_unmap: .quad 0
rot_unmap_calls: .quad 0
rot_fail_enqueue: .quad 0
rot_charge: .quad 0
rot_retire: .zero 32
rot_cb_count: .quad 0
rot_cb_capture: .quad 0
rot_cb_first: .quad 0
rot_cb_second: .quad 0
rot_cb_rax: .quad 0
rot_cb_rdx: .quad 0
.text
rot_fail:
    mov rdi, [rip + rot_stage]
    add rdi, 70
    call sys_exit
    ud2
FN rot_alloc
    cmp qword ptr [rip + rot_fail_alloc], 0
    jne 1f
    jmp ext_prepare_retire_alloc_custom
1:  mov rdx, -12
    xor eax, eax
    ret
.ifdef ROT_INSTRUMENTED
FN ext_runtime_retire_one
    PROLOGUE
    mov rbx, rdi
    call rot_retire_one_impl
    mov [rip + rot_cb_rax], rax
    mov [rip + rot_cb_rdx], rdx
    inc qword ptr [rip + rot_cb_count]
    cmp qword ptr [rip + rot_cb_capture], 0
    je 2f
    cmp qword ptr [rip + rot_cb_count], 1
    jne 1f
    mov [rip + rot_cb_first], rbx
1:  cmp qword ptr [rip + rot_cb_count], 2
    jne 2f
    mov [rip + rot_cb_second], rbx
2:  EPILOGUE
.endif
FN rot_enqueue
    cmp qword ptr [rip + rot_fail_enqueue], 0
    je ext_prepare_retire_enqueue_custom
    mov rax, -5
    ret
rot_drain:
    PROLOGUE
    mov ebx, 65536
1:  mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    test rax, rax
    js rot_fail
    cmp qword ptr [rip + rot_retire], 1
    ja rot_fail
    cmp qword ptr [rip + rot_retire + 16], 0
    jne rot_fail
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp rot_fail
2:  EPILOGUE
rot_static_config:
    call rot_reset
    lea rax, [rip + rot_o]
    mov [rip + rot_config + ROC_owner], rax
    lea rax, [rip + rot_n]
    mov [rip + rot_config + ROC_name], rax
    lea rax, [rip + rot_k]
    mov [rip + rot_config + ROC_key], rax
    lea rax, [rip + rot_t]
    mov [rip + rot_config + ROC_title], rax
    lea rax, [rip + rot_keys_expected]
    mov [rip + rot_config + ROC_keys], rax
    ret
rot_reset:
    lea rdi, [rip + rot_config]
    lea rsi, [rip + rot_base]
    mov edx, ROC_SIZE
    jmp memcpy
rot_new:
    lea rdi, [rip + rot_config]
    jmp ext_runtime_new
rot_match:
    mov rdi, rbx
    mov esi, 1
    mov edx, 7
    lea rcx, [rip + rot_o]
    lea r8, [rip + rot_n]
    lea r9, [rip + rot_k]
    jmp ext_runtime_matches
rot_bad:
    call rot_new
    test rax, rax
    jnz rot_fail
    cmp rdx, -22
    jne rot_fail
    ret

FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + rot_live], rax
    call ext_prepare_retire_charge
    mov [rip + rot_charge], rax
    mov qword ptr [rip + rot_stage], 1
    lea rdi, [rip + rot_owner]
    lea rsi, [rip + rot_o]
    mov edx, 2
    call memcpy
    lea rdi, [rip + rot_name]
    lea rsi, [rip + rot_n]
    mov edx, 4
    call memcpy
    lea rdi, [rip + rot_key]
    lea rsi, [rip + rot_k]
    mov edx, 4
    call memcpy
    lea rdi, [rip + rot_title]
    lea rsi, [rip + rot_t]
    mov edx, 6
    call memcpy
    lea rdi, [rip + rot_keys]
    lea rsi, [rip + rot_keys_expected]
    mov edx, 6
    call memcpy
    call rot_reset
    # A refused allocation consumes no incarnation and leaves caller input unchanged.
    mov qword ptr [rip + rot_fail_alloc], 1
    call rot_new
    test rax, rax
    jnz rot_fail
    cmp rdx, -12
    jne rot_fail
    mov qword ptr [rip + rot_fail_alloc], 0
    call rot_new
    test rax, rax
    jz rot_fail
    test rdx, rdx
    jnz rot_fail
    mov rbx, rax
    cmp qword ptr [rbx + RO_incarnation], 1
    jne rot_fail
    cmp qword ptr [rbx + RO_refs], 1
    jne rot_fail
    cmp qword ptr [rbx + 88], 0
    jne rot_fail
    # Every string is copied, including the independent flattened wire spelling.
    mov byte ptr [rip + rot_owner], 'x'
    mov byte ptr [rip + rot_name], 'x'
    mov byte ptr [rip + rot_key], 'x'
    mov byte ptr [rip + rot_title], 'x'
    mov byte ptr [rip + rot_keys], 'x'
    xor r12d, r12d
1:  mov rdi, rbx
    mov rsi, r12
    call ext_runtime_get
    test rax, rax
    jz rot_fail
    lea rcx, [rip + rot_expected]
    mov rsi, [rcx + r12*8]
    mov rdi, rax
    call strcmp_eq
    test eax, eax
    jz rot_fail
    inc r12
    cmp r12, 6
    jb 1b
    mov rdi, rbx
    mov esi, 6
    call ext_runtime_get
    test rax, rax
    jnz rot_fail
    call rot_match
    cmp eax, 1
    jne rot_fail
    mov qword ptr [rip + rot_stage], 2
    # Change each member of the exact authority tuple independently.
    mov r12d, 1
2:  mov rdi, rbx
    mov esi, 1
    mov edx, 7
    lea rcx, [rip + rot_o]
    lea r8, [rip + rot_n]
    lea r9, [rip + rot_k]
    cmp r12, 1
    jne 21f
    mov esi, 2
21: cmp r12, 2
    jne 22f
    mov edx, 8
22: cmp r12, 3
    jne 23f
    lea rcx, [rip + rot_wrong_owner]
23: cmp r12, 4
    jne 24f
    lea r8, [rip + rot_wrong_name]
24: cmp r12, 5
    jne 25f
    lea r9, [rip + rot_wrong_key]
25: call ext_runtime_matches
    test eax, eax
    jnz rot_fail
    inc r12
    cmp r12, 6
    jb 2b
    # Equal-length mismatches above and every shorter/longer identity prefix must fail.
    xor r12d, r12d
.Lrot_prefix:
    lea rax, [rip + rot_prefixes]
    mov r13, [rax + r12]
    mov r14, [rax + r12 + 8]
    mov rdi, rbx
    mov esi, 1
    mov edx, 7
    lea rcx, [rip + rot_o]
    lea r8, [rip + rot_n]
    lea r9, [rip + rot_k]
    test r13, r13
    jnz 26f
    mov rcx, r14
26: cmp r13, 1
    jne 27f
    mov r8, r14
27: cmp r13, 2
    jne 28f
    mov r9, r14
28: call ext_runtime_matches
    test eax, eax
    jnz rot_fail
    add r12, 16
    cmp r12, 96
    jb .Lrot_prefix
    mov rdi, rbx
    call ext_runtime_retain
    test rax, rax
    jnz rot_fail
    mov rdi, rbx
    call ext_runtime_release
    cmp qword ptr [rbx + RO_refs], 1
    jne rot_fail
    mov qword ptr [rbx + RO_refs], -1
    mov rdi, rbx
    call ext_runtime_retain
    cmp rax, -75
    jne rot_fail
    cmp qword ptr [rbx + RO_refs], -1
    jne rot_fail
    mov qword ptr [rbx + RO_refs], 0
    mov rdi, rbx
    call ext_runtime_retain
    cmp rax, -22
    jne rot_fail
    mov rdi, rbx
    call ext_runtime_release
    cmp rax, -22
    jne rot_fail
    test rdx, rdx
    jnz rot_fail
    mov qword ptr [rbx + RO_refs], 1
    mov rdi, rbx
    call ext_runtime_revoke
    mov rdi, rbx
    call ext_runtime_revoke
    call rot_match
    test eax, eax
    jnz rot_fail
    # Same-key replacement is independent and cannot revive the retained old owner.
    call rot_reset
    lea rax, [rip + rot_o]
    mov [rip + rot_config + ROC_owner], rax
    lea rax, [rip + rot_n]
    mov [rip + rot_config + ROC_name], rax
    lea rax, [rip + rot_k]
    mov [rip + rot_config + ROC_key], rax
    call rot_new
    test rax, rax
    jz rot_fail
    mov r13, rax
    cmp qword ptr [rax + RO_incarnation], 2
    jne rot_fail
    xchg rbx, r13
    call rot_match
    cmp eax, 1
    jne rot_fail
    xchg rbx, r13
    call rot_match
    test eax, eax
    jnz rot_fail
    mov rdi, r13
    call ext_runtime_release
    mov rdi, rbx
    call ext_runtime_release
    mov qword ptr [rip + rot_stage], 3
    # Constructor boundaries and invalid inputs fail before allocating a record.
    xor r12d, r12d
3:  call rot_reset
    lea rax, [rip + rot_bad_fields]
    mov rcx, [rax + r12]
    mov rdx, [rax + r12 + 8]
    lea rax, [rip + rot_config]
    mov [rax + rcx], rdx
    call rot_bad
    add r12, 16
    lea rax, [rip + rot_bad_fields_end]
    lea rcx, [rip + rot_bad_fields]
    sub rax, rcx
    cmp r12, rax
    jb 3b
    xor edi, edi
    call ext_runtime_new
    test rax, rax
    jnz rot_fail
    cmp rdx, -22
    jne rot_fail
    # Simultaneous maximum string sizes and a forty-byte local key retain correct offsets.
    mov qword ptr [rip + rot_stage], 4
    lea r12, [rip + rot_owner]
    mov r13d, 4
4:  mov rdi, r12
    mov esi, 'a'
    mov edx, 65536
    call memset
    mov byte ptr [r12 + 65536], 0
    add r12, 65538
    dec r13
    jnz 4b
    lea rdi, [rip + rot_key]
    mov esi, 'a'
    mov edx, 40
    call memset
    mov byte ptr [rip + rot_key + 40], 0
    call rot_reset
    mov qword ptr [rip + rot_config + ROC_keyslen], 65536
    call rot_new
    test rax, rax
    jz rot_fail
    mov rbx, rax
    cmp qword ptr [rax + RO_allocsize], RO_SIZE + 7 + 5 * 65536 + 80
    jne rot_fail
    mov rdi, rbx
    mov esi, 5
    call ext_runtime_get
    cmp byte ptr [rax + 65536], '.'
    jne rot_fail
    cmp byte ptr [rax + 65536 + 41], 0
    jne rot_fail
    mov rdi, rbx
    call ext_runtime_release
    # One-byte excess for each independently counted string.
    lea r12, [rip + rot_owner]
    mov r13d, 3
5:  mov byte ptr [r12 + 65536], 'a'
    call rot_bad
    mov byte ptr [r12 + 65536], 0
    add r12, 65538
    dec r13
    jnz 5b
    mov byte ptr [rip + rot_key + 40], 'a'
    call rot_bad
    mov byte ptr [rip + rot_key + 40], 0
    # Empty title and empty counted keys are valid; NULL empty keys is copied as a NUL.
    call rot_reset
    lea rax, [rip + rot_empty]
    mov [rip + rot_config + ROC_title], rax
    mov qword ptr [rip + rot_config + ROC_keys], 0
    mov qword ptr [rip + rot_config + ROC_keyslen], 0
    call rot_new
    test rax, rax
    jz rot_fail
    mov rdi, rax
    call ext_runtime_release
    # Digits and underscore are valid local keys; the highest positive session is valid.
    lea r12, [rip + rot_valid_keys]
    mov r13d, 2
.Lrot_valid_key:
    mov rax, [r12]
    mov [rip + rot_config + ROC_key], rax
    mov rax, 0x7fffffffffffffff
    mov [rip + rot_config + ROC_session], rax
    call rot_new
    test rax, rax
    jz rot_fail
    mov rcx, 0x7fffffffffffffff
    cmp [rax + RO_session], rcx
    jne rot_fail
    mov rdi, rax
    call ext_runtime_release
    add r12, 8
    dec r13
    jnz .Lrot_valid_key
    # Reclaim earlier records before exact charged ownership assertions.
    call rot_drain
    call ext_prepare_retire_charge
    cmp rax, [rip + rot_charge]
    jne rot_fail
    mov qword ptr [rip + rot_stage], 6
    call rot_static_config
    call rot_new
    test rax, rax
    jz rot_fail
    mov rbx, rax
    mov r13, [rbx + RO_incarnation]
    mov rdi, [rbx + RO_allocsize]
    add rdi, RD_SIZE
    call prep_alloc_charge
    mov r12, rax
    call ext_prepare_retire_charge
    sub rax, [rip + rot_charge]
    cmp rax, r12
    jne rot_fail
    lea rdi, [rip + rot_retire]
    call ext_prepare_retire_status
    cmp qword ptr [rip + rot_retire + 8], 0
    jne rot_fail
    # Retain/drop does not double charge, invoke a callback, or free an owner.
    mov rdi, rbx
    call ext_runtime_retain
    test rax, rax
    jnz rot_fail
    mov rdi, rbx
    call ext_runtime_release_deferred
    test rax, rax
    jnz rot_fail
    cmp rdx, 1
    jne rot_fail
    cmp qword ptr [rbx + RO_refs], 1
    jne rot_fail
    call ext_prepare_retire_charge
    sub rax, [rip + rot_charge]
    cmp rax, r12
    jne rot_fail
    mov qword ptr [rip + rot_stage], 7
    # Exact actual common admission, with no incarnation burned.
    mov r14, [rip + prep_total_charge]
    mov qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    mov r15, [rip + g_mem_live]
    call rot_new
    test rax, rax
    jnz rot_fail
    cmp rdx, -EV_RESOURCE
    jne rot_fail
    cmp qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    jne rot_fail
    cmp [rip + g_mem_live], r15
    jne rot_fail
    # An allocation exactly fits the remaining rounded charge. One byte less refuses.
    mov rax, PREP_TOTAL_CAP
    sub rax, r12
    inc rax
    mov [rip + prep_total_charge], rax
    mov [rip + rot_retire], rax
    call rot_new
    test rax, rax
    jnz rot_fail
    cmp rdx, -EV_RESOURCE
    jne rot_fail
    mov rax, [rip + rot_retire]
    cmp [rip + prep_total_charge], rax
    jne rot_fail
    cmp [rip + g_mem_live], r15
    jne rot_fail
    dec qword ptr [rip + prep_total_charge]
    call rot_new
    test rax, rax
    jz rot_fail
    test rdx, rdx
    jnz rot_fail
    cmp qword ptr [rip + prep_total_charge], PREP_TOTAL_CAP
    jne rot_fail
    inc r13
    cmp [rax + RO_incarnation], r13
    jne rot_fail
    mov rdi, rax
    call ext_runtime_release
    cmp rdx, 1
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    test rax, rax
    jnz rot_fail
    mov rax, PREP_TOTAL_CAP
    sub rax, r12
    cmp [rip + prep_total_charge], rax
    jne rot_fail
    cmp [rip + g_mem_live], r15
    jne rot_fail
    mov [rip + prep_total_charge], r14
    mov qword ptr [rip + rot_stage], 8
    # Private enqueue fault must restore sole reference and report unconsumed.
    mov qword ptr [rip + rot_cb_count], 0
    mov qword ptr [rip + rot_fail_enqueue], 1
    mov rdi, rbx
    call ext_runtime_release
    cmp rax, -5
    jne rot_fail
    test rdx, rdx
    jnz rot_fail
    cmp qword ptr [rbx + RO_refs], 1
    jne rot_fail
    mov qword ptr [rip + rot_fail_enqueue], 0
    mov rdi, rbx
    call ext_runtime_release
    test rax, rax
    jnz rot_fail
    cmp rdx, 1
    jne rot_fail
    cmp qword ptr [rbx + RO_refs], 0
    jne rot_fail
    mov rdi, rbx
    call ext_runtime_retain
    cmp rax, -22
    jne rot_fail
    mov rdi, rbx
    call ext_runtime_release
    cmp rax, -22
    jne rot_fail
    test rdx, rdx
    jnz rot_fail
    mov qword ptr [rip + rot_stage], 9
    # No callback happened in release, including the failed enqueue path.
    cmp qword ptr [rip + rot_cb_count], 0
    jne rot_fail
    # One record remains fully charged until exactly one work unit consumes it.
    call ext_prepare_retire_charge
    sub rax, [rip + rot_charge]
    cmp rax, r12
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    test rax, rax
    jnz rot_fail
    cmp qword ptr [rip + rot_retire], 1
    jne rot_fail
    cmp qword ptr [rip + rot_cb_count], 1
    jne rot_fail
    cmp qword ptr [rip + rot_cb_rax], 0
    jne rot_fail
    cmp qword ptr [rip + rot_cb_rdx], 1
    jne rot_fail
    call ext_prepare_retire_charge
    cmp rax, [rip + rot_charge]
    jne rot_fail
    mov qword ptr [rip + rot_stage], 10
    # Admission refusal consumed no incarnation. Two queued owners share FIFO work.
    call rot_new
    test rax, rax
    jz rot_fail
    mov rbx, rax
    inc r13
    cmp [rbx + RO_incarnation], r13
    jne rot_fail
    call rot_new
    test rax, rax
    jz rot_fail
    mov r14, rax
    mov qword ptr [rip + rot_cb_count], 0
    mov qword ptr [rip + rot_cb_capture], 1
    mov rdi, rbx
    call ext_runtime_release
    mov rdi, r14
    call ext_runtime_release
    cmp qword ptr [rip + rot_cb_count], 0
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    cmp rax, 1
    jne rot_fail
    cmp qword ptr [rip + rot_retire + 8], 1
    jne rot_fail
    cmp qword ptr [rip + rot_cb_count], 1
    jne rot_fail
    cmp [rip + rot_cb_first], rbx
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    test rax, rax
    jnz rot_fail
    cmp qword ptr [rip + rot_retire], 1
    jne rot_fail
    cmp qword ptr [rip + rot_cb_count], 2
    jne rot_fail
    cmp [rip + rot_cb_second], r14
    jne rot_fail
    mov qword ptr [rip + rot_cb_capture], 0
    call rot_drain
    mov qword ptr [rip + rot_stage], 11
    # A failed large native unmap keeps its exact original header, payload and charge.
    lea rax, [rip + rot_title]
    mov [rip + rot_config + ROC_title], rax
    lea rdi, [rip + rot_title]
    mov ecx, 65536
    mov al, 't'
    rep stosb
    mov byte ptr [rdi], 0
    call rot_new
    test rax, rax
    jz rot_fail
    mov rbx, rax
    mov r12, [rbx - RD_SIZE - 16]
    mov r13, [rbx - RD_SIZE - 8]
    call ext_prepare_retire_charge
    mov r14, rax
    mov r15, [rip + g_mem_live]
    mov qword ptr [rip + rot_unmap_calls], 0
    mov qword ptr [rip + rot_fail_unmap], 1
    mov rdi, rbx
    call ext_runtime_release
    cmp rdx, 1
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    cmp rax, 1
    jne rot_fail
    cmp qword ptr [rip + rot_retire + 16], 1
    jne rot_fail
    cmp qword ptr [rip + rot_retire + 24], ROT_UNMAP_ERROR
    jne rot_fail
    cmp [rbx - RD_SIZE - 16], r12
    jne rot_fail
    cmp [rbx - RD_SIZE - 8], r13
    jne rot_fail
    cmp [rip + g_mem_live], r15
    jne rot_fail
    call ext_prepare_retire_charge
    cmp rax, r14
    jne rot_fail
    cmp qword ptr [rip + rot_unmap_calls], 1
    jne rot_fail
    cmp qword ptr [rip + rot_cb_rax], ROT_UNMAP_ERROR
    jne rot_fail
    cmp qword ptr [rip + rot_cb_rdx], 0
    jne rot_fail
    cmp [rbx - RD_SIZE + RD_object], rbx
    jne rot_fail
    cmp qword ptr [rbx + RO_titlelen], 65536
    jne rot_fail
    mov rdi, rbx
    mov esi, 3
    call ext_runtime_get
    cmp byte ptr [rax], 't'
    jne rot_fail
    cmp byte ptr [rax + 65535], 't'
    jne rot_fail
    # Ordinary pumping must not retry a blocked record.
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    cmp rax, 1
    jne rot_fail
    cmp qword ptr [rip + rot_retire], 0
    jne rot_fail
    cmp qword ptr [rip + rot_unmap_calls], 1
    jne rot_fail
    call ext_prepare_retire_ack
    cmp rax, -16
    jne rot_fail
    mov edi, 1
    call ext_prepare_retire_retry_known
    cmp rax, 1
    jne rot_fail
    cmp rdx, 1
    jne rot_fail
    cmp qword ptr [rip + rot_unmap_calls], 1
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    test rax, rax
    jnz rot_fail
    cmp qword ptr [rip + rot_retire], 1
    jne rot_fail
    cmp qword ptr [rip + rot_cb_rax], 0
    jne rot_fail
    cmp qword ptr [rip + rot_cb_rdx], 1
    jne rot_fail
    mov edi, 1
    lea rsi, [rip + rot_retire]
    call ext_prepare_retire_step
    test rax, rax
    jnz rot_fail
    cmp qword ptr [rip + rot_retire], 0
    jne rot_fail
    cmp qword ptr [rip + rot_retire + 24], ROT_UNMAP_ERROR
    jne rot_fail
    cmp qword ptr [rip + rot_unmap_calls], 2
    jne rot_fail
    call ext_prepare_retire_charge
    cmp rax, [rip + rot_charge]
    jne rot_fail
    call ext_prepare_retire_ack
    test rax, rax
    jnz rot_fail
    lea rdi, [rip + rot_retire]
    call ext_prepare_retire_status
    cmp qword ptr [rip + rot_retire + 24], 0
    jne rot_fail
    call rot_static_config
    mov qword ptr [rip + rot_stage], 5
    mov rdi, 0x7ffffffffffffffe
    call rot_set_incarnation
    call rot_new
    test rax, rax
    jz rot_fail
    mov rcx, 0x7fffffffffffffff
    cmp [rax + RO_incarnation], rcx
    jne rot_fail
    mov rdi, rax
    call ext_runtime_release
    call rot_new
    test rax, rax
    jnz rot_fail
    cmp rdx, -75
    jne rot_fail
    xor edi, edi
    call ext_runtime_release
    test rax, rax
    jnz rot_fail
    cmp rdx, 1
    jne rot_fail
    xor edi, edi
    call ext_runtime_retain
    cmp rax, -22
    jne rot_fail
    call rot_drain
    call ext_prepare_retire_charge
    cmp rax, [rip + rot_charge]
    jne rot_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + rot_live]
    jne rot_fail
    lea rdi, [rip + rot_ok]
    call strlen
    mov rdx, rax
    mov edi, 1
    lea rsi, [rip + rot_ok]
    call write_all
    xor eax, eax
    EPILOGUE
# Replaced only in the private exact-source fixture link.
FN rot_set_incarnation
    ret
.section .rodata
rot_o: .asciz "o"
rot_n: .asciz "abc"
rot_k: .asciz "run"
rot_t: .asciz "Title"
rot_keys_expected: .asciz "ctrl+x"
rot_wire: .asciz "abc.run"
rot_wrong_owner: .asciz "p"
rot_wrong_name: .asciz "abd"
rot_wrong_key: .asciz "rum"
rot_long_owner: .asciz "op"
rot_short_name: .asciz "ab"
rot_long_name: .asciz "abcd"
rot_short_key: .asciz "ru"
rot_long_key: .asciz "runs"
rot_empty: .asciz ""
rot_upper: .asciz "Run"
rot_dash: .asciz "a-b"
rot_slash: .asciz "r/un"
rot_high: .byte 128, 0
rot_digit: .asciz "a0_9z"
rot_under: .asciz "_"
rot_nul_keys: .ascii "a\0b"
.p2align 3
rot_expected: .quad rot_o, rot_n, rot_k, rot_t, rot_keys_expected, rot_wire
rot_base: .quad 1, 7, rot_owner, rot_name, rot_key, rot_title, rot_keys, 6
rot_prefixes:
    .quad 0, rot_empty, 0, rot_long_owner
    .quad 1, rot_short_name, 1, rot_long_name
    .quad 2, rot_short_key, 2, rot_long_key
rot_valid_keys: .quad rot_digit, rot_under
rot_bad_fields:
    .quad ROC_target, 0, ROC_session, 0, ROC_session, -1
    .quad ROC_owner, 0, ROC_owner, rot_empty
    .quad ROC_name, 0, ROC_name, rot_empty
    .quad ROC_key, 0, ROC_key, rot_empty, ROC_key, rot_upper, ROC_key, rot_dash
    .quad ROC_key, rot_slash, ROC_key, rot_high
    .quad ROC_title, 0, ROC_keys, 0, ROC_keyslen, 65537
    .quad ROC_keys, rot_nul_keys
rot_bad_fields_end:
rot_ok: .asciz "ok owned runtime command identity and sessions\n"
