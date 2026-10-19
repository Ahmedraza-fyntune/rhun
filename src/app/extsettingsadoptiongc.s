# One producer slot/reference/self per budget unit. No queue reads after cancellation.
.include "rhun.inc"
.include "app/extsettingsadoption.inc"
.text
# gc(budget1..64)->examined units/-EINVAL,RDX first cleanup diagnostic.
FN ext_settings_adoption_gc
    cmp rdi, 1
    jb .Lapg_bad_leaf
    cmp rdi, 64
    ja .Lapg_bad_leaf
    PROLOGUE 24
    mov r12, rdi
    xor r13d, r13d
    xor r14d, r14d
    call time_ms
    mov [rsp], rax
.Lapg_loop:
    cmp r13, r12
    jae .Lapg_done
    mov rbx, [rip + settings_adoption_retired_head]
    test rbx, rbx
    jz .Lapg_done
    mov rax, [rsp]
    cmp rax, [rbx + AP_retiredue]
    jb .Lapg_done
    inc r13
    mov rax, [rbx + AP_dropindex]
    cmp rax, 128
    jae .Lapg_plan
    lea r15, [rbx + rax * 8 + AP_views]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lapg_next_view
    call ext_settings_view_release
    test rax, rax
    js .Lapg_retained
    mov qword ptr [r15], 0
.Lapg_next_view:
    inc qword ptr [rbx + AP_dropindex]
    jmp .Lapg_progress
.Lapg_plan:
    lea r15, [rbx + AP_plan]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lapg_pending
    call ext_settings_catalog_release
    jmp .Lapg_reference
.Lapg_pending:
    lea r15, [rbx + AP_pending]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lapg_oldmodel
    call ext_settings_snapshot_release
    jmp .Lapg_reference
.Lapg_oldmodel:
    lea r15, [rbx + AP_oldmodel]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lapg_oldsource
    call ext_settings_model_release
    jmp .Lapg_reference
.Lapg_oldsource:
    lea r15, [rbx + AP_retiredsource]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lapg_svc
    call ext_settings_snapshot_release
    jmp .Lapg_reference
.Lapg_svc:
    lea r15, [rbx + AP_svc]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lapg_self
    call ext_settings_service_release
.Lapg_reference:
    test rax, rax
    js .Lapg_retained
    mov qword ptr [r15], 0
.Lapg_progress:
    mov qword ptr [rbx + AP_retiredue], 0
    mov qword ptr [rbx + AP_retiredelay], 0
    jmp .Lapg_loop
.Lapg_self:
    # Capture linkage before a consumed free; never read the self prefix afterward.
    mov rax, [rbx + AP_next]
    mov [rsp + 8], rax
    mov rdi, rbx
    call ext_settings_memory_free
    cmp rcx, 1
    jne .Lapg_retained
    test r14, r14
    js 1f
    test rdx, rdx
    jns 1f
    mov r14, rdx
1:  mov rax, [rsp + 8]
    mov [rip + settings_adoption_retired_head], rax
    test rax, rax
    jnz 2f
    mov qword ptr [rip + settings_adoption_retired_tail], 0
2:  dec qword ptr [rip + settings_adoption_retired_count]
    jmp .Lapg_loop
.Lapg_retained:
    test rax, rax
    js 1f
    mov rax, -5
1:  test r14, r14
    js 2f
    mov r14, rax
2:  cmp qword ptr [rbx + AP_cleanup], 0
    jne 3f
    mov [rbx + AP_cleanup], rax
3:  mov rax, [rbx + AP_retiredelay]
    test rax, rax
    jnz 4f
    mov eax, 8
4:  add rax, rax
    cmp rax, 1000
    jbe 5f
    mov eax, 1000
5:  mov [rbx + AP_retiredelay], rax
    add rax, [rsp]
    jns 6f
    mov rax, 0x7fffffffffffffff
6:  mov [rbx + AP_retiredue], rax
.Lapg_done:
    mov rax, r13
    mov rdx, r14
    EPILOGUE
.Lapg_bad_leaf:
    mov rax, -22
    xor edx, edx
    ret
