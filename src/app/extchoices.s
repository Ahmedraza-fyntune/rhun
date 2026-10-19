# Pure settings merge. Disk locking and publication belong to the persistence adapter.
.include "rhun.inc"
.include "app/extchoices.inc"
.equ ECF_input, 0
.equ ECF_length, 8
.equ ECF_delta, 16
.equ ECF_count, 24
.equ ECF_output, 32
.equ ECF_used, 40
.equ ECF_last, 48
.equ ECF_SIZE, 56
.section .rodata
.Lec_open: .ascii "["
.Lec_close: .ascii "]\n"
.Lec_equal: .ascii "="
.Lec_lf: .ascii "\n"
.text

# ec_text(ptr,len,mode) ->1/0. mode0 snapshot,1 section/key,2 value.
ec_text:
    test rsi, rsi
    jz .Lec_yes
    test rdi, rdi
    jz .Lec_no
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call snippet_utf8_valid
    test eax, eax
    jz .Lec_text_no
    xor ecx, ecx
1:  movzx eax, byte ptr [rbx + rcx]
    cmp eax, 127
    je .Lec_text_no
    cmp eax, 32
    jae 3f
    test r13d, r13d
    jz 2f
    cmp r13d, 2
    jne .Lec_text_no
    cmp eax, 9
    je 3f
    jmp .Lec_text_no
2:  cmp eax, 9
    je 3f
    cmp eax, 13
    je 3f
    cmp eax, 10
    jne .Lec_text_no
3:  inc rcx
    cmp rcx, r12
    jb 1b
    mov eax, 1
    EPILOGUE
.Lec_text_no:
    xor eax, eax
    EPILOGUE
.Lec_yes:
    mov eax, 1
    ret
.Lec_no:
    xor eax, eax
    ret

# Complete grammar check before ini_next, which otherwise silently skips bad lines.
ec_snapshot:
    PROLOGUE
    mov rbx, rdi
    lea r12, [rdi + rsi]
    xor edx, edx
    call ec_text
    test eax, eax
    jz .Lec_snapshot_bad
1:  cmp rbx, r12
    jae .Lec_snapshot_ok
    mov r13, rbx
2:  cmp r13, r12
    jae 3f
    cmp byte ptr [r13], 10
    je 3f
    inc r13
    jmp 2b
3:  mov r14, r13
    cmp r14, r12
    jae 4f
    inc r14
4:  mov rdi, rbx
    mov rsi, r13
    sub rsi, rbx
    call trim
    mov rbx, r14
    test rdx, rdx
    jz 1b
    cmp byte ptr [rax], '#'
    je 1b
    cmp byte ptr [rax], ';'
    je 1b
    cmp byte ptr [rax], '['
    jne 5f
    cmp byte ptr [rax + rdx - 1], ']'
    je 1b
5:  xor ecx, ecx
6:  cmp rcx, rdx
    jae .Lec_snapshot_bad
    cmp byte ptr [rax + rcx], '='
    je 7f
    inc rcx
    jmp 6b
7:  mov rdi, rax
    mov rsi, rcx
    call trim
    test rdx, rdx
    jnz 1b
.Lec_snapshot_bad:
    xor eax, eax
    EPILOGUE
.Lec_snapshot_ok:
    mov eax, 1
    EPILOGUE

# ec_name(ptr,len) ->1/0, nonempty already-trimmed section/key span.
ec_name:
    test rsi, rsi
    jz .Lec_no
    cmp rsi, EC_LIMIT
    ja .Lec_no
    test rdi, rdi
    jz .Lec_no
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edx, 1
    call ec_text
    test eax, eax
    jz 1f
    mov rdi, rbx
    mov rsi, r12
    call trim
    cmp rax, rbx
    jne 2f
    cmp rdx, r12
    jne 2f
    mov eax, 1
    EPILOGUE
2:  xor eax, eax
1:  EPILOGUE

# Append a counted span, or just measure it when output is NULL.
ec_emit:
    mov rax, [rdi + ECF_used]
    add rax, rdx
    jc .Lec_emit_large
    cmp rax, EC_LIMIT
    ja .Lec_emit_large
    test rdx, rdx
    jz 2f
    movzx ecx, byte ptr [rsi + rdx - 1]
    mov [rdi + ECF_last], rcx
    mov rcx, [rdi + ECF_output]
    test rcx, rcx
    jz 2f
    PROLOGUE
    mov rbx, rdi
    mov r12, rax
    mov rdi, rcx
    add rdi, [rbx + ECF_used]
    call memcpy
    mov [rbx + ECF_used], r12
    xor eax, eax
    EPILOGUE
