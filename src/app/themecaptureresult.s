# Immutable owned result bytes. Existing borrowed bytes stay live through consumed release.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.bss
.globl g_theme_capture_results
g_theme_capture_results: .zero 8
.text
# Internal constructor. Caller transfers request, wire and capacity reservation explicitly.
FN tc_result_alloc
    PROLOGUE
    mov edi, TCS_SIZE
    call tc_alloc_try
    test rax, rax
    jz 1f
    mov qword ptr [rax + TCS_refs], 1
1:  EPILOGUE
FN theme_capture_result_retain
    test rdi, rdi
    jz .Ltcsr_invalid
    cmp qword ptr [rdi + TCS_state], TCS_LIVE
    jne .Ltcsr_busy
    cmp qword ptr [rdi + TCS_validated], 1
    jne .Ltcsr_busy
    mov rax, [rdi + TCS_refs]
    test rax, rax
    jz .Ltcsr_invalid
    cmp rax, -1
    je .Ltcsr_overflow
    inc qword ptr [rdi + TCS_refs]
    mov rax, rdi
    xor edx, edx
    ret
.Ltcsr_overflow:
    xor eax, eax
    mov rdx, -75
    ret
.Ltcsr_busy:
    xor eax, eax
    mov rdx, -16
    ret
.Ltcsr_invalid:
    xor eax, eax
    mov rdx, -22
    ret

# Last ref retires request first, then wire plus statically Small self in one final call.
FN theme_capture_result_release
    test rdi, rdi
    jz .Ltcsf_empty
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + TCS_cleanup]
    cmp qword ptr [rbx + TCS_refs], 0
    je .Ltcsf_invalid
    cmp qword ptr [rbx + TCS_refs], 1
    je 1f
    dec qword ptr [rbx + TCS_refs]
    xor eax, eax
    mov edx, 1
    EPILOGUE
1:  mov qword ptr [rbx + TCS_state], TCS_RETIRING
    mov r12, [rbx + TCS_cleanup]
    mov rdi, [rbx + TCS_request]
    test rdi, rdi
    jz .Ltcsf_wire
    call tc_request_dispose
    test rax, rax
    jns 2f
    test r12, r12
    jnz 2f
    mov r12, rax
    mov [rbx + TCS_cleanup], rax
2:  test rdx, rdx
    jz .Ltcsf_retained
    mov qword ptr [rbx + TCS_request], 0
    mov qword ptr [rbx + TCS_release_cursor], 1
    jmp .Ltcsf_retained
.Ltcsf_wire:
    # Validate every fallible self/counter/charge precondition before consuming borrowed wire.
    mov rdi, rbx
    call mem_capacity
    cmp rax, TCS_SMALL_CHARGE - 16
    jne .Ltcsf_invalid
    cmp qword ptr [rbx + TCS_reservation], 1
    ja .Ltcsf_invalid
    cmp qword ptr [rbx + TCS_reservation], 0
    je 3f
    cmp qword ptr [rip + g_theme_capture_results], 0
    je .Ltcsf_invalid
3:  mov r13d, TCS_SMALL_CHARGE
    mov rdi, [rbx + TCS_wire]
    test rdi, rdi
    jz 4f
    call mem_capacity
    add rax, 16
    jc .Ltcsf_invalid
    add r13, rax
    jc .Ltcsf_invalid
4:  cmp [rip + g_theme_capture_charge], r13
    jb .Ltcsf_invalid
    mov rdi, [rbx + TCS_wire]
    call tc_free
    test rax, rax
    jns 5f
    test r12, r12
    jnz 5f
    mov r12, rax
    mov [rbx + TCS_cleanup], rax
5:  test rdx, rdx
    jz .Ltcsf_retained
    # No fallible operation after this point: Small self path has no native unmap.
.if TCS_SIZE + 16 > TCS_SMALL_CHARGE
.error "TCS final self consumption must fit its statically proven Small class"
.endif
    cmp qword ptr [rbx + TCS_reservation], 0
    je 6f
    dec qword ptr [rip + g_theme_capture_results]
6:  mov rdi, rbx
    call mem_free
    sub qword ptr [rip + g_theme_capture_charge], TCS_SMALL_CHARGE
    mov rax, r12
    mov edx, 1
    EPILOGUE
.Ltcsf_invalid:
    test r12, r12
    jnz .Ltcsf_retained
    mov r12, -22
    mov [rbx + TCS_cleanup], r12
.Ltcsf_retained:
    mov rax, r12
    xor edx, edx
    EPILOGUE
.Ltcsf_empty:
    xor eax, eax
    mov edx, 1
    ret

# A found failed row still returns0 with explicit source/cleanup status and no data pointers.
FN theme_capture_result_row
    test rdi, rdi
    jz .Ltcsv_bad
    test rdx, rdx
    jz .Ltcsv_bad
    cmp qword ptr [rdi + TCS_state], TCS_LIVE
    jne .Ltcsv_busy
    cmp qword ptr [rdi + TCS_validated], 1
    jne .Ltcsv_busy
    cmp qword ptr [rdi + TCS_refs], 0
    je .Ltcsv_bad
    cmp qword ptr [rdi + TCS_count], TC_SOURCE_MAX
    ja .Ltcsv_bad
    xor ecx, ecx
1:  cmp rcx, [rdi + TCS_count]
    jae .Ltcsv_missing
    mov rax, rcx
    shl rax, 4
    cmp [rdi + TCS_rows + rax], rsi
    je 2f
    inc rcx
    jmp 1b
2:  PROLOGUE TCV_SIZE
    mov r12, rdx
    mov rax, [rdi + TCS_rows + rax + 8]
    add rax, [rdi + TCS_wire]
    mov rbx, rax
    mov rdi, rsp
    xor esi, esi
    mov edx, TCV_SIZE
    call memset
    mov rax, [rbx + 8]
    mov [rsp + TCV_primary], rax
    mov rdx, [rbx + 16]
    mov [rsp + TCV_cleanup], rdx
    or rax, rdx
    jnz 3f
    lea rax, [rbx + TC_RESULT_ROW + TC_PALETTE_SIZE]
    mov [rsp + TCV_bytes], rax
    mov rax, [rbx + 24]
    mov [rsp + TCV_length], rax
    lea rax, [rbx + TC_RESULT_ROW]
    mov [rsp + TCV_palette], rax
    lea rax, [rbx + 72]
    mov [rsp + TCV_defined], rax
    mov eax, [rbx + 68]
    mov [rsp + TCV_dark], rax
    lea rax, [rbx + 32]
    mov [rsp + TCV_digest], rax
3:  mov rdi, r12
    mov rsi, rsp
    mov edx, TCV_SIZE
    call memcpy
    xor eax, eax
    EPILOGUE
.Ltcsv_bad:
    mov rax, -22
    ret
.Ltcsv_busy:
    mov rax, -16
    ret
.Ltcsv_missing:
    mov rax, -2
    ret
FN theme_capture_result_omarchy
    test rdi, rdi
    jz .Ltcsv_bad
    test rsi, rsi
    jz .Ltcsv_bad
    cmp qword ptr [rdi + TCS_state], TCS_LIVE
    jne .Ltcsv_busy
    cmp qword ptr [rdi + TCS_validated], 1
    jne .Ltcsv_busy
    cmp qword ptr [rdi + TCS_refs], 0
    je .Ltcsv_bad
    cmp qword ptr [rdi + TCS_scope], 0
    je .Ltcsv_missing
    PROLOGUE TCO_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + TCS_wire]
    mov rdi, rsp
    xor esi, esi
    mov edx, TCO_SIZE
    call memset
    mov rax, [r13 + 104]
    mov [rsp + TCO_primary], rax
    mov rdx, [r13 + 112]
    mov [rsp + TCO_cleanup], rdx
    mov rcx, [rbx + TCS_scope]
    mov [rsp + TCO_scope], rcx
    or rax, rdx
    jnz 4f
    mov rax, [rbx + TCS_name_length]
    mov [rsp + TCO_length], rax
    mov rax, [rbx + TCS_presence]
    mov [rsp + TCO_presence], rax
    test al, 1
    jz 5f
    lea rax, [r13 + TC_HEADER_SIZE]
    mov [rsp + TCO_name], rax
5:  mov eax, [r13 + 120]
    mov [rsp + TCO_light], rax
    lea rax, [r13 + 128]
    mov [rsp + TCO_proof], rax
4:  mov rdi, r12
    mov rsi, rsp
    mov edx, TCO_SIZE
    call memcpy
    xor eax, eax
    EPILOGUE
