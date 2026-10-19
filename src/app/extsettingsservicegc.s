# Failed constructor/domain retirement keeps every child until accepted release.
.include "rhun.inc"
.include "app/extsettingsservice.inc"
.text
# gc(budget1..64)->completed ownership units,RDX first cleanup.
# Busy children stop this pass. Native mapping failures transfer into ESM disposer.
FN ext_settings_service_gc
    test rdi, rdi
    jz .Lsvg_bad_leaf
    cmp rdi, 64
    ja .Lsvg_bad_leaf
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
    xor r14d, r14d
.Lsvg_next:
    test r12, r12
    jz .Lsvg_return
    mov rbx, [rip + settings_service_retired_head]
    test rbx, rbx
    jz .Lsvg_return
    # No domain with unresolved native/adoption ownership can be destroyed.
    cmp qword ptr [rbx + SV_job], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_frame], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_release_frame], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_delivery], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_sap], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_srt], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_batch], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_pending], 0
    jne .Lsvg_busy
    cmp qword ptr [rbx + SV_provisional], 0
    jne .Lsvg_busy
    mov rdi, [rbx + SV_detached_model]
    test rdi, rdi
    jz .Lsvg_source
    call ext_settings_model_release
    test rax, rax
    js .Lsvg_primary
    mov qword ptr [rbx + SV_detached_model], 0
    jmp .Lsvg_unit
.Lsvg_source:
    mov rdi, [rbx + SV_replaced_source]
    test rdi, rdi
    jz .Lsvg_accepted_source
    call ext_settings_snapshot_release
    test rax, rax
    js .Lsvg_primary
    mov qword ptr [rbx + SV_replaced_source], 0
    jmp .Lsvg_unit
.Lsvg_accepted_source:
    mov rdi, [rbx + SV_source]
    test rdi, rdi
    jz .Lsvg_queue
    call ext_settings_snapshot_release
    test rax, rax
    js .Lsvg_primary
    mov qword ptr [rbx + SV_source], 0
    jmp .Lsvg_unit
.Lsvg_queue:
    mov rdi, [rbx + SV_queue]
    test rdi, rdi
    jz .Lsvg_path
    call ext_settings_queue_free
    test rax, rax
    js .Lsvg_primary
    cmp rcx, 1
    jne .Lsvg_busy
    mov qword ptr [rbx + SV_queue], 0
    jmp .Lsvg_cleanup
.Lsvg_path:
    mov rdi, [rbx + SV_path]
    test rdi, rdi
    jz .Lsvg_self
    call ext_settings_memory_free
    test rax, rax
    js .Lsvg_primary
    cmp rcx, 1
    jne .Lsvg_busy
    mov qword ptr [rbx + SV_path], 0
.Lsvg_cleanup:
    test rdx, rdx
    jns .Lsvg_unit
    cmp qword ptr [rbx + SV_cleanup], 0
    jne 1f
    mov [rbx + SV_cleanup], rdx
1:  test r14, r14
    jnz .Lsvg_unit
    mov r14, rdx
.Lsvg_unit:
    inc r13
    dec r12
    jmp .Lsvg_next
.Lsvg_self:
    mov r15, [rbx + SV_next]
    test r14, r14
    jnz 1f
    mov r14, [rbx + SV_cleanup]
1:  mov rdi, rbx
    call ext_settings_memory_free
    test rax, rax
    js .Lsvg_primary
    cmp rcx, 1
    jne .Lsvg_busy
    # Self may be unmapped. Only captured linkage/accounting can be used now.
    mov [rip + settings_service_retired_head], r15
    test r15, r15
    jnz 2f
    mov qword ptr [rip + settings_service_retired_tail], 0
2:  dec qword ptr [rip + settings_service_retired_count]
    test r14, r14
    jnz .Lsvg_unit
    test rdx, rdx
    jns .Lsvg_unit
    mov r14, rdx
    jmp .Lsvg_unit
.Lsvg_busy:
    mov rax, -16
.Lsvg_primary:
    test r14, r14
    jnz .Lsvg_return
    mov r14, rax
.Lsvg_return:
    mov rax, r13
    mov rdx, r14
    EPILOGUE
.Lsvg_bad_leaf:
    mov rax, -22
    xor edx, edx
    ret
