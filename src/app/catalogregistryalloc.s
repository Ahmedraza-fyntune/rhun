# One allocation attempt per merge slice. All storage is charged through one EO.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.include "app/catalogregistrymap.inc"
.text
# Internal owned RG. Returns1 (including one cursor-only skip),0complete,negative.
FN registry_allocate_one
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + RW_alloc]
    test rax, rax
    jz .Lrgal_suppliers
    cmp rax, 1
    je .Lrgal_grrows
    cmp rax, 2
    je .Lrgal_grview
    cmp rax, 3
    je .Lrgal_themes
    cmp rax, 4
    je .Lrgal_meta
    cmp rax, 5
    je .Lrgal_candidates
    cmp rax, 6
    je .Lrgal_scratch
    cmp rax, 7
    je .Lrgal_grmap
    cmp rax, 8
    je .Lrgal_thmap
    cmp rax, 9
    je .Lrgal_grnodes
    cmp rax, 10
    je .Lrgal_thnodes
    cmp rax, 11
    jne .Lrgal_bad
    xor eax, eax
    EPILOGUE
.Lrgal_suppliers:
    mov esi, REG_EP_CAP * RGS_SIZE
    mov r12d, RG_suppliers
    jmp .Lrgal_array
.Lrgal_grrows:
    imul rsi, [rbx + RW_grcap], GRR_SIZE
    mov r12d, RG_grammars
    jmp .Lrgal_array
.Lrgal_grview:
    mov rsi, [rbx + RW_grcap]
    shl rsi, 3
    mov r12d, RG_grammar_view
    jmp .Lrgal_array
.Lrgal_themes:
    imul rsi, [rbx + RW_thcap], TH_SIZE
    mov r12d, RG_themes
    jmp .Lrgal_array
.Lrgal_meta:
    imul rsi, [rbx + RW_thcap], TM_SIZE
    mov r12d, RG_meta
    jmp .Lrgal_array
.Lrgal_candidates:
    mov rsi, [rbx + RW_thcap]
    shl rsi, 4
    mov r12d, RG_candidates
.Lrgal_array:
    test rsi, rsi
    jz .Lrgal_advance
    mov rdi, rbx
    call prep_owned_alloc
    test rax, rax
    jz .Lrgal_error
    mov [rbx + r12], rax
    jmp .Lrgal_advance
.Lrgal_scratch:
    mov rdi, [rbx + PO_eo]
    mov esi, PO_SIZE
    call prep_object_create
    test rax, rax
    jz .Lrgal_error
    mov [rbx + RG_scratch_po], rax
    jmp .Lrgal_advance
.Lrgal_grmap:
    mov r12d, RG_grammar_map
    jmp .Lrgal_map
.Lrgal_thmap:
    mov r12d, RG_theme_map
.Lrgal_map:
    mov rdi, [rbx + RG_scratch_po]
    mov esi, RM_SIZE
    call prep_owned_alloc
    test rax, rax
    jz .Lrgal_error
    mov [rbx + r12], rax
    jmp .Lrgal_advance
.Lrgal_grnodes:
    mov r12, [rbx + RG_grammar_map]
    mov r13, [rbx + RW_grcap]
    jmp .Lrgal_nodes
.Lrgal_thnodes:
    mov r12, [rbx + RG_theme_map]
    mov r13, [rbx + RW_thcap]
.Lrgal_nodes:
    lea r13, [r13 + r13 + 1]
    imul rsi, r13, RM_NODE_SIZE
    mov rdi, [rbx + RG_scratch_po]
    call prep_owned_alloc
    test rax, rax
    jz .Lrgal_error
    mov rdi, r12
    mov rsi, rax
    mov rdx, r13
    call registry_map_init
    test rax, rax
    js .Lrgal_return
.Lrgal_advance:
    inc qword ptr [rbx + RW_alloc]
    mov eax, 1
.Lrgal_return:
    EPILOGUE
.Lrgal_error:
    mov rax, rdx
    EPILOGUE
.Lrgal_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE
