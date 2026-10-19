.include "app/extsettingsrequest.inc"
.include "app/extsettingsworker.inc"
.section .rodata
rqt_tag: .quad 17,37,11,29
.ifdef WINDOWS
rqt_path: .ascii "C:/settings.ini"
.equ RQT_PATHLEN, 15
.else
rqt_path: .ascii "/tmp/settings.ini"
.equ RQT_PATHLEN, 17
.endif
rqt_ok: .ascii "ok counted settings REQUEST producer and immutable rows\n"
.equ RQT_OKLEN, 56
.bss
.p2align 3
.globl rqt_poison, rqt_fail_alloc
rqt_poison: .quad 0
rqt_fail_alloc: .quad 0
rqt_stage: .quad 0
rqt_live: .quad 0
rqt_charge: .quad 0
rqt_frame: .quad 0
rqt_batch: .quad 0
rqt_request: .zero SRQ_SIZE
rqt_cursor: .zero ESQ_SIZE
rqt_copy: .zero ESQ_SIZE
rqt_decoded: .zero SWR_SIZE
.text
.globl rqt_poison_fail
rqt_poison_fail:
    mov edi, 219
    call sys_exit
rqt_fail:
    mov rdi, [rip + rqt_stage]
    call sys_exit
rqt_cursor_copy:
    lea rdi, [rip + rqt_copy]
    lea rsi, [rip + rqt_cursor]
    mov edx, ESQ_SIZE
    jmp memcpy
rqt_cursor_same:
    PROLOGUE
    lea rdi, [rip + rqt_copy]
    lea rsi, [rip + rqt_cursor]
    mov edx, ESQ_SIZE
    call memeq
    test eax, eax
    jz rqt_fail
    EPILOGUE
rqt_begin:
    lea rdi, [rip + rqt_request]
    lea rsi, [rip + rqt_cursor]
    jmp ext_settings_request_begin
rqt_step_one:
    PROLOGUE
    mov rdi, [rip + rqt_frame]
    mov rsi, [rip + rqt_batch]
    lea rdx, [rip + rqt_cursor]
    mov ecx, 1
    mov qword ptr [rip + rqt_poison], 1
    call ext_settings_request_step
    mov qword ptr [rip + rqt_poison], 0
    test rax, rax
    js rqt_fail
    cmp rdx, 1
    ja rqt_fail
    cmp rcx, 1024
    ja rqt_fail
    EPILOGUE
