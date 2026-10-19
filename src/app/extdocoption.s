# ext_doc_option(doc or 0, OPT_*) -> eax the document's override (section 6c), 0 for none. An
# override lives as long as the extension that set it runs (ext_options_clear). Clobbers rax only.
.include "rhun.inc"
.text
FN ext_doc_option
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp rsi, 4
    jae 9f
    mov eax, [rdi + DOC_oval + rsi*4]
9:  ret
