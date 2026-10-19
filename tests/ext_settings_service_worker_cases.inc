# Real ordinary SVC/helper integration. The fixture alone composes an empty catalog.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.section .rodata
svw_marker: .asciz "--extension-settings-worker"
svw_section: .ascii "owner/tool"
svw_key: .ascii "pinned"
svw_yes: .ascii "yes"
svw_no: .ascii "no"
.data
svw_sigact: .quad 1,0,0,0
.bss
.p2align 3
svw_svc: .quad 0
svw_held: .quad 0
svw_baseline: .quad 0
svw_stage: .quad 0
svw_mode: .quad 0
svw_length: .quad 0
svw_digest: .zero 32
svw_newer: .quad 0
svw_deadline: .quad 0
svw_epoch: .quad 0
svw_result: .zero 64
.text
svw_fail:
    mov r15, [rip + svw_stage]
    mov rax, [rip + svw_svc]
    test rax, rax
    jz 1f
    cmp [rip + settings_service_current], rax
    jne 1f
    lea rsi, [rax + SV_primary]
    mov edi, 2
    mov edx, 64
    call write_all
1:  mov rdi, r15
    call sys_exit
# Scheduled real timer: no fast-loop throughput assumption.
svw_wait:
    PROLOGUE
    call time_ms
    cmp rax, [rip + svw_deadline]
    jae svw_fail
    mov rdi, [rip + svw_svc]
    mov rsi, rax
    call ext_settings_service_timeout
    test rax, rax
    jle 1f
    cmp rax, 1000
    ja svw_fail
    mov rdx, rax
    xor edi, edi
    xor esi, esi
    SYS SYS_poll
1:  EPILOGUE
# Real Q accepted delta, synchronously copies fixed test input.
svw_put:
    PROLOGUE EC_SIZE
    mov [rsp + EC_value], rdi
    mov [rsp + EC_vallen], rsi
    lea rax, [rip + svw_section]
    mov [rsp + EC_section], rax
    mov qword ptr [rsp + EC_seclen], 10
    lea rax, [rip + svw_key]
    mov [rsp + EC_key], rax
    mov qword ptr [rsp + EC_keylen], 6
    mov qword ptr [rsp + EC_remove], 0
    mov rax, [rip + svw_svc]
    mov rdi, [rax + SV_queue]
    mov rsi, rsp
    call ext_settings_queue_put
    test rax, rax
    jnz svw_fail
    EPILOGUE
# No EXT schemas in this fixture. Uses actual pure whole-set model constructor.
svw_install_empty:
    PROLOGUE ECSCP_SIZE
    mov rax, [rip + svw_held]
    mov [rsp + ECSCP_source], rax
    mov qword ptr [rsp + ECSCP_rows], 0
    mov qword ptr [rsp + ECSCP_count], 0
    mov rax, [rip + esv_registry_epoch]
    mov [rsp + ECSCP_registry], rax
    mov rax, [rip + esv_model_epoch]
    mov [rsp + ECSCP_model], rax
    mov rax, [rip + esv_service_queue]
    mov rax, [rax + EQ_epoch]
    mov [rsp + ECSCP_dirty], rax
    mov rdi, rsp
    call ext_settings_catalog_prepare
    test rax, rax
    jz svw_fail
    mov r12, rax
1:  mov rdi, r12
    mov esi, 65536
    call ext_settings_catalog_step
    test rax, rax
    js svw_fail
    cmp rax, 1
    jne 1b
    mov rdi, r12
    call ext_settings_catalog_check
    test rax, rax
    jnz svw_fail
    mov rdi, r12
    call ext_settings_catalog_publish
    mov rdi, r12
    call ext_settings_catalog_release
    test rax, rax
    jnz svw_fail
    mov rax, [rip + svw_svc]
    mov qword ptr [rax + SV_installed], 1
    EPILOGUE
FN main
    PROLOGUE 64
    mov qword ptr [rip + svw_stage], 200
    mov edi, 13
    lea rsi, [rip + svw_sigact]
    xor edx, edx
    mov r10d, 8
    SYS SYS_rt_sigaction
    cmp qword ptr [rip + g_argc], 2
    jb svw_fail
    mov rax, [rip + g_argv]
    mov rdi, [rax + 8]
    lea rsi, [rip + svw_marker]
    call strcmp_eq
    test eax, eax
    jz .Lsvw_parent
    cmp qword ptr [rip + g_argc], 6
    jne 8f
    mov rax, [rip + g_argv]
    mov rax, [rax + 40]
    cmp word ptr [rax], 0x3930
    jne 8f
    mov qword ptr [rip + svwf_child_die], 1
8:  mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call ext_settings_worker_main
    EPILOGUE