FN main
    PROLOGUE
    mov rax, [rip + g_mem_live]
    mov [rip + rqt_live], rax
    mov qword ptr [rip + rqt_stage], 210
    call ext_settings_queue_create
    test rax, rax
    jz rqt_fail
    mov rbx, rax
    lea r12, [rip + sq_delta]
    lea rax, [rip + sq_section]
    mov [r12 + EC_section], rax
    mov qword ptr [r12 + EC_seclen], 7
    lea rax, [rip + sq_key]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 9
    lea rax, [rip + sq_one]
    mov [r12 + EC_value], rax
    mov qword ptr [r12 + EC_vallen], 3
    call sq_put
    test rax, rax
    jnz rqt_fail
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jz rqt_fail
    mov [rip + rqt_batch], rax
    lea rdx, [rip + rqt_request]
    lea rcx, [rip + rqt_tag]
    mov [rdx + SRQ_tag], rcx
    lea rcx, [rip + rqt_path]
    mov [rdx + SRQ_path], rcx
    mov qword ptr [rdx + SRQ_length], RQT_PATHLEN
    mov [rdx + SRQ_batch], rax
    mov qword ptr [rdx + SRQ_mode], 9
    # Refused input and allocation never overwrite the caller's cursor.
    lea rdi, [rip + rqt_cursor]
    mov esi, 90
    mov edx, ESQ_SIZE
    call memset
    call rqt_cursor_copy
    call rqt_begin
    test rax, rax
    jnz rqt_fail
    cmp rdx, -22
    jne rqt_fail
    call rqt_cursor_same
    mov qword ptr [rip + rqt_request + SRQ_mode], 2
    call ext_settings_memory_total
    mov [rip + rqt_charge], rax
    mov qword ptr [rip + rqt_fail_alloc], 1
    call rqt_begin
    test rax, rax
    jnz rqt_fail
    cmp rdx, -12
    jne rqt_fail
    call rqt_cursor_same
    call ext_settings_memory_total
    cmp [rip + rqt_charge], rax
    jne rqt_fail
    mov qword ptr [rip + rqt_stage], 211
    call rqt_begin
    test rax, rax
    jz rqt_fail
    test rdx, rdx
    jnz rqt_fail
    mov [rip + rqt_frame], rax
    cmp qword ptr [rax + EJF_length], 91 + RQT_PATHLEN
    jne rqt_fail
    cmp qword ptr [rax + EJF_sealed], 0
    jne rqt_fail
    call rqt_cursor_copy
    mov rdi, [rip + rqt_frame]
    mov rsi, [rip + rqt_batch]
    lea rdx, [rip + rqt_cursor]
    xor ecx, ecx
    call ext_settings_request_step
    cmp rax, -22
    jne rqt_fail
    or rdx, rcx
    jnz rqt_fail
    call rqt_cursor_same
    mov rdi, [rip + rqt_frame]
    mov rsi, [rip + rqt_batch]
    lea rdx, [rip + rqt_cursor]
    mov ecx, 65537
    call ext_settings_request_step
    cmp rax, -22
    jne rqt_fail
    or rdx, rcx
    jnz rqt_fail
    call rqt_cursor_same
    mov edi, 1
    mov rsi, [rip + rqt_batch]
    lea rdx, [rip + rqt_cursor]
    mov ecx, 1
    mov qword ptr [rip + rqt_poison], 1
    call ext_settings_request_step
    mov qword ptr [rip + rqt_poison], 0
    cmp rax, -22
    jne rqt_fail
    call rqt_cursor_same
    # Five one-byte slices leave a partial rowheader before a newer Q intent arrives.
    mov r13d, 5
1:  call rqt_step_one
    test rax, rax
    jnz rqt_fail
    cmp rdx, 1
    jne rqt_fail
    dec r13
    jnz 1b
    lea rax, [rip + sq_two]
    mov [r12 + EC_value], rax
    call sq_put
    test rax, rax
    jnz rqt_fail
    mov qword ptr [rip + rqt_stage], 212
    mov r13d, 1000
    mov r14d, 5
2:  call rqt_step_one
    add r14, rdx
    test rax, rax
    jnz 3f
    or rdx, rcx
    jz rqt_fail
    dec r13
    jz rqt_fail
    jmp 2b
3:  cmp rax, 1
    jne rqt_fail
    cmp r14, 35
    jne rqt_fail
    mov r15, [rip + rqt_frame]
    cmp qword ptr [r15 + EJF_sealed], 1
    jne rqt_fail
    call rqt_step_one
    cmp rax, 1
    jne rqt_fail
    or rdx, rcx
    jnz rqt_fail
    lea rdi, [r15 + EJF_body]
    mov rsi, [r15 + EJF_length]
    lea rdx, [rip + rqt_decoded]
    call ext_settings_worker_request
    test rax, rax
    jnz rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_mode], 2
    jne rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_count], 1
    jne rqt_fail
    mov rdi, [rip + rqt_decoded + SWR_delta + EC_value]
    lea rsi, [rip + sq_one]
    mov edx, 3
    call memeq
    test eax, eax
    jz rqt_fail
    mov qword ptr [rip + rqt_stage], 213
    mov rdi, [rip + rqt_batch]
    call ext_settings_batch_ack
    test rax, rax
    jnz rqt_fail
    cmp qword ptr [rbx + EQ_count], 1
    jne rqt_fail
    call sq_find
    test rax, rax
    jz rqt_fail
    mov rdi, [rax + EC_value]
    lea rsi, [rip + sq_two]
    mov edx, 3
    call memeq
    test eax, eax
    jz rqt_fail
    mov rdi, r15
    call ext_settings_frame_free
    cmp rcx, 1
    jne rqt_fail
    mov qword ptr [rip + rqt_frame], 0
    mov qword ptr [rip + rqt_cursor + ESQ_magic], 0
    mov rdi, [rip + rqt_batch]
    call ext_settings_batch_free
    cmp rcx, 1
    jne rqt_fail
    mov qword ptr [rip + rqt_batch], 0
    mov rdi, rbx
    call ext_settings_queue_gc
    call sq_clear
    mov rdi, rbx
    call ext_settings_queue_free
    cmp rcx, 1
    jne rqt_fail
    call rqt_empty_cases
    call rqt_large_cases
    call rqt_row_cases
    call ext_settings_memory_total
    test rax, rax
    jnz rqt_fail
    mov rax, [rip + g_mem_live]
    cmp [rip + rqt_live], rax
    jne rqt_fail
    mov edi, 1
    lea rsi, [rip + rqt_ok]
    mov edx, RQT_OKLEN
    SYS SYS_write
    xor edi, edi
    call sys_exit

.section .rodata
rqt_a: .ascii "a"
rqt_b: .ascii "b"
rqt_extra_key: .ascii "z"
.bss
.p2align 3
.globl rqt_fail_unmap, rqt_now
rqt_fail_unmap: .quad 0
rqt_now: .quad 0
rqt_free_live: .quad 0
rqt_longpath: .zero 4096
rqt_value: .zero 1048550
.text
FN rqt_time
    mov rax, [rip + rqt_now]
    ret
.ifdef WINDOWS
FN rqt_native_unmap
    cmp qword ptr [rip + rqt_fail_unmap], 0
    je 1f
    dec qword ptr [rip + rqt_fail_unmap]
    mov ecx, 1
1:  jmp [rip + __imp_VirtualFree]
.else
FN rqt_native_unmap
    cmp qword ptr [rip + rqt_fail_unmap], 0
    je 1f
    dec qword ptr [rip + rqt_fail_unmap]
    mov edi, 1
1:  SYS SYS_munmap
    ret
.endif
rqt_long_inputs:
    PROLOGUE
    lea rdi, [rip + rqt_value]
    mov esi, 'v'
    mov edx, 1048550
    call memset
    lea rdi, [rip + rqt_longpath]
    mov esi, 'a'
    mov edx, 4095
    call memset
    lea rax, [rip + rqt_longpath]
.ifdef WINDOWS
    mov byte ptr [rax], 'C'
    mov byte ptr [rax + 1], ':'
    mov byte ptr [rax + 2], '/'
    mov ecx, 258
.else
    mov byte ptr [rax], '/'
    mov ecx, 256
.endif
1:  mov byte ptr [rax + rcx], '/'
    add ecx, 256
    cmp ecx, 4095
    jb 1b
    mov byte ptr [rax + 4095], 0
    mov [rip + rqt_request + SRQ_path], rax
    mov qword ptr [rip + rqt_request + SRQ_length], 4095
    lea rax, [rip + rqt_a]
    mov [r12 + EC_section], rax
    mov qword ptr [r12 + EC_seclen], 1
    lea rax, [rip + rqt_b]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 1
    lea rax, [rip + rqt_value]
    mov [r12 + EC_value], rax
    mov qword ptr [r12 + EC_remove], 0
    EPILOGUE
# encode current owned frame/batch with caller budget in RDI.
rqt_encode_budget:
    PROLOGUE 16
    mov [rsp], rdi
    mov r13d, 1000000
    xor r14d, r14d
    mov qword ptr [rip + rqt_poison], 1
1:  mov rdi, [rip + rqt_frame]
    mov rsi, [rip + rqt_batch]
    lea rdx, [rip + rqt_cursor]
    mov rcx, [rsp]
    call ext_settings_request_step
    test rax, rax
    js rqt_fail
    cmp rdx, [rsp]
    ja rqt_fail
    cmp rcx, 1024
    ja rqt_fail
    add r14, rdx
    test rax, rax
    jnz 2f
    or rdx, rcx
    jz rqt_fail
    dec r13
    jz rqt_fail
    jmp 1b
