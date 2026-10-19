# Rounded ownership charging. Allocator retained chunks and executable assets are separate.
.include "rhun.inc"
.include "app/themecapture.inc"
.bss
.globl g_theme_capture_charge
g_theme_capture_charge: .zero 8
.data
.globl g_theme_capture_limit
g_theme_capture_limit: .quad TC_MEMORY_CAP
.text
# Internal allocations charge exactly the block/header rounding in mem.s.
FN tc_alloc_try
    PROLOGUE
    mov rbx, rdi
    cmp rbx, TC_MEMORY_CAP
    ja 9f
    lea rax, [rbx + 16]
    cmp rax, 65536
    ja 1f
    dec rax
    or rax, 31
    bsr rcx, rax
    inc ecx
    mov eax, 1
    shl rax, cl
    jmp 2f
1:  add rax, 4095
    and rax, -4096
2:  mov r12, rax
    mov rcx, [rip + g_theme_capture_limit]
    cmp r12, rcx
    ja 9f
    sub rcx, r12
    cmp [rip + g_theme_capture_charge], rcx
    ja 9f
    mov rdi, rbx
    call mem_alloc_try
    test rax, rax
    jz 9f
    add [rip + g_theme_capture_charge], r12
    EPILOGUE
9:  xor eax, eax
    EPILOGUE
# Checked release retains pointer, allocator header and quota until consumed1.
FN tc_free
    test rdi, rdi
    jz 2f
    PROLOGUE
    mov rbx, rdi
    call mem_capacity
    lea r12, [rax + 16]
    cmp [rip + g_theme_capture_charge], r12
    jb 1f
    mov rdi, rbx
    call prep_cleanup_free
    test rdx, rdx
    jz 3f
    sub [rip + g_theme_capture_charge], r12
    xor eax, eax
3:  EPILOGUE
1:  mov rax, -22
    xor edx, edx
    EPILOGUE
2:  xor eax, eax
    mov edx, 1
    ret
# Bounded foreign allocator/native ownership reserves are released after actual consumption.
FN tc_charge_reserve
    mov rax, [rip + g_theme_capture_limit]
    cmp rdi, rax
    ja 1f
    sub rax, rdi
    cmp [rip + g_theme_capture_charge], rax
    ja 1f
    add [rip + g_theme_capture_charge], rdi
    xor eax, eax
    ret
1:  mov rax, -12
    ret
FN tc_charge_release
    cmp [rip + g_theme_capture_charge], rdi
    jb 1f
    sub [rip + g_theme_capture_charge], rdi
    xor eax, eax
    ret
1:  mov rax, -22
    ret
