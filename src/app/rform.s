# form views (feature view-form): rows of fields an extension describes and the user fills in:
# text, multi-line area, number, check, select, button and static label fields. Fields with the
# same ROW share a line by WEIGHT; a label shows above an input, right of a check, on a button; a
# message under a field in its severity's color. The user owns a field's value: each field counts
# the user's edits (its sequence), and a "value SEQ" record replaces the value only when SEQ is the
# field's sequence (the extension saw the last edit); caret and selection stay the user's.
#
#   form N LEN + N field records   the whole form (values the user owns kept by KEY)
#   field LEN + one record         adds or updates that KEY
#   record: KEY TYPE ROW WEIGHT LABEL_LEN EXTRA_LEN LF LABEL EXTRA, EXTRA records value SEQ LEN,
#   placeholder LEN, options LEN (LF-separated), lines N 0, range MIN MAX STEP 0, msg SEVERITY LEN,
#   disabled 0, primary 0, mono 0, password 0
#
# Events: change REV KEY SEQ LEN + value, press REV KEY, submit REV KEY.
.include "rhun.inc"

.equ FM_FIELDS, 200
.equ FM_TEXT_MAX, 65536
.equ FM_AREA_MAX, 1048576
.equ FM_LABEL_MAX, 200
.equ FM_KEY_MAX, 64

.equ FT_TEXT, 1
.equ FT_AREA, 2
.equ FT_NUMBER, 3
.equ FT_CHECK, 4
.equ FT_SELECT, 5
.equ FT_BUTTON, 6
.equ FT_LABEL, 7

.equ FFF_DISABLED, 1
.equ FFF_PRIMARY, 2
.equ FFF_MONO, 4
.equ FFF_PASSWORD, 8
.equ FFF_RANGE, 16

.equ ID_FORM, 0x5d8000           # + slot << 8 + field: a field's widgets (a check, a select, a button)

# a field
STRUCT
F FF_key, 8             # owned cstr
F FF_label, 8           # owned cstr
F FF_ph, 8              # owned cstr or 0
F FF_opts, 8            # owned: the options, LF-separated, or 0
F FF_msg, 8             # owned cstr or 0
F FF_tf, TF_SIZE        # its text (text, area, number; a select's chosen option)
F FF_seq, 8             # the user's edits
F FF_min, 8             # a number's range, in millionths
F FF_max, 8
F FF_step, 8
F FF_type, 4            # FT_*
F FF_row, 4
F FF_weight, 4
F FF_lines, 4           # an area's height in lines
F FF_sev, 4             # its message's SEV_*
F FF_flags, 4           # FFF_*
F FF_on, 4              # a check's state
F FF_nopts, 4
F FF_x, 4               # its input as last drawn
F FF_y, 4
F FF_w, 4
F FF_h, 4
F FF_mark, 4            # listed by the form op being applied
F FF_pad, 4
ENDSTRUCT FF_SIZE

# a form
STRUCT
F FM_fields, 8          # FF * FM_FIELDS
F FM_n, 4
F FM_focus, 4           # the field with the keyboard, -1
F FM_scroll, 4
F FM_slot, 4            # its instance
F FM_contenth, 4
F FM_pad, 4
ENDSTRUCT FM_SIZE

.bss
.p2align 3
rr_f: .zero RR_SIZE
evb: .zero SB_SIZE
tsb: .zero SB_SIZE
rec_key: .quad 0                # a field record being read: its parts
rec_keylen: .quad 0
rec_type: .long 0
rec_row: .long 0
rec_weight: .long 0
rec_pad: .long 0
rec_label: .quad 0
rec_labellen: .quad 0
rec_extra: .quad 0
rec_extralen: .quad 0
rec_end: .quad 0
rec_starts: .zero 8 * 6
rec_lens: .zero 8 * 6
menu_form: .quad 0              # the select whose options a menu shows: its form and field
menu_field: .long 0
.p2align 3
menu_items: .zero 16 * 33
row_vals: .zero 4 * FM_FIELDS   # layout: the distinct rows, sorted
order: .zero 4 * FM_FIELDS      # display order of the fields

.data
tf_ids: .long 0x6e0000          # text fields' ids (caret identity)

.text

# fm_ff(FM*, i) -> rax FF*
fm_ff:
    imul rax, rsi, FF_SIZE
    add rax, [rdi + FM_fields]
    ret

# form_new(slot) -> rax a form (no fields)
FN form_new
    PROLOGUE
    mov ebx, edi
    mov edi, FM_SIZE
    call mem_alloc
    mov r12, rax
    mov rdi, r12
    xor esi, esi
    mov edx, FM_SIZE
    call memset
    mov [r12 + FM_slot], ebx
    mov dword ptr [r12 + FM_focus], -1
    mov edi, FF_SIZE * FM_FIELDS
    call mem_alloc
    mov [r12 + FM_fields], rax
    mov rax, r12
    EPILOGUE

# ff_free(FF*): its strings and text
ff_free:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + FF_key]
    call mem_free
    mov rdi, [rbx + FF_label]
    call mem_free
    mov rdi, [rbx + FF_ph]
    call mem_free
    mov rdi, [rbx + FF_opts]
    call mem_free
    mov rdi, [rbx + FF_msg]
    call mem_free
    lea rdi, [rbx + FF_tf + TF_sb]
    call sb_free
    EPILOGUE

# form_free(FM*)
FN form_free
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  cmp r12d, [rbx + FM_n]
    jae 2f
    mov rdi, rbx
    mov esi, r12d
    call fm_ff
    mov rdi, rax
    call ff_free
    inc r12d
    jmp 1b
2:  mov rdi, [rbx + FM_fields]
    call mem_free
    mov rdi, rbx
    call mem_free
9:  EPILOGUE

# ---------------- records ----------------

# read_record(p, end) -> rax past it, 0 when it is not one: its parts in rec_*
read_record:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14, r12                # the header: up to its LF
1:  cmp r14, r13
    jae 8f
    cmp byte ptr [r14], 10
    je 2f
    inc r14
    jmp 1b
2:  # six fields, one space apart
    xor ebx, ebx
    mov r15, r12
3:  cmp r15, r14
    jae 8f
    mov rcx, r15
4:  cmp rcx, r14
    jae 41f
    cmp byte ptr [rcx], ' '
    je 41f
    inc rcx
    jmp 4b
41: cmp rcx, r15
    je 8f
    lea rax, [rip + rec_starts]
    mov [rax + rbx*8], r15
    mov rdx, rcx
    sub rdx, r15
    lea rax, [rip + rec_lens]
    mov [rax + rbx*8], rdx
    mov r15, rcx
    inc ebx
    cmp ebx, 6
    je 5f
    cmp r15, r14
    jae 8f
    inc r15                     # the space
    jmp 3b
5:  cmp r15, r14
    jne 8f                      # more than six
    mov rax, [rip + rec_starts]
    mov [rip + rec_key], rax
    mov rcx, [rip + rec_lens]
    mov [rip + rec_keylen], rcx
    cmp rcx, FM_KEY_MAX
    ja 8f
    xor edx, edx                # KEY: [A-Za-z0-9_.-]
51: cmp rdx, rcx
    jae 52f
    movzx eax, byte ptr [r12 + rdx]
    lea r8, [rip + key_chars]
    cmp byte ptr [r8 + rax], 0
    je 8f
    inc rdx
    jmp 51b
