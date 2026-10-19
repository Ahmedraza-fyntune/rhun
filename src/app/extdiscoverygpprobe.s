# Resumable physical reachability with the runtime's exact two lookup policies.
.include "rhun.inc"
.include "app/extvalidate.inc"
.include "app/extdiscoverygp.inc"
.text
# ctx,offset,len. Recheck extents before each hash or comparison follows bytes.
FN pg_word_extent
    cmp rsi, [rdi + GPC_pool]
    jb .Lpgp_bad
    test rdx, rdx
    jz .Lpgp_bad
    cmp rdx, [rdi + GPC_sourcebytes]
    ja .Lpgp_bad
    mov rax, rsi
    add rax, rdx
    jc .Lpgp_bad
    cmp rax, [rdi + GPC_length]
    jae .Lpgp_bad
    xor eax, eax
    ret

# ctx ->0equal/2different/1pending/negative. Each side's byte read is metered.
FN pg_compare_step
    PROLOGUE
    mov rbx, rdi
.Lpgc_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpgc_pending
    cmp qword ptr [rbx + GPC_policy], 0
    je .Lpgc_sensitive
    mov rax, [rbx + GPC_comparestate]
    test rax, rax
    jz .Lpgc_char_start
    cmp rax, 1
    je .Lpgc_needle
    cmp rax, 2
    je .Lpgc_hay
    cmp rax, 3
    je .Lpgc_fold_needle
    cmp rax, 4
    je .Lpgc_fold_hay
    jmp .Lpgc_bad
.Lpgc_char_start:
    mov rax, [rbx + GPC_comparecursor]
    cmp rax, [rbx + GPC_candidatelength]
    jae .Lpgc_equal
    mov qword ptr [rbx + GPC_needleread], 0
    mov qword ptr [rbx + GPC_hayread], 0
    mov qword ptr [rbx + GPC_utf8remaining], 0
    mov qword ptr [rbx + GPC_comparestate], 1
.Lpgc_needle:
    mov rax, [rbx + GPC_comparecursor]
    add rax, [rbx + GPC_needleread]
    cmp rax, [rbx + GPC_candidatelength]
    jae .Lpgc_bad
    add rax, [rbx + GPC_candidate]
    add rax, [rbx + GPC_wire]
    mov rsi, rax
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgc_pending
    mov rsi, rax
    mov rdi, rbx
    xor edx, edx
    call pg_utf8_push
    test rax, rax
    js .Lpgc_exit
    inc qword ptr [rbx + GPC_needleread]
    cmp qword ptr [rbx + GPC_utf8remaining], 0
    jne .Lpgc_again
    mov rax, [rbx + GPC_utf8scalar]
    mov [rbx + GPC_needlescalar], rax
    mov rax, [rbx + GPC_needleread]
    mov [rbx + GPC_needlewidth], rax
    mov qword ptr [rbx + GPC_utf8remaining], 0
    mov qword ptr [rbx + GPC_comparestate], 2
.Lpgc_hay:
    mov rax, [rbx + GPC_comparecursor]
    add rax, [rbx + GPC_hayread]
    cmp rax, [rbx + GPC_probelength]
    jae .Lpgc_bad
    add rax, [rbx + GPC_probeoffset]
    add rax, [rbx + GPC_wire]
    mov rsi, rax
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgc_pending
    mov rsi, rax
    mov rdi, rbx
    xor edx, edx
    call pg_utf8_push
    test rax, rax
    js .Lpgc_exit
    inc qword ptr [rbx + GPC_hayread]
    cmp qword ptr [rbx + GPC_utf8remaining], 0
    jne .Lpgc_again
    mov rax, [rbx + GPC_utf8scalar]
    mov [rbx + GPC_hayscalar], rax
    mov rdx, [rbx + GPC_hayread]
    mov [rbx + GPC_haywidth], rdx
    cmp rdx, [rbx + GPC_needlewidth]
    jne .Lpgc_different
    mov rcx, [rbx + GPC_needlescalar]
    cmp rax, rcx
    je .Lpgc_char_equal
    cmp rax, 128
    jae 3f
    cmp rcx, 128
    jae 3f
    lea rdx, [rax - 'A']
    cmp rdx, 25
    ja 1f
    or eax, 0x20
1:  lea rdx, [rcx - 'A']
    cmp rdx, 25
    ja 2f
    or ecx, 0x20
