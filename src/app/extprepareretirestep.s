# Exactly one ownership/free/phase unit. Synchronous helpers explicitly select mode1.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
# close(record,slotPtr,index)->0 consumed/-error blocked;RDXdisposition,RCXdiagnostic.
FN prep_retire_close_slot
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [r12]
    test rdi, rdi
    js .Lrcl_empty
    mov rcx, r13
    add ecx, RDF_UNKNOWN_BASE
    bt qword ptr [rbx + RD_state], rcx
    jc .Lrcl_unknown
    mov rcx, r13
    add ecx, RDF_KNOWN_BASE
    bt qword ptr [rbx + RD_state], rcx
    jc .Lrcl_known
    mov [rbx + RD_native], rdi
    call ext_root_close
    mov r14, rax
    mov r15, rdx
    cmp rdx, 1
    je .Lrcl_consumed
    test r14, r14
    js 1f
    mov r14, -5
1:  mov rcx, r13
    add ecx, RDF_KNOWN_BASE
    cmp r15, 2
    jne 2f
    mov rcx, r13
    add ecx, RDF_UNKNOWN_BASE
2:  bts qword ptr [rbx + RD_state], rcx
    mov rdi, rbx
    mov rsi, r14
    call ext_prepare_retire_note_error
    mov rax, r14
    mov rdx, r15
    mov rcx, r14
    EPILOGUE
.Lrcl_consumed:
    mov qword ptr [r12], -1
    mov qword ptr [rbx + RD_native], 0
    mov rdi, rbx
    mov rsi, r14
    call ext_prepare_retire_note_error
    xor eax, eax
    mov edx, 1
    mov rcx, r14
    EPILOGUE
.Lrcl_unknown:
    mov edx, 2
    jmp .Lrcl_saved_error
.Lrcl_known:
    xor edx, edx
.Lrcl_saved_error:
    mov rax, [rbx + RD_diagnostic]
    test rax, rax
    js 3f
    mov rax, -5
3:  mov rcx, rax
    EPILOGUE
.Lrcl_empty:
    xor eax, eax
    mov edx, 1
    xor ecx, ecx
    EPILOGUE

# one(record,syncMode)->0 recordconsumed/1 pending/-errno blocked.
# RDX disposition for blocked; RCX cleanup diagnostic even after consumed self.
FN prep_retire_one
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rdi + RD_object]
    cmp qword ptr [rdi + RD_kind], RD_EO
    je .Lrone_eo
    cmp qword ptr [rdi + RD_kind], RD_LEDGER
    je .Lrone_ledger
    cmp qword ptr [rdi + RD_kind], RD_EP
    je .Lrone_ep
    cmp qword ptr [rdi + RD_kind], RD_CUSTOM_FIRST
    jb .Lrone_bad
    cmp qword ptr [rdi + RD_kind], RD_CUSTOM_LAST
    ja .Lrone_bad
    mov rdi, rbx
    call prep_retire_dispatch_custom
    xor ecx, ecx
    EPILOGUE
.Lrone_ep:
    cmp qword ptr [rbx + RD_phase], 0
    je .Lrone_grammars
    cmp qword ptr [rbx + RD_phase], 1
    je .Lrone_values
    cmp qword ptr [rbx + RD_phase], 2
    je .Lrone_dirs
    cmp qword ptr [rbx + RD_phase], 3
    je .Lrone_ledger
    jmp .Lrone_bad
.Lrone_grammars:
    mov r14, [rbx + RD_index]
    cmp r14, [r13 + EP_grammars + VEC_len]
    jae .Lrone_next_phase
    mov r15, [r13 + EP_grammars + VEC_ptr]
    lea r15, [r15 + r14*8]
    mov rdi, [r15]
    test rdi, rdi
    jz .Lrone_grammar_done
    test r12, r12
    jz 1f
    call grammar_prepare_release
    jmp 2f
1:  call grammar_prepare_release_deferred
2:  test rdx, rdx
    jz .Lrone_bad
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, rax
    call ext_prepare_retire_note_error
    mov qword ptr [r15], 0
    inc qword ptr [rbx + RD_index]
    mov rcx, [rsp]
    mov eax, 1
    xor edx, edx
    EPILOGUE
.Lrone_grammar_done:
    inc qword ptr [rbx + RD_index]
    jmp .Lrone_pending