52: mov rdi, [rip + rec_starts + 8]     # TYPE
    mov rsi, [rip + rec_lens + 8]
    lea rdx, [rip + type_words]
    call word_of
    test eax, eax
    jz 8f
    mov [rip + rec_type], eax
    mov edi, 2                  # ROW 1-200
    call rec_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 200
    ja 8f
    mov [rip + rec_row], eax
    mov edi, 3                  # WEIGHT 1-12
    call rec_num
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, 12
    ja 8f
    mov [rip + rec_weight], eax
    mov edi, 4
    call rec_num
    test edx, edx
    jz 8f
    cmp rax, FM_LABEL_MAX
    ja 8f
    mov [rip + rec_labellen], rax
    mov edi, 5
    call rec_num
    test edx, edx
    jz 8f
    mov [rip + rec_extralen], rax
    lea rcx, [r14 + 1]
    mov [rip + rec_label], rcx
    add rcx, [rip + rec_labellen]
    mov [rip + rec_extra], rcx
    add rcx, [rip + rec_extralen]
    cmp rcx, r13
    ja 8f
    mov [rip + rec_end], rcx
    mov rdi, [rip + rec_label]  # the label is one line
    mov rcx, [rip + rec_labellen]
    xor edx, edx
6:  cmp rdx, rcx
    jae 7f
    cmp byte ptr [rdi + rdx], 10
    je 8f
    inc rdx
    jmp 6b
7:  mov rax, [rip + rec_end]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# rec_num(i) -> rax the record header's field i as a number, edx 1 when all of it is digits
rec_num:
    push rbx
    mov ebx, edi
    lea rax, [rip + rec_starts]
    mov rdi, [rax + rbx*8]
    lea rax, [rip + rec_lens]
    mov rsi, [rax + rbx*8]
    call parse_u64
    lea rcx, [rip + rec_lens]
    cmp rdx, [rcx + rbx*8]
    jne 8f
    mov edx, 1
    pop rbx
    ret
8:  xor edx, edx
    pop rbx
    ret

# word_of(ptr, len, table of cstrs 0-ended) -> eax its index + 1, 0 when none
word_of:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
1:  mov rdx, [r14 + rbx*8]
    test rdx, rdx
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc ebx
    jmp 1b
2:  lea eax, [rbx + 1]
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# extra_check() -> eax 1 when rec_extra holds well-formed records within the limits (2: a value
#   over its cap)
extra_check:
    PROLOGUE
    mov r12, [rip + rec_extra]
    mov r13, r12
    add r13, [rip + rec_extralen]
1:  cmp r12, r13
    jae 7f
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + rr_f]
    call tree_rec_read
    test rax, rax
    jz 8f
    mov r12, rax
    lea rdi, [rip + rr_f]
    xor esi, esi
    lea rdx, [rip + .Lx_value]
    call tree_rec_is
    test eax, eax
    jz 1b
    mov ecx, FM_TEXT_MAX        # a value: within its type's cap
    cmp dword ptr [rip + rec_type], FT_AREA
    jne 2f
    mov ecx, FM_AREA_MAX
2:  cmp [rip + rr_f + RR_len], rcx
    ja 6f
    jmp 1b
6:  mov eax, 2
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# form_check(FM*, data, len, n or -1 for a field op) -> eax 0, 1 a syntax error, 2 toobig
FN form_check
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    mov r14d, ecx
    xor r15d, r15d              # records
1:  cmp r12, r13
    jae 3f
    mov rdi, r12
    mov rsi, r13
    call read_record
    test rax, rax
    jz 8f
    mov r12, rax
    call extra_check
    test eax, eax
    jz 8f
    cmp eax, 2
    je 7f
    inc r15d
    cmp r14d, -1
    jne 1b
    cmp r12, r13                # a field op: one record exactly
    jne 8f
3:  cmp r14d, -1
    je 4f
    cmp r15d, r14d
    jne 8f
    cmp r15d, FM_FIELDS
    ja 7f
    xor eax, eax
    EPILOGUE
4:  cmp r15d, 1
    jne 8f
    # a new key on a full form: too many
    mov rdi, rbx
    mov rsi, [rip + rec_key]
    mov rdx, [rip + rec_keylen]
    call field_find
    cmp eax, -1
    jne 5f
    cmp dword ptr [rbx + FM_n], FM_FIELDS
    jae 7f
5:  xor eax, eax
    EPILOGUE
7:  mov eax, 2
    EPILOGUE
8:  mov eax, 1
    EPILOGUE

# field_find(FM*, key, len) -> eax its index, or -1
field_find:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14d, [rbx + FM_n]
    jae 8f
    mov rdi, rbx
    mov esi, r14d
    call fm_ff
    mov r15, rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r15 + FF_key]
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc r14d
    jmp 1b
2:  mov eax, r14d
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# form_apply(FM*, data, len, n or -1): the records (form_check passed); a form op drops the fields
#   it does not list and keeps its order
FN form_apply
    PROLOGUE 16
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rsi + rdx]
    mov r14d, ecx
    cmp r14d, -1
    je 1f
    xor ecx, ecx                # nothing listed yet
0:  cmp ecx, [rbx + FM_n]
    jae 1f
    mov rdi, rbx
    mov esi, ecx
    push rcx
    push rcx
    call fm_ff
    pop rcx
    pop rcx
    mov dword ptr [rax + FF_mark], 0
    inc ecx
    jmp 0b
1:  xor r15d, r15d              # the place in a form op's order
2:  cmp r12, r13
    jae 5f
    mov rdi, r12
    mov rsi, r13
    call read_record
    test rax, rax
    jz 5f
    mov r12, rax
    mov rdi, rbx
    call apply_record           # -> eax the field's index
    cmp r14d, -1
    je 2b
    # a form op: in its place in the order
    mov ecx, eax
    cmp ecx, r15d
    je 3f
    mov rdi, rbx
    mov esi, ecx
    mov edx, r15d
    call field_swap
3:  mov rdi, rbx
    mov esi, r15d
    call fm_ff
    mov dword ptr [rax + FF_mark], 1
    inc r15d
    jmp 2b
5:  cmp r14d, -1
    je 9f
    # the fields not listed go (they are past the listed ones now)
6:  mov eax, [rbx + FM_n]
    cmp eax, r15d
    jbe 9f
    dec eax
    mov [rbx + FM_n], eax
    mov rdi, rbx
    mov esi, eax
    call fm_ff
    mov rdi, rax
    call ff_free
    jmp 6b
9:  mov eax, [rbx + FM_focus]   # the keyboard's field still there
    cmp eax, [rbx + FM_n]
    jb 91f
    mov dword ptr [rbx + FM_focus], -1
91: mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# field_swap(FM*, i, j): two fields change places
field_swap:
    PROLOGUE FF_SIZE + 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov rdi, rbx
    mov esi, r12d
    call fm_ff
    mov r14, rax
    mov rdi, rbx
    mov esi, r13d
    call fm_ff
    mov r15, rax
    mov rdi, rsp
    mov rsi, r14
    mov edx, FF_SIZE
    call memcpy
    mov rdi, r14
    mov rsi, r15
    mov edx, FF_SIZE
    call memcpy
    mov rdi, r15
    mov rsi, rsp
    mov edx, FF_SIZE
    call memcpy
    mov eax, [rbx + FM_focus]   # the keyboard follows its field
    cmp eax, r12d
    jne 1f
    mov [rbx + FM_focus], r13d
    jmp 9f
1:  cmp eax, r13d
    jne 9f
    mov [rbx + FM_focus], r12d
9:  EPILOGUE