2:  mov qword ptr [rip + rqt_poison], 0
    cmp rax, 1
    jne rqt_fail
    mov rax, r14
    EPILOGUE
rqt_drop_batch_queue:
    PROLOGUE
    mov rdi, [rip + rqt_batch]
    call ext_settings_batch_free
    cmp rcx, 1
    jne rqt_fail
    mov qword ptr [rip + rqt_batch], 0
    call sq_clear
    mov rdi, rbx
    call ext_settings_queue_free
    cmp rcx, 1
    jne rqt_fail
    EPILOGUE
rqt_decode:
    mov rdi, [rip + rqt_frame]
    mov rsi, [rdi + EJF_length]
    add rdi, EJF_body
    lea rdx, [rip + rqt_decoded]
    jmp ext_settings_worker_request
rqt_large_cases:
    PROLOGUE
    mov qword ptr [rip + rqt_stage], 214
    call ext_settings_queue_create
    test rax, rax
    jz rqt_fail
    mov rbx, rax
    lea r12, [rip + sq_delta]
    call rqt_long_inputs
    mov qword ptr [r12 + EC_vallen], 1048550
    call sq_put
    test rax, rax
    jnz rqt_fail
    cmp qword ptr [rbx + EQ_payload], 1048552
    jne rqt_fail
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jz rqt_fail
    mov [rip + rqt_batch], rax
    mov [rip + rqt_request + SRQ_batch], rax
    mov qword ptr [rip + rqt_request + SRQ_mode], 2
    call rqt_begin
    test rax, rax
    jz rqt_fail
    mov [rip + rqt_frame], rax
    cmp qword ptr [rax + EJF_length], 1052719
    jne rqt_fail
    mov edi, 65536
    call rqt_encode_budget
    cmp rax, 1048568
    jne rqt_fail
    call rqt_decode
    test rax, rax
    jnz rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_delta + EC_vallen], 1048550
    jne rqt_fail
    mov rdi, [rip + rqt_decoded + SWR_delta + EC_value]
    lea rsi, [rip + rqt_value]
    mov edx, 1048550
    call memeq
    test eax, eax
    jz rqt_fail
    # This resulting empty-file merge fits its independent1MiB disk cap.
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + rqt_decoded + SWR_delta]
    mov ecx, 1
    call ext_choices_merge
    test rax, rax
    jz rqt_fail
    cmp rdx, 1048557
    jne rqt_fail
    mov rdi, rax
    call mem_free
    # Actual munmap/VirtualFree failure retains mapping and charge in ESM disposer.
    mov qword ptr [rip + rqt_stage], 215
    mov qword ptr [rip + rqt_now], 1000
    mov qword ptr [rip + rqt_fail_unmap], 1
    call ext_settings_memory_total
    mov [rip + rqt_charge], rax
    mov rax, [rip + g_mem_live]
    mov [rip + rqt_free_live], rax
    mov rdi, [rip + rqt_frame]
    call ext_settings_frame_free
    test rax, rax
    jnz rqt_fail
    cmp rcx, 1
    jne rqt_fail
    test rdx, rdx
    jns rqt_fail
    mov qword ptr [rip + rqt_frame], 0
    mov qword ptr [rip + rqt_cursor + ESQ_magic], 0
    mov qword ptr [rip + rqt_cursor + ESQ_frame], 0
    cmp qword ptr [rip + rqt_fail_unmap], 0
    jne rqt_fail
    call ext_settings_memory_total
    cmp [rip + rqt_charge], rax
    jne rqt_fail
    mov rax, [rip + g_mem_live]
    cmp [rip + rqt_free_live], rax
    jne rqt_fail
    call ext_settings_memory_pending
    cmp rax, 1
    jne rqt_fail
    mov qword ptr [rip + rqt_now], 2000
    mov edi, 1
    call ext_settings_memory_gc
    cmp rax, 1
    jne rqt_fail
    test rdx, rdx
    js rqt_fail
    call ext_settings_memory_pending
    test rax, rax
    jnz rqt_fail
    call rqt_drop_batch_queue
    EPILOGUE
