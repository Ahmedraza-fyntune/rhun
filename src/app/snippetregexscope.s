# Scoped operations override only private matcher flags for one synchronous call.
.include "rhun.inc"
.text
# snippet_regex_scoped_assert(ctx, kind, explicit i/m bits) -> assertion
FN snippet_regex_scoped_assert
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + RX_flags]
    mov rax, r12
    and rax, -7
    or rax, rdx
    mov [rbx + RX_flags], rax
    call snippet_regex_assert
    mov [rbx + RX_flags], r12
    EPILOGUE
# snippet_regex_scoped_reference(ctx, group, explicit i bit) -> match
FN snippet_regex_scoped_reference
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + RX_flags]
    mov rax, r12
    and rax, -3
    or rax, rdx
    mov [rbx + RX_flags], rax
    call snippet_regex_reference
    mov [rbx + RX_flags], r12
    EPILOGUE