2:  mov [rdi + ECF_used], rax
    xor eax, eax
    ret
.Lec_emit_large:
    mov rax, -27
    ret

# Emit a validated field, adding only the required line separator.
ec_emit_field:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + ECF_used], 0
    je 1f
    cmp qword ptr [rbx + ECF_last], 10
    je 1f
    lea rsi, [rip + .Lec_lf]
    mov edx, 1
    call ec_emit
    test rax, rax
    js 2f
1:  mov rdi, rbx
    mov rsi, [r12 + EC_key]
    mov rdx, [r12 + EC_keylen]
    call ec_emit
    test rax, rax
    js 2f
    mov rdi, rbx
    lea rsi, [rip + .Lec_equal]
    mov edx, 1
    call ec_emit
    test rax, rax
    js 2f
    mov rdi, rbx
    mov rsi, [r12 + EC_value]
    mov rdx, [r12 + EC_vallen]
    call ec_emit
    test rax, rax
    js 2f
    mov rdi, rbx
    lea rsi, [rip + .Lec_lf]
    mov edx, 1
    call ec_emit
2:  EPILOGUE

# Emit one header for an absent exact section.
ec_emit_header:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + ECF_used], 0
    je 1f
    cmp qword ptr [rbx + ECF_last], 10
    je 1f
    lea rsi, [rip + .Lec_lf]
    mov edx, 1
    call ec_emit
    test rax, rax
    js 2f
1:  mov rdi, rbx
    lea rsi, [rip + .Lec_open]
    mov edx, 1
    call ec_emit
    test rax, rax
    js 2f
    mov rdi, rbx
    mov rsi, [r12 + EC_section]
    mov rdx, [r12 + EC_seclen]
    call ec_emit
    test rax, rax
    js 2f
    mov rdi, rbx
    lea rsi, [rip + .Lec_close]
    mov edx, 2
    call ec_emit
2:  EPILOGUE

# Two identical counted line passes; sections are matched only at source headers.
# stack: next0,line8,section16/24,matchCount32,key40/48,group56,cache128[128],seen1152[128].
ec_filter:
    PROLOGUE 1280
    mov rbx, rdi
    mov qword ptr [rbx + ECF_used], 0
    mov qword ptr [rbx + ECF_last], 0
    mov r12, [rbx + ECF_input]
    mov r13, [rbx + ECF_length]
    add r13, r12
    mov [rsp], r12
    mov qword ptr [rsp + 32], 0
    lea rdi, [rsp + 1152]
    xor esi, esi
    mov edx, 128
    call memset
.Lec_filter_line:
    mov r14, [rsp]
    cmp r14, r13
    jae .Lec_filter_tail
    mov [rsp + 8], r14
    mov r15, r14
1:  cmp r15, r13
    jae 2f
    cmp byte ptr [r15], 10
    je 2f
    inc r15
    jmp 1b
2:  mov rax, r15
    cmp rax, r13
    jae 3f
    inc rax
3:  mov [rsp], rax
    mov rdi, r14
    mov rsi, r15
    sub rsi, r14
    call trim
    test rdx, rdx
    jz .Lec_filter_line
    cmp byte ptr [rax], '#'
    je .Lec_filter_line
    cmp byte ptr [rax], ';'
    je .Lec_filter_line
    cmp byte ptr [rax], '['
    jne .Lec_filter_key
    cmp byte ptr [rax + rdx - 1], ']'
    jne .Lec_filter_key
    lea rdi, [rax + 1]
    lea rsi, [rdx - 2]
    call trim
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov qword ptr [rsp + 32], 0
    xor r14d, r14d
    mov r15, [rbx + ECF_delta]
.Lec_filter_cache:
    cmp r14, [rbx + ECF_count]
    jae .Lec_filter_header
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, [r15 + EC_section]
    mov rcx, [r15 + EC_seclen]
    call str_eq
    test eax, eax
    jz 1f
    mov rax, [rsp + 32]
    mov [rsp + rax*8 + 128], r14
    inc qword ptr [rsp + 32]
1:  inc r14
    add r15, EC_SIZE
    jmp .Lec_filter_cache
.Lec_filter_header:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp]
    sub rdx, r12
    call ec_emit
    test rax, rax
    js .Lec_filter_done
    mov r12, [rsp]
    xor r14d, r14d
.Lec_filter_insert:
    cmp r14, [rsp + 32]
    jae .Lec_filter_line
    mov rax, [rsp + r14*8 + 128]
    cmp byte ptr [rsp + rax + 1152], 0
    jne 1f
    imul r15, rax, EC_SIZE
    add r15, [rbx + ECF_delta]
    cmp qword ptr [r15 + EC_remove], 0
    jne 1f
    mov byte ptr [rsp + rax + 1152], 1
    mov rdi, rbx
    mov rsi, r15
    call ec_emit_field
    test rax, rax
    js .Lec_filter_done