# apply_record(FM*) -> eax the field's index: rec_* into a new or the existing field of its KEY
apply_record:
    PROLOGUE 32
    mov rbx, rdi
    mov rdi, rbx
    mov rsi, [rip + rec_key]
    mov rdx, [rip + rec_keylen]
    call field_find
    mov dword ptr [rsp + 8], 0  # new
    cmp eax, -1
    jne 1f
    mov eax, [rbx + FM_n]
    inc dword ptr [rbx + FM_n]
    mov [rsp], eax
    mov rdi, rbx
    mov esi, eax
    call fm_ff
    mov r12, rax
    mov rdi, r12
    xor esi, esi
    mov edx, FF_SIZE
    call memset
    mov rdi, [rip + rec_key]
    mov rsi, [rip + rec_keylen]
    call mem_dup
    mov [r12 + FF_key], rax
    inc dword ptr [rip + tf_ids]
    mov eax, [rip + tf_ids]
    mov [r12 + FF_tf + TF_id], eax
    mov dword ptr [r12 + FF_tf + TF_prefx], -1
    mov dword ptr [r12 + FF_lines], 4
    mov dword ptr [rsp + 8], 1
    jmp 2f
1:  mov [rsp], eax
    mov rdi, rbx
    mov esi, eax
    call fm_ff
    mov r12, rax
    mov eax, [rip + rec_type]   # another type: its value starts again
    cmp eax, [r12 + FF_type]
    je 2f
    lea rdi, [r12 + FF_tf]
    call tf_clear
    mov qword ptr [r12 + FF_seq], 0
    mov dword ptr [r12 + FF_on], 0
    mov dword ptr [rsp + 8], 1
2:  mov eax, [rip + rec_type]
    mov [r12 + FF_type], eax
    mov eax, [rip + rec_row]
    mov [r12 + FF_row], eax
    mov eax, [rip + rec_weight]
    mov [r12 + FF_weight], eax
    mov rdi, [r12 + FF_label]
    call mem_free
    mov rdi, [rip + rec_label]
    mov rsi, [rip + rec_labellen]
    call mem_dup
    mov [r12 + FF_label], rax
    # the records: flags and message start over each time; the value by its sequence
    and dword ptr [r12 + FF_flags], 0
    mov rdi, [r12 + FF_msg]
    call mem_free
    mov qword ptr [r12 + FF_msg], 0
    mov r13, [rip + rec_extra]
    mov r14, r13
    add r14, [rip + rec_extralen]
.Lar_rec:
    cmp r13, r14
    jae .Lar_done
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + rr_f]
    call tree_rec_read
    test rax, rax
    jz .Lar_done
    mov r13, rax
    mov rdi, [rip + rr_f]       # its name
    mov rsi, [rip + rr_f + 8]
    lea rdx, [rip + extra_words]
    call word_of
    lea rcx, [rip + extra_fns]
    test eax, eax
    jz .Lar_rec
    mov rdi, r12
    mov esi, [rsp + 8]
    call [rcx + rax*8 - 8]
    jmp .Lar_rec
.Lar_done:
    mov eax, [rsp]
    EPILOGUE

# the extra records' appliers: (FF*, new)

x_value:
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    # SEQ: "-" or a number; it applies at creation or when it is the field's sequence
    xor r13d, r13d
    lea rdi, [rip + rr_f]
    mov esi, 1
    lea rdx, [rip + .Ldash]
    call tree_rec_is
    test eax, eax
    jnz 1f
    lea rdi, [rip + rr_f]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 9f
    mov r13, rax
1:  test r12d, r12d
    jnz 2f
    cmp r13, [rbx + FF_seq]
    jne 9f
2:  cmp dword ptr [rbx + FF_type], FT_CHECK
    jne 3f
    mov rdi, [rip + rr_f + RR_data]
    mov rsi, [rip + rr_f + RR_len]
    lea rdx, [rip + .Lyes]
    call str_eq_cstr
    mov [rbx + FF_on], eax
    jmp 9f
3:  # the text; the caret and selection stay where they were (within it)
    mov r14, [rbx + FF_tf + TF_cur]
    mov r15, [rbx + FF_tf + TF_anchor]
    lea rdi, [rbx + FF_tf]
    mov rsi, [rip + rr_f + RR_data]
    mov rdx, [rip + rr_f + RR_len]
    call tf_set
    test r12d, r12d
    jnz 9f
    mov rax, [rip + rr_f + RR_len]
    cmp r14, rax
    cmova r14, rax
    cmp r15, rax
    cmova r15, rax
    mov [rbx + FF_tf + TF_cur], r14
    mov [rbx + FF_tf + TF_anchor], r15
9:  EPILOGUE

x_placeholder:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + FF_ph]
    call mem_free
    mov rdi, [rip + rr_f + RR_data]
    mov rsi, [rip + rr_f + RR_len]
    call mem_dup
    mov [rbx + FF_ph], rax
    EPILOGUE

x_options:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + FF_opts]
    call mem_free
    mov rdi, [rip + rr_f + RR_data]
    mov rsi, [rip + rr_f + RR_len]
    call mem_dup
    mov [rbx + FF_opts], rax
    xor ecx, ecx                # how many
    mov rdx, [rip + rr_f + RR_len]
    test rdx, rdx
    jz 2f
    mov ecx, 1
    xor r8d, r8d
1:  cmp r8, rdx
    jae 2f
    cmp byte ptr [rax + r8], 10
    jne 11f
    inc ecx
11: inc r8
    jmp 1b
2:  mov [rbx + FF_nopts], ecx
    EPILOGUE

x_lines:
    push rbx
    mov rbx, rdi
    lea rdi, [rip + rr_f]
    mov esi, 1
    call tree_rec_num
    test edx, edx
    jz 9f
    test eax, eax
    jz 9f
    cmp eax, 30
    jbe 1f
    mov eax, 30
1:  mov [rbx + FF_lines], eax
9:  pop rbx
    ret

x_range:
    PROLOGUE
    mov rbx, rdi
    lea rdi, [rip + rr_f]
    mov esi, 1
    call field_milli
    test edx, edx
    jz 9f
    mov r12, rax
    lea rdi, [rip + rr_f]
    mov esi, 2
    call field_milli
    test edx, edx
    jz 9f
    mov r13, rax
    lea rdi, [rip + rr_f]
    mov esi, 3
    call field_milli
    test edx, edx
    jz 9f
    test rax, rax
    jle 9f
    mov [rbx + FF_min], r12
    mov [rbx + FF_max], r13
    mov [rbx + FF_step], rax
    or dword ptr [rbx + FF_flags], FFF_RANGE
9:  EPILOGUE

x_msg:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + FF_msg]
    call mem_free
    mov qword ptr [rbx + FF_msg], 0
    lea rdi, [rip + rr_f]
    mov esi, 1
    lea rdx, [rip + .Lerror]
    call tree_rec_is
    mov r12d, SEV_ERROR
    test eax, eax
    jnz 1f
    lea rdi, [rip + rr_f]
    mov esi, 1
    lea rdx, [rip + .Lwarning]
    call tree_rec_is
    mov r12d, SEV_WARNING
    test eax, eax
    jnz 1f
    mov r12d, SEV_INFO
1:  mov [rbx + FF_sev], r12d
    cmp qword ptr [rip + rr_f + RR_len], 0
    je 9f
    mov rdi, [rip + rr_f + RR_len]
    mov rsi, [rip + rr_f + RR_data]
    mov edx, 1000
    call utf8_cut
    mov rsi, rax
    mov rdi, [rip + rr_f + RR_data]
    call mem_dup
    mov [rbx + FF_msg], rax
