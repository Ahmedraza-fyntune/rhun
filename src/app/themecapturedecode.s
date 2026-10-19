# Untrusted result decoder. Only complete, budgeted validation makes a TCS observable.
.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.include "app/themecapturedecode.inc"
.text
# status in RAX -> bool. Exact signed bounded errno, including cleanup-only failure.
tcd_status:
    test rax, rax
    jg 1f
    cmp rax, -4095
    jl 1f
    mov eax, 1
    ret
1:  xor eax, eax
    ret
# Fixed control region only, never a variable payload scan.
tcd_zero:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 0
    jne 3f
    inc rcx
    jmp 1b
2:  mov eax, 1
    ret
3:  xor eax, eax
    ret

# Fixed header validation. Global failure is recorded as FAILED with both exact statuses.
tcd_header:
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + TCS_wire]
    test r13, r13
    jz .Ltcdh_bad
    mov r14, [rbx + TCS_length]
    cmp r14, TC_HEADER_SIZE
    jb .Ltcdh_bad
    cmp r14, TC_OUTPUT_CAP
    ja .Ltcdh_bad
    mov r15, [rbx + TCS_request]
    test r15, r15
    jz .Ltcdh_bad
    cmp qword ptr [r15 + TCQ_length], TC_HEADER_SIZE
    jb .Ltcdh_bad
    cmp qword ptr [r15 + TCQ_length], TC_INPUT_CAP
    ja .Ltcdh_bad
    mov r15, [r15 + TCQ_wire]
    test r15, r15
    jz .Ltcdh_bad
    mov rax, 0x0031534552544852
    cmp [r13], rax
    jne .Ltcdh_bad
    cmp dword ptr [r13 + 8], 1
    jne .Ltcdh_bad
    cmp dword ptr [r13 + 12], TC_HEADER_SIZE
    jne .Ltcdh_bad
    cmp [r13 + 16], r14
    jne .Ltcdh_bad
    mov eax, [r15 + 28]
    cmp [r13 + 28], eax
    jne .Ltcdh_bad
    cmp dword ptr [r13 + 100], T_COUNT
    jne .Ltcdh_bad
    lea rdi, [r13 + 32]
    lea rsi, [r15 + 32]
    mov edx, 64
    call memeq
    test eax, eax
    jz .Ltcdh_bad
    lea rdi, [r13 + 176]
    mov esi, 80
    call tcd_zero
    test eax, eax
    jz .Ltcdh_bad
    mov rax, [r13 + 160]
    call tcd_status
    test eax, eax
    jz .Ltcdh_bad
    mov rax, [r13 + 168]
    call tcd_status
    test eax, eax
    jz .Ltcdh_bad
    mov rax, [r13 + 160]
    or rax, [r13 + 168]
    jz .Ltcdh_success
    cmp r14, TC_HEADER_SIZE
    jne .Ltcdh_bad
    cmp dword ptr [r13 + 24], 0
    jne .Ltcdh_bad
    cmp dword ptr [r13 + 96], 0
    jne .Ltcdh_bad
    lea rdi, [r13 + 104]
    mov esi, 56
    call tcd_zero
    test eax, eax
    jz .Ltcdh_bad
    mov rax, [r13 + 160]
    mov [r12 + TCD_primary], rax
    mov rax, [r13 + 168]
    mov [r12 + TCD_cleanup], rax
    mov qword ptr [r12 + TCD_phase], TCD_FAILED
    xor eax, eax
    EPILOGUE
.Ltcdh_success:
    mov eax, [r13 + 24]
    cmp eax, TC_SOURCE_MAX
    ja .Ltcdh_bad
    cmp [r15 + 24], eax
    jne .Ltcdh_bad
    mov [rbx + TCS_count], rax
    mov eax, [r13 + 96]
    cmp eax, TC_NAME_CAP
    ja .Ltcdh_bad
    mov [rbx + TCS_name_length], rax
    add rax, TC_HEADER_SIZE
    cmp rax, r14
    ja .Ltcdh_bad
    mov eax, [r15 + 96]
    add rax, TC_HEADER_SIZE
    mov [r12 + TCD_request_offset], rax
    mov qword ptr [r12 + TCD_offset], TC_HEADER_SIZE
    mov qword ptr [r12 + TCD_phase], TCD_NAME
    mov eax, [r13 + 28]
    cmp eax, 3
    jne 1f
    mov eax, TC_SCOPE_FULL