.Lrone_values:
    mov r14, [rbx + RD_index]
    cmp r14, [r13 + EP_ext + EXT_sdefs + VEC_len]
    jae .Lrone_next_phase
    imul r15, r14, SD_SIZE
    add r15, [r13 + EP_ext + EXT_sdefs + VEC_ptr]
    mov rdi, [r15 + SD_value]
    call prep_pointer_charge
    mov r14, rax
    mov rdi, [r15 + SD_value]
    call prep_cleanup_free
    test rax, rax
    js .Lrone_known_error
    mov qword ptr [r15 + SD_value], 0
    mov rax, [r13 + PO_eo]
    sub [rax + EO_used], r14
    sub [r13 + EP_valuecharge], r14
    sub [rip + prep_total_charge], r14
    inc qword ptr [rbx + RD_index]
    jmp .Lrone_pending
.Lrone_dirs:
    mov r14, [rbx + RD_index]
    cmp r14, 3
    jae .Lrone_next_phase
    lea rsi, [r13 + r14*8 + EP_root]
    mov rdi, rbx
    mov rdx, r14
    call prep_retire_close_slot
    test rax, rax
    js .Lrone_return
    inc qword ptr [rbx + RD_index]
    mov eax, 1
    EPILOGUE
.Lrone_next_phase:
    inc qword ptr [rbx + RD_phase]
    mov qword ptr [rbx + RD_index], 0
    jmp .Lrone_pending

.Lrone_ledger:
    mov r15, [r13 + PO_eo]
    cmp qword ptr [r15 + EO_refs], 0
    je .Lrone_bad
    mov r14, [r13 + PO_allocs]
    test r14, r14
    jz .Lrone_bad
    mov rax, [r14 + AO_next]
    mov [rsp], rax
    mov rax, [r14 + AO_charge]
    mov [rsp + 8], rax
    mov qword ptr [rsp + 16], 0
    mov rdi, r14
    lea rax, [r13 - AO_SIZE]
    cmp r14, rax
    je 5f
    cmp qword ptr [rsp], 0
    je .Lrone_bad
    jmp 1f
5:  cmp qword ptr [rsp], 0
    jne .Lrone_bad
    mov qword ptr [rsp + 16], 1
    sub rdi, RD_SIZE
1:  call prep_cleanup_free
    test rax, rax
    js .Lrone_known_error
    mov rax, [rsp + 8]
    sub [r15 + EO_used], rax
    sub [rip + prep_total_charge], rax
    cmp qword ptr [rsp + 16], 0
    jne .Lrone_object_gone
    mov rax, [rsp]
    mov [r13 + PO_allocs], rax
    jmp .Lrone_pending
.Lrone_object_gone:
    # No object/prefix reads after this point.
    mov rdi, r15
    test r12, r12
    jz 2f
    call ext_prepare_owner_release
    jmp 3f
2:  call ext_prepare_owner_release_deferred
3:  mov rcx, rax
    test rax, rax
    jns 4f
    cmp qword ptr [rip + prep_retire_first_diagnostic], 0
    jne 4f
    mov [rip + prep_retire_first_diagnostic], rax
4:  xor eax, eax
    mov edx, 1
    EPILOGUE

.Lrone_eo:
    cmp qword ptr [rbx + RD_phase], 0
    jne .Lrone_eo_free
    mov rdi, rbx
    lea rsi, [r13 + EO_lease]
    xor edx, edx
    call prep_retire_close_slot
    test rax, rax
    js .Lrone_return
    mov qword ptr [rbx + RD_phase], 1
    mov eax, 1
    EPILOGUE
.Lrone_eo_free:
    cmp qword ptr [rbx + RD_phase], 1
    jne .Lrone_bad
    mov rdi, rbx
    call prep_pointer_charge
    mov r14, rax
    cmp [r13 + EO_used], rax
    jne .Lrone_bad
    mov rdi, rbx
    call prep_cleanup_free
    test rax, rax
    js .Lrone_known_error
    sub [rip + prep_total_charge], r14
    xor eax, eax
    mov edx, 1
    xor ecx, ecx
    EPILOGUE

.Lrone_known_error:
    mov r14, rax
    mov rdi, rbx
    mov rsi, rax
    call ext_prepare_retire_note_error
    mov rax, r14
    xor edx, edx
    mov rcx, r14
.Lrone_return:
    EPILOGUE
.Lrone_pending:
    mov eax, 1
    xor edx, edx
    xor ecx, ecx
    EPILOGUE
.Lrone_bad:
    mov rax, -EV_BAD_PREPARE
    mov edx, 2
    mov rcx, rax
    EPILOGUE