9:  EPILOGUE

x_disabled:
    or dword ptr [rdi + FF_flags], FFF_DISABLED
    ret
x_primary:
    or dword ptr [rdi + FF_flags], FFF_PRIMARY
    ret
x_mono:
    or dword ptr [rdi + FF_flags], FFF_MONO
    ret
x_password:
    or dword ptr [rdi + FF_flags], FFF_PASSWORD
    ret

# field_milli(rr, i) -> rax the field as millionths ("-12.5" -> -12500000), edx 1 when it reads
field_milli:
    PROLOGUE
    mov eax, esi
    shl eax, 4
    mov r12, [rdi + rax]        # ptr
    mov r13, [rdi + rax + 8]    # len
    mov rdi, r12
    mov rsi, r13
    call parse_milli
    EPILOGUE

# parse_milli(ptr, len) -> rax millionths, edx 1 when it is [-]digits[.digits] (6 decimals kept)
FN parse_milli
    xor eax, eax
    xor edx, edx
    xor r8d, r8d                # negative
    xor r9d, r9d                # digits seen
    xor r10d, r10d              # decimals
    mov r11d, -1                # in the fraction: -1 no
    xor ecx, ecx
    test rsi, rsi
    jz 8f
    cmp byte ptr [rdi], '-'
    jne 1f
    mov r8d, 1
    inc ecx
1:  cmp rcx, rsi
    jae 5f
    movzx edx, byte ptr [rdi + rcx]
    cmp edx, '.'
    jne 2f
    cmp r11d, -1
    jne 8f
    xor r11d, r11d
    inc ecx
    jmp 1b
2:  sub edx, '0'
    cmp edx, 9
    ja 8f
    inc r9d
    cmp r11d, -1
    je 3f
    cmp r10d, 6
    jae 4f                      # past six decimals: dropped
    inc r10d
3:  imul rax, rax, 10
    add rax, rdx
    mov rdx, 100000000000000
    cmp rax, rdx
    ja 8f
4:  inc ecx
    jmp 1b
5:  test r9d, r9d
    jz 8f
6:  cmp r10d, 6
    jae 7f
    imul rax, rax, 10
    inc r10d
    jmp 6b
7:  test r8d, r8d
    jz 71f
    neg rax
71: mov edx, 1
    ret
8:  xor eax, eax
    xor edx, edx
    ret

# fmt_milli(sb, millionths): as text, decimals only as many as it needs
fmt_milli:
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jns 1f
    mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
    neg r12
1:  mov rax, r12
    xor edx, edx
    mov ecx, 1000000
    div rcx
    mov r13, rdx                # the fraction
    mov rdi, rbx
    mov rsi, rax
    call sb_push_u64
    test r13, r13
    jz 9f
    mov rdi, rbx
    mov esi, '.'
    call sb_push_byte
    mov ecx, 100000             # six digits, trailing zeros off
2:  test r13, r13
    jz 9f
    mov rax, r13
    xor edx, edx
    div rcx
    mov r13, rdx
    push rcx
    push rcx
    lea esi, [rax + '0']
    mov rdi, rbx
    call sb_push_byte
    pop rcx
    pop rcx
    mov rax, rcx
    xor edx, edx
    mov ecx, 10
    div rcx
    mov rcx, rax
    test rcx, rcx
    jnz 2b
9:  EPILOGUE

# ---------------- layout and drawing ----------------

# sort_order(FM*): the fields by row, in their order within a row (order[], FM_n of them)
sort_order:
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12d, [rbx + FM_n]
    jae 9f
    mov rdi, rbx
    mov esi, r12d
    call fm_ff
    mov r13d, [rax + FF_row]
    mov r14d, r12d              # insertion: past every field with a row not above its own
2:  test r14d, r14d
    jz 3f
    lea rax, [rip + order]
    mov esi, [rax + r14*4 - 4]
    mov rdi, rbx
    call fm_ff
    cmp [rax + FF_row], r13d
    jbe 3f
    lea rax, [rip + order]
    mov ecx, [rax + r14*4 - 4]
    mov [rax + r14*4], ecx
    dec r14d
    jmp 2b
3:  lea rax, [rip + order]
    mov [rax + r14*4], r12d
    inc r12d
    jmp 1b
9:  EPILOGUE

# focusable(FF*) -> eax 1 for a field that takes the keyboard (not a label, not disabled)
focusable:
    xor eax, eax
    cmp dword ptr [rdi + FF_type], FT_LABEL
    je 9f
    test dword ptr [rdi + FF_flags], FFF_DISABLED
    jnz 9f
    mov eax, 1
9:  ret

# has_label_above(FF*) -> eax 1 for an input whose label shows above it
has_label_above:
    xor eax, eax
    mov ecx, [rdi + FF_type]
    cmp ecx, FT_CHECK
    je 9f
    cmp ecx, FT_BUTTON
    je 9f
    cmp ecx, FT_LABEL
    je 9f
    mov rcx, [rdi + FF_label]
    test rcx, rcx
    jz 9f
    cmp byte ptr [rcx], 0
    je 9f
    mov eax, 1
9:  ret

# input_h(FF*) -> eax its input's height
input_h:
    push rbx
    mov rbx, rdi
    M eax, MI_28
    cmp dword ptr [rbx + FF_type], FT_AREA
    jne 1f
    call ta_line_h
    imul eax, [rbx + FF_lines]
    add eax, [rip + g_mt + 4*MI_12]
    jmp 9f
1:  cmp dword ptr [rbx + FF_type], FT_CHECK
    jne 2f
    M eax, MI_24
    jmp 9f
2:  cmp dword ptr [rbx + FF_type], FT_LABEL
    jne 9f
    mov eax, [rip + g_face_ui + FACE_lineh]
9:  pop rbx
    ret

# field_h(FF*) -> eax its whole height: label above, input, message under
field_h:
    PROLOGUE
    mov rbx, rdi
    call input_h
    mov r12d, eax
    mov rdi, rbx
    call has_label_above
    test eax, eax
    jz 1f
    add r12d, [rip + g_face_small + FACE_lineh]
    add r12d, [rip + g_mt + 4*MI_4]
1:  cmp qword ptr [rbx + FF_msg], 0
    je 2f
    add r12d, [rip + g_face_small + FACE_lineh]
    add r12d, [rip + g_mt + 4*MI_2]
2:  mov eax, r12d
    EPILOGUE

# form_draw(FM*, x, y, w, h, focused): its rows of fields, the wheel scrolls them
FN form_draw
    PROLOGUE 96
    mov rbx, rdi
    mov [rsp], esi              # x
    mov [rsp + 4], edx          # y
    mov [rsp + 8], ecx          # w
    mov [rsp + 12], r8d         # h
    mov [rsp + 16], r9d         # focused
    mov rdi, rbx
    call sort_order
    # the content's height: rows one after another
    M eax, MI_12
    mov [rsp + 20], eax         # running height
    xor r12d, r12d              # place in order
.Lfd_hrow:
    cmp r12d, [rbx + FM_n]
    jae .Lfd_hdone
    lea rax, [rip + order]
    mov esi, [rax + r12*4]
    mov rdi, rbx
    call fm_ff
    mov r13d, [rax + FF_row]
    xor r14d, r14d              # the row's height
1:  cmp r12d, [rbx + FM_n]
    jae 2f
    lea rax, [rip + order]
    mov esi, [rax + r12*4]
    mov rdi, rbx
    call fm_ff
    cmp [rax + FF_row], r13d
    jne 2f
    mov rdi, rax
    call field_h
    cmp eax, r14d
    cmovl eax, r14d
    mov r14d, eax
    inc r12d
    jmp 1b