1:  mov [rbx + TCS_scope], rax
    test rax, rax
    jnz .Ltcdh_omarchy
    cmp dword ptr [r13 + 96], 0
    jne .Ltcdh_bad
    lea rdi, [r13 + 104]
    mov esi, 56
    call tcd_zero
    test eax, eax
    jz .Ltcdh_bad
    xor eax, eax
    EPILOGUE
.Ltcdh_omarchy:
    mov rax, [r13 + 104]
    call tcd_status
    test eax, eax
    jz .Ltcdh_bad
    mov rax, [r13 + 112]
    call tcd_status
    test eax, eax
    jz .Ltcdh_bad
    mov rax, [r13 + 104]
    or rax, [r13 + 112]
    jz .Ltcdh_om_success
    cmp dword ptr [r13 + 96], 0
    jne .Ltcdh_bad
    lea rdi, [r13 + 120]
    mov esi, 40
    call tcd_zero
    test eax, eax
    jz .Ltcdh_bad
    cmp dword ptr [r15 + 104], 0
    je 2f
    mov qword ptr [r12 + TCD_require_changed], 1
2:  xor eax, eax
    EPILOGUE
.Ltcdh_om_success:
    cmp dword ptr [r13 + 120], 1
    ja .Ltcdh_bad
    mov eax, [r13 + 124]
    test eax, -16
    jnz .Ltcdh_bad
    mov [rbx + TCS_presence], rax
    test eax, 1
    jnz 3f
    cmp dword ptr [r13 + 96], 0
    jne .Ltcdh_bad
3:  cmp qword ptr [rbx + TCS_scope], TC_SCOPE_NAME
    jne 4f
    test eax, 14
    jnz .Ltcdh_bad
    cmp dword ptr [r13 + 120], 0
    jne .Ltcdh_bad
    jmp 6f
4:  test eax, 4
    jz 5f
    test eax, 8
    jz .Ltcdh_bad
    cmp dword ptr [r13 + 120], 1
    jne .Ltcdh_bad
5:  cmp dword ptr [r13 + 120], 1
    jne 6f
    test eax, 6
    jz .Ltcdh_bad
6:  lea rdi, [r13 + 128]
    mov esi, 32
    call tcd_zero
    test eax, eax
    jnz .Ltcdh_bad
    mov eax, [r15 + 104]
    test eax, eax
    jz 7f
    cmp rax, [rbx + TCS_scope]
    jne 7f
    lea rdi, [r13 + 128]
    lea rsi, [r15 + 128]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Ltcdh_bad
7:  xor eax, eax
    EPILOGUE
.Ltcdh_bad:
    mov rax, -22
    EPILOGUE

# step(TCS,TCD,budget1..65536)->1pending/0done/negativeprimary, chargedbytes, cleanup.
FN tc_result_decode_step
    test rdi, rdi
    jz .Ltcdd_bad_leaf
    test rsi, rsi
    jz .Ltcdd_bad_leaf
    test rdx, rdx
    jz .Ltcdd_bad_leaf
    cmp rdx, 65536
    ja .Ltcdd_bad_leaf
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + TCS_wire]
    mov r14, rdx
    mov [rsp], rdx
    mov r15d, 256
.Ltcdd_loop:
    mov rax, [r12 + TCD_phase]
    cmp rax, TCD_DONE
    je .Ltcdd_done
    cmp rax, TCD_FAILED
    je .Ltcdd_failed
    cmp rax, TCD_HEADER
    je .Ltcdd_header
    cmp rax, TCD_NAME
    je .Ltcdd_name
    cmp rax, TCD_ROW_HEADER
    je .Ltcdd_row_header
    cmp rax, TCD_PALETTE
    je .Ltcdd_palette
    cmp rax, TCD_RAW
    je .Ltcdd_raw
    jmp .Ltcdd_protocol
