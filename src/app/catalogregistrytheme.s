# Exact raw-path replacement into private descriptors, with counted TCNR strings.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extprepare.inc"
.include "app/catalogregistry.inc"
.include "app/catalogregistrywork.inc"
.text
FN registry_theme_one
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx + RW_stage]
    test rax, rax
    jz .Lrgt_next
    cmp rax, 1
    je .Lrgt_key
    cmp rax, 2
    je .Lrgt_map
    cmp rax, 3
    je .Lrgt_id
    cmp rax, 4
    je .Lrgt_name
    cmp rax, 5
    je .Lrgt_install
    jmp .Lrgt_bad
.Lrgt_next:
    mov r12, [rbx + RW_ep]
    cmp r12, [rbx + RG_ninput]
    jae .Lrgt_views
    imul rax, r12, RGS_SIZE
    add rax, [rbx + RG_inputs]
    mov r13, [rax + RGS_ep]
    mov rcx, [rbx + RW_item]
    cmp rcx, [r13 + EP_themeviews + VEC_len]
    jae .Lrgt_next_ep
    imul r14, rcx, PT_SIZE
    add r14, [r13 + EP_themeviews + VEC_ptr]
    cmp [r14 + TH_owner], r13
    jne .Lrgt_bad
    mov [rbx + RW_current], r14
    mov rax, [r14 + TH_path]
    test rax, rax
    jz .Lrgt_bad
    mov [rbx + RW_scanptr], rax
    mov qword ptr [rbx + RW_scanlen], 0
    mov qword ptr [rbx + RW_scanlimit], 4096
    mov qword ptr [rbx + RW_stage], 1
    jmp .Lrgt_pending
.Lrgt_key:
    call registry_scan_one
    test rax, rax
    js .Lrgt_return
    jnz .Lrgt_pending
    mov rdx, [rbx + RW_scanlen]
    mov [rbx + RW_keylen], rdx
    mov rsi, [rbx + RW_scanptr]
    mov rcx, [rbx + RG_ntheme]
    inc rcx
    cmp rcx, REG_ROW_CAP
    mov eax, REG_ROW_CAP
    cmova rcx, rax
    mov rdi, [rbx + RG_theme_map]
    call registry_map_start
    test rax, rax
    js .Lrgt_return
    mov qword ptr [rbx + RW_stage], 2
    jmp .Lrgt_pending
.Lrgt_map:
    mov rsi, [rbx + RG_theme_map]
    call registry_map_one
    test rax, rax
    js .Lrgt_return
    jnz .Lrgt_pending
    dec rdx
    test rcx, rcx
    jnz 1f
    mov rdx, [rbx + RG_ntheme]
1:  mov [rbx + RW_target], rdx
    cmp rdx, [rbx + RG_ntheme]
    ja .Lrgt_bad
    cmp rdx, [rbx + RW_thcap]
    jae .Lrgt_resource
    mov rax, [rbx + RW_current]
    mov rax, [rax + TH_id]
    mov [rbx + RW_scanptr], rax
    mov qword ptr [rbx + RW_scanlen], 0
    mov qword ptr [rbx + RW_scanlimit], 4095
    mov qword ptr [rbx + RW_stage], 3
    jmp .Lrgt_pending
.Lrgt_id:
    call registry_scan_one
    test rax, rax
    js .Lrgt_return
    jnz .Lrgt_pending
    mov rax, [rbx + RW_scanlen]
    mov [rbx + RW_idlen], rax
    mov rax, [rbx + RW_current]
    mov rax, [rax + TH_name]
    mov [rbx + RW_scanptr], rax
    mov qword ptr [rbx + RW_scanlen], 0
    mov qword ptr [rbx + RW_scanlimit], PREP_CAP
    mov qword ptr [rbx + RW_stage], 4
    jmp .Lrgt_pending
.Lrgt_name:
    call registry_scan_one
    test rax, rax
    js .Lrgt_return
    jnz .Lrgt_pending
    mov rax, [rbx + RW_scanlen]
    mov [rbx + RW_namelen], rax
    mov qword ptr [rbx + RW_stage], 5
    jmp .Lrgt_pending
.Lrgt_install:
    mov r12, [rbx + RW_target]
    imul r13, r12, TM_SIZE
    add r13, [rbx + RG_meta]
    cmp qword ptr [r13 + TM_kind], REG_EXTENSION
    jne 2f
    mov rax, [r13 + TM_supplier]
    cmp rax, [rbx + RG_ninput]
    jae .Lrgt_bad
    imul rax, rax, RGS_SIZE
    add rax, [rbx + RG_inputs]
    cmp qword ptr [rax + RGS_themes], 0
    je .Lrgt_bad
    dec qword ptr [rax + RGS_themes]
2:  mov rax, [rbx + RW_ep]
    mov [r13 + TM_supplier], rax
    imul rax, rax, RGS_SIZE
    add rax, [rbx + RG_inputs]
    inc qword ptr [rax + RGS_themes]
    imul rdi, r12, TH_SIZE
    add rdi, [rbx + RG_themes]
    mov r14, [rbx + RW_current]
    mov rsi, r14
    mov edx, TH_SIZE
    call memcpy
    mov qword ptr [r13 + TM_kind], REG_EXTENSION
    mov [r13 + TM_pt], r14
    mov rax, [r14 + TH_path]
    mov [r13 + TM_key], rax
    mov rax, [rbx + RW_keylen]
    mov [r13 + TM_keylen], rax
    mov qword ptr [r13 + TM_path], 0
    mov qword ptr [r13 + TM_pathlen], 0
    mov rax, [rbx + RW_idlen]
    mov [r13 + TM_idlen], rax
    mov rax, [rbx + RW_namelen]
    mov [r13 + TM_namelen], rax
    mov qword ptr [r13 + TM_baseordinal], -1
    cmp r12, [rbx + RG_ntheme]
    jne 3f
    inc qword ptr [rbx + RG_ntheme]
3:  inc qword ptr [rbx + RW_item]
    mov qword ptr [rbx + RW_stage], 0
    jmp .Lrgt_pending
.Lrgt_next_ep:
    inc qword ptr [rbx + RW_ep]
    mov qword ptr [rbx + RW_item], 0
    jmp .Lrgt_pending
.Lrgt_views:
    mov qword ptr [rbx + RG_phase], RG_FINAL_VIEWS
    mov qword ptr [rbx + RW_stage], 0
    mov qword ptr [rbx + RG_index], 0
.Lrgt_pending:
    mov eax, 1
.Lrgt_return:
    EPILOGUE
.Lrgt_resource:
    mov rax, -EV_RESOURCE
    EPILOGUE
.Lrgt_bad:
    mov rax, -EV_BAD_PREPARE
    EPILOGUE