2:  add r14d, [rip + g_mt + 4*MI_12]
    add [rsp + 20], r14d
    jmp .Lfd_hrow
.Lfd_hdone:
    mov eax, [rsp + 20]
    mov [rbx + FM_contenth], eax
    # the wheel over it, within the content
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call ui_in
    test eax, eax
    jz 3f
    mov eax, [rip + g_scroll_y]
    add [rbx + FM_scroll], eax
3:  mov eax, [rbx + FM_contenth]
    sub eax, [rsp + 12]
    xor ecx, ecx
    cmp eax, ecx
    cmovl eax, ecx
    cmp [rbx + FM_scroll], eax
    jle 4f
    mov [rbx + FM_scroll], eax
4:  cmp dword ptr [rbx + FM_scroll], 0
    jge 5f
    mov dword ptr [rbx + FM_scroll], 0
5:  mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_clip_push
    mov eax, [rsp + 4]
    add eax, [rip + g_mt + 4*MI_12]
    sub eax, [rbx + FM_scroll]
    mov [rsp + 24], eax         # the row's top
    xor r12d, r12d
.Lfd_row:
    cmp r12d, [rbx + FM_n]
    jae .Lfd_done
    # the row: its fields, their weights, its height
    lea rax, [rip + order]
    mov esi, [rax + r12*4]
    mov rdi, rbx
    call fm_ff
    mov r13d, [rax + FF_row]
    mov [rsp + 28], r12d        # its first
    xor r14d, r14d              # weights
    xor r15d, r15d              # height
    mov dword ptr [rsp + 32], 0 # count
6:  cmp r12d, [rbx + FM_n]
    jae 7f
    lea rax, [rip + order]
    mov esi, [rax + r12*4]
    mov rdi, rbx
    call fm_ff
    cmp [rax + FF_row], r13d
    jne 7f
    add r14d, [rax + FF_weight]
    mov rdi, rax
    call field_h
    cmp eax, r15d
    cmovl eax, r15d
    mov r15d, eax
    inc dword ptr [rsp + 32]
    inc r12d
    jmp 6b
7:  mov [rsp + 36], r15d        # its height
    # the room for the fields: the width less the margins and the gaps between them
    mov eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_24]
    mov ecx, [rsp + 32]
    dec ecx
    imul ecx, [rip + g_mt + 4*MI_12]
    sub eax, ecx
    mov [rsp + 40], eax         # room
    mov eax, [rsp]
    add eax, [rip + g_mt + 4*MI_12]
    mov [rsp + 44], eax         # x
    mov ecx, [rsp + 28]
.Lfd_field:
    cmp ecx, r12d
    jae .Lfd_rownext
    mov [rsp + 48], ecx
    lea rax, [rip + order]
    mov esi, [rax + rcx*4]
    mov [rsp + 52], esi         # its index
    mov rdi, rbx
    call fm_ff
    mov r13, rax
    mov eax, [rsp + 40]         # its width: its share of the room
    imul eax, [r13 + FF_weight]
    xor edx, edx
    div r14d
    mov [rsp + 56], eax
    mov rdi, rbx
    mov rsi, r13
    mov edx, [rsp + 44]
    mov ecx, [rsp + 24]
    mov r8d, eax
    mov r9d, [rsp + 52]
    mov eax, [rsp + 16]
    push rax
    push rax
    call field_draw
    add rsp, 16
    mov eax, [rsp + 56]
    add eax, [rip + g_mt + 4*MI_12]
    add [rsp + 44], eax
    mov ecx, [rsp + 48]
    inc ecx
    jmp .Lfd_field
.Lfd_rownext:
    mov eax, [rsp + 36]
    add eax, [rip + g_mt + 4*MI_12]
    add [rsp + 24], eax
    jmp .Lfd_row
.Lfd_done:
    call gfx_clip_pop
    EPILOGUE

# field_draw(FM*, FF*, x, y, w, index, [stack] form focused): one field
field_draw:
    PROLOGUE 64
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx              # x
    mov [rsp + 4], ecx          # y
    mov [rsp + 8], r8d          # w
    mov [rsp + 12], r9d         # index
    mov eax, [rbp + 16]
    xor ecx, ecx
    test eax, eax
    jz 1f
    cmp r9d, [rbx + FM_focus]
    sete cl
1:  mov [rsp + 16], ecx         # this one has the keyboard
    COLOR eax, T_FG
    test dword ptr [r12 + FF_flags], FFF_DISABLED
    jz 2f
    COLOR eax, T_MUTED
2:  mov [rsp + 20], eax         # its text color
    # the label above
    mov rdi, r12
    call has_label_above
    test eax, eax
    jz 3f
    mov rdi, [r12 + FF_label]
    call strlen
    mov r9, rax
    mov eax, [rsp + 8]
    COLOR ecx, T_MUTED
    push rax
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rip + g_face_small + FACE_lineh]
    mov r8, [r12 + FF_label]
    call ui_text_v_fit
    add rsp, 16
    mov eax, [rip + g_face_small + FACE_lineh]
    add eax, [rip + g_mt + 4*MI_4]
    add [rsp + 4], eax
3:  mov rdi, r12
    call input_h
    mov [rsp + 24], eax         # the input's height
    mov eax, [rsp]
    mov [r12 + FF_x], eax
    mov eax, [rsp + 4]
    mov [r12 + FF_y], eax
    mov eax, [rsp + 8]
    mov [r12 + FF_w], eax
    mov eax, [rsp + 24]
    mov [r12 + FF_h], eax
    mov eax, [rsp + 12]         # its widgets' id
    mov ecx, [rbx + FM_slot]
    shl ecx, 8
    add eax, ecx
    add eax, ID_FORM
    mov [rsp + 28], eax
    mov eax, [r12 + FF_type]
    cmp eax, FT_TEXT
    je .Lfw_text
    cmp eax, FT_NUMBER
    je .Lfw_text
    cmp eax, FT_AREA
    je .Lfw_area
    cmp eax, FT_CHECK
    je .Lfw_check
    cmp eax, FT_SELECT
    je .Lfw_select
    cmp eax, FT_BUTTON
    je .Lfw_button
    # a label: its text
    mov rdi, [r12 + FF_label]
    call strlen
    mov r9, rax
    mov eax, [rsp + 8]
    mov ecx, [rsp + 20]
    push rax
    push rcx
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 24]
    mov r8, [r12 + FF_label]
    call ui_text_v_fit
    add rsp, 16
    jmp .Lfw_msg
.Lfw_text:
    mov rax, [r12 + FF_ph]
    test rax, rax
    jnz 4f
    lea rax, [rip + .Lempty]
4:  push rax
    push rax
    lea rdi, [r12 + FF_tf]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 8]
    mov r8d, [rsp + 16 + 24]
    mov r9d, [rsp + 16 + 16]
    call ui_textfield
    add rsp, 16
    jmp .Lfw_pressed
.Lfw_area:
    mov rax, [r12 + FF_ph]
    test rax, rax
    jnz 5f
    lea rax, [rip + .Lempty]
5:  push rax
    push rax
    lea rdi, [r12 + FF_tf]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 8]
    mov r8d, [rsp + 16 + 24]
    mov r9d, [rsp + 16 + 16]
    call ui_textarea
    add rsp, 16
