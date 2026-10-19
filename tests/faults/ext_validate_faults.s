.include "app/extprepare.inc"
# Test-link interposition only. Product sources and objects are never modified.
.bss
.p2align 3
evf_loaded: .quad 0
evf_read_n: .quad 0
evf_alloc_n: .quad 0
evf_zero: .quad 0
evf_scan_fail: .quad 0
evf_reads: .quad 0
evf_allocs: .quad 0
evf_stat_n: .quad 0
evf_close_n: .quad 0
evf_stats: .quad 0
evf_closes: .quad 0
evf_image_mode: .quad 0
evf_partial: .quad 0
epf_hide_plan: .quad 0
.text
evf_number:
    PROLOGUE
    call getenv
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rax
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call parse_u64
9:  EPILOGUE
evf_init:
    cmp qword ptr [rip + evf_loaded], 0
    jne 9f
    PROLOGUE
    mov qword ptr [rip + evf_loaded], 1
    lea rdi, [rip + evf_read_key]
    call evf_number
    mov [rip + evf_read_n], rax
    lea rdi, [rip + evf_alloc_key]
    call evf_number
    mov [rip + evf_alloc_n], rax
    lea rdi, [rip + evf_zero_key]
    call evf_number
    mov [rip + evf_zero], rax
    lea rdi, [rip + evf_scan_key]
    call evf_number
    mov [rip + evf_scan_fail], rax
    lea rdi, [rip + evf_stat_key]
    call evf_number
    mov [rip + evf_stat_n], rax
    lea rdi, [rip + evf_close_key]
    call evf_number
    mov [rip + evf_close_n], rax
    lea rdi, [rip + evf_image_key]
    call evf_number
    mov [rip + evf_image_mode], rax
    lea rdi, [rip + evf_partial_key]
    call evf_number
    mov [rip + evf_partial], rax
    lea rdi, [rip + epf_hide_key]
    call evf_number
    mov [rip + epf_hide_plan], rax
    EPILOGUE
9:  ret
FN mem_alloc_try
    PROLOGUE 16
    mov [rsp], rdi
    call evf_init
    inc qword ptr [rip + evf_allocs]
    mov rax, [rip + evf_alloc_n]
    cmp rax, [rip + evf_allocs]
    je 8f
    mov rdi, [rsp]
    call evf_mem_alloc_try_real
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
FN ext_root_read
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    call evf_init
    inc qword ptr [rip + evf_reads]
    mov rax, [rip + evf_read_n]
    cmp rax, [rip + evf_reads]
    je 8f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    cmp qword ptr [rip + evf_partial], 0
    je 7f
    cmp rdx, 256
    jbe 7f
    mov edx, 256
7:  call evf_ext_root_read_real
    EPILOGUE
8:  mov rax, -5
    cmp qword ptr [rip + evf_zero], 0
    je 9f
    xor eax, eax
9:  EPILOGUE
.ifdef WINDOWS
FN win_dir_scan_handle_try
.else
FN dir_scan_fd_try
.endif
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    call evf_init
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    call evf_scan_real
    test rax, rax
    jnz 9f
    cmp qword ptr [rip + evf_scan_fail], 0
    je 9f
    mov rax, -5
9:  EPILOGUE
.section .rodata
evf_read_key: .asciz "RHUN_EV_READ_N"
evf_alloc_key: .asciz "RHUN_EV_ALLOC_N"
evf_zero_key: .asciz "RHUN_EV_ZERO"
evf_scan_key: .asciz "RHUN_EV_SCAN_FAIL"

.text
.ifdef WINDOWS
FN win_ext_root_stat
.else
FN ext_root_stat
.endif
    PROLOGUE 16
    mov [rsp], rdi
    mov [rsp + 8], rsi
    call evf_init
    inc qword ptr [rip + evf_stats]
    mov rax, [rip + evf_stat_n]
    cmp rax, [rip + evf_stats]
    je 8f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call evf_stat_real
    EPILOGUE
8:  mov rax, -2
    EPILOGUE