rqt_row_cases:
    PROLOGUE
    mov qword ptr [rip + rqt_stage], 216
    call ext_settings_queue_create
    test rax, rax
    jz rqt_fail
    mov rbx, rax
    lea r12, [rip + sq_delta]
    xor r13d, r13d
1:  lea rdi, [rip + sq_keybuf]
    mov byte ptr [rdi], 'k'
    inc rdi
    mov rsi, r13
    call fmt_u64
    lea rax, [rip + sq_keybuf]
    sub rdi, rax
    mov [r12 + EC_key], rax
    mov [r12 + EC_keylen], rdi
    mov qword ptr [r12 + EC_remove], 0
    cmp r13, 127
    je 3f
    mov rax, r13
    xor edx, edx
    mov ecx, 17
    div rcx
    test rdx, rdx
    jnz 4f
    mov qword ptr [r12 + EC_remove], 1
    xor edx, edx
    jmp 2f
4:  mov edx, 8000
    jmp 2f
3:  mov rdx, EC_LIMIT
    sub rdx, [rbx + EQ_payload]
    sub rdx, [r12 + EC_seclen]
    sub rdx, rdi
2:  mov [r12 + EC_vallen], rdx
    call sq_put
    test rax, rax
    jnz rqt_fail
    inc r13
    cmp r13, 128
    jb 1b
    cmp qword ptr [rbx + EQ_payload], EC_LIMIT
    jne rqt_fail
    lea rax, [rip + rqt_extra_key]
    mov [r12 + EC_key], rax
    mov qword ptr [r12 + EC_keylen], 1
    mov qword ptr [r12 + EC_vallen], 0
    call sq_put
    cmp rax, -27
    jne rqt_fail
    cmp qword ptr [rbx + EQ_count], 128
    jne rqt_fail
    cmp qword ptr [rbx + EQ_seq], 128
    jne rqt_fail
    mov rdi, rbx
    call ext_settings_queue_batch
    test rax, rax
    jz rqt_fail
    mov [rip + rqt_batch], rax
    mov [rip + rqt_request + SRQ_batch], rax
    call rqt_begin
    test rax, rax
    jz rqt_fail
    mov [rip + rqt_frame], rax
    cmp qword ptr [rax + EJF_length], 1054775
    jne rqt_fail
    mov edi, 17
    call rqt_encode_budget
    cmp rax, EC_LIMIT + 128 * 16
    jne rqt_fail
    call rqt_decode
    test rax, rax
    jnz rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_count], 128
    jne rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_delta + EC_remove], 1
    jne rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_delta + EC_vallen], 0
    jne rqt_fail
    mov rdi, [rip + rqt_frame]
    call ext_settings_frame_free
    cmp rcx, 1
    jne rqt_fail
    mov qword ptr [rip + rqt_frame], 0
    mov qword ptr [rip + rqt_cursor + ESQ_magic], 0
    call rqt_drop_batch_queue
    EPILOGUE
rqt_empty_cases:
    PROLOGUE
    mov qword ptr [rip + rqt_stage], 217
    mov qword ptr [rip + rqt_request + SRQ_batch], 0
    mov qword ptr [rip + rqt_batch], 0
    mov r13d, 1
1:  mov [rip + rqt_request + SRQ_mode], r13
    call rqt_begin
    test rax, rax
    jz rqt_fail
    mov [rip + rqt_frame], rax
    mov edi, 1
    call rqt_encode_budget
    test rax, rax
    jnz rqt_fail
    call rqt_decode
    test rax, rax
    jnz rqt_fail
    cmp [rip + rqt_decoded + SWR_mode], r13
    jne rqt_fail
    cmp qword ptr [rip + rqt_decoded + SWR_count], 0
    jne rqt_fail
    mov rdi, [rip + rqt_frame]
    call ext_settings_frame_free
    cmp rcx, 1
    jne rqt_fail
    mov qword ptr [rip + rqt_frame], 0
    mov qword ptr [rip + rqt_cursor + ESQ_magic], 0
    add r13, 2
    cmp r13, 3
    jbe 1b
    EPILOGUE