.Lfw_pressed:
    test eax, UB_PRESS
    jz .Lfw_msg
    test dword ptr [r12 + FF_flags], FFF_DISABLED
    jnz .Lfw_msg
    mov eax, [rsp + 12]
    mov [rbx + FM_focus], eax
    jmp .Lfw_msg
.Lfw_check:
    # a box (checked: the check mark), its label right of it; a click toggles it
    mov rdi, [r12 + FF_label]
    call strlen
    mov [rsp + 48], rax
    lea rdi, [rip + g_face_ui]
    mov rsi, [r12 + FF_label]
    mov rdx, rax
    call text_width
    add eax, [rip + g_mt + 4*MI_24]
    mov ecx, [rsp + 8]
    cmp eax, ecx
    cmovg eax, ecx
    mov [rsp + 36], eax
    mov edi, [rsp + 28]         # the whole field takes the click
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 24]
    call ui_btn
    mov [rsp + 40], eax
    M ecx, MI_16
    mov edi, [rsp]
    mov esi, [rsp + 24]
    sub esi, ecx
    sar esi, 1
    add esi, [rsp + 4]
    mov [rsp + 44], esi
    mov edx, ecx
    M r8d, MI_3
    COLOR r9d, T_BORDER
    cmp dword ptr [rsp + 16], 0
    je 6f
    COLOR r9d, T_ACCENT
6:  COLOR eax, T_INPUT
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    cmp dword ptr [r12 + FF_on], 0
    je 7f
    mov edi, IC_CHECK
    mov esi, [rsp]
    mov edx, [rsp + 44]
    M ecx, MI_16
    COLOR r8d, T_ACCENT
    call icon_draw
7:  mov eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_24]
    mov ecx, [rsp + 20]
    push rax
    push rcx
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    add esi, [rip + g_mt + 4*MI_24]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 24]
    mov r8, [r12 + FF_label]
    mov r9, [rsp + 16 + 48]
    call ui_text_v_fit
    add rsp, 16
    test dword ptr [r12 + FF_flags], FFF_DISABLED
    jnz .Lfw_msg
    test dword ptr [rsp + 40], UB_PRESS
    jz 8f
    mov eax, [rsp + 12]
    mov [rbx + FM_focus], eax
8:  test dword ptr [rsp + 40], UB_CLICK
    jz .Lfw_msg
    mov rdi, rbx
    mov esi, [rsp + 12]
    call check_toggle
    jmp .Lfw_msg
.Lfw_select:
    # a box with the chosen option and a chevron; a click opens the options
    mov edi, [rsp + 28]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 24]
    call ui_btn
    mov [rsp + 40], eax
    mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 24]
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    cmp dword ptr [rsp + 16], 0
    je 9f
    COLOR r9d, T_ACCENT
9:  COLOR eax, T_INPUT
    push rax
    push rax
    call gfx_frame
    add rsp, 16
    mov eax, [rsp + 8]
    sub eax, [rip + g_mt + 4*MI_32]
    mov ecx, [rsp + 20]
    push rax
    push rcx
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    add esi, [rip + g_mt + 4*MI_8]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 24]
    mov r8, [r12 + FF_tf + TF_sb + SB_ptr]
    mov r9, [r12 + FF_tf + TF_sb + SB_len]
    call ui_text_v_fit
    add rsp, 16
    mov edi, IC_CHEV_D
    mov esi, [rsp]
    add esi, [rsp + 8]
    sub esi, [rip + g_mt + 4*MI_24]
    M ecx, MI_16
    mov edx, [rsp + 24]
    sub edx, ecx
    sar edx, 1
    add edx, [rsp + 4]
    COLOR r8d, T_MUTED
    call icon_draw
    test dword ptr [r12 + FF_flags], FFF_DISABLED
    jnz .Lfw_msg
    test dword ptr [rsp + 40], UB_PRESS
    jz 10f
    mov eax, [rsp + 12]
    mov [rbx + FM_focus], eax
10: test dword ptr [rsp + 40], UB_CLICK
    jz .Lfw_msg
    mov rdi, rbx
    mov esi, [rsp + 12]
    call select_open
    jmp .Lfw_msg
.Lfw_button:
    mov edi, [rsp + 28]
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov ecx, [rsp + 8]
    mov r8d, [rsp + 24]
    call ui_btn
    mov [rsp + 40], eax
    COLOR r9d, T_INPUT
    test dword ptr [rsp + 40], UB_HOVER
    jz 11f
    COLOR r9d, T_HOVER
11: test dword ptr [r12 + FF_flags], FFF_PRIMARY
    jz 12f
    COLOR r9d, T_ACCENT
12: mov edi, [rsp]
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 24]
    M r8d, MI_RADIUS
    call gfx_round_rect
    cmp dword ptr [rsp + 16], 0
    je 13f
    mov edi, [rsp]              # the keyboard's button: a frame
    mov esi, [rsp + 4]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 24]
    M r8d, MI_RADIUS
    COLOR r9d, T_FG
    COLOR eax, T_ACCENT
    test dword ptr [r12 + FF_flags], FFF_PRIMARY
    jnz 121f
    COLOR eax, T_INPUT
121:push rax
    push rax
    call gfx_frame
    add rsp, 16
13: mov eax, [rsp + 20]
    test dword ptr [r12 + FF_flags], FFF_PRIMARY
    jz 14f
    COLOR eax, T_ACCENT_FG
14: push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    mov ecx, [rsp + 16 + 8]
    mov r8d, [rsp + 16 + 24]
    mov r9, [r12 + FF_label]
    call ui_text_center
    add rsp, 16
    test dword ptr [r12 + FF_flags], FFF_DISABLED
    jnz .Lfw_msg
    test dword ptr [rsp + 40], UB_PRESS
    jz 15f
    mov eax, [rsp + 12]
    mov [rbx + FM_focus], eax
15: test dword ptr [rsp + 40], UB_CLICK
    jz .Lfw_msg
    mov edi, [rbx + FM_slot]
    lea rsi, [rip + .Le_press]
    mov rdx, [r12 + FF_key]
    mov rcx, -1
    xor r8d, r8d
    xor r9d, r9d
    call rview_form_event
.Lfw_msg:
    # its message under it, in its severity's color
    mov rax, [r12 + FF_msg]
    test rax, rax
    jz .Lfw_ret
    mov rdi, rax
    call strlen
    mov r9, rax
    COLOR ecx, T_MUTED
    cmp dword ptr [r12 + FF_sev], SEV_ERROR
    jne 16f
    COLOR ecx, T_ERROR
16: cmp dword ptr [r12 + FF_sev], SEV_WARNING
    jne 17f
    COLOR ecx, T_WARNING
17: mov eax, [rsp + 8]
    push rax
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 16]
    mov edx, [rsp + 16 + 4]
    add edx, [rsp + 16 + 24]
    add edx, [rip + g_mt + 4*MI_2]
    mov ecx, [rip + g_face_small + FACE_lineh]
    mov r8, [r12 + FF_msg]
    call ui_text_v_fit
    add rsp, 16
.Lfw_ret:
    EPILOGUE

# ---------------- input ----------------

# changed(FM*, i): the user changed the field: its sequence goes up, the extension hears its value
changed:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rbx
    mov esi, r12d
    call fm_ff
    mov r13, rax
    inc qword ptr [r13 + FF_seq]
    cmp dword ptr [r13 + FF_type], FT_CHECK
    jne 1f
    lea rsi, [rip + .Lyes]
    mov edx, 3
    cmp dword ptr [r13 + FF_on], 0
    jne 2f
    lea rsi, [rip + .Lno]
    mov edx, 2
    jmp 2f