.Ltcdd_header:
    cmp r15, 256
    jb .Ltcdd_pending
    sub r15, 256
    mov rdi, rbx
    mov rsi, r12
    call tcd_header
    test rax, rax
    js .Ltcdd_error
    jmp .Ltcdd_loop
.Ltcdd_name:
    mov rcx, [r12 + TCD_offset]
    mov rax, [rbx + TCS_name_length]
    add rax, TC_HEADER_SIZE
    cmp rcx, rax
    jae 1f
    test r14, r14
    jz .Ltcdd_pending
    mov al, [r13 + rcx]
    dec r14
    inc qword ptr [r12 + TCD_offset]
    test al, al
    jz .Ltcdd_protocol
    jmp .Ltcdd_name
1:  mov qword ptr [r12 + TCD_phase], TCD_ROW_HEADER
    jmp .Ltcdd_loop
.Ltcdd_row_header:
    mov rax, [r12 + TCD_row]
    cmp rax, [rbx + TCS_count]
    jae .Ltcdd_finish
    cmp r15, TC_RESULT_ROW
    jb .Ltcdd_pending
    sub r15, TC_RESULT_ROW
    mov rax, [r12 + TCD_offset]
    lea rcx, [rax + TC_RESULT_ROW + TC_PALETTE_SIZE]
    cmp rcx, [rbx + TCS_length]
    ja .Ltcdd_protocol
    mov [r12 + TCD_row_start], rax
    lea rdi, [r13 + rax]
    mov [rsp + 8], rdi
    mov rax, [rbx + TCS_request]
    mov rsi, [r12 + TCD_request_offset]
    lea rdx, [rsi + TC_REQUEST_ROW]
    cmp rdx, [rax + TCQ_length]
    ja .Ltcdd_protocol
    mov rax, [rax + TCQ_wire]
    add rax, rsi
    mov edx, [rax]
    cmp [rdi], edx
    jne .Ltcdd_protocol
    mov edx, [rax + 4]
    lea rdx, [rsi + TC_REQUEST_ROW + rdx]
    mov rax, [rbx + TCS_request]
    cmp rdx, [rax + TCQ_length]
    ja .Ltcdd_protocol
    mov [r12 + TCD_request_offset], rdx
    cmp dword ptr [rdi + 4], 0
    jne .Ltcdd_protocol
    mov rax, [rdi + 8]
    call tcd_status
    test eax, eax
    jz .Ltcdd_protocol
    mov rdi, [rsp + 8]
    mov rax, [rdi + 16]
    call tcd_status
    test eax, eax
    jz .Ltcdd_protocol
    mov rdi, [rsp + 8]
    cmp qword ptr [r12 + TCD_require_changed], 0
    je 2f
    cmp qword ptr [rdi + 8], -1008
    jne .Ltcdd_protocol
2:  mov rax, [rdi + 8]
    or rax, [rdi + 16]
    jz .Ltcdd_success_row
    mov qword ptr [r12 + TCD_row_failed], 1
    add rdi, 24
    mov esi, 72
    call tcd_zero
    test eax, eax
    jz .Ltcdd_protocol
    mov qword ptr [r12 + TCD_raw_length], 0
    jmp .Ltcdd_row_ready
.Ltcdd_success_row:
    mov qword ptr [r12 + TCD_row_failed], 0
    mov rax, [rdi + 24]
    cmp rax, TC_THEME_CAP
    ja .Ltcdd_protocol
    mov [r12 + TCD_raw_length], rax
    add rax, [r12 + TCD_row_start]
    add rax, TC_RESULT_ROW + TC_PALETTE_SIZE
    cmp rax, [rbx + TCS_length]
    ja .Ltcdd_protocol
    cmp dword ptr [rdi + 64], T_COUNT
    jne .Ltcdd_protocol
    cmp dword ptr [rdi + 68], 1
    ja .Ltcdd_protocol
    mov rax, [rdi + 80]
    shr rax, T_COUNT - 64
    jnz .Ltcdd_protocol
    cmp qword ptr [rdi + 88], 0
    jne .Ltcdd_protocol
.Ltcdd_row_ready:
    add qword ptr [r12 + TCD_offset], TC_RESULT_ROW
    mov qword ptr [r12 + TCD_progress], 0
    mov qword ptr [r12 + TCD_phase], TCD_PALETTE
    jmp .Ltcdd_loop