2:  cmp eax, ecx
    jne .Lpgc_different
    jmp .Lpgc_char_equal
3:  mov qword ptr [rbx + GPC_comparestate], 3
.Lpgc_fold_needle:
    mov rdi, rbx
    mov rsi, [rbx + GPC_needlescalar]
    call pg_fold_scalar
    test rdx, rdx
    jz .Lpgc_pending
    mov [rbx + GPC_needlefold], rax
    mov qword ptr [rbx + GPC_comparestate], 4
.Lpgc_fold_hay:
    mov rdi, rbx
    mov rsi, [rbx + GPC_hayscalar]
    call pg_fold_scalar
    test rdx, rdx
    jz .Lpgc_pending
    mov [rbx + GPC_hayfold], rax
    cmp rax, [rbx + GPC_needlefold]
    jne .Lpgc_different
.Lpgc_char_equal:
    mov rax, [rbx + GPC_needlewidth]
    add [rbx + GPC_comparecursor], rax
    mov qword ptr [rbx + GPC_comparestate], 0
    jmp .Lpgc_again
.Lpgc_sensitive:
    mov rax, [rbx + GPC_comparecursor]
    cmp rax, [rbx + GPC_candidatelength]
    jae .Lpgc_equal
    cmp qword ptr [rbx + GPC_comparehave], 0
    jne 1f
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_candidate]
    add rsi, rax
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgc_pending
    mov [rbx + GPC_comparebyte], rax
    mov qword ptr [rbx + GPC_comparehave], 1
1:  mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_probeoffset]
    add rsi, [rbx + GPC_comparecursor]
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgc_pending
    cmp rax, [rbx + GPC_comparebyte]
    jne .Lpgc_different
    mov qword ptr [rbx + GPC_comparehave], 0
    inc qword ptr [rbx + GPC_comparecursor]
    jmp .Lpgc_again
.Lpgc_equal:
    xor eax, eax
.Lpgc_exit:
    EPILOGUE
.Lpgc_different:
    mov eax, 2
    EPILOGUE
.Lpgc_pending:
    mov eax, 1
    EPILOGUE
.Lpgc_bad:
    mov rdi, rbx
    mov rsi, -EV_BAD_GRAMMAR
    call pg_fail
    EPILOGUE

FN pg_reach_step
    PROLOGUE
    mov rbx, rdi
.Lpgp_again:
    cmp qword ptr [rbx + GPC_units], 16
    jae .Lpgc_pending
    mov rsi, [rbx + GPC_wordindex]
    cmp rsi, [rbx + GPC_wcap]
    jae .Lpgp_valid
    mov rax, [rbx + GPC_fieldindex]
    cmp rax, 0
    je .Lpgp_candidate_begin
    cmp rax, 1
    je .Lpgp_candidate_read
    cmp rax, 2
    je .Lpgp_hash
    cmp rax, 3
    je .Lpgp_policy_begin
    cmp rax, 4
    je .Lpgp_probe_begin
    cmp rax, 5
    je .Lpgp_probe_read
    cmp rax, 6
    je .Lpgp_compare
    jmp .Lpgc_bad
.Lpgp_candidate_begin:
    mov rdi, rbx
    mov edx, GPC_candidate
    call pg_word_record_begin
    test rax, rax
    js .Lpgc_exit
    mov qword ptr [rbx + GPC_fieldindex], 1
.Lpgp_candidate_read:
    mov rdi, rbx
    call pg_word_record_step
    test rax, rax
    js .Lpgc_exit
    jnz .Lpgc_pending
    inc qword ptr [rbx + GPC_units]
    cmp qword ptr [rbx + GPC_candidate], 0
    je .Lpgp_word_done
    mov rdi, rbx
    mov rsi, [rbx + GPC_candidate]
    mov rdx, [rbx + GPC_candidatelength]
    call pg_word_extent
    test rax, rax
    js .Lpgc_exit
    mov eax, 2166136261
    mov [rbx + GPC_hash], rax
    mov [rbx + GPC_hashfold], rax
    mov qword ptr [rbx + GPC_hashcursor], 0
    mov qword ptr [rbx + GPC_policy], 0
    mov qword ptr [rbx + GPC_fieldindex], 2
    jmp .Lpgp_again