1:  mov rsi, [r13 + FF_tf + TF_sb + SB_ptr]
    mov rdx, [r13 + FF_tf + TF_sb + SB_len]
2:  mov r8, rsi
    mov r9, rdx
    mov edi, [rbx + FM_slot]
    lea rsi, [rip + .Le_change]
    mov rdx, [r13 + FF_key]
    mov rcx, [r13 + FF_seq]
    call rview_form_event
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# check_toggle(FM*, i)
check_toggle:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call fm_ff
    xor dword ptr [rax + FF_on], 1
    mov rdi, rbx
    mov esi, r12d
    call changed
    add rsp, 8
    pop r12
    pop rbx
    ret

# select_open(FM*, i): its options as a menu under it
select_open:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    call fm_ff
    mov r13, rax
    mov [rip + menu_form], rbx
    mov [rip + menu_field], r12d
    lea rdi, [rip + tsb]        # the options as cstrs
    call sb_clear
    mov rsi, [r13 + FF_opts]
    test rsi, rsi
    jz 9f
    lea rdi, [rip + tsb]
    call sb_push_cstr
    lea rdi, [rip + tsb]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + tsb + SB_ptr]
    mov rcx, [rip + tsb + SB_len]
    xor r14d, r14d              # items
    mov r15, rax                # the current option's start
    xor edx, edx
1:  cmp rdx, rcx
    jae 3f
    movzx r8d, byte ptr [rax + rdx]
    cmp r8d, 10
    je 2f
    test r8d, r8d
    jnz 21f
2:  mov byte ptr [rax + rdx], 0
    cmp r14d, 32
    jae 3f
    mov r9, r14
    shl r9, 4
    lea r10, [rip + menu_items]
    mov [r10 + r9], r15
    lea r11, [rip + select_pick]
    mov [r10 + r9 + 8], r11
    inc r14d
    lea r15, [rax + rdx + 1]
21: inc rdx
    jmp 1b
3:  test r14d, r14d
    jz 9f
    mov r9, r14
    shl r9, 4
    lea r10, [rip + menu_items]
    mov qword ptr [r10 + r9], 0
    mov qword ptr [r10 + r9 + 8], 0
    lea rdi, [rip + menu_items]
    mov esi, [r13 + FF_x]
    mov edx, [r13 + FF_y]
    add edx, [r13 + FF_h]
    call ctx_menu_open
9:  EPILOGUE

# select_pick(): the option g_menu_index becomes the select's value
select_pick:
    PROLOGUE
    mov rbx, [rip + menu_form]
    test rbx, rbx
    jz 9f
    mov r12d, [rip + menu_field]
    cmp r12d, [rbx + FM_n]
    jae 9f
    mov eax, [rip + g_menu_index]
    shl rax, 4
    lea rcx, [rip + menu_items]
    mov r13, [rcx + rax]
    test r13, r13
    jz 9f
    mov rdi, r13
    call strlen
    mov r14, rax
    mov rdi, rbx
    mov esi, r12d
    call fm_ff
    lea rdi, [rax + FF_tf]
    mov rsi, r13
    mov rdx, r14
    call tf_set
    mov rdi, rbx
    mov esi, r12d
    call changed
9:  EPILOGUE

# form_key(FM*, keysym, cp, mods) -> eax 1 when the form took the key
FN form_key
    PROLOGUE 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    # Tab and Shift+Tab move between the fields that take the keyboard
    cmp r12d, KEY_TAB
    je 1f
    cmp r12d, KEY_ISO_LEFT_TAB
    jne 3f
    mov r14d, MOD_SHIFT
1:  mov rdi, rbx
    call sort_order
    mov rdi, rbx
    mov esi, r14d
    call focus_next
    mov eax, 1
    EPILOGUE
3:  mov eax, [rbx + FM_focus]
    cmp eax, -1
    je 8f
    mov rdi, rbx
    mov esi, eax
    call fm_ff
    mov r15, rax
    mov eax, [r15 + FF_type]
    cmp eax, FT_TEXT
    je .Lfk_text
    cmp eax, FT_NUMBER
    je .Lfk_number
    cmp eax, FT_AREA
    je .Lfk_area
    cmp eax, FT_CHECK
    je .Lfk_check
    cmp eax, FT_SELECT
    je .Lfk_select
    cmp eax, FT_BUTTON
    je .Lfk_button
    jmp 8f
.Lfk_number:
    cmp r12d, KEY_UP
    je 4f
    cmp r12d, KEY_DOWN
    jne .Lfk_text
4:  test dword ptr [r15 + FF_flags], FFF_RANGE
    jz .Lfk_text
    mov rdi, [r15 + FF_tf + TF_sb + SB_ptr]
    mov rsi, [r15 + FF_tf + TF_sb + SB_len]
    call parse_milli
    test edx, edx
    jnz 41f
    mov rax, [r15 + FF_min]
    jmp 43f
41: mov rcx, [r15 + FF_step]
    cmp r12d, KEY_UP
    je 42f
    neg rcx
42: add rax, rcx
43: cmp rax, [r15 + FF_min]
    jge 44f
    mov rax, [r15 + FF_min]
44: cmp rax, [r15 + FF_max]
    jle 45f
    mov rax, [r15 + FF_max]
45: mov [rsp], rax
    lea rdi, [rip + tsb]
    call sb_clear
    lea rdi, [rip + tsb]
    mov rsi, [rsp]
    call fmt_milli
    lea rdi, [r15 + FF_tf]
    mov rsi, [rip + tsb + SB_ptr]
    mov rdx, [rip + tsb + SB_len]
    call tf_set
    mov rdi, rbx
    mov esi, [rbx + FM_focus]
    call changed
    jmp 7f
.Lfk_text:
    cmp r12d, KEY_RETURN
    je .Lfk_submit
    cmp r12d, KEY_KP_ENTER
    je .Lfk_submit
    mov rax, [r15 + FF_tf + TF_revision]
    mov [rsp], rax
    lea rdi, [r15 + FF_tf]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tf_key
    test eax, eax
    jz 8f
    jmp .Lfk_edited
.Lfk_area:
    cmp r12d, KEY_RETURN
    jne 5f
    test r14d, MOD_CTRL
    jnz .Lfk_submit
5:  mov rax, [r15 + FF_tf + TF_revision]
    mov [rsp], rax
    lea rdi, [r15 + FF_tf]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call ta_key
    test eax, eax
    jz 8f
.Lfk_edited:
    mov rax, [r15 + FF_tf + TF_revision]
    cmp rax, [rsp]
    je 7f                       # the caret moved, the text did not change
    mov rdi, rbx
    mov esi, [rbx + FM_focus]
    call changed
    jmp 7f
.Lfk_submit:
    mov edi, [rbx + FM_slot]
    lea rsi, [rip + .Le_submit]
    mov rdx, [r15 + FF_key]
    mov rcx, -1
    xor r8d, r8d
    xor r9d, r9d
    call rview_form_event
    jmp 7f
.Lfk_check:
    cmp r12d, ' '
    jne 8f
    mov rdi, rbx
    mov esi, [rbx + FM_focus]
    call check_toggle
    jmp 7f
.Lfk_select:
    cmp r12d, KEY_RETURN
    je 6f
    cmp r12d, ' '
    je 6f
    cmp r12d, KEY_DOWN
    jne 8f
6:  mov rdi, rbx
    mov esi, [rbx + FM_focus]
    call select_open
    jmp 7f
