# One bounded view/plan construction or producer-reference action per call.
.include "rhun.inc"
.include "app/extprepare.inc"
.include "app/extsettingsadoption.inc"
.text
# Internal, caller holds registered BUILDING SAP. No export or automatic retry here.
FN settings_adoption_build_step
    PROLOGUE ECSCP_SIZE
    mov rbx, rdi
    call settings_adoption_current
    test rax, rax
    js .Lapbs_done
    cmp qword ptr [rbx + AP_state], APS_BUILDING
    jne .Lapbs_again
    mov rax, [rbx + AP_phase]
    cmp rax, APP_NEXT
    je .Lapbs_next
    cmp rax, APP_VIEW
    je .Lapbs_view
    cmp rax, APP_PLAN
    je .Lapbs_plan
    cmp rax, APP_PLANSTEP
    je .Lapbs_planstep
    cmp rax, APP_DROPS
    je .Lapbs_drops
    mov rax, -71
    jmp .Lapbs_done
.Lapbs_next:
    mov r12, [rbx + AP_oldmodel]
    mov r13, [rbx + AP_index]
1:  cmp r13, 128
    jae .Lapbs_views_done
    mov rax, [r12 + r13 * 8 + ELM_slots]
    test rax, rax
    jnz .Lapbs_begin_view
    inc r13
    jmp 1b
.Lapbs_begin_view:
    mov [rbx + AP_index], r13
    mov rdi, [rax + EV_ep]
    mov rsi, [rbx + AP_pending]
    call ext_settings_view_begin
    test rax, rax
    jz .Lapbs_pointer_error
    mov [rbx + r13 * 8 + AP_views], rax
    mov qword ptr [rbx + AP_phase], APP_VIEW
    jmp .Lapbs_pending
.Lapbs_views_done:
    mov qword ptr [rbx + AP_index], 128
    mov qword ptr [rbx + AP_phase], APP_PLAN
    jmp .Lapbs_pending
.Lapbs_view:
    mov r13, [rbx + AP_index]
    mov r12, [rbx + r13 * 8 + AP_views]
    mov rdi, r12
    mov esi, 65536
    call ext_settings_view_step
    test rax, rax
    js .Lapbs_done
    cmp rax, 1
    jne .Lapbs_pending
    mov rax, [rbx + AP_count]
    cmp rax, 128
    jae .Lapbs_protocol
    shl rax, 5
    lea r14, [rbx + rax + AP_rows]
    mov [r14 + ECSR_view], r12
    mov [r14 + ECSR_slot], r13
    mov rax, [r12 + EV_ep]
    mov rdx, [rax + EP_ext + EXT_owner]
    mov [r14 + ECSR_owner], rdx
    mov rdx, [rax + EP_ext + EXT_name]
    mov [r14 + ECSR_name], rdx
    inc qword ptr [rbx + AP_count]
    inc qword ptr [rbx + AP_index]
    mov qword ptr [rbx + AP_phase], APP_NEXT
    jmp .Lapbs_pending
.Lapbs_plan:
    mov rax, [rbx + AP_pending]
    mov [rsp + ECSCP_source], rax
    lea rax, [rbx + AP_rows]
    mov [rsp + ECSCP_rows], rax
    mov rax, [rbx + AP_count]
    mov [rsp + ECSCP_count], rax
    mov rax, [rbx + AP_registry]
    mov [rsp + ECSCP_registry], rax
    mov rax, [rbx + AP_dirty]
    mov [rsp + ECSCP_dirty], rax
    mov rax, [rbx + AP_model]
    mov [rsp + ECSCP_model], rax
    mov rdi, rsp
    call ext_settings_refresh_prepare
    test rax, rax
    jz .Lapbs_pointer_error
    mov [rbx + AP_plan], rax
    mov qword ptr [rbx + AP_phase], APP_PLANSTEP
    jmp .Lapbs_pending
.Lapbs_planstep:
    mov rdi, [rbx + AP_plan]
    mov esi, 65536
    call ext_settings_catalog_step
    test rax, rax
    js .Lapbs_done
    cmp rax, 1
    jne .Lapbs_pending
    mov qword ptr [rbx + AP_phase], APP_DROPS
    jmp .Lapbs_pending
.Lapbs_drops:
    mov r13, [rbx + AP_dropindex]
1:  cmp r13, 128
    jae .Lapbs_ready
    mov rdi, [rbx + r13 * 8 + AP_views]
    test rdi, rdi
    jnz 2f
    inc r13
    jmp 1b
2:  mov [rbx + AP_dropindex], r13
    call ext_settings_view_release
    test rax, rax
    js .Lapbs_done
    mov qword ptr [rbx + r13 * 8 + AP_views], 0
    inc qword ptr [rbx + AP_dropindex]
    jmp .Lapbs_pending
.Lapbs_ready:
    mov qword ptr [rbx + AP_dropindex], 128
    mov qword ptr [rbx + AP_phase], APP_READY
    mov qword ptr [rbx + AP_state], APS_READY
    mov eax, 1
    EPILOGUE
.Lapbs_pointer_error:
    mov rax, rdx
    jmp .Lapbs_done
.Lapbs_protocol:
    mov rax, -71
.Lapbs_done:
    EPILOGUE
.Lapbs_pending:
    xor eax, eax
    EPILOGUE
.Lapbs_again:
    mov rax, -11
    EPILOGUE