.Lsvw_parent:
    cmp qword ptr [rip + g_argc], 5
    jne svw_fail
    mov rax, [rip + g_mem_live]
    mov [rip + svw_baseline], rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 16]
    call parse_u64
    cmp rax, 1
    jb svw_fail
    cmp rax, 15
    ja svw_fail
    mov [rip + svw_mode], rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call strlen
    mov rsi, rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 24]
    call parse_u64
    cmp rax, 1048576
    ja svw_fail
    mov [rip + svw_length], rax
    mov rax, [rip + g_argv]
    mov rdi, [rax + 32]
    lea rsi, [rip + svw_digest]
    call ext_validate_unhex
    test rax, rax
    jnz svw_fail
    mov rax, [rip + g_argv]
    mov rbx, [rax + 8]
    mov rdi, rbx
    call strlen
    mov [rsp + SVI_path], rbx
    mov [rsp + SVI_length], rax
    mov qword ptr [rsp + SVI_context], 67
    mov qword ptr [rsp + SVI_nonce], 11
    cmp qword ptr [rip + svw_mode], 9
    jne 9f
    mov qword ptr [rsp + SVI_nonce], 9
9:
    mov qword ptr [rsp + SVI_nonce + 8], 29
    mov rdi, rsp
    call ext_settings_service_create
    test rax, rax
    jz svw_fail
    mov [rip + svw_svc], rax
    cmp qword ptr [rip + svw_mode], 13
    je 8f
    cmp qword ptr [rip + svw_mode], 15
    jne 9f
8:  call svwf_busy_begin
9:  call time_ms
    add rax, 30000
    mov [rip + svw_deadline], rax
    mov qword ptr [rip + svw_stage], 201
.Lsvw_read:
    call time_ms
    mov rsi, rax
    mov rdi, [rip + svw_svc]
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    cmp qword ptr [rip + svw_mode], 13
    je 7f
    cmp qword ptr [rip + svw_mode], 15
    jne 8f
7:  call svwf_read_close_retry
    cmp rax, 1
    je .Lsvw_cleanup
    jmp .Lsvw_read_wait
8:  call svwf_read_observe
    cmp rax, 1
    je .Lsvw_cleanup
    cmp qword ptr [rip + svw_mode], 12
    jne 9f
    call svwf_malformed
    cmp rax, 1
    je .Lsvw_cleanup
    jmp .Lsvw_read_wait
9:  mov rdi, [rip + svw_svc]
    cmp qword ptr [rip + svw_mode], 6
    je .Lsvw_read_wait
    cmp qword ptr [rdi + SV_primary], 0
    jne svw_fail
    cmp qword ptr [rdi + SV_source], 0
    je .Lsvw_read_wait
    cmp qword ptr [rdi + SV_phase], 0
    jne .Lsvw_read_wait
    mov qword ptr [rip + svw_stage], 211
    lea rsi, [rip + svw_epoch]
    call ext_settings_service_source
    test rax, rax
    jz svw_fail
    mov [rip + svw_held], rax
    mov qword ptr [rip + svw_stage], 212
    cmp qword ptr [rip + svw_epoch], 1
    jne svw_fail
    cmp qword ptr [rax + ESB_exists], 1
    jne svw_fail
    mov rdx, [rip + svw_length]
    cmp [rax + ESB_length], rdx
    jne svw_fail
    mov qword ptr [rip + svw_stage], 213
    lea rdi, [rax + ESB_digest]
    lea rsi, [rip + svw_digest]
    mov edx, 32
    call memeq
    test eax, eax
    jz svw_fail
    cmp qword ptr [rip + svw_mode], 1
    je .Lsvw_cleanup
    cmp qword ptr [rip + svw_mode], 10
    je .Lsvw_reload
    cmp qword ptr [rip + svw_mode], 11
    je .Lsvw_reload
    jmp .Lsvw_save_begin
.Lsvw_reload:
    call svwf_reload
    jmp .Lsvw_cleanup
.Lsvw_read_wait:
    call svw_wait
    jmp .Lsvw_read
.Lsvw_save_begin:
    mov qword ptr [rip + svw_stage], 202
    call svw_install_empty
    cmp qword ptr [rip + svw_mode], 14
    jne 9f
    call svwf_busy_begin
9:  lea rdi, [rip + svw_yes]
    mov esi, 3
    call svw_put
.Lsvw_save:
    call time_ms
    mov rsi, rax
    mov rdi, [rip + svw_svc]
    call ext_settings_service_step
    test rax, rax
    js svw_fail
    call svwf_save_observe
    cmp rax, 1
    je .Lsvw_cleanup
    mov rbx, [rip + svw_svc]
    cmp qword ptr [rip + svw_mode], 3
    je 9f
    cmp qword ptr [rip + svw_mode], 4
    je 9f
    cmp qword ptr [rbx + SV_primary], 0
    jne svw_fail
9:
    cmp qword ptr [rip + svw_newer], 0
    jne 1f
    cmp qword ptr [rbx + SV_batch], 0
    je 1f
    lea rdi, [rip + svw_no]
    mov esi, 2
    call svw_put
    mov qword ptr [rip + svw_newer], 1
