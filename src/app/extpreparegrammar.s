# A prepared GR owns all parser memory and retains its package lifetime owner.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.text
FN grammar_parse_prepare
    xor ecx, ecx
    jmp .Lgpp_begin
FN grammar_parse_prepare_legacy
    mov ecx, 1
.Lgpp_begin:
    PROLOGUE 16
    mov [rsp], rcx
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, 2 * 1024 * 1024
    ja .Lgpp_resource
    test rbx, rbx
    jz .Lgpp_bad
    mov rdi, rbx
    mov rsi, r12
    call prep_ini_text_valid
    test eax, eax
    jz .Lgpp_bad
    mov rdi, r13
    mov esi, GP_SIZE
    call prep_object_create
    test rax, rax
    jz .Lgpp_alloc_error
    mov r14, rax
    mov rcx, [rsp]
    mov [r14 + GP_legacy], rcx
    lea rdi, [rax + GP_gr]
    mov rsi, rbx
    mov rdx, r12
    mov rcx, r14
    call grammar_fill_context
    cmp qword ptr [r14 + PO_error], 0
    jne .Lgpp_discard
    cmp qword ptr [r14 + GP_legacy], 1
    je .Lgpp_ready
    mov rsi, [r14 + GP_name_len]
    test rsi, rsi
    jz .Lgpp_name
    cmp rsi, 128
    ja .Lgpp_name
    mov rdi, [r14 + GP_gr + GR_name]
    call ext_validate_text
    test eax, eax
    jz .Lgpp_name
.Lgpp_ready:
    mov qword ptr [r14 + PO_ready], 1
    mov rax, r14
    xor edx, edx
    xor ecx, ecx
.Lgpp_done:
    EPILOGUE
.Lgpp_name:
    mov qword ptr [r14 + PO_error], -EV_BAD_GRAMMAR
.Lgpp_discard:
    mov r15, [r14 + PO_error]
    mov rdi, r14
    call prep_owned_dispose
    mov rcx, rax
    mov rdx, r15
    xor eax, eax
    EPILOGUE
.Lgpp_alloc_error:
    xor ecx, ecx
    jmp .Lgpp_done
.Lgpp_resource:
    mov rdx, -EV_RESOURCE
    xor ecx, ecx
    xor eax, eax
    EPILOGUE
.Lgpp_bad:
    mov rdx, -EV_BAD_GRAMMAR
    xor ecx, ecx
    xor eax, eax
    EPILOGUE

FN grammar_prepare_retain
    jmp prep_object_retain

FN grammar_prepare_release
    mov esi, RD_LEDGER
    jmp prep_retire_po_release_sync

FN grammar_prepare_gr
    xor eax, eax
    cmp qword ptr [rdi + PO_ready], 1
    jne 1f
    lea rax, [rdi + GP_gr]
1:  ret