1:  inc r14
    jmp .Lec_filter_insert
.Lec_filter_key:
    mov r15, rax
    xor ecx, ecx
1:  cmp rcx, rdx
    jae .Lec_filter_bad
    cmp byte ptr [r15 + rcx], '='
    je 2f
    inc rcx
    jmp 1b
2:  mov rdi, r15
    mov rsi, rcx
    call trim
    mov [rsp + 40], rax
    mov [rsp + 48], rdx
    xor r14d, r14d
.Lec_filter_matchkey:
    cmp r14, [rsp + 32]
    jae .Lec_filter_line
    mov rax, [rsp + r14*8 + 128]
    imul r15, rax, EC_SIZE
    add r15, [rbx + ECF_delta]
    mov rdi, [rsp + 40]
    mov rsi, [rsp + 48]
    mov rdx, [r15 + EC_key]
    mov rcx, [r15 + EC_keylen]
    call str_eq
    test eax, eax
    jnz .Lec_filter_skip
    inc r14
    jmp .Lec_filter_matchkey
.Lec_filter_skip:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [rsp + 8]
    sub rdx, r12
    call ec_emit
    test rax, rax
    js .Lec_filter_done
    mov r12, [rsp]
    jmp .Lec_filter_line
.Lec_filter_tail:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    sub rdx, r12
    call ec_emit
    test rax, rax
    js .Lec_filter_done
    xor r14d, r14d
.Lec_filter_append:
    cmp r14, [rbx + ECF_count]
    jae .Lec_filter_ok
    cmp byte ptr [rsp + r14 + 1152], 0
    jne .Lec_filter_advance
    imul r15, r14, EC_SIZE
    add r15, [rbx + ECF_delta]
    cmp qword ptr [r15 + EC_remove], 0
    jne .Lec_filter_advance
    mov [rsp + 56], r15
    mov rdi, rbx
    mov rsi, r15
    call ec_emit_header
    test rax, rax
    js .Lec_filter_done
    xor r15d, r15d
.Lec_filter_group:
    cmp r15, [rbx + ECF_count]
    jae .Lec_filter_advance
    cmp byte ptr [rsp + r15 + 1152], 0
    jne .Lec_filter_group_next
    imul rax, r15, EC_SIZE
    add rax, [rbx + ECF_delta]
    cmp qword ptr [rax + EC_remove], 0
    jne .Lec_filter_group_next
    mov [rsp + 64], rax
    mov rdx, [rsp + 56]
    mov rdi, [rax + EC_section]
    mov rsi, [rax + EC_seclen]
    mov rcx, [rdx + EC_seclen]
    mov rdx, [rdx + EC_section]
    call str_eq
    test eax, eax
    jz .Lec_filter_group_next
    mov byte ptr [rsp + r15 + 1152], 1
    mov rdi, rbx
    mov rsi, [rsp + 64]
    call ec_emit_field
    test rax, rax
    js .Lec_filter_done
.Lec_filter_group_next:
    inc r15
    jmp .Lec_filter_group
.Lec_filter_advance:
    inc r14
    jmp .Lec_filter_append
.Lec_filter_bad:
    mov rax, -22
    jmp .Lec_filter_done
.Lec_filter_ok:
    xor eax, eax
.Lec_filter_done:
    EPILOGUE

# ext_choices_validate(snapshot,len)->0/-errno, with no allocation or shared iterator.
FN ext_choices_validate
    cmp rsi, EC_LIMIT
    ja 1f
    PROLOGUE
    call ec_snapshot
    test eax, eax
    jz 2f
    xor eax, eax
    EPILOGUE
2:  mov rax, -22
    EPILOGUE
1:  mov rax, -27
    ret

# ext_choices_validate_delta(EC*) ->0/-errno. Pure; spans stay caller-owned.
FN ext_choices_validate_delta
    test rdi, rdi
    jz .Lecd_invalid_leaf
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + EC_remove], 1
    ja .Lecd_invalid
    mov rdi, [rbx + EC_section]
    mov rsi, [rbx + EC_seclen]
    call ec_name
    test eax, eax
    jz .Lecd_invalid
    mov rdi, [rbx + EC_key]
    mov rsi, [rbx + EC_keylen]
    call ec_name
    test eax, eax
    jz .Lecd_invalid
    mov rax, [rbx + EC_key]
    cmp byte ptr [rax], '#'
    je .Lecd_invalid
    cmp byte ptr [rax], ';'
    je .Lecd_invalid
    xor ecx, ecx
