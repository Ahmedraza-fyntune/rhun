# A pending native choice opens after a slow grammar refresh without losing its snippet pointer.
.include "rhun.inc"
.bss
.p2align 3
dlc_tab: .zero TAB_SIZE
dlc_dump: .zero SB_SIZE
.text
FN main
    PROLOGUE
    call doc_new
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    lea rdx, [rip + dlc_text]
    mov ecx, 3
    xor r8d, r8d
    call doc_insert
    lea rdi, [rip + dlc_text]
    mov esi, 3
    lea rdx, [rip + dlc_fields]
    mov ecx, dlc_fields_end - dlc_fields
    mov r8d, 1
    mov r9d, FEAT_SNIPPETS | FEAT_SNIPPET_VARIANTS
    call snippet_decode_fields
    test rax, rax
    jz .Ldlc_bad
    mov rdi, rbx
    mov rsi, rax
    xor edx, edx
    call snippet_attach
    lea rax, [rip + dlc_tab]
    mov qword ptr [rax + TAB_kind], TAB_DOC
    mov [rax + TAB_doc], rbx
    mov [rip + g_tabs + VEC_ptr], rax
    mov qword ptr [rip + g_tabs + VEC_len], 1
    mov qword ptr [rip + g_tab_cur], 0
    mov [rip + g_doc], rbx
    mov dword ptr [rip + g_focus], FOCUS_EDITOR
    mov dword ptr [rip + g_caret_ok], 0
    # An epoch miss resolves to plain and clobbers volatile argument registers.
    mov qword ptr [rbx + DOC_language_epoch], 0
    call complete_draw
    lea rdi, [rip + dlc_dump]
    call complete_dump
    mov rdi, [rip + dlc_dump + SB_ptr]
    mov rsi, [rip + dlc_dump + SB_len]
    lea rdx, [rip + dlc_expected]
    mov ecx, dlc_expected_end - dlc_expected
    call str_find
    test rax, rax
    js .Ldlc_bad
    mov edi, KEY_ESCAPE
    xor esi, esi
    xor edx, edx
    call complete_key
    mov rdi, rbx
    call doc_free
    mov rdi, [rip + dlc_dump + SB_ptr]
    call mem_free
    mov edi, 1
    lea rsi, [rip + dlc_ok]
    mov edx, dlc_ok_end - dlc_ok
    call write_all
    xor eax, eax
    EPILOGUE
.Ldlc_bad:
    mov eax, 73
    EPILOGUE
.section .rodata
dlc_text: .ascii "x x"
dlc_fields: .ascii "field 1 0 1 0 0\nfield 2 2 3 0 0\nchoice 1 3 13\n1\nx0\n6\na\n😀"
dlc_fields_end:
dlc_expected: .ascii "complete open=2 items=3 shown=3"
dlc_expected_end:
dlc_ok: .ascii "ok native snippet choices after lazy grammar synchronization\n"
dlc_ok_end:
