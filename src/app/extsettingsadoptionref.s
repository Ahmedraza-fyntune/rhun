# SAP graph releases accept references into bounded retirement without native IO.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.bss
.p2align 3
.globl settings_adoption_retired_head, settings_adoption_retired_tail
.globl settings_adoption_retired_count
settings_adoption_retired_head: .quad 0
settings_adoption_retired_tail: .quad 0
settings_adoption_retired_count: .quad 0
.text
FN ext_settings_adoption_retain
    test rdi, rdi
    jz .Lapr_bad
    mov rax, SAP_MAGIC
    cmp [rdi + AP_magic], rax
    jne .Lapr_bad
    cmp qword ptr [rdi + AP_refs], 0
    jle .Lapr_bad
    cmp qword ptr [rdi + AP_state], APS_RETIRED
    jae .Lapr_bad
    mov rax, 0x7fffffffffffffff
    cmp [rdi + AP_refs], rax
    jae .Lapr_overflow
    inc qword ptr [rdi + AP_refs]
    xor eax, eax
    ret
.Lapr_bad:
    mov rax, -22
    ret
.Lapr_overflow:
    mov rax, -75
    ret
# Last registered reference cannot be dropped without explicit authority invalidation.
FN ext_settings_adoption_release
    test rdi, rdi
    jz .Lapr_release_ok
    mov rax, SAP_MAGIC
    cmp [rdi + AP_magic], rax
    jne .Lapr_release_bad
    cmp qword ptr [rdi + AP_refs], 0
    jle .Lapr_release_bad
    cmp qword ptr [rdi + AP_state], APS_RETIRED
    jae .Lapr_release_bad
    cmp qword ptr [rdi + AP_refs], 1
    ja .Lapr_decrement
    mov rax, [rdi + AP_svc]
    test rax, rax
    jz .Lapr_enqueue
    cmp [rax + SV_sap], rdi
    je .Lapr_release_busy
.Lapr_enqueue:
    mov qword ptr [rdi + AP_refs], 0
    mov qword ptr [rdi + AP_state], APS_RETIRED
    mov qword ptr [rdi + AP_next], 0
    mov rax, [rip + settings_adoption_retired_tail]
    test rax, rax
    jz 1f
    mov [rax + AP_next], rdi
    jmp 2f
1:  mov [rip + settings_adoption_retired_head], rdi
2:  mov [rip + settings_adoption_retired_tail], rdi
    inc qword ptr [rip + settings_adoption_retired_count]
    jmp .Lapr_release_ok
.Lapr_decrement:
    dec qword ptr [rdi + AP_refs]
.Lapr_release_ok:
    xor eax, eax
    xor edx, edx
    mov ecx, 1
    ret
.Lapr_release_busy:
    mov rax, -16
    jmp .Lapr_refused
.Lapr_release_bad:
    mov rax, -22
.Lapr_refused:
    xor edx, edx
    xor ecx, ecx
    ret
# Invalidates only this exact borrowed registration. Pending source and batch remain.
FN ext_settings_adoption_cancel
    test rdi, rdi
    jz .Lapr_bad
    mov rax, SAP_MAGIC
    cmp [rdi + AP_magic], rax
    jne .Lapr_bad
    cmp qword ptr [rdi + AP_refs], 0
    jle .Lapr_bad
    cmp qword ptr [rdi + AP_state], APS_CANCELED
    je .Lapr_cancel_ok
    cmp qword ptr [rdi + AP_state], APS_BUILDING
    jb .Lapr_bad
    cmp qword ptr [rdi + AP_state], APS_EXPORTED
    ja .Lapr_cancel_stale
    mov rax, [rdi + AP_svc]
    test rax, rax
    jz .Lapr_cancel_state
    cmp [rax + SV_sap], rdi
    jne .Lapr_cancel_state
    mov rdx, [rdi + AP_ticket]
    cmp [rax + SV_sap_ticket], rdx
    jne .Lapr_cancel_state
    cmp qword ptr [rdi + AP_state], APS_EXPORTED
    jne 1f
    mov qword ptr [rax + SV_apply_grant], 0
    cmp qword ptr [rax + SV_apply_error], 0
    jne 1f
    mov qword ptr [rax + SV_apply_error], -125
1:  mov qword ptr [rax + SV_sap], 0
    mov qword ptr [rax + SV_sap_ticket], 0
.Lapr_cancel_state:
    mov qword ptr [rdi + AP_state], APS_CANCELED
.Lapr_cancel_ok:
    xor eax, eax
    ret
.Lapr_cancel_stale:
    mov rax, -116
    ret
FN ext_settings_adoption_pending
    mov rax, [rip + settings_adoption_retired_count]
    ret