1:  cmp byte ptr [rax + rcx], '='
    je .Lecd_invalid
    inc rcx
    cmp rcx, [rbx + EC_keylen]
    jb 1b
    cmp qword ptr [rbx + EC_remove], 0
    jne .Lecd_ok
    cmp qword ptr [rbx + EC_vallen], EC_LIMIT
    ja .Lecd_large
    mov rdi, [rbx + EC_value]
    mov rsi, [rbx + EC_vallen]
    mov edx, 2
    call ec_text
    test eax, eax
    jz .Lecd_invalid
    mov rax, [rbx + EC_key]
    cmp byte ptr [rax], '['
    jne .Lecd_ok
    mov rdi, [rbx + EC_value]
    mov rsi, [rbx + EC_vallen]
    call trim
    test rdx, rdx
    jz .Lecd_ok
    cmp byte ptr [rax + rdx - 1], ']'
    je .Lecd_invalid
.Lecd_ok:
    xor eax, eax
    EPILOGUE
.Lecd_large:
    mov rax, -27
    EPILOGUE
.Lecd_invalid:
    mov rax, -22
    EPILOGUE
.Lecd_invalid_leaf:
    mov rax, -22
    ret

# ext_choices_merge(snapshot,len,deltas,count)->owned bytes,length or0,-errno.
FN ext_choices_merge
    cmp rsi, EC_LIMIT
    ja .Lec_large
    test rcx, rcx
    jz .Lec_invalid
    cmp rcx, EC_BATCH
    ja .Lec_toomany
    test rdx, rdx
    jz .Lec_invalid
    PROLOGUE 80
    mov [rsp + ECF_input], rdi
    mov [rsp + ECF_length], rsi
    mov [rsp + ECF_delta], rdx
    mov [rsp + ECF_count], rcx
    mov qword ptr [rsp + ECF_output], 0
    call ec_snapshot
    test eax, eax
    jz .Lec_merge_invalid
    mov rbx, [rsp + ECF_delta]
    xor r12d, r12d
.Lec_delta:
    cmp r12, [rsp + ECF_count]
    jae .Lec_measure
    mov rdi, rbx
    call ext_choices_validate_delta
    test rax, rax
    js .Lec_merge_error
.Lec_duplicate_check:
    mov r13, [rsp + ECF_delta]
    xor r14d, r14d
1:  cmp r14, r12
    jae .Lec_delta_next
    mov rdi, [rbx + EC_section]
    mov rsi, [rbx + EC_seclen]
    mov rdx, [r13 + EC_section]
    mov rcx, [r13 + EC_seclen]
    call str_eq
    test eax, eax
    jz 2f
    mov rdi, [rbx + EC_key]
    mov rsi, [rbx + EC_keylen]
    mov rdx, [r13 + EC_key]
    mov rcx, [r13 + EC_keylen]
    call str_eq
    test eax, eax
    jnz .Lec_merge_invalid
2:  inc r14
    add r13, EC_SIZE
    jmp 1b
.Lec_delta_next:
    inc r12
    add rbx, EC_SIZE
    jmp .Lec_delta
.Lec_measure:
    mov rdi, rsp
    call ec_filter
    test rax, rax
    js .Lec_merge_error
    mov r13, [rsp + ECF_used]
    lea rdi, [r13 + 1]
    call mem_alloc_try
    test rax, rax
    jz .Lec_merge_nomem
    mov r12, rax
    mov [rsp + ECF_output], rax
    mov rdi, rsp
    call ec_filter
    test rax, rax
    js .Lec_merge_free
    cmp [rsp + ECF_used], r13
    jne .Lec_merge_changed
    mov byte ptr [r12 + r13], 0
    mov rax, r12
    mov rdx, r13
    EPILOGUE
.Lec_merge_changed:
    mov rax, -22
.Lec_merge_free:
    mov rbx, rax
    mov rdi, r12
    call mem_free
    mov rax, rbx
    jmp .Lec_merge_error
.Lec_merge_nomem:
    mov rax, -12
    jmp .Lec_merge_error
.Lec_merge_large:
    mov rax, -27
    jmp .Lec_merge_error
.Lec_merge_invalid:
    mov rax, -22
.Lec_merge_error:
    mov rdx, rax
    xor eax, eax
    EPILOGUE
.Lec_invalid:
    mov rdx, -22
    xor eax, eax
    ret
.Lec_toomany:
    mov rdx, -7
    xor eax, eax
    ret
.Lec_large:
    mov rdx, -27
    xor eax, eax
    ret
