.include "rhun.inc"
.include "app/themecapture.inc"
.include "app/themecaptureresult.inc"
.section .rodata
tcsrt_raw: .byte 114,97,119,0
.ifdef WINDOWS
tcsrt_path: .asciz "C:/unrequested.theme"
.else
tcsrt_path: .asciz "/unrequested.theme"
.endif
.bss
.globl tcsrt_wire_target
tcsrt_wire_target: .zero 8
.text
tcsrt_fail:
    mov edi, 73
    call sys_exit
FN main
    PROLOGUE 288
    mov r15, [rip + g_mem_live]
    mov rdi, rsp
    xor esi, esi
    mov edx, 288
    call memset
    mov qword ptr [rsp + TCFG_job], 1
    mov qword ptr [rsp + TCFG_context], 2
    mov qword ptr [rsp + TCFG_nonce], 1
    mov rdi, rsp
    xor esi, esi
    call theme_capture_request_begin
    test rax, rax
    jz tcsrt_fail
    mov r14, rax
    mov rdi, r14
    mov esi, 17
    lea rdx, [rip + tcsrt_path]
    call theme_capture_request_add
    test rax, rax
    jnz tcsrt_fail
    mov rdi, r14
    call theme_capture_request_seal
    test rax, rax
    jnz tcsrt_fail
    call tc_result_alloc
    test rax, rax
    jz tcsrt_fail
    mov r12, rax
    mov [r12 + TCS_request], r14
    mov qword ptr [r14 + TCQ_state], TCQ_OWNED
    mov qword ptr [r12 + TCS_reservation], 1
    mov qword ptr [rip + g_theme_capture_results], 1
    mov edi, TC_OUTPUT_CAP
    call tc_alloc_try
    test rax, rax
    jz tcsrt_fail
    mov r13, rax
    mov [r12 + TCS_wire], rax
    mov [rip + tcsrt_wire_target], rax
    mov qword ptr [r12 + TCS_length], 660
    mov qword ptr [r12 + TCS_count], 1
    mov qword ptr [r12 + TCS_scope], 1
    mov qword ptr [r12 + TCS_presence], 1
    mov qword ptr [r12 + TCS_rows], 17
    mov qword ptr [r12 + TCS_rows + 8], 256
    mov dword ptr [r13 + 256], 17
    mov qword ptr [r13 + 256 + 24], 4
    mov dword ptr [r13 + 256 + 64], T_COUNT
    mov dword ptr [r13 + 256 + 68], 1
    lea rdi, [r13 + 656]
    lea rsi, [rip + tcsrt_raw]
    mov edx, 4
    call memcpy
    lea rdi, [r13 + 128]
    mov esi, 85
    mov edx, 32
    call memset
    mov qword ptr [r12 + TCS_state], TCS_LIVE
    mov qword ptr [r12 + TCS_validated], 1
    mov qword ptr [r12 + TCS_refs], -1
    mov rdi, r12
    call theme_capture_result_retain
    test rax, rax
    jnz tcsrt_fail
    cmp rdx, -75
    jne tcsrt_fail
    mov qword ptr [r12 + TCS_refs], 1
    mov rdi, r12
    call theme_capture_result_retain
    cmp rax, r12
    jne tcsrt_fail
    test rdx, rdx
    jnz tcsrt_fail
    mov rdi, r12
    call theme_capture_result_release
    test rax, rax
    jnz tcsrt_fail
    cmp rdx, 1
    jne tcsrt_fail
    cmp qword ptr [r12 + TCS_refs], 1
    jne tcsrt_fail
    mov rdi, r12
    mov esi, 17
    lea rdx, [rsp + 80]
    call theme_capture_result_row
    test rax, rax
    jnz tcsrt_fail
    lea rax, [r13 + 656]
    cmp [rsp + 80 + TCV_bytes], rax
    jne tcsrt_fail
    cmp qword ptr [rsp + 80 + TCV_length], 4
    jne tcsrt_fail
    lea rax, [r13 + 352]
    cmp [rsp + 80 + TCV_palette], rax
    jne tcsrt_fail
    lea rax, [r13 + 328]
    cmp [rsp + 80 + TCV_defined], rax
    jne tcsrt_fail
    cmp qword ptr [rsp + 80 + TCV_dark], 1
    jne tcsrt_fail
    lea rax, [r13 + 288]
    cmp [rsp + 80 + TCV_digest], rax
    jne tcsrt_fail
    mov rdi, r12
    lea rsi, [rsp + 144]
    call theme_capture_result_omarchy
    test rax, rax
    jnz tcsrt_fail
    lea rax, [r13 + 256]
    cmp [rsp + 144 + TCO_name], rax
    jne tcsrt_fail
    cmp qword ptr [rsp + 144 + TCO_length], 0
    jne tcsrt_fail
    lea rax, [r13 + 128]
    cmp [rsp + 144 + TCO_proof], rax
    jne tcsrt_fail
    cmp qword ptr [rsp + 144 + TCO_presence], 1
    jne tcsrt_fail
    cmp qword ptr [rsp + 144 + TCO_scope], 1
    jne tcsrt_fail
    lea rdi, [rsp + 208]
    mov esi, 90
    mov edx, TCV_SIZE
    call memset
    mov rdi, r12
    mov esi, 18
    lea rdx, [rsp + 208]
    call theme_capture_result_row
    cmp rax, -2
    jne tcsrt_fail
    xor ecx, ecx
1:  cmp byte ptr [rsp + 208 + rcx], 90
    jne tcsrt_fail
    inc ecx
    cmp ecx, TCV_SIZE
    jb 1b
    # Request retirement is separate; old result borrows remain live while consumed0.
    mov rdi, r12
    call theme_capture_result_release
    test rax, rax
    jnz tcsrt_fail
    test rdx, rdx
    jnz tcsrt_fail
    cmp qword ptr [r12 + TCS_request], 0
    jne tcsrt_fail
    mov rdi, [rsp + 80 + TCV_bytes]
    lea rsi, [rip + tcsrt_raw]
    mov edx, 4
    call memeq
    test eax, eax
    jz tcsrt_fail
    mov rdi, r12
    mov esi, 17
    lea rdx, [rsp + 208]
    call theme_capture_result_row
    cmp rax, -16
    jne tcsrt_fail
    mov rdi, r12
    call theme_capture_result_release
    test rax, rax
    jnz tcsrt_fail
    cmp rdx, 1
    jne tcsrt_fail
    cmp qword ptr [rip + g_theme_capture_results], 0
    jne tcsrt_fail
    cmp qword ptr [rip + g_theme_capture_charge], 0
    jne tcsrt_fail
    cmp r15, [rip + g_mem_live]
    jne tcsrt_fail
    xor eax, eax
    EPILOGUE
