# Classify a native directory without following reparse points.
.include "win.inc"
.text
FN extwatch_directory
    PROLOGUE 96
    call win_file_path_try
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rcx, rax
    API GetFileAttributesW
    mov r12d, eax
    mov rdi, rbx
    call mem_free
    cmp r12d, -1
    je 8f
    test r12d, 0x400
    jnz 8f
    xor eax, eax
    test r12d, 16
    setnz al
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