.Ltcdd_palette:
    cmp qword ptr [r12 + TCD_progress], TC_PALETTE_SIZE
    jae 3f
    test r14, r14
    jz .Ltcdd_pending
    mov rax, [r12 + TCD_offset]
    mov al, [r13 + rax]
    dec r14
    inc qword ptr [r12 + TCD_offset]
    inc qword ptr [r12 + TCD_progress]
    cmp qword ptr [r12 + TCD_row_failed], 0
    je .Ltcdd_palette
    test al, al
    jnz .Ltcdd_protocol
    jmp .Ltcdd_palette
3:  cmp qword ptr [r12 + TCD_row_failed], 0
    jne .Ltcdd_row_complete
    lea rdi, [r12 + TCD_sha]
    call sha256_init
    mov qword ptr [r12 + TCD_progress], 0
    mov qword ptr [r12 + TCD_phase], TCD_RAW
    jmp .Ltcdd_loop
.Ltcdd_raw:
    mov rax, [r12 + TCD_raw_length]
    sub rax, [r12 + TCD_progress]
    jz .Ltcdd_hash_finish
    test r14, r14
    jz .Ltcdd_pending
    cmp rax, r14
    cmova rax, r14
    mov [rsp + 8], rax
    sub r14, rax
    lea rdi, [r12 + TCD_sha]
    mov rsi, [r12 + TCD_offset]
    add rsi, r13
    mov rdx, rax
    call sha256_update
    test eax, eax
    jz .Ltcdd_hash_error
    mov rax, [rsp + 8]
    add [r12 + TCD_offset], rax
    add [r12 + TCD_progress], rax
    jmp .Ltcdd_raw
.Ltcdd_hash_finish:
    lea rdi, [r12 + TCD_sha]
    lea rsi, [r12 + TCD_digest]
    call sha256_final
    test eax, eax
    jz .Ltcdd_hash_error
    lea rdi, [r12 + TCD_digest]
    mov rsi, [r12 + TCD_row_start]
    lea rsi, [r13 + rsi + 32]
    mov edx, 32
    call memeq
    test eax, eax
    jz .Ltcdd_protocol
.Ltcdd_row_complete:
    mov rcx, [r12 + TCD_row]
    shl rcx, 4
    mov rax, [r12 + TCD_row_start]
    mov edx, [r13 + rax]
    mov [rbx + TCS_rows + rcx], rdx
    mov [rbx + TCS_rows + rcx + 8], rax
    inc qword ptr [r12 + TCD_row]
    mov qword ptr [r12 + TCD_phase], TCD_ROW_HEADER
    jmp .Ltcdd_loop
.Ltcdd_finish:
    mov rax, [r12 + TCD_offset]
    cmp rax, [rbx + TCS_length]
    jne .Ltcdd_protocol
    mov rax, [rbx + TCS_request]
    mov rdx, [r12 + TCD_request_offset]
    cmp rdx, [rax + TCQ_length]
    jne .Ltcdd_protocol
    mov qword ptr [rbx + TCS_validated], 1
    mov qword ptr [rbx + TCS_state], TCS_LIVE
    mov qword ptr [r12 + TCD_phase], TCD_DONE
.Ltcdd_done:
    xor eax, eax
    xor ecx, ecx
    jmp .Ltcdd_return
.Ltcdd_pending:
    mov eax, 1
    xor ecx, ecx
    jmp .Ltcdd_return
.Ltcdd_protocol:
    mov rax, -22
    jmp .Ltcdd_error
.Ltcdd_hash_error:
    mov rax, -5
.Ltcdd_error:
    mov [r12 + TCD_primary], rax
    mov qword ptr [r12 + TCD_phase], TCD_FAILED
.Ltcdd_failed:
    mov rax, [r12 + TCD_primary]
    mov rcx, [r12 + TCD_cleanup]
.Ltcdd_return:
    mov rdx, [rsp]
    sub rdx, r14
    EPILOGUE
.Ltcdd_bad_leaf:
    mov rax, -22
    xor edx, edx
    xor ecx, ecx
    ret