1:  cmp qword ptr [rbx + SV_commit], 1
    jne .Lsvw_save_wait
    cmp qword ptr [rbx + SV_pending], 0
    je .Lsvw_save_wait
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvw_save_wait
    cmp qword ptr [rbx + SV_phase], 0
    jne .Lsvw_save_wait
    cmp qword ptr [rbx + SV_batch_phase], 2
    jne svw_fail
    cmp qword ptr [rbx + SV_batch], 0
    je svw_fail
    cmp qword ptr [rbx + SV_source_epoch], 1
    jne svw_fail
    mov rdi, [rbx + SV_queue]
    cmp qword ptr [rdi + EQ_count], 1
    jne svw_fail
    lea rsi, [rip + svw_section]
    mov edx, 10
    lea rcx, [rip + svw_key]
    mov r8d, 6
    call ext_settings_queue_find
    test rax, rax
    jz svw_fail
    cmp qword ptr [rax + EC_vallen], 2
    jne svw_fail
    mov rdi, [rax + EC_value]
    lea rsi, [rip + svw_no]
    mov edx, 2
    call memeq
    test eax, eax
    jz svw_fail
    mov rdi, rbx
    lea rsi, [rip + svw_epoch]
    call ext_settings_service_source
    test rax, rax
    jnz svw_fail
    cmp rdx, -16
    jne svw_fail
    jmp .Lsvw_cleanup
.Lsvw_save_wait:
    call svw_wait
    jmp .Lsvw_save
.Lsvw_cleanup:
    cmp qword ptr [rip + svw_mode], 5
    jne 5f
    cmp qword ptr [rip + svwf_local_retry], 1
    jne svw_fail
    cmp qword ptr [rip + svwf_conversion_attempts], 2
    jne svw_fail
5:  cmp qword ptr [rip + svw_mode], 7
    jne 6f
    cmp qword ptr [rip + svwf_native_fail], 1
    jne svw_fail
    cmp qword ptr [rip + svwf_backoff_seen], 0
    je svw_fail
6:  cmp qword ptr [rip + svw_mode], 8
    jne 7f
    cmp qword ptr [rip + svwf_frame_fail], 1
    jne svw_fail
    cmp qword ptr [rip + svwf_command_fail], 1
    jne svw_fail
    cmp qword ptr [rip + svwf_finish_seen], 0
    je svw_fail
7:
    # Explicit fixture-only discard after settled actual native lifetime. No ACK.
    mov qword ptr [rip + svw_stage], 203
    mov rbx, [rip + svw_svc]
    mov rax, [rbx + SV_uncertain]
    mov [rip + svw_result + 40], rax
    mov rax, [rbx + SV_cleanup]
    mov [rip + svw_result + 32], rax
    mov rax, [rbx + SV_source_epoch]
    mov [rip + svw_result], rax
    mov rax, [rbx + SV_pending_epoch]
    mov [rip + svw_result + 8], rax
    mov rax, [rbx + SV_commit]
    mov [rip + svw_result + 16], rax
    mov rax, [rbx + SV_batch_phase]
    mov [rip + svw_result + 24], rax
    mov rdi, [rbx + SV_pending]
    call ext_settings_snapshot_release
    test rax, rax
    jnz svw_fail
    mov qword ptr [rbx + SV_pending], 0
    mov rdi, [rip + svw_held]
    call ext_settings_snapshot_release
    test rax, rax
    jnz svw_fail
    mov qword ptr [rip + svw_held], 0
    mov rdi, [rbx + SV_batch]
    test rdi, rdi
    jz 1f
    call ext_settings_batch_free
    test rax, rax
    jnz svw_fail
    cmp rcx, 1
    jne svw_fail
    mov qword ptr [rbx + SV_batch], 0
1:  mov rdi, [rbx + SV_queue]
    call ext_settings_queue_discard_step
    test rax, rax
    jnz 1b
    mov r12d, 32
2:  mov rdi, [rbx + SV_queue]
    call ext_settings_queue_gc
    dec r12
    jnz 2b
    mov qword ptr [rbx + SV_state], SV_SHUTTING
    mov rdi, rbx
    call ext_settings_service_detach_check
    test rax, rax
    jnz svw_fail
    mov rdi, rbx
    call ext_settings_service_detach_publish
    mov rdi, rbx
    call ext_settings_service_release
    test rax, rax
    jnz svw_fail
    mov r12d, 128
3:  mov edi, 1
    call ext_settings_service_gc
    test rdx, rdx
    jns 4f
    cmp qword ptr [rip + svw_mode], 6
    je 4f
    cmp qword ptr [rip + svw_mode], 7
    je 4f
    cmp qword ptr [rip + svw_mode], 8
    jne svw_fail
4:  mov edi, 64
    call ext_settings_catalog_gc
    mov edi, 64
    call ext_settings_model_gc
    mov edi, 64
    call ext_settings_snapshot_gc
    dec r12
    jnz 3b
    call ext_settings_memory_total
    test rax, rax
    jnz svw_fail
    mov rax, [rip + g_mem_live]
    cmp [rip + svw_baseline], rax
    jne svw_fail
    mov edi, 1
    lea rsi, [rip + svw_result]
    mov edx, 64
    call write_all
    xor eax, eax
    EPILOGUE

.include "ext_settings_service_worker_faults.inc"
