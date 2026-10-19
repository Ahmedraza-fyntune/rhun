# The fixture models a preflighted metadata slot and a distinct retained host activation.
.section .rodata
lc_owner_source: .byte 1
.zero 31
lc_owner_tree: .zero 32
lc_unaccepted_args: .asciz "--unaccepted"
lc_config_prefix: .asciz "XDG_CONFIG_HOME="
lc_borrow_fields: .quad EXT_title, EXT_version, EXT_dir, EXT_prog, EXT_script, EXT_runs, EXT_args
.bss
.p2align 3
lc_ep: .quad 0
lc_ea: .quad 0
lc_initial_ep: .quad 0
lc_old_ea: .quad 0
lc_old_metadata: .quad 0
lc_retire_status: .zero 32
lc_config_env: .zero 4120
.text
lc_ep_create:
    PROLOGUE
    mov rdi, -1
    mov rsi, [rip + tek_plan + KE_payload]
    mov rdx, [rip + tek_plan + KE_owner]
    mov rcx, [rip + tek_plan + KE_name]
    call ext_prepare_alloc
    test rax, rax
    jz .Ltek_fail
    mov rbx, rax
    mov [rip + lc_ep], rax
    mov qword ptr [rip + lc_initial_ep], 1
    mov qword ptr [rbx + EP_kind], 2
    mov rdi, rbx
    call ext_prepare_enable_deferred
    test rax, rax
    jnz .Ltek_fail
    mov rsi, [rip + tek_plan + KE_program]
    call lc_owned_dup
    mov [rbx + EP_ext + EXT_prog], rax
    lea rsi, [rip + lc_arguments]
    call lc_owned_dup
    mov [rbx + EP_ext + EXT_args], rax
    mov eax, [rip + tek_plan + KE_needs]
    mov [rbx + EP_ext + EXT_needs], eax
    mov rax, [rbx + PO_eo]
    mov rcx, [rip + tek_plan + KE_lease]
    mov [rax + EO_lease], rcx
    mov dword ptr [rbx + EP_ext + EXT_manifest_ok], 1
    mov qword ptr [rbx + PO_ready], 1
    EPILOGUE

lc_owned_dup:
    PROLOGUE
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call prep_owned_dup
    test rax, rax
    jz .Ltek_fail
    EPILOGUE

lc_plan_capture:
    PROLOGUE
    mov rdi, [rip + lc_ep]
    lea rsi, [rip + tek_plan]
    mov edx, EA_LEGACY
    lea rcx, [rip + lc_owner_source]
    lea r8, [rip + lc_owner_tree]
    call ext_activation_owner_create
    test rax, rax
    jz .Ltek_fail
    test rdx, rdx
    jnz .Ltek_fail
    mov rbx, rax
    mov rdi, [rip + lc_ea]
    test rdi, rdi
    jz 1f
    call ext_activation_owner_release
    call lc_consumed
1:  mov [rip + lc_ea], rbx
    mov rdi, rbx
    call ext_activation_owner_plan
    test rax, rax
    jz .Ltek_fail
    mov [rip + tek_owned_plan], rax
    cmp qword ptr [rip + lc_initial_ep], 0
    je 2f
    mov qword ptr [rip + lc_initial_ep], 0
    mov rdi, [rip + lc_ep]
    call ext_prepare_release_deferred
    call lc_consumed
2:  EPILOGUE

lc_consumed:
    test rax, rax
    jnz .Ltek_fail
    cmp rdx, 1
    jne .Ltek_fail
    ret

# Actual keeper_close and raw EOF must already have completed; no status-only shortcut.
lc_owner_take:
    PROLOGUE
    cmp qword ptr [rip + lc_extension + EXT_activation_owner], 0
    je 1f
    lea rdi, [rip + lc_extension]
    xor esi, esi
    lea rdx, [rip + lc_old_ea]
    call ext_activation_host_swap
    call lc_consumed
    mov rdi, [rip + lc_old_ea]
    mov qword ptr [rip + lc_old_ea], 0
    call ext_activation_owner_release
    call lc_consumed
1:  EPILOGUE

