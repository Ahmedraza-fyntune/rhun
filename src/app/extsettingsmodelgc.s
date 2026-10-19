# Final model disposal walks fixed slot ownership, not schema or provider fields.
.include "rhun.inc"
.include "app/extsettingsview.inc"
.text
# Provider descriptors and copied strings occupy one owned immutable packed block.
# Any raw-source spans inside it are protected by this model's independent ESB ref.
# gc(maxUnits1..64)->logical ownership units,RDX first cleanup.
FN ext_settings_model_gc
    test rdi, rdi
    jz .Lmodelgc_invalid
    cmp rdi, 64
    ja .Lmodelgc_invalid
    PROLOGUE
    mov r12, rdi
    xor r13d, r13d
    xor r15d, r15d
.Lmodelgc_loop:
    test r12, r12
    jz .Lmodelgc_return
    mov rbx, [rip + esv_model_retired_head]
    test rbx, rbx
    jz .Lmodelgc_return
    mov rcx, [rbx + ELM_gcindex]
    cmp rcx, 128
    jae .Lmodelgc_extra
    lea r14, [rbx + ELM_slots + rcx * 8]
    mov rdi, [r14]
    call ext_settings_view_release
    test rax, rax
    jnz .Lmodelgc_blocked
    mov qword ptr [r14], 0
    inc qword ptr [rbx + ELM_gcindex]
    jmp .Lmodelgc_unit
.Lmodelgc_extra:
    mov rax, [rbx + ELM_gcphase]
    test rax, rax
    jz .Lmodelgc_providers
    cmp rax, 1
    je .Lmodelgc_source
    mov r14, [rbx + ELM_next]
    mov rdi, rbx
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lmodelgc_blocked
    mov [rip + esv_model_retired_head], r14
    test r14, r14
    jnz 1f
    mov qword ptr [rip + esv_model_retired_tail], 0
1:  dec qword ptr [rip + esv_model_retired_count]
    jmp .Lmodelgc_note
.Lmodelgc_providers:
    mov rdi, [rbx + ELM_providers]
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lmodelgc_blocked
    mov qword ptr [rbx + ELM_providers], 0
    inc qword ptr [rbx + ELM_gcphase]
    jmp .Lmodelgc_note
.Lmodelgc_source:
    mov rdi, [rbx + ELM_source]
    call ext_settings_snapshot_release
    test rax, rax
    jnz .Lmodelgc_blocked
    mov qword ptr [rbx + ELM_source], 0
    inc qword ptr [rbx + ELM_gcphase]
    jmp .Lmodelgc_unit
.Lmodelgc_note:
    test rdx, rdx
    jns .Lmodelgc_unit
    test r15, r15
    jnz .Lmodelgc_unit
    mov r15, rdx
.Lmodelgc_unit:
    inc r13
    dec r12
    jmp .Lmodelgc_loop
.Lmodelgc_blocked:
    test r15, r15
    jnz .Lmodelgc_return
    test rax, rax
    js 1f
    mov rax, -22
1:  mov r15, rax
.Lmodelgc_return:
    mov rax, r13
    mov rdx, r15
    EPILOGUE
.Lmodelgc_invalid:
    mov rax, -22
    xor edx, edx
    ret