.Lfk_button:
    cmp r12d, KEY_RETURN
    je 61f
    cmp r12d, ' '
    jne 8f
61: mov edi, [rbx + FM_slot]
    lea rsi, [rip + .Le_press]
    mov rdx, [r15 + FF_key]
    mov rcx, -1
    xor r8d, r8d
    xor r9d, r9d
    call rview_form_event
7:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# focus_next(FM*, mods): the keyboard to the next field that takes it (Shift: the previous), in
#   display order, round
focus_next:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, [rbx + FM_n]
    test r13d, r13d
    jz 9f
    # where the focused field is in the order
    mov r14d, -1
    xor ecx, ecx
1:  cmp ecx, r13d
    jae 2f
    lea rax, [rip + order]
    mov edx, [rax + rcx*4]
    cmp edx, [rbx + FM_focus]
    jne 11f
    mov r14d, ecx
11: inc ecx
    jmp 1b
2:  xor r15d, r15d              # tries
3:  cmp r15d, r13d
    jae 9f
    inc r15d
    test r12d, MOD_SHIFT
    jnz 4f
    inc r14d
    cmp r14d, r13d
    jb 5f
    xor r14d, r14d
    jmp 5f
4:  dec r14d
    jns 5f
    lea r14d, [r13 - 1]
5:  lea rax, [rip + order]
    mov esi, [rax + r14*4]
    mov rdi, rbx
    call fm_ff
    mov rdi, rax
    call focusable
    test eax, eax
    jz 3b
    lea rax, [rip + order]
    mov eax, [rax + r14*4]
    mov [rbx + FM_focus], eax
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# form_field(FM*) -> rax the text field with the keyboard (text, number, area), or 0
FN form_field
    test rdi, rdi
    jz 8f
    mov esi, [rdi + FM_focus]
    cmp esi, -1
    je 8f
    call fm_ff
    mov ecx, [rax + FF_type]
    cmp ecx, FT_TEXT
    je 1f
    cmp ecx, FT_NUMBER
    je 1f
    cmp ecx, FT_AREA
    jne 8f
1:  add rax, FF_tf
    ret
8:  xor eax, eax
    ret

# form_paste(FM*, ptr, len) -> eax 1 when its focused text field took the paste
FN form_paste
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call form_field
    test rax, rax
    jz 8f
    mov r14, rax
    mov rdi, rbx
    mov esi, [rbx + FM_focus]
    call fm_ff
    cmp dword ptr [rax + FF_type], FT_AREA
    je 1f
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call tf_insert
    jmp 2f
1:  mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call ta_insert
2:  mov rdi, rbx
    mov esi, [rbx + FM_focus]
    call changed
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# form_dump(FM*, sb): "field KEY type=T row=R seq=S on=O [focus] [disabled] at=X,Y size=WxH
#   [msg=SEV:TEXT] value=V" per field, in display order
FN form_dump
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call sort_order
    xor r13d, r13d
1:  cmp r13d, [rbx + FM_n]
    jae 9f
    lea rax, [rip + order]
    mov esi, [rax + r13*4]
    mov r15d, esi
    mov rdi, rbx
    call fm_ff
    mov r14, rax
    mov rdi, r12
    lea rsi, [rip + .Ld_field]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + FF_key]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_type]
    call sb_push_cstr
    mov eax, [r14 + FF_type]
    lea rcx, [rip + type_words]
    mov rsi, [rcx + rax*8 - 8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_row]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r14 + FF_row]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_seq]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + FF_seq]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_on]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r14 + FF_on]
    call sb_push_u64
    cmp r15d, [rbx + FM_focus]
    jne 2f
    mov rdi, r12
    lea rsi, [rip + .Ld_focus]
    call sb_push_cstr
2:  test dword ptr [r14 + FF_flags], FFF_DISABLED
    jz 3f
    mov rdi, r12
    lea rsi, [rip + .Ld_disabled]
    call sb_push_cstr
3:  mov rdi, r12
    lea rsi, [rip + .Ld_at]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r14 + FF_x]
    call sb_push_u64
    mov rdi, r12
    mov esi, ','
    call sb_push_byte
    mov rdi, r12
    mov esi, [r14 + FF_y]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_size]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r14 + FF_w]
    call sb_push_u64
    mov rdi, r12
    mov esi, 'x'
    call sb_push_byte
    mov rdi, r12
    mov esi, [r14 + FF_h]
    call sb_push_u64
    mov rax, [r14 + FF_msg]
    test rax, rax
    jz 4f
    mov rdi, r12
    lea rsi, [rip + .Ld_msg]
    call sb_push_cstr
    mov eax, [r14 + FF_sev]
    lea rcx, [rip + sev_words]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    mov esi, ':'
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r14 + FF_msg]
    call sb_push_cstr
4:  mov rdi, r12
    lea rsi, [rip + .Ld_value]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + FF_tf + TF_sb + SB_ptr]
    mov rdx, [r14 + FF_tf + TF_sb + SB_len]
    call sb_push
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
    inc r13d
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lx_value: .asciz "value"
.Lx_placeholder: .asciz "placeholder"
.Lx_options: .asciz "options"
.Lx_lines: .asciz "lines"
.Lx_range: .asciz "range"
.Lx_msg: .asciz "msg"
.Lx_disabled: .asciz "disabled"
.Lx_primary: .asciz "primary"
.Lx_mono: .asciz "mono"
.Lx_password: .asciz "password"
.Lt_text: .asciz "text"
.Lt_area: .asciz "area"
.Lt_number: .asciz "number"
.Lt_check: .asciz "check"
.Lt_select: .asciz "select"
.Lt_button: .asciz "button"
.Lt_label: .asciz "label"
.Ldash: .asciz "-"
.Lyes: .asciz "yes"
.Lno: .asciz "no"
.Lerror: .asciz "error"
.Lwarning: .asciz "warning"
.Linfo: .asciz "info"
.Lhint: .asciz "hint"
.Lempty: .asciz ""
.Le_change: .asciz "change"
.Le_press: .asciz "press"
.Le_submit: .asciz "submit"
.Ld_field: .asciz "field "
.Ld_type: .asciz " type="
.Ld_row: .asciz " row="
.Ld_seq: .asciz " seq="
.Ld_on: .asciz " on="
.Ld_focus: .asciz " focus"
.Ld_disabled: .asciz " disabled"
.Ld_at: .asciz " at="
.Ld_size: .asciz " size="
.Ld_msg: .asciz " msg="
.Ld_value: .asciz " value="
.p2align 3
type_words: .quad .Lt_text, .Lt_area, .Lt_number, .Lt_check, .Lt_select, .Lt_button, .Lt_label, 0
extra_words: .quad .Lx_value, .Lx_placeholder, .Lx_options, .Lx_lines, .Lx_range, .Lx_msg, .Lx_disabled
    .quad .Lx_primary, .Lx_mono, .Lx_password, 0
extra_fns: .quad x_value, x_placeholder, x_options, x_lines, x_range, x_msg, x_disabled, x_primary, x_mono
    .quad x_password
sev_words: .quad .Lerror, .Lwarning, .Linfo, .Lhint      # SEV_*
# bytes a KEY may hold: letters, digits, _ . -
key_chars:
    .zero 45
    .byte 1, 1, 0                               # - .
    .byte 1, 1, 1, 1, 1, 1, 1, 1, 1, 1          # 0-9
    .zero 7
    .byte 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1    # A-Z
    .byte 0, 0, 0, 0, 1, 0                      # _
    .byte 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1    # a-z
    .zero 133
