# Copied scalar overrides lose authority immediately when their stable owner hides.
.include "rhun.inc"
.text
FN ext_doc_option
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .Ledo_none
    cmp r12, 4
    jae .Ledo_none
    mov rdi, [rbx + DOC_oown + r12*8]
    call ext_has_identity
    test eax, eax
    jz .Ledo_none
    mov eax, [rbx + DOC_oval + r12*4]
    EPILOGUE
.Ledo_none:
    xor eax, eax
    EPILOGUE