# Exact hidden metadata and durable identity withdrawal after native collection.
lc_metadata_drop:
    PROLOGUE
    cmp qword ptr [rip + lc_extension + EXT_metadata_owner], 0
    je 2f
    mov qword ptr [rip + g_ext_prepared_catalog_active], 1
    lea rdi, [rip + lc_extension]
    call ext_slot_hide_pure
    lea rdi, [rip + lc_extension]
    lea rsi, [rip + lc_old_metadata]
    call ext_slot_metadata_take
    call lc_consumed
    mov rdi, [rip + lc_old_metadata]
    mov qword ptr [rip + lc_old_metadata], 0
    call ext_prepare_release_deferred
    call lc_consumed
2:  cmp qword ptr [rip + lc_extension + EXT_identity_owner], 0
    je 3f
    lea rdi, [rip + lc_extension]
    lea rsi, [rip + lc_old_metadata]
    call ext_host_identity_take
    call lc_consumed
    mov rdi, [rip + lc_old_metadata]
    mov qword ptr [rip + lc_old_metadata], 0
    call ext_host_identity_release
    call lc_consumed
3:  EPILOGUE

lc_retire_pump:
    PROLOGUE
    mov rbx, 4096
1:  mov edi, 1
    lea rsi, [rip + lc_retire_status]
    call ext_prepare_retire_step
    test rax, rax
    js .Ltek_fail
    cmp qword ptr [rip + lc_retire_status], 1
    ja .Ltek_fail
    cmp qword ptr [rip + lc_retire_status + 16], 0
    jne .Ltek_fail
    cmp qword ptr [rip + lc_retire_status + 24], 0
    jne .Ltek_fail
    test rax, rax
    jz 2f
    dec rbx
    jnz 1b
    jmp .Ltek_fail
2:  EPILOGUE

# A detached prepared legacy host remains gated through restart and actual disable/re-enable.
lc_after_collection:
    PROLOGUE
    call lc_owner_take
    mov qword ptr [rip + tek_owned_plan], 0
    call lc_retire_pump
    cmp qword ptr [rip + lc_extension + EXT_metadata_owner], 0
    je .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_activation_required], 1
    jne .Ltek_fail
    mov rdi, [rip + lc_marker]
    SYS SYS_unlink
    test rax, rax
    js .Ltek_fail
    lea rdi, [rip + lc_extension]
    call ext_restart
    call lc_no_new_host
    mov dword ptr [rip + lc_extension + EXT_status], ES_STOPPED
    lea rdi, [rip + lc_extension]
    mov esi, 1
    call ext_set_disabled
    cmp dword ptr [rip + lc_extension + EXT_status], ES_DISABLED
    jne .Ltek_fail
    lea rdi, [rip + lc_extension]
    xor esi, esi
    call ext_set_disabled
    call lc_no_new_host
    call lc_no_marker
    mov dword ptr [rip + lc_extension + EXT_status], ES_REMOVED
    lea rdi, [rip + lc_extension]
    call ext_start
    cmp dword ptr [rip + lc_extension + EXT_status], ES_REMOVED
    jne .Ltek_fail
    call lc_no_new_host
    call lc_metadata_drop
    mov qword ptr [rip + lc_ep], 0
    call lc_retire_pump
    call ext_prepare_retire_charge
    test rax, rax
    jnz .Ltek_fail
    EPILOGUE

lc_no_new_host:
    cmp qword ptr [rip + lc_extension + EXT_activation_owner], 0
    jne .Ltek_fail
    cmp qword ptr [rip + lc_extension + EXT_activation_plan], 0
    jne .Ltek_fail
    cmp qword ptr [rip + lc_extension + EXT_keeper], 0
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_pid], 0
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_in], -1
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_out], -1
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_log], -1
    jne .Ltek_fail
    cmp dword ptr [rip + lc_extension + EXT_activation_required], 1
    jne .Ltek_fail
    ret

# Bounded prefix match, stopping at an early NUL in any inherited environment entry.
lc_is_config:
    xor ecx, ecx
1:  mov al, [rdi + rcx]
    test al, al
    jz 2f
    lea rdx, [rip + lc_config_prefix]
    cmp al, [rdx + rcx]
    jne 2f
    inc rcx
    cmp rcx, 16
    jb 1b
    mov eax, 1
    ret
2:  xor eax, eax
    ret