.Lpgp_hash:
    mov rax, [rbx + GPC_hashcursor]
    cmp rax, [rbx + GPC_candidatelength]
    jae 2f
    mov rsi, [rbx + GPC_wire]
    add rsi, [rbx + GPC_candidate]
    add rsi, rax
    mov rdi, rbx
    call pg_read_byte
    test rdx, rdx
    jz .Lpgc_pending
    mov ecx, [rbx + GPC_hash]
    xor ecx, eax
    imul ecx, ecx, 16777619
    mov [rbx + GPC_hash], rcx
    lea ecx, [rax - 'A']
    cmp ecx, 25
    ja 1f
    or eax, 0x20
1:  mov ecx, [rbx + GPC_hashfold]
    xor ecx, eax
    imul ecx, ecx, 16777619
    mov [rbx + GPC_hashfold], rcx
    inc qword ptr [rbx + GPC_hashcursor]
    jmp .Lpgp_again
2:  mov qword ptr [rbx + GPC_fieldindex], 3
.Lpgp_policy_begin:
    mov rax, [rbx + GPC_hash]
    cmp qword ptr [rbx + GPC_policy], 0
    je 1f
    mov rax, [rbx + GPC_hashfold]
1:  mov rcx, [rbx + GPC_wcap]
    dec rcx
    and rax, rcx
    mov [rbx + GPC_probe], rax
    mov qword ptr [rbx + GPC_probes], 0
    mov qword ptr [rbx + GPC_fieldindex], 4
    jmp .Lpgp_again
.Lpgp_probe_begin:
    cmp qword ptr [rbx + GPC_probes], 512
    jae .Lpgp_policy_fail
    mov rdi, rbx
    mov rsi, [rbx + GPC_probe]
    mov edx, GPC_probeoffset
    call pg_word_record_begin
    test rax, rax
    js .Lpgc_exit
    inc qword ptr [rbx + GPC_probes]
    mov qword ptr [rbx + GPC_fieldindex], 5
.Lpgp_probe_read:
    mov rdi, rbx
    call pg_word_record_step
    test rax, rax
    js .Lpgc_exit
    jnz .Lpgc_pending
    inc qword ptr [rbx + GPC_units]
    mov rax, [rbx + GPC_probe]
    cmp rax, [rbx + GPC_wordindex]
    je .Lpgp_word_done
    cmp qword ptr [rbx + GPC_probeoffset], 0
    je .Lpgp_policy_fail
    mov rax, [rbx + GPC_probelength]
    cmp rax, [rbx + GPC_candidatelength]
    jne .Lpgp_probe_next
    mov rdi, rbx
    mov rsi, [rbx + GPC_probeoffset]
    mov rdx, rax
    call pg_word_extent
    test rax, rax
    js .Lpgc_exit
    mov qword ptr [rbx + GPC_comparecursor], 0
    mov qword ptr [rbx + GPC_comparestate], 0
    mov qword ptr [rbx + GPC_comparehave], 0
    mov qword ptr [rbx + GPC_fieldindex], 6
    jmp .Lpgp_again
.Lpgp_compare:
    mov rdi, rbx
    call pg_compare_step
    test rax, rax
    js .Lpgc_exit
    cmp rax, 1
    je .Lpgc_pending
    test rax, rax
    jz .Lpgp_policy_fail
.Lpgp_probe_next:
    mov rax, [rbx + GPC_probe]
    inc rax
    mov rcx, [rbx + GPC_wcap]
    dec rcx
    and rax, rcx
    mov [rbx + GPC_probe], rax
    mov qword ptr [rbx + GPC_fieldindex], 4
    jmp .Lpgp_again
.Lpgp_policy_fail:
    cmp qword ptr [rbx + GPC_policy], 0
    jne .Lpgc_bad
    test qword ptr [rbx + GPC_flags], GF_NOCASE
    jz .Lpgc_bad
    mov qword ptr [rbx + GPC_policy], 1
    mov qword ptr [rbx + GPC_fieldindex], 3
    jmp .Lpgp_again
.Lpgp_word_done:
    inc qword ptr [rbx + GPC_wordindex]
    mov qword ptr [rbx + GPC_fieldindex], 0
    jmp .Lpgp_again
.Lpgp_valid:
    mov qword ptr [rbx + GPC_state], GPC_VALID
    inc qword ptr [rbx + GPC_units]
    xor eax, eax
    EPILOGUE
.Lpgp_bad:
    mov rsi, -EV_BAD_GRAMMAR
    jmp pg_fail
