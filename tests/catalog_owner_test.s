# Real shared dispatcher, fresh EO transfer and partial-owner cancellation.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.bss
.p2align 3
co_stage: .quad 0
co_charge: .quad 0
co_live: .quad 0
co_object: .quad 0
co_report: .zero 32
.text
co_fail:
    mov rdi, [rip + co_stage]
    add rdi, 40
    call sys_exit
    ud2
co_wrong_handler:
    jmp co_fail
co_drain:
    PROLOGUE
    mov r12d, 1000
1:  mov edi, 1
    lea rsi, [rip + co_report]
    call ext_prepare_retire_step
    test rax, rax
    js co_fail
    cmp qword ptr [rip + co_report], 1
    ja co_fail
    cmp qword ptr [rip + co_report + 16], 0
    jne co_fail
    test rax, rax
    jz 2f
    dec r12
    jnz 1b
    jmp co_fail
2:  call ext_prepare_retire_charge
    cmp rax, [rip + co_charge]
    jne co_fail
    mov rax, [rip + g_mem_live]
    cmp rax, [rip + co_live]
    jne co_fail
    EPILOGUE
FN main
    PROLOGUE
    mov qword ptr [rip + co_stage], 1
    call ext_prepare_retire_charge
    mov [rip + co_charge], rax
    mov rax, [rip + g_mem_live]
    mov [rip + co_live], rax
    mov edi, C7_BASE
    call catalog_object_create
    test rax, rax
    jnz co_fail
    cmp rdx, -2
    jne co_fail
    test rcx, rcx
    jnz co_fail
    call catalog_kind7_init
    test rax, rax
    jnz co_fail
    call catalog_kind7_init
    test rax, rax
    jnz co_fail
    call catalog_kind7_check
    test rax, rax
    jnz co_fail
    mov edi, C7_KIND
    lea rsi, [rip + co_wrong_handler]
    mov edx, 1
    call ext_prepare_retire_register_kind
    cmp rax, -17
    jne co_fail
    mov edi, C7_KIND
    lea rsi, [rip + catalog_retire_one]
    xor edx, edx
    call ext_prepare_retire_register_kind
    cmp rax, -17
    jne co_fail
    call catalog_kind7_check
    test rax, rax
    jnz co_fail
    mov qword ptr [rip + co_stage], 2
    mov edi, C7_BASE
    call catalog_object_create
    test rax, rax
    jz co_fail
    test rdx, rdx
    jnz co_fail
    test rcx, rcx
    jnz co_fail
    mov rbx, rax
    mov [rip + co_object], rax
    cmp qword ptr [rbx + PO_refs], 1
    jne co_fail
    cmp qword ptr [rbx + RB_constructor_eo], 0
    jne co_fail
    mov rax, [rbx + PO_eo]
    cmp qword ptr [rax + EO_refs], 1
    jne co_fail
    mov rdi, rbx
    call registry_base_retain
    cmp rax, -EV_BAD_PREPARE
    jne co_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne co_fail
    mov rdi, rbx
    call registry_base_view
    test rax, rax
    jnz co_fail
    cmp rdx, -EV_BAD_PREPARE
    jne co_fail
    mov rdi, rbx
    call registry_base_status
    test rax, rax
    jnz co_fail
    test rdx, rdx
    jnz co_fail
    test rcx, rcx
    jnz co_fail
    test r8, r8
    jnz co_fail
    mov rdi, rbx
    lea rsi, [rbx - RD_PO_BACK]
    call catalog_retire_one
    cmp rax, -EV_BAD_PREPARE
    jne co_fail
    cmp rdx, 2
    jne co_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne co_fail
    mov rdi, rbx
    call registry_base_release_deferred
    test rax, rax
    jnz co_fail
    cmp rdx, 1
    jne co_fail
    call co_drain
    mov qword ptr [rip + co_stage], 3
    mov edi, C7_REGISTRY
    call catalog_object_create
    test rax, rax
    jz co_fail
    test rdx, rdx
    jnz co_fail
    mov rbx, rax
    mov rdi, rbx
    call registry_release_deferred
    test rax, rax
    jnz co_fail
    cmp rdx, 1
    jne co_fail
    call co_drain
    mov qword ptr [rip + co_stage], 4
    mov edi, C7_REGISTRY
    call catalog_object_create
    test rax, rax
    jz co_fail
    mov rbx, rax
    mov qword ptr [rbx - RD_PO_BACK + RD_kind], RD_LEDGER
    mov qword ptr [rbx + PO_error], -5
    mov qword ptr [rbx + RG_phase], RG_FAILED
    mov rdi, rbx
    call registry_release_deferred
    test rax, rax
    jnz co_fail
    cmp rdx, 1
    jne co_fail
    call co_drain
    mov qword ptr [rip + co_stage], 5
    mov edi, C7_BASE
    call catalog_object_create
    test rax, rax
    jz co_fail
    mov rbx, rax
    mov qword ptr [rbx + RB_version], 23
    mov qword ptr [rbx + RB_view + 64], 23
    mov qword ptr [rbx + RB_phase], RB_READY
    mov qword ptr [rbx + PO_ready], 1
    mov rdi, rbx
    call registry_base_retain
    test rax, rax
    jnz co_fail
    cmp qword ptr [rbx + PO_refs], 2
    jne co_fail
    mov rdi, rbx
    call registry_base_view
    lea rcx, [rbx + RB_view]
    cmp rax, rcx
    jne co_fail
    test rdx, rdx
    jnz co_fail
    cmp qword ptr [rax + 64], 23
    jne co_fail
    mov rdi, rbx
    call registry_base_release_deferred
    cmp rdx, 1
    jne co_fail
    cmp qword ptr [rbx + PO_refs], 1
    jne co_fail
    mov rdi, rbx
    call registry_base_release_deferred
    cmp rdx, 1
    jne co_fail
    call co_drain
    mov qword ptr [rip + co_stage], 6
    mov edi, C7_REGISTRY
    call catalog_object_create
    test rax, rax
    jz co_fail
    mov rbx, rax
    mov qword ptr [rbx + PO_refs], 0
    mov qword ptr [rbx - RD_PO_BACK + RD_state], RDF_PO | RD_RUNNING
    mov qword ptr [rbx + C7_role], C7_PLAN
    mov rdi, rbx
    lea rsi, [rbx - RD_PO_BACK]
    call catalog_retire_one
    cmp rax, -EV_BAD_PREPARE
    jne co_fail
    cmp rdx, 2
    jne co_fail
    cmp qword ptr [rbx - RD_PO_BACK + RD_phase], 0
    jne co_fail
    mov qword ptr [rbx + C7_role], C7_REGISTRY
    mov qword ptr [rbx + C7_magic], 0
    mov rdi, rbx
    lea rsi, [rbx - RD_PO_BACK]
    call catalog_retire_one
    cmp rax, -EV_BAD_PREPARE
    jne co_fail
    cmp rdx, 2
    jne co_fail
    mov rax, C7_MAGIC
    mov [rbx + C7_magic], rax
    mov qword ptr [rbx + C7_bytes], C7_SIZE
    mov rdi, rbx
    lea rsi, [rbx - RD_PO_BACK]
    call catalog_retire_one
    cmp rax, -EV_BAD_PREPARE
    jne co_fail
    cmp rdx, 2
    jne co_fail
    mov qword ptr [rbx + C7_bytes], RG_SIZE
    mov qword ptr [rbx + PO_refs], 1
    mov qword ptr [rbx - RD_PO_BACK + RD_state], RDF_PO | RD_ACTIVE
    mov rdi, rbx
    call registry_release_deferred
    cmp rdx, 1
    jne co_fail
    call co_drain
    xor eax, eax
    EPILOGUE