.ifdef WINDOWS
FN win_ext_root_close
.else
FN ext_root_close
.endif
    PROLOGUE 16
    mov [rsp], rdi
    call evf_init
    inc qword ptr [rip + evf_closes]
    mov rdi, [rsp]
    call evf_close_real
    mov [rsp + 8], rdx
    test rax, rax
    jnz 9f
    mov rdx, [rip + evf_close_n]
    cmp rdx, [rip + evf_closes]
    jne 9f
    mov rax, -5
9:  mov rdx, [rsp + 8]
    EPILOGUE
.section .rodata
evf_stat_key: .asciz "RHUN_EV_STAT_N"
evf_close_key: .asciz "RHUN_EV_CLOSE_N"

.text
FN prep_owned_exec_stat
    PROLOGUE 16
    mov [rsp], rdi
    mov [rsp + 8], rsi
    call evf_init
    inc qword ptr [rip + evf_stats]
    mov rax, [rip + evf_stat_n]
    cmp rax, [rip + evf_stats]
    je 8f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call evf_owned_stat_real
    test rax, rax
    jnz 9f
    cmp qword ptr [rip + evf_image_mode], 3
    jne 9f
    mov rcx, [rip + g_ext_image_capture]
    test rcx, rcx
    jz 9f
    mov rdx, [rsp]
    cmp [rcx + EP_capture_handle], rdx
    jne 9f
    mov rdx, [rsp + 8]
    add qword ptr [rdx + ER_size], 56
9:  EPILOGUE
8:  mov rax, -2
    EPILOGUE

FN ext_root_read_once
    PROLOGUE 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    call evf_init
    inc qword ptr [rip + evf_reads]
    mov rax, [rip + evf_read_n]
    cmp rax, [rip + evf_reads]
    je .Lepfr_io
    mov rbx, [rip + g_ext_image_capture]
    test rbx, rbx
    jz .Lepfr_normal
    mov rax, [rsp]
    cmp [rbx + EP_capture_handle], rax
    jne .Lepfr_normal
    cmp qword ptr [rip + evf_image_mode], 4
    je .Lepfr_eintr
    cmp qword ptr [rip + evf_image_mode], 2
    jne .Lepfr_normal
    cmp qword ptr [rsp + 24], 9
    jae .Lepfr_zero
    cmp qword ptr [rsp + 16], 9
    jbe .Lepfr_normal
    mov qword ptr [rsp + 16], 9
.Lepfr_normal:
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    mov rcx, [rsp + 24]
    cmp qword ptr [rip + evf_partial], 0
    je 7f
    cmp rdx, 256
    jbe 7f
    mov edx, 256
7:  call evf_once_real
    cmp rax, 4
    jb .Lepfr_done
    cmp qword ptr [rip + evf_image_mode], 1
    jne .Lepfr_done
    test rbx, rbx
    jz .Lepfr_done
    mov rcx, [rsp]
    cmp [rbx + EP_capture_handle], rcx
    jne .Lepfr_done
    cmp qword ptr [rsp + 24], 0
    jne .Lepfr_done
    mov rcx, [rsp + 8]
.ifdef WINDOWS
    mov word ptr [rcx], 0x5a4d
.else
.ifdef MACOS
    mov dword ptr [rcx], 0xfeedfacf
.else
    mov dword ptr [rcx], 0x464c457f
.endif
.endif
.Lepfr_done:
    EPILOGUE
.Lepfr_io:
    mov rax, -5
    cmp qword ptr [rip + evf_zero], 0
    je .Lepfr_done
.Lepfr_zero:
    xor eax, eax
    EPILOGUE
.Lepfr_eintr:
    mov rax, -EINTR
    EPILOGUE
.section .rodata
evf_image_key: .asciz "RHUN_EP_IMAGE_MODE"
evf_partial_key: .asciz "RHUN_EP_PARTIAL"

.text
FN prep_asset_plan
    PROLOGUE
    mov rbx, rdi
    call evf_init
    cmp qword ptr [rip + epf_hide_plan], 0
    jne 1f
    mov rdi, rbx
    call epf_plan_real
    EPILOGUE
1:  xor eax, eax
    EPILOGUE
.section .rodata
epf_hide_key: .asciz "RHUN_EP_HIDE_PLAN"
