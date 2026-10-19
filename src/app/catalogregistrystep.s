# Resumable private composition. One fixed unit or <=4096 source bytes per turn.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.include "app/catalogregistrymap.inc"
.text
FN registry_step
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .Lrgstep_invalid
    cmp r12, REG_STEP_BYTES
    ja .Lrgstep_invalid
    mov esi, C7_REGISTRY
    call catalog_is_owned
    test eax, eax
    jz .Lrgstep_invalid
    cmp qword ptr [rbx + RG_phase], RG_READY
    je .Lrgstep_cached_ready
    cmp qword ptr [rbx + RG_phase], RG_FAILED
    je .Lrgstep_cached_error
    cmp qword ptr [rbx + RG_sealed], 1
    jne .Lrgstep_invalid_busy
    mov qword ptr [rbx + RW_bytes], 0
    mov qword ptr [rbx + RW_units], 0
    mov [rbx + RW_budget], r12
.Lrgstep_loop:
    cmp qword ptr [rbx + RW_units], REG_STEP_UNITS
    jae .Lrgstep_pending
    mov rax, [rbx + RW_bytes]
    cmp rax, [rbx + RW_budget]
    jae .Lrgstep_pending
    inc qword ptr [rbx + RW_units]
    mov rdi, rbx
    mov rax, [rbx + RG_phase]
    cmp rax, RG_ALLOCATE
    je .Lrgstep_allocate
    cmp rax, RG_COPY_BASE
    je .Lrgstep_base
    cmp rax, RG_GRAMMAR
    je .Lrgstep_grammar
    cmp rax, RG_THEME
    je .Lrgstep_theme
    cmp rax, RG_FINAL_VIEWS
    je .Lrgstep_views
    cmp rax, RG_FINAL_REFS
    je .Lrgstep_refs
    cmp rax, RG_DROP_INPUT
    je .Lrgstep_drop
    mov rax, -EV_BAD_PREPARE
    jmp .Lrgstep_fail
.Lrgstep_allocate:
    call registry_allocate_one
    test rax, rax
    js .Lrgstep_fail
    jnz .Lrgstep_pending
    mov qword ptr [rbx + RG_phase], RG_COPY_BASE
    jmp .Lrgstep_loop
.Lrgstep_base:
    call registry_copy_base_one
    jmp .Lrgstep_result
.Lrgstep_grammar:
    call registry_grammar_one
    jmp .Lrgstep_result
.Lrgstep_theme:
    call registry_theme_one
    jmp .Lrgstep_result
.Lrgstep_views:
    call registry_final_view_one
    jmp .Lrgstep_result
.Lrgstep_refs:
    call registry_final_ref_one
    jmp .Lrgstep_result
.Lrgstep_drop:
    call registry_drop_input_one
.Lrgstep_result:
    test rax, rax
    js .Lrgstep_fail
    jz .Lrgstep_ready
    cmp rax, 2
    je .Lrgstep_pending
    jmp .Lrgstep_loop
.Lrgstep_fail:
    mov rdi, rbx
    call catalog_fail
.Lrgstep_error:
    mov rax, [rbx + PO_error]
    jmp .Lrgstep_return
.Lrgstep_ready:
    xor eax, eax
    jmp .Lrgstep_return
.Lrgstep_pending:
    mov eax, 1
.Lrgstep_return:
    mov rdx, [rbx + PO_error]
    mov rcx, [rbx - RD_PO_BACK + RD_diagnostic]
    mov r8, [rbx + RW_bytes]
    mov r9, [rbx + RW_units]
    EPILOGUE
.Lrgstep_cached_ready:
    xor eax, eax
    jmp .Lrgstep_cached
.Lrgstep_cached_error:
    mov rax, [rbx + PO_error]
.Lrgstep_cached:
    mov rdx, [rbx + PO_error]
    mov rcx, [rbx - RD_PO_BACK + RD_diagnostic]
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
.Lrgstep_invalid_busy:
    mov rax, -16
    mov rdx, rax
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE
.Lrgstep_invalid:
    mov rax, -22
    mov rdx, rax
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    EPILOGUE

# One already-counted unit in the outer step. May inspect both key sources.
FN registry_map_one
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, [rbx + RW_budget]
    sub rsi, [rbx + RW_bytes]
    cmp rsi, REG_BYTE_UNIT
    jbe 1f
    mov esi, REG_BYTE_UNIT
1:  mov edx, 1
    call registry_map_step
    add [rbx + RW_bytes], r8
    EPILOGUE

# Incremental NUL length, charging the inspected terminator too. No copy or parser.
FN registry_scan_one
    mov rsi, [rdi + RW_scanptr]
    test rsi, rsi
    jz .Lrgscan_bad
    mov rax, [rdi + RW_scanlen]
    mov r8, [rdi + RW_scanlimit]
    mov rcx, [rdi + RW_budget]
    sub rcx, [rdi + RW_bytes]
    cmp rcx, REG_BYTE_UNIT
    jbe 1f
    mov ecx, REG_BYTE_UNIT
1:  xor r9d, r9d
2:  test rcx, rcx
    jz .Lrgscan_pending
    cmp rax, r8
    ja .Lrgscan_resource
    cmp byte ptr [rsi + rax], 0
    lea r9, [r9 + 1]
    je .Lrgscan_done
    inc rax
    dec rcx
    jmp 2b
.Lrgscan_pending:
    mov [rdi + RW_scanlen], rax
    add [rdi + RW_bytes], r9
    mov eax, 1
    ret
.Lrgscan_done:
    mov [rdi + RW_scanlen], rax
    add [rdi + RW_bytes], r9
    xor eax, eax
    ret
.Lrgscan_resource:
    add [rdi + RW_bytes], r9
    mov rax, -EV_RESOURCE
    ret
.Lrgscan_bad:
    mov rax, -EV_BAD_PREPARE
    ret
