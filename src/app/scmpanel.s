# scmpanel: a second version control system's panels (protocol 1.1 feature scm, docs/extensions/
# v1.1.md): an extension registers a root (scm-register) and rhun adds a sidebar section for it, which
# the extension fills with scm-update: a status line, an optional message box, up to four action
# buttons, and groups of resources (path, status letter, color) in the shared tree widget, each with a
# command for its click and actions in its menu. The explorer and tab titles color the provider's files
# after git's; quick-diff bases (scmext.s) apply under its roots.
.include "rhun.inc"

.equ SP_MAX, 16                 # providers, all extensions
.equ SP_EXT_MAX, 4              # providers of one extension
.equ SP_BODY_MAX, 4194304       # an scm-update body
.equ SP_RES_MAX, 10000          # resources in one update
.equ SP_GROUP_MAX, 64
.equ SP_ACT_MAX, 4              # top-level actions (buttons)
.equ SP_ITEM_ACT_MAX, 8         # actions of a group or a resource (its menu)
.equ SP_TEXT_MAX, 200           # status, placeholder, labels
.equ SP_TIP_MAX, 1000           # a resource's tooltip
.equ SP_TSLOT, 224              # an action's inline key (16 bytes) and title (208) in SP_tblob
.equ SP_INLINE_MAX, 4           # inline buttons on a row
.equ SP_INPUT_MAX, 65536        # the message box's text
.equ ID_SP, 0x7a0000            # + slot * 16 + n: a provider's buttons and header buttons (0x5f0000 is views')
.equ ID_SPBOX, 0x7a8000         # + its handle: a provider's message box

# a provider
STRUCT
F SP_ext, 8             # its extension, 0 for a free slot
F SP_tree, 8            # TR*
F SP_root, 8            # cstr owned, without a trailing /
F SP_rootlen, 8
F SP_label, 8           # cstr owned
F SP_body, 8            # owned: the last scm-update body (records below point into it)
F SP_blen, 8
F SP_status, 8          # in the body
F SP_statlen, 8
F SP_ph, 8              # cstr owned: the message box's placeholder; 0: no message box
F SP_act, VEC_SIZE      # AC: the top-level actions first (SP_nact of them), then the others
F SP_grp, VEC_SIZE      # GR
F SP_res, VEC_SIZE      # RS
F SP_tab, 8             # PT slots: the resources' paths and their folders (explorer colors)
F SP_tcap, 8
F SP_nact, 4
F SP_pid, 4             # the extension's process that registered it
F SP_handle, 4          # SCM, as the extension knows it
F SP_place, 4           # its sidebar section
F SP_inbox, 4           # the message box has the keyboard
F SP_pad, 4
F SP_ta, 8              # TA records for the tree's inline buttons, one per action (owned), "aN" keys
F SP_nta, 8
F SP_tblob, 8           # their keys and titles (owned)
F SP_gen, 8             # updates taken: a menu opened before the latest one runs nothing
F SP_tf, TF_SIZE        # the message box
ENDSTRUCT SP_SIZE

# an action: a command reference with an icon and a label
STRUCT
F AC_name, 8            # in the body
F AC_nlen, 8
F AC_args, 8
F AC_alen, 8
F AC_label, 8           # empty: the command's title
F AC_llen, 8
F AC_icon, 4            # IC_* or -1
F AC_pad, 4
ENDSTRUCT AC_SIZE

STRUCT
F GR_id, 8
F GR_idlen, 8
F GR_label, 8
F GR_llen, 8
F GR_act0, 4            # its actions in SP_act
F GR_nact, 4
F GR_res0, 4            # its resources in SP_res
F GR_nres, 4
ENDSTRUCT GR_SIZE

STRUCT
F RS_path, 8            # relative to the root, in the body
F RS_plen, 8
F RS_code, 4            # its letter
F RS_color, 4           # T_* slot, -1: none
F RS_group, 4
F RS_cmd, 4             # its click's action in SP_act, -1: open the file
F RS_act0, 4
F RS_nact, 4
F RS_tip, 8             # its tooltip, in the body (0: none)
F RS_tiplen, 8
ENDSTRUCT RS_SIZE

# a path of the table: a resource or a folder above one
STRUCT
F PT_ptr, 8             # 0: an empty slot
F PT_len, 4
F PT_code, 4            # letter; a folder: the strongest below it as the explorer shows it
F PT_color, 4
F PT_dir, 4
ENDSTRUCT PT_SIZE

.bss
.p2align 3
sp_slots: .zero SP_SIZE * SP_MAX
parse: .zero SP_SIZE            # an update being parsed (its vectors, then swapped in)
tmp: .zero SB_SIZE
rb: .zero SB_SIZE
menu_items: .zero 16 * (SP_ITEM_ACT_MAX + 2)
menu_sp: .quad 0                # the provider and the actions of the open menu
menu_gen: .quad 0               # its SP_gen then
parse_rootlen: .quad 0          # the root's length of the provider an update is parsed for
menu_act: .zero 4 * SP_ITEM_ACT_MAX
menu_path: .zero SB_SIZE        # its resource's path, absolute, a cstr ("" for a group)
handle_seq: .long 0
menu_n: .long 0
.p2align 3
xrec: .zero SB_SIZE             # a node's "inline LEN" record
ikeys: .zero SB_SIZE            # and its keys
diffsb: .zero SB_SIZE           # the diff a click opens
dname: .zero 4200               # its file's name, a cstr
diff_doc: .quad 0               # the document whose base a click waits for, its provider, and
diff_sp: .quad 0                #   the resource's path
diff_plen: .quad 0
diff_path: .zero 4096
dtabs: .zero 32 * 24            # diff tabs a click opened: doc id, provider (SP*), its handle and
dtab_n: .quad 0                 #   the file's absolute path (owned) packed: id, sp, path ptr
title_line: .zero SB_SIZE       # "scm OWNER/NAME ROOT": the header buttons' target

.text

# ---------------- requests ----------------

# ID scm-register LEN + ROOT_LEN LABEL_LEN LF <ROOT><LABEL> -> ok ID SCM
FN scmext_h_register
    PROLOGUE 32
    call req
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 3
    jne 8f
    call extproto_body
    mov r13, rax
    lea r14, [rax + rdx]        # end
    # ROOT_LEN LABEL_LEN LF
    mov rdi, r13
    mov rsi, r14
    call num_sp
    jc 8f
    mov [rsp], rax              # root length
    call num_eol
    jc 8f
    mov [rsp + 8], rax          # label length
    mov rcx, [rsp]
    add rcx, rax
    mov rax, r14
    sub rax, rdi
    cmp rax, rcx
    jne 8f
    mov [rsp + 16], rdi         # the root
    mov rcx, [rsp]
    test rcx, rcx
    jz 8f
    cmp rcx, 4095
    ja 8f
    mov rax, [rsp + 8]
    test rax, rax
    jz 8f
    cmp rax, SP_TEXT_MAX
    ja 8f
    mov rdi, [rsp + 16]
    mov rsi, [rsp]
    add rsi, [rsp + 8]
    call clean_text
    test eax, eax
    jz 8f
    mov rdi, [rsp + 16]
    cmp byte ptr [rdi], '/'
    je 1f
.ifdef WINDOWS
    cmp qword ptr [rsp], 3
    jb 8f
    cmp byte ptr [rdi + 1], ':'
    jne 8f
.else
    jmp 8f
.endif
1:  # the same root again: its handle
    mov rdi, [rsp + 16]
    mov rsi, [rsp]
    call root_trim
    mov [rsp], rax
    mov rdi, [rsp + 16]
    mov rsi, rax
    call find_root
    test rax, rax
    jz 2f
    mov esi, [rax + SP_handle]
    mov rdi, r12
    call reply_ok_num
    jmp 9f
2:  # room: per extension and in all
    xor ecx, ecx
    xor edx, edx
    lea r15, [rip + sp_slots]
    xor r8d, r8d                # a free slot
21: cmp ecx, SP_MAX
    jae 23f
    imul rax, rcx, SP_SIZE
    add rax, r15
    inc ecx
    cmp qword ptr [rax + SP_ext], 0
    jne 22f
    test r8, r8
    jnz 21b
    mov r8, rax
    jmp 21b
22: cmp [rax + SP_ext], rbx
    jne 21b
    inc edx
    jmp 21b
23: cmp edx, SP_EXT_MAX
    jae 7f
    test r8, r8
    jz 7f
    mov r15, r8
    mov rdi, r15
    xor esi, esi
    mov edx, SP_SIZE
    call memset
    mov [r15 + SP_ext], rbx
    mov eax, [rbx + EXT_pid]
    mov [r15 + SP_pid], eax
    inc dword ptr [rip + handle_seq]
    mov eax, [rip + handle_seq]
    mov [r15 + SP_handle], eax
    mov rdi, [rsp + 16]
    mov rsi, [rsp]
    call mem_dup
    mov [r15 + SP_root], rax
    mov rax, [rsp]
    mov [r15 + SP_rootlen], rax
    mov rax, r14                # the label ends the body
    sub rax, [rsp + 8]
    mov rdi, rax
    mov rsi, [rsp + 8]
    call mem_dup
    mov [r15 + SP_label], rax
    lea rdi, [rip + sp_tree_ops]
    mov rsi, r15
    call tree_new
    mov [r15 + SP_tree], rax
    mov rax, r15
    lea rcx, [rip + sp_slots]
    sub rax, rcx
    xor edx, edx
    mov ecx, SP_SIZE
    div ecx
    mov [rsp + 24], eax         # the slot
    # the message box's id is the registration's (a later provider in this slot gets another, so a
    # paste captured for this one never lands in it)
    mov eax, [r15 + SP_handle]
    and eax, 0x7fff
    add eax, ID_SPBOX
    mov [r15 + SP_tf + TF_id], eax
    # its section, named OWNER/NAME.scm.N in the config
    lea rdi, [rip + tmp]
    call sb_clear
    mov rdi, rbx
    call ext_full_name
    lea rdi, [rip + tmp]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Ldot_scm]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, [r15 + SP_handle]
    call sb_push_u64
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    mov edi, PLACE_SIDEBAR
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [r15 + SP_label]
    lea rcx, [rip + sp_place_ops]
    mov r8, r15
    call place_add
    mov [r15 + SP_place], eax
    test eax, eax
    js 6f
    mov esi, [r15 + SP_handle]
    mov rdi, r12
    call reply_ok_num
    # the open files under the root: their quick-diff provider may be this one now
    mov rdi, [r15 + SP_root]
    mov rsi, [r15 + SP_rootlen]
    call scmext_qd_root
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
6:  mov rdi, r15
    call sp_free
    mov dword ptr [r15 + SP_place], -1
7:  mov rdi, r12
    lea rsi, [rip + .Le_full]
    call extproto_error
    EPILOGUE
8:  call extproto_answer_syntax
9:  EPILOGUE

# ID scm-update SCM LEN + body -> ok ID: the provider's panel, replaced whole
FN scmext_h_update
    PROLOGUE 16
    call req
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 4
    jne 8f
    mov edi, 2
    call handle_arg
    test rax, rax
    jz 9f
    mov r15, rax
    mov rax, [r15 + SP_rootlen]
    mov [rip + parse_rootlen], rax
    call extproto_body
    mov rdi, rax
    mov rsi, rdx
    call parse_update
    test eax, eax
    jz 7f
    mov rdi, r15
    call take_update
    mov rdi, r12
    call extproto_ok
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
7:  call parse_drop
8:  call extproto_answer_syntax
9:  EPILOGUE

# ID scm-input SCM -> ok ID LEN + the message box's text
FN scmext_h_input
    PROLOGUE
    call req
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 3
    jne 8f
    mov edi, 2
    call handle_arg
    test rax, rax
    jz 9f
    mov r15, rax
    lea rdi, [r15 + SP_tf]
    call tf_text
    mov r13, rax
    mov r14, rdx
    lea rdi, [rip + rb]
    call sb_clear
    lea rdi, [rip + rb]
    lea rsi, [rip + .Lok]
    call sb_push_cstr
    lea rdi, [rip + rb]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + rb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + rb]
    mov rsi, r14
    call sb_push_u64
    lea rdi, [rip + rb]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + rb]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    mov rdi, rbx
    mov rsi, [rip + rb + SB_ptr]
    mov rdx, [rip + rb + SB_len]
    call ext_send_checked
    EPILOGUE
8:  call extproto_answer_syntax
9:  EPILOGUE

# ID scm-input-set SCM LEN + text -> ok ID: the message box holds the text (empty clears it)
FN scmext_h_input_set
    PROLOGUE
    call req
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 4
    jne 8f
    mov edi, 2
    call handle_arg
    test rax, rax
    jz 9f
    mov r15, rax
    call extproto_body
    cmp rdx, SP_INPUT_MAX
    ja 8f
    lea rdi, [r15 + SP_tf]
    mov rsi, rax
    call tf_set
    mov rdi, r12
    call extproto_ok
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
8:  call extproto_answer_syntax
9:  EPILOGUE

# req() -> eax 1 with rbx the extension and r12 its request id when it agreed scm; else answered
req:
    push r13
    call extproto_cur
    mov rbx, rax
    call extproto_req_id
    mov r12, rax
    FEAT_TEST rbx, FEAT_SCM
    jnz 1f
    mov rdi, r12
    lea rsi, [rip + .Le_unknown]
    call extproto_error
    xor eax, eax
    pop r13
    ret
1:  mov eax, 1
    pop r13
    ret

# handle_arg(field) -> rax the extension rbx's provider that field names, or 0 after answering
handle_arg:
    push r13
    call extproto_field
    test edx, edx
    jz 7f
    lea r13, [rip + sp_slots]
    xor ecx, ecx
1:  cmp ecx, SP_MAX
    jae 8f
    imul rdx, rcx, SP_SIZE
    add rdx, r13
    inc ecx
    cmp [rdx + SP_ext], rbx
    jne 1b
    mov esi, [rdx + SP_handle]
    cmp rsi, rax
    jne 1b
    mov rax, rdx
    pop r13
    ret
7:  call extproto_answer_syntax
    xor eax, eax
    pop r13
    ret
8:  mov rdi, r12
    lea rsi, [rip + .Le_noscm]
    call extproto_error
    xor eax, eax
    pop r13
    ret

# reply_ok_num(id, n): "ok ID N"
reply_ok_num:
    PROLOGUE
    mov r13, rdi
    mov r14d, esi
    lea rdi, [rip + rb]
    call sb_clear
    lea rdi, [rip + rb]
    lea rsi, [rip + .Lok]
    call sb_push_cstr
    lea rdi, [rip + rb]
    mov rsi, r13
    call sb_push_u64
    lea rdi, [rip + rb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + rb]
    mov esi, r14d
    call sb_push_u64
    lea rdi, [rip + rb]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + rb + SB_ptr]
    mov rdx, [rip + rb + SB_len]
    call ext_send_checked
    EPILOGUE

# root_trim(ptr, len) -> rax the length without trailing slashes (one stays for "/")
root_trim:
1:  cmp rsi, 1
    jbe 9f
    cmp byte ptr [rdi + rsi - 1], '/'
    jne 9f
    dec rsi
    jmp 1b
9:  mov rax, rsi
    ret

# find_root(ptr, len) -> rax rbx's provider of that root, or 0
find_root:
    push r13
    push r14
    push r15
    mov r13, rdi
    mov r14, rsi
    lea r15, [rip + sp_slots]
    xor ecx, ecx
1:  cmp ecx, SP_MAX
    jae 8f
    imul rdx, rcx, SP_SIZE
    add rdx, r15
    inc ecx
    cmp [rdx + SP_ext], rbx
    jne 1b
    cmp [rdx + SP_rootlen], r14
    jne 1b
    push rcx
    push rdx
    mov rdi, [rdx + SP_root]
    mov rsi, r13
    mov rdx, r14
    call memeq
    pop rdx
    pop rcx
    test eax, eax
    jz 1b
    mov rax, rdx
    jmp 9f
8:  xor eax, eax
9:  pop r15
    pop r14
    pop r13
    ret

# clean_text(ptr, len) -> eax 1 without NUL, CR or LF
clean_text:
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    test eax, eax
    jz 8f
    cmp eax, 10
    je 8f
    cmp eax, 13
    je 8f
    jmp 1b
2:  mov eax, 1
    ret
8:  xor eax, eax
    ret

# ---------------- reading an update ----------------
# STATUS_LEN INPUT_LEN NACT NGROUP LF <STATUS><INPUT>, NACT actions, NGROUP groups:
#   action   "action ICON NAME ARGS_LEN LABEL_LEN" LF <ARGS><LABEL>
#   group    "group ID LABEL_LEN NACT NRES" LF <LABEL>, NACT actions, NRES resources
#   resource "res CODE COLOR PATH_LEN NREC" LF <PATH>, NREC records: a command reference
#            ("command NAME ARGS_LEN" LF <ARGS>, its click, before its actions), an action, a tooltip
#            ("tip LEN" LF <TEXT>), or any other
#            "NAME ... LEN" LF + LEN bytes (skipped)
# The parse state: rdi the position, r14 the end (kept in pp_pos / pp_end); carry set on an error.

# num_sp(ptr, end) -> rax the decimal number at ptr, rdi after it and one space; CF on an error
num_sp:
    mov rsi, rsi
    call num_at
    jc 9f
    cmp rdi, rsi
    jae 8f
    cmp byte ptr [rdi], ' '
    jne 8f
    inc rdi
    clc
    ret
8:  stc
9:  ret
# num_eol: num_sp ending in LF
num_eol:
    mov rsi, r14
    call num_at
    jc 9f
    cmp rdi, rsi
    jae 8f
    cmp byte ptr [rdi], 10
    jne 8f
    inc rdi
    clc
    ret
8:  stc
9:  ret
# num_at(ptr, end) -> rax the decimal number (1 to 9 digits) at ptr, rdi after it; CF when none
num_at:
    xor eax, eax
    xor ecx, ecx
1:  cmp rdi, rsi
    jae 2f
    movzx edx, byte ptr [rdi]
    sub edx, '0'
    cmp edx, 9
    ja 2f
    imul rax, rax, 10
    add rax, rdx
    inc rdi
    inc ecx
    cmp ecx, 9
    ja 8f
    jmp 1b
2:  test ecx, ecx
    jz 8f
    clc
    ret
8:  stc
    ret

# word_sp(ptr, end) -> rax the word's start, rdx its length, rdi after it and one space; CF if none
word_sp:
    mov rax, rdi
1:  cmp rdi, rsi
    jae 8f
    cmp byte ptr [rdi], ' '
    je 2f
    cmp byte ptr [rdi], 10
    je 8f
    inc rdi
    jmp 1b
2:  mov rdx, rdi
    sub rdx, rax
    jz 8f
    inc rdi
    clc
    ret
8:  stc
    ret

# take(ptr, n, end) -> rax ptr, rdi ptr + n; CF when past the end
take:
    mov rax, rdi
    add rdi, rsi
    jc 8f
    cmp rdi, rdx
    ja 8f
    clc
    ret
8:  stc
    ret

# parse_update(ptr, len) -> eax 1 when the body is a whole update: its records in `parse`
parse_update:
    PROLOGUE 64
    mov r13, rdi                # the body
    mov r14, rsi
    call parse_drop
    mov rdi, r13
    mov rsi, r14
    cmp rsi, SP_BODY_MAX
    ja 8f
    lea r14, [rdi + rsi]        # its end
    mov [rip + parse + SP_body], rdi
    mov [rip + parse + SP_blen], rsi
    mov rsi, r14
    call num_sp
    jc 8f
    mov [rsp], rax              # status length
    mov rsi, r14
    call num_sp
    jc 8f
    mov [rsp + 8], rax          # placeholder length
    mov rsi, r14
    call num_sp
    jc 8f
    cmp rax, SP_ACT_MAX
    ja 8f
    mov [rsp + 16], rax         # actions
    call num_eol
    jc 8f
    cmp rax, SP_GROUP_MAX
    ja 8f
    mov [rsp + 24], rax         # groups
    cmp qword ptr [rsp], SP_TEXT_MAX
    ja 8f
    cmp qword ptr [rsp + 8], SP_TEXT_MAX
    ja 8f
    mov rsi, [rsp]
    mov rdx, r14
    call take
    jc 8f
    mov [rip + parse + SP_status], rax
    mov rcx, [rsp]
    mov [rip + parse + SP_statlen], rcx
    mov rsi, [rsp + 8]
    mov rdx, r14
    call take
    jc 8f
    mov [rsp + 32], rax         # the placeholder
    mov [rsp + 40], rdi
    mov rdi, [rip + parse + SP_status]
    mov rsi, [rsp]
    call clean_text
    test eax, eax
    jz 8f
    mov rdi, [rsp + 32]
    mov rsi, [rsp + 8]
    call clean_text
    test eax, eax
    jz 8f
    cmp qword ptr [rsp + 8], 0
    je 1f
    mov rdi, [rsp + 32]
    mov rsi, [rsp + 8]
    call mem_dup
    mov [rip + parse + SP_ph], rax
1:  mov rdi, [rsp + 40]
    mov rax, [rsp + 16]
    mov [rip + parse + SP_nact], eax
    mov r15, rax
2:  test r15, r15
    jz 3f
    call parse_action
    jc 8f
    dec r15
    jmp 2b
3:  mov r15, [rsp + 24]
4:  test r15, r15
    jz 5f
    call parse_group
    jc 8f
    dec r15
    jmp 4b
5:  cmp rdi, r14
    jne 8f
    call dup_groups
    test eax, eax
    jnz 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# dup_groups() -> eax 1 when two of parse's groups have the same id (their rows would collide)
dup_groups:
    PROLOGUE
    mov r12, [rip + parse + SP_grp + VEC_ptr]
    mov r13, [rip + parse + SP_grp + VEC_len]
    xor ebx, ebx
1:  inc rbx
    cmp rbx, r13
    jae 8f
    xor r14d, r14d
2:  cmp r14, rbx
    jae 1b
    imul rdi, rbx, GR_SIZE
    add rdi, r12
    imul rcx, r14, GR_SIZE
    add rcx, r12
    inc r14
    mov rsi, [rdi + GR_idlen]
    cmp rsi, [rcx + GR_idlen]
    jne 2b
    mov rdx, rsi
    mov rsi, [rcx + GR_id]
    mov rdi, [rdi + GR_id]
    call memeq
    test eax, eax
    jz 2b
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# parse_action(): an action at rdi (end r14) onto parse's SP_act; CF on an error
parse_action:
    PROLOGUE 48
    mov rsi, r14
    call word_sp
    jc 8f
    cmp rdx, 6
    jne 8f
    cmp dword ptr [rax], 0x69746361     # "acti"
    jne 8f
    cmp word ptr [rax + 4], 0x6e6f      # "on"
    jne 8f
    mov rsi, r14
    call action_rest
    jc 8f
    clc
    EPILOGUE
8:  stc
    EPILOGUE

# action_rest(): "ICON NAME ARGS_LEN LABEL_LEN" LF <ARGS><LABEL> at rdi onto parse's SP_act -> eax
#   its index; CF on an error
action_rest:
    PROLOGUE 64
    mov rsi, r14
    call word_sp                # ICON
    jc 8f
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rsi, r14
    call word_sp                # NAME
    jc 8f
    mov [rsp + 16], rax
    mov [rsp + 24], rdx
    mov rsi, r14
    call num_sp                 # ARGS_LEN
    jc 8f
    cmp rax, CRF_ARGS_MAX
    ja 8f
    mov [rsp + 32], rax
    call num_eol                # LABEL_LEN
    jc 8f
    cmp rax, SP_TEXT_MAX
    ja 8f
    mov [rsp + 40], rax
    mov rsi, [rsp + 32]
    mov rdx, r14
    call take
    jc 8f
    mov [rsp + 48], rax         # ARGS
    mov rsi, [rsp + 40]
    mov rdx, r14
    call take
    jc 8f
    mov [rsp + 56], rax         # LABEL
    mov r15, rdi
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call cmd_name_ok
    test eax, eax
    jz 8f
    mov rdi, [rsp + 56]
    mov rsi, [rsp + 40]
    call clean_text
    test eax, eax
    jz 8f
    # ICON: an icon name, or "-"
    mov ebx, -1
    cmp qword ptr [rsp + 8], 1
    jne 1f
    mov rax, [rsp]
    cmp byte ptr [rax], '-'
    je 2f
1:  mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call tree_icon_code
    test eax, eax
    js 8f
    test eax, NDI_FILE
    jnz 8f
    mov ebx, eax
2:  lea rdi, [rip + parse + SP_act]
    mov esi, AC_SIZE
    call vec_push
    mov rcx, [rsp + 16]
    mov [rax + AC_name], rcx
    mov rcx, [rsp + 24]
    mov [rax + AC_nlen], rcx
    mov rcx, [rsp + 48]
    mov [rax + AC_args], rcx
    mov rcx, [rsp + 32]
    mov [rax + AC_alen], rcx
    mov rcx, [rsp + 56]
    mov [rax + AC_label], rcx
    mov rcx, [rsp + 40]
    mov [rax + AC_llen], rcx
    mov [rax + AC_icon], ebx
    mov rdi, r15
    mov rax, [rip + parse + SP_act + VEC_len]
    dec eax
    clc
    EPILOGUE
8:  stc
    EPILOGUE

# parse_group(): "group ID LABEL_LEN NACT NRES" LF <LABEL>, its actions and resources; CF on an error
parse_group:
    PROLOGUE 48
    mov rsi, r14
    call word_sp
    jc 8f
    cmp rdx, 5
    jne 8f
    cmp dword ptr [rax], 0x756f7267     # "grou"
    jne 8f
    cmp byte ptr [rax + 4], 'p'
    jne 8f
    mov rsi, r14
    call word_sp                # ID
    jc 8f
    cmp rdx, 64
    ja 8f
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rsi, r14
    call num_sp                 # LABEL_LEN
    jc 8f
    cmp rax, SP_TEXT_MAX
    ja 8f
    mov [rsp + 16], rax
    mov rsi, r14
    call num_sp                 # NACT
    jc 8f
    cmp rax, SP_ITEM_ACT_MAX
    ja 8f
    mov [rsp + 24], rax
    call num_eol                # NRES
    jc 8f
    mov [rsp + 32], rax
    add rax, [rip + parse + SP_res + VEC_len]
    cmp rax, SP_RES_MAX
    ja 8f
    mov rsi, [rsp + 16]
    mov rdx, r14
    call take
    jc 8f
    mov [rsp + 40], rax         # LABEL
    mov r15, rdi
    mov rdi, rax
    mov rsi, [rsp + 16]
    call clean_text
    test eax, eax
    jz 8f
    lea rdi, [rip + parse + SP_grp]
    mov esi, GR_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + GR_id], rcx
    mov rcx, [rsp + 8]
    mov [rax + GR_idlen], rcx
    mov rcx, [rsp + 40]
    mov [rax + GR_label], rcx
    mov rcx, [rsp + 16]
    mov [rax + GR_llen], rcx
    mov rcx, [rip + parse + SP_act + VEC_len]
    mov [rax + GR_act0], ecx
    mov rcx, [rsp + 24]
    mov [rax + GR_nact], ecx
    mov rcx, [rip + parse + SP_res + VEC_len]
    mov [rax + GR_res0], ecx
    mov rcx, [rsp + 32]
    mov [rax + GR_nres], ecx
    mov rdi, r15
    mov rbx, [rsp + 24]
1:  test rbx, rbx
    jz 2f
    call parse_action
    jc 8f
    dec rbx
    jmp 1b
2:  mov rbx, [rsp + 32]
3:  test rbx, rbx
    jz 4f
    call parse_resource
    jc 8f
    dec rbx
    jmp 3b
4:  clc
    EPILOGUE
8:  stc
    EPILOGUE

# parse_resource(): "res CODE COLOR PATH_LEN NREC" LF <PATH> and its records; CF on an error
parse_resource:
    PROLOGUE 64
    mov rsi, r14
    call word_sp
    jc 8f
    cmp rdx, 3
    jne 8f
    cmp word ptr [rax], 0x6572          # "re"
    jne 8f
    cmp byte ptr [rax + 2], 's'
    jne 8f
    mov rsi, r14
    call word_sp                # CODE: one printable character
    jc 8f
    cmp rdx, 1
    jne 8f
    movzx ecx, byte ptr [rax]
    cmp ecx, 0x21
    jb 8f
    cmp ecx, 0x7e
    ja 8f
    mov [rsp], ecx
    mov rsi, r14
    call word_sp                # COLOR
    jc 8f
    mov r15, rdi
    mov rdi, rax
    mov rsi, rdx
    call color_slot
    cmp eax, -2
    je 8f
    mov [rsp + 4], eax
    mov rdi, r15
    mov rsi, r14
    call num_sp                 # PATH_LEN
    jc 8f
    test rax, rax
    jz 8f
    mov rcx, [rip + parse_rootlen]
    lea rcx, [rcx + rax + 1]
    cmp rcx, 4095               # ROOT/PATH is a path rhun can open and name in a menu
    ja 8f
    mov [rsp + 8], rax
    call num_eol                # NREC
    jc 8f
    cmp rax, 64
    ja 8f
    mov [rsp + 16], rax
    mov rsi, [rsp + 8]
    mov rdx, r14
    call take
    jc 8f
    mov [rsp + 24], rax         # PATH
    mov r15, rdi
    mov rdi, rax
    mov rsi, [rsp + 8]
    call clean_text
    test eax, eax
    jz 8f
    mov rax, [rsp + 24]
    cmp byte ptr [rax], '/'
    je 8f
    lea rdi, [rip + parse + SP_res]
    mov esi, RS_SIZE
    call vec_push
    mov rbx, [rip + parse + SP_res + VEC_len]
    dec rbx                     # its index (the vector may move while records are read)
    mov rcx, [rsp + 24]
    mov [rax + RS_path], rcx
    mov rcx, [rsp + 8]
    mov [rax + RS_plen], rcx
    mov ecx, [rsp]
    mov [rax + RS_code], ecx
    mov ecx, [rsp + 4]
    mov [rax + RS_color], ecx
    mov rcx, [rip + parse + SP_grp + VEC_len]
    dec ecx
    mov [rax + RS_group], ecx
    mov dword ptr [rax + RS_cmd], -1
    mov rcx, [rip + parse + SP_act + VEC_len]
    mov [rax + RS_act0], ecx
    mov dword ptr [rax + RS_nact], 0
    mov rdi, r15
    mov r15, [rsp + 16]
1:  test r15, r15
    jz 7f
    dec r15
    mov rsi, r14
    call word_sp                # the record's name
    jc 8f
    mov [rsp + 32], rax
    mov [rsp + 40], rdx
    cmp rdx, 7
    jne 2f
    cmp dword ptr [rax], 0x6d6d6f63     # "comm"
    jne 2f
    cmp dword ptr [rax + 3], 0x646e616d # "mand"
    jne 2f
    # command NAME ARGS_LEN: the click, an action without icon or label
    call command_rest
    jc 8f
    imul rcx, rbx, RS_SIZE
    add rcx, [rip + parse + SP_res + VEC_ptr]
    cmp dword ptr [rcx + RS_cmd], -1
    jne 8f                      # one click
    mov [rcx + RS_cmd], eax
    jmp 1b
2:  cmp rdx, 6
    jne 3f
    cmp dword ptr [rax], 0x69746361     # "acti"
    jne 3f
    cmp word ptr [rax + 4], 0x6e6f      # "on"
    jne 3f
    call action_rest
    jc 8f
    imul rcx, rbx, RS_SIZE
    add rcx, [rip + parse + SP_res + VEC_ptr]
    inc dword ptr [rcx + RS_nact]
    cmp dword ptr [rcx + RS_nact], SP_ITEM_ACT_MAX
    ja 8f
    # its actions must follow each other: a click recorded between them moves them
    mov edx, [rcx + RS_act0]
    add edx, [rcx + RS_nact]
    dec edx
    cmp edx, eax
    jne 8f
    jmp 1b
3:  # tip LEN: the tooltip
    cmp qword ptr [rsp + 40], 3
    jne 4f
    mov rax, [rsp + 32]
    cmp word ptr [rax], 0x6974          # "ti"
    jne 4f
    cmp byte ptr [rax + 2], 'p'
    jne 4f
    call num_eol
    jc 8f
    cmp rax, SP_TIP_MAX
    ja 8f
    mov [rsp + 48], rax
    mov rsi, rax
    mov rdx, r14
    call take
    jc 8f
    imul rcx, rbx, RS_SIZE
    add rcx, [rip + parse + SP_res + VEC_ptr]
    mov [rcx + RS_tip], rax
    mov rdx, [rsp + 48]
    mov [rcx + RS_tiplen], rdx
    jmp 1b
4:  # any other record: its fields end in its body length
    call skip_record
    jc 8f
    jmp 1b
7:  # a click recorded among the actions breaks their run: keep it before them
    clc
    EPILOGUE
8:  stc
    EPILOGUE

# command_rest(): "NAME ARGS_LEN" LF <ARGS> at rdi onto parse's SP_act (no icon, no label) -> eax its
#   index; CF on an error
command_rest:
    PROLOGUE 32
    mov rsi, r14
    call word_sp
    jc 8f
    mov [rsp], rax
    mov [rsp + 8], rdx
    call num_eol
    jc 8f
    cmp rax, CRF_ARGS_MAX
    ja 8f
    mov [rsp + 16], rax
    mov rsi, rax
    mov rdx, r14
    call take
    jc 8f
    mov [rsp + 24], rax
    mov r15, rdi
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call cmd_name_ok
    test eax, eax
    jz 8f
    # the resource's actions run from RS_act0 on: a click between them would break the run, so it
    # goes into the vector only before the first action (or after the last, when there are none yet)
    lea rdi, [rip + parse + SP_act]
    mov esi, AC_SIZE
    call vec_push
    mov rcx, [rsp]
    mov [rax + AC_name], rcx
    mov rcx, [rsp + 8]
    mov [rax + AC_nlen], rcx
    mov rcx, [rsp + 24]
    mov [rax + AC_args], rcx
    mov rcx, [rsp + 16]
    mov [rax + AC_alen], rcx
    mov qword ptr [rax + AC_label], 0
    mov qword ptr [rax + AC_llen], 0
    mov dword ptr [rax + AC_icon], -1
    mov rdi, r15
    mov rax, [rip + parse + SP_act + VEC_len]
    dec eax
    # a click after the resource's actions began: its actions start after it
    imul rcx, rbx, RS_SIZE
    add rcx, [rip + parse + SP_res + VEC_ptr]
    cmp dword ptr [rcx + RS_nact], 0
    jne 8f
    lea edx, [rax + 1]
    mov [rcx + RS_act0], edx
    clc
    EPILOGUE
8:  stc
    EPILOGUE

# skip_record(): the rest of a record line whose last field is its body length, and the body; CF
#   on an error
skip_record:
    mov r8, rdi                 # the line's start
1:  cmp rdi, r14
    jae 8f
    cmp byte ptr [rdi], 10
    je 2f
    inc rdi
    jmp 1b
2:  mov r9, rdi                 # its LF
    mov rcx, rdi
3:  cmp rcx, r8
    jbe 4f
    cmp byte ptr [rcx - 1], ' '
    je 4f
    dec rcx
    jmp 3b
4:  push rdi
    mov rdi, rcx
    mov rsi, r9
    call num_at                 # the last field: the body's length
    mov rsi, rdi
    pop rdi
    jc 8f
    cmp rsi, r9
    jne 8f
    inc rdi                     # past the LF
    mov rsi, rax
    mov rdx, r14
    jmp take
8:  stc
    ret

# color_slot(ptr, len) -> eax the T_* slot of a color name, -1 for "-", -2 for an unknown name
color_slot:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov eax, -1
    cmp r13, 1
    jne 1f
    cmp byte ptr [r12], '-'
    je 9f
1:  lea rbx, [rip + color_names]
2:  mov rdx, [rbx]
    mov eax, -2
    test rdx, rdx
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 3f
    add rbx, 16
    jmp 2b
3:  mov eax, [rbx + 8]
9:  EPILOGUE

# parse_drop(): what parse holds goes
parse_drop:
    push rbx
    lea rdi, [rip + parse + SP_act]
    call vec_free
    lea rdi, [rip + parse + SP_grp]
    call vec_free
    lea rdi, [rip + parse + SP_res]
    call vec_free
    mov rdi, [rip + parse + SP_ph]
    call mem_free
    lea rdi, [rip + parse]
    xor esi, esi
    mov edx, SP_SIZE
    call memset
    pop rbx
    ret

# take_update(sp): parse's records replace the provider's; the body is copied and its pointers moved
take_update:
    PROLOGUE 16
    mov r15, rdi
    mov rdi, [rip + parse + SP_blen]
    call mem_alloc
    mov r13, rax
    mov rdi, rax
    mov rsi, [rip + parse + SP_body]
    mov rdx, [rip + parse + SP_blen]
    call memcpy
    mov r14, r13
    sub r14, [rip + parse + SP_body]    # how far every pointer into the body moves
    # the old update goes
    lea rdi, [r15 + SP_act]
    call vec_free
    lea rdi, [r15 + SP_grp]
    call vec_free
    lea rdi, [r15 + SP_res]
    call vec_free
    mov rdi, [r15 + SP_body]
    call mem_free
    mov rdi, [r15 + SP_ph]
    call mem_free
    mov rdi, [r15 + SP_tab]
    call mem_free
    mov qword ptr [r15 + SP_tab], 0
    mov qword ptr [r15 + SP_tcap], 0
    # the new one
    mov [r15 + SP_body], r13
    mov rax, [rip + parse + SP_blen]
    mov [r15 + SP_blen], rax
    mov rax, [rip + parse + SP_status]
    add rax, r14
    mov [r15 + SP_status], rax
    mov rax, [rip + parse + SP_statlen]
    mov [r15 + SP_statlen], rax
    mov rax, [rip + parse + SP_ph]
    mov [r15 + SP_ph], rax
    mov qword ptr [rip + parse + SP_ph], 0
    mov eax, [rip + parse + SP_nact]
    mov [r15 + SP_nact], eax
    lea rsi, [rip + parse + SP_act]
    lea rdi, [r15 + SP_act]
    mov ecx, VEC_SIZE
    rep movsb
    lea rsi, [rip + parse + SP_grp]
    lea rdi, [r15 + SP_grp]
    mov ecx, VEC_SIZE
    rep movsb
    lea rsi, [rip + parse + SP_res]
    lea rdi, [r15 + SP_res]
    mov ecx, VEC_SIZE
    rep movsb
    lea rdi, [rip + parse + SP_act]
    xor eax, eax
    mov ecx, VEC_SIZE * 3
    rep stosb
    # move the pointers
    xor ecx, ecx
1:  cmp rcx, [r15 + SP_act + VEC_len]
    jae 2f
    imul rax, rcx, AC_SIZE
    add rax, [r15 + SP_act + VEC_ptr]
    add [rax + AC_name], r14
    add [rax + AC_args], r14
    cmp qword ptr [rax + AC_label], 0
    je 11f
    add [rax + AC_label], r14
11: inc rcx
    jmp 1b
2:  xor ecx, ecx
3:  cmp rcx, [r15 + SP_grp + VEC_len]
    jae 4f
    imul rax, rcx, GR_SIZE
    add rax, [r15 + SP_grp + VEC_ptr]
    add [rax + GR_id], r14
    add [rax + GR_label], r14
    inc rcx
    jmp 3b
4:  xor ecx, ecx
5:  cmp rcx, [r15 + SP_res + VEC_len]
    jae 6f
    imul rax, rcx, RS_SIZE
    add rax, [r15 + SP_res + VEC_ptr]
    add [rax + RS_path], r14
    cmp qword ptr [rax + RS_tip], 0
    je 51f
    add [rax + RS_tip], r14
51: inc rcx
    jmp 5b
6:  call parse_drop
    inc qword ptr [r15 + SP_gen]
    mov rdi, r15
    call build_table
    mov rdi, r15
    call build_actions
    mov rdi, r15
    call build_tree
    EPILOGUE

# build_actions(sp): every action as an inline button the tree can show ("aN" for action N, its icon,
#   its label as the tooltip); rows name theirs in an "inline" record
build_actions:
    PROLOGUE 16
    mov r15, rdi
    mov r12, [r15 + SP_act + VEC_len]
    lea rdi, [r12 + 1]
    imul rdi, rdi, TA_SIZE
    call mem_alloc
    mov r13, rax                # TA
    lea rdi, [r12 + 1]
    imul rdi, rdi, SP_TSLOT
    call mem_alloc
    mov r14, rax                # keys and titles
    xor ebx, ebx
1:  cmp rbx, r12
    jae 2f
    imul rdi, rbx, SP_TSLOT
    add rdi, r14
    mov [rsp], rdi
    mov byte ptr [rdi], 'a'
    inc rdi
    mov rsi, rbx
    call fmt_u64
    lea rcx, [rax + 1]          # the key's length: "a" and the digits
    imul rax, rbx, TA_SIZE
    add rax, r13
    mov rdx, [rsp]
    mov [rax + TA_key], rdx
    mov [rax + TA_keylen], rcx
    add rdx, 16
    mov [rax + TA_title], rdx
    imul rsi, rbx, AC_SIZE
    add rsi, [r15 + SP_act + VEC_ptr]
    mov ecx, [rsi + AC_icon]
    mov [rax + TA_icon], ecx
    mov rdi, r15
    call action_label           # into tmp, a cstr
    mov rsi, [rip + tmp + SB_ptr]
    mov rdi, [rsp]
    add rdi, 16
    mov ecx, SP_TSLOT - 17
3:  mov al, [rsi]
    test al, al
    jz 4f
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz 3b
4:  mov byte ptr [rdi], 0
    inc rbx
    jmp 1b
2:  mov rdi, [r15 + SP_tree]
    mov rsi, r13
    mov rdx, r12
    call tree_set_actions
    mov rdi, [r15 + SP_ta]
    call mem_free
    mov rdi, [r15 + SP_tblob]
    call mem_free
    mov [r15 + SP_ta], r13
    mov [r15 + SP_nta], r12
    mov [r15 + SP_tblob], r14
    EPILOGUE

# inline_rec(sp, first action, count) -> rax, rdx the "inline LEN" record of the actions among them
#   that have an icon (at most four), or rdx 0 when none has
inline_rec:
    PROLOGUE 16
    mov r15, rdi
    mov r12d, esi
    lea r13d, [rsi + rdx]
    lea rdi, [rip + ikeys]
    call sb_clear
    xor r14d, r14d              # buttons
1:  cmp r12d, r13d
    jae 2f
    cmp r14d, SP_INLINE_MAX
    jae 2f
    mov eax, r12d
    inc r12d
    imul rcx, rax, AC_SIZE
    add rcx, [r15 + SP_act + VEC_ptr]
    cmp dword ptr [rcx + AC_icon], 0
    jl 1b
    test r14d, r14d
    jz 11f
    push rax
    push rax
    lea rdi, [rip + ikeys]
    mov esi, ' '
    call sb_push_byte
    pop rax
    pop rax
11: imul rax, rax, TA_SIZE
    add rax, [r15 + SP_ta]
    lea rdi, [rip + ikeys]
    mov rsi, [rax + TA_key]
    mov rdx, [rax + TA_keylen]
    call sb_push
    inc r14d
    jmp 1b
2:  xor edx, edx
    test r14d, r14d
    jz 9f
    lea rdi, [rip + xrec]
    call sb_clear
    lea rdi, [rip + xrec]
    lea rsi, [rip + .Linline]
    call sb_push_cstr
    lea rdi, [rip + xrec]
    mov rsi, [rip + ikeys + SB_len]
    call sb_push_u64
    lea rdi, [rip + xrec]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + xrec]
    mov rsi, [rip + ikeys + SB_ptr]
    mov rdx, [rip + ikeys + SB_len]
    call sb_push
    mov rax, [rip + xrec + SB_ptr]
    mov rdx, [rip + xrec + SB_len]
9:  EPILOGUE

# ---------------- the tree and the path table ----------------

# build_tree(sp): its groups and their resources into the provider's tree (expansion and cursor stay)
build_tree:
    PROLOGUE 32
    mov r15, rdi
    mov rbx, [r15 + SP_tree]
    mov rdi, rbx
    xor esi, esi
    call tree_kids_begin
    xor r12d, r12d
1:  cmp r12, [r15 + SP_grp + VEC_len]
    jae 2f
    imul r13, r12, GR_SIZE
    add r13, [r15 + SP_grp + VEC_ptr]
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov esi, 'g'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r13 + GR_id]
    mov rdx, [r13 + GR_idlen]
    call sb_push
    mov rdi, r15
    mov esi, [r13 + GR_act0]
    mov edx, [r13 + GR_nact]
    call inline_rec
    push rdx
    push rax
    mov rdi, rbx
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    mov rcx, [r13 + GR_label]
    mov r8, [r13 + GR_llen]
    mov r9d, KIDS_OPEN
    call tree_kid_x
    add rsp, 16
    mov r14d, eax
    test eax, eax
    js 11f                      # (ids are checked unique: never)
    mov rdi, rbx
    mov esi, r14d
    mov edx, [r13 + GR_nres]
    call tree_set_badge
    mov rdi, rbx
    mov esi, r14d
    mov rdx, r12
    bts rdx, 32                 # a group: its index with bit 32
    call tree_set_user
11: inc r12
    jmp 1b
2:  mov rdi, rbx
    xor esi, esi
    call tree_kids_end
    # each group's resources
    xor r12d, r12d
3:  cmp r12, [r15 + SP_grp + VEC_len]
    jae 9f
    imul r13, r12, GR_SIZE
    add r13, [r15 + SP_grp + VEC_ptr]
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov esi, 'g'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r13 + GR_id]
    mov rdx, [r13 + GR_idlen]
    call sb_push
    mov rdi, rbx
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    call tree_find
    test eax, eax
    jle 81f
    mov rdi, rbx
    mov esi, eax
    call tree_kids_begin
    mov r14d, [r13 + GR_res0]
    mov eax, [r13 + GR_nres]
    add eax, r14d
    mov [rsp], eax
4:  cmp r14d, [rsp]
    jae 8f
    mov rdi, r15
    mov rsi, r13
    mov edx, r14d
    call res_node
    inc r14d
    jmp 4b
8:  mov rdi, rbx
    xor esi, esi
    call tree_kids_end
81: inc r12
    jmp 3b
9:  EPILOGUE

# res_node(sp, group, resource index): its tree node under the group being listed
res_node:
    PROLOGUE 32
    mov r15, rdi
    mov r12, rsi
    mov [rsp], edx
    imul r13, rdx, RS_SIZE
    add r13, [r15 + SP_res + VEC_ptr]
    mov rbx, [r15 + SP_tree]
    # id "r" GROUP NUL PATH
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov esi, 'r'
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r12 + GR_id]
    mov rdx, [r12 + GR_idlen]
    call sb_push
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    lea rdi, [rip + tmp]
    mov rsi, [r13 + RS_path]
    mov rdx, [r13 + RS_plen]
    call sb_push
    # label: the file's name; desc: its letter and folder
    mov rdi, [r13 + RS_path]
    mov rsi, [r13 + RS_plen]
    call path_basename
    mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov rdi, r15
    mov esi, [r13 + RS_act0]
    mov edx, [r13 + RS_nact]
    call inline_rec
    push rdx
    push rax
    mov rdi, rbx
    mov rsi, [rip + tmp + SB_ptr]
    mov rdx, [rip + tmp + SB_len]
    mov rcx, [rsp + 24]         # the file's name (rsp moved by the two pushes)
    mov r8, [rsp + 32]
    xor r9d, r9d
    call tree_kid_x
    add rsp, 16
    mov r14d, eax
    test eax, eax
    js 9f                       # the path is listed twice in the group: the first one shows
    mov rdi, rbx
    mov esi, r14d
    mov edx, [rsp]
    call tree_set_user
    mov edx, [r13 + RS_color]
    test edx, edx
    js 1f
    mov rdi, rbx
    mov esi, r14d
    call tree_set_color
1:  mov rdi, rbx
    mov esi, r14d
    mov rdx, [r13 + RS_tip]
    mov rcx, [r13 + RS_tiplen]
    call tree_set_tip
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lfile_pfx]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    call sb_push
    mov rdi, [rip + tmp + SB_ptr]
    mov rsi, [rip + tmp + SB_len]
    call tree_icon_code
    mov edx, eax
    mov rdi, rbx
    mov esi, r14d
    mov ecx, -1
    call tree_set_icon
    lea rdi, [rip + tmp]
    call sb_clear
    lea rdi, [rip + tmp]
    mov esi, [r13 + RS_code]
    call sb_push_byte
    mov rax, [rsp + 8]
    sub rax, [r13 + RS_path]    # the folder's length with its /
    jz 2f
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lsep]
    call sb_push_cstr
    mov rdx, [rsp + 8]
    sub rdx, [r13 + RS_path]
    dec rdx
    lea rdi, [rip + tmp]
    mov rsi, [r13 + RS_path]
    call sb_push
2:  mov rdi, rbx
    mov esi, r14d
    mov rdx, [rip + tmp + SB_ptr]
    mov rcx, [rip + tmp + SB_len]
    call tree_set_desc
9:  EPILOGUE

# build_table(sp): the resources' paths and their folders, for the explorer's letters and colors
build_table:
    PROLOGUE 16
    mov r15, rdi
    mov rax, [r15 + SP_res + VEC_len]
    test rax, rax
    jz 9f
    # room for each path and a few folders, a power of two at least four times that
    lea rax, [rax*8]
    mov ecx, 64
1:  cmp rcx, rax
    jae 2f
    shl rcx, 1
    jmp 1b
2:  mov [r15 + SP_tcap], rcx
    imul rdi, rcx, PT_SIZE
    call mem_alloc
    mov [r15 + SP_tab], rax
    mov qword ptr [rsp], 0      # paths in it
    xor r12d, r12d
3:  cmp r12, [r15 + SP_res + VEC_len]
    jae 9f
    imul r13, r12, RS_SIZE
    add r13, [r15 + SP_res + VEC_ptr]
    inc r12
    mov rdi, r15
    mov rsi, [r13 + RS_path]
    mov rdx, [r13 + RS_plen]
    mov ecx, [r13 + RS_code]
    mov r8d, [r13 + RS_color]
    xor r9d, r9d
    call pt_add
    add [rsp], rax
    # the folders above it (while the table has room)
    mov r14, [r13 + RS_plen]
4:  dec r14
    jle 3b
    mov rax, [r13 + RS_path]
    cmp byte ptr [rax + r14], '/'
    jne 4b
    mov rax, [r15 + SP_tcap]
    shr rax, 1
    cmp [rsp], rax
    jae 3b
    mov rdi, r15
    mov rsi, [r13 + RS_path]
    mov rdx, r14
    mov ecx, [r13 + RS_code]
    mov r8d, [r13 + RS_color]
    mov r9d, 1
    call pt_add
    add [rsp], rax
    jmp 4b
9:  EPILOGUE

# pt_add(sp, ptr, len, code, color, dir) -> rax 1 when the path is new in the table (a folder keeps the
#   first color seen)
pt_add:
    PROLOGUE 16
    mov r15, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], ecx
    mov [rsp + 4], r8d
    mov [rsp + 8], r9d
    mov rdi, r15
    mov rsi, r12
    mov rdx, r13
    call pt_find
    cmp qword ptr [rax + PT_ptr], 0
    jne 9f
    mov [rax + PT_ptr], r12
    mov [rax + PT_len], r13d
    mov ecx, [rsp]
    mov [rax + PT_code], ecx
    mov ecx, [rsp + 4]
    mov [rax + PT_color], ecx
    mov ecx, [rsp + 8]
    mov [rax + PT_dir], ecx
    mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# pt_find(sp, ptr, len) -> rax the slot of that path, or the empty slot for it
pt_find:
    PROLOGUE
    mov r15, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsi
    mov rsi, rdx
    call hash_line
    mov r14, [r15 + SP_tcap]
    dec r14
    and rax, r14
    mov rbx, rax
1:  imul rax, rbx, PT_SIZE
    add rax, [r15 + SP_tab]
    cmp qword ptr [rax + PT_ptr], 0
    je 9f
    mov ecx, [rax + PT_len]
    cmp rcx, r13
    jne 2f
    push rax
    push rax
    mov rdi, [rax + PT_ptr]
    mov rsi, r12
    mov rdx, r13
    call memeq
    mov ecx, eax
    pop rax
    pop rax
    test ecx, ecx
    jnz 9f
2:  inc rbx
    and rbx, r14
    jmp 1b
9:  EPILOGUE

# FN vcs_status_of(path cstr) -> eax the letter (0: unchanged), edx 1 for a folder with changes below,
#   ecx its color (ARGB): git's first, then the providers' resources (explorer, tabs)
FN vcs_status_of
    PROLOGUE
    mov r12, rdi
    call git_status_of
    test eax, eax
    jz 1f
    mov r13d, eax
    mov r14d, edx
    mov edi, eax
    call git_code_color
    mov ecx, eax
    mov eax, r13d
    mov edx, r14d
    EPILOGUE
1:  mov rdi, r12
    call strlen
    mov r13, rax
    lea rbx, [rip + sp_slots]
    xor r15d, r15d
2:  cmp r15d, SP_MAX
    jae 8f
    imul r14, r15, SP_SIZE
    add r14, rbx
    inc r15d
    cmp qword ptr [r14 + SP_ext], 0
    je 2b
    cmp qword ptr [r14 + SP_tab], 0
    je 2b
    mov rcx, [r14 + SP_rootlen]
    lea rax, [rcx + 1]
    cmp r13, rax
    jbe 2b
    cmp byte ptr [r12 + rcx], '/'
    jne 2b
    mov rdi, r12
    mov rsi, [r14 + SP_root]
    mov rdx, rcx
    call memeq
    test eax, eax
    jz 2b
    mov rcx, [r14 + SP_rootlen]
    lea rsi, [r12 + rcx + 1]
    mov rdx, r13
    sub rdx, rcx
    dec rdx
    mov rdi, r14
    call pt_find
    cmp qword ptr [rax + PT_ptr], 0
    je 2b
    mov r13d, [rax + PT_code]
    mov r14d, [rax + PT_dir]
    mov edi, [rax + PT_color]
    test edi, edi
    js 3f
    mov esi, T_GIT_MOD
    call tree_color
    jmp 4f
3:  mov edi, r13d
    call git_code_color
4:  mov ecx, eax
    mov eax, r13d
    mov edx, r14d
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    xor ecx, ecx
    EPILOGUE

# FN vcs_path_color(path cstr) -> eax ARGB for its name, 0 when unchanged
FN vcs_path_color
    push rbx
    call vcs_status_of
    test eax, eax
    jz 1f
    mov eax, ecx
1:  pop rbx
    ret

# FN scm_root_ext(path cstr or 0) -> rax the extension whose registered root holds the path (the
#   longest such root), or 0 (quick-diff bases, scmext.s)
FN scm_root_ext
    PROLOGUE
    xor r15d, r15d              # the extension
    xor ebx, ebx                # its root's length
    test rdi, rdi
    jz 8f
    mov r12, rdi
    call strlen
    mov r13, rax
    xor r14d, r14d
1:  cmp r14d, SP_MAX
    jae 8f
    lea rax, [rip + sp_slots]
    imul rcx, r14, SP_SIZE
    add rcx, rax
    inc r14d
    cmp qword ptr [rcx + SP_ext], 0
    je 1b
    mov rdx, [rcx + SP_rootlen]
    cmp rdx, rbx
    jbe 1b
    lea rax, [rdx + 1]
    cmp r13, rax
    jb 1b
    cmp rdx, 1
    je 2f                       # the root "/" holds every path
    cmp byte ptr [r12 + rdx], '/'
    jne 1b                      # /repo/sub does not hold /repo/subX
2:  push rcx
    push rdx
    mov rdi, r12
    mov rsi, [rcx + SP_root]
    call memeq
    pop rdx
    pop rcx
    test eax, eax
    jz 1b
    mov rbx, [rcx + SP_rootlen]
    mov r15, [rcx + SP_ext]
    jmp 1b
8:  mov rax, r15
    EPILOGUE

# ---------------- the panel ----------------

# sp_draw(sp, x, y, w, h): status, message box, buttons, then the tree
sp_draw:
    PROLOGUE 64
    mov r15, rdi
    mov [rsp], esi              # x
    mov [rsp + 4], edx          # y (moves down)
    mov [rsp + 8], ecx          # w
    mov [rsp + 12], r8d         # h
    add edx, r8d
    mov [rsp + 16], edx         # bottom
    call place_focused
    xor ecx, ecx
    cmp eax, [r15 + SP_place]
    sete cl
    mov [rsp + 20], ecx         # it has the keyboard
    M eax, MI_12
    mov ecx, [rsp]
    add ecx, eax
    mov [rsp + 24], ecx         # content x
    mov ecx, [rsp + 8]
    sub ecx, eax
    sub ecx, eax
    mov [rsp + 28], ecx         # content w
    # the status line
    mov rax, [r15 + SP_statlen]
    test rax, rax
    jz 1f
    mov eax, [rsp + 28]
    COLOR ecx, T_MUTED
    push rax
    push rcx
    lea rdi, [rip + g_face_small]
    mov esi, [rsp + 24 + 16]
    mov edx, [rsp + 4 + 16]
    M ecx, MI_24
    mov r8, [r15 + SP_status]
    mov r9, [r15 + SP_statlen]
    call ui_text_v_fit
    add rsp, 16
    M eax, MI_24
    add [rsp + 4], eax
1:  # the message box
    cmp qword ptr [r15 + SP_ph], 0
    je 2f
    lea rdi, [r15 + SP_tf]
    mov esi, [rsp + 28]
    call ta_layout
    mov ecx, 6
    cmp eax, ecx
    cmova eax, ecx
    mov ebx, eax
    call ta_line_h
    imul ebx, eax
    add ebx, [rip + g_mt + 4*MI_12]
    mov rax, [r15 + SP_ph]
    push rax
    push rax
    lea rdi, [r15 + SP_tf]
    mov esi, [rsp + 24 + 16]
    mov edx, [rsp + 4 + 16]
    mov ecx, [rsp + 28 + 16]
    mov r8d, ebx
    xor r9d, r9d
    cmp dword ptr [rsp + 20 + 16], 0
    je 11f
    mov r9d, [r15 + SP_inbox]
11: call ui_textarea
    add rsp, 16
    test eax, UB_PRESS
    jz 12f
    mov dword ptr [r15 + SP_inbox], 1
    mov edi, [r15 + SP_place]
    call place_focus
12: add ebx, [rip + g_mt + 4*MI_8]
    add [rsp + 4], ebx
2:  # the buttons, in one row
    mov ecx, [r15 + SP_nact]
    test ecx, ecx
    jz 4f
    mov eax, [rsp + 28]
    xor edx, edx
    div ecx
    mov [rsp + 32], eax         # each button's width with its gap
    mov dword ptr [rsp + 36], 0
3:  mov eax, [rsp + 36]
    cmp eax, [r15 + SP_nact]
    jae 31f
    mov rdi, r15
    mov esi, eax
    mov ecx, [rsp + 32]
    imul ecx, eax
    add ecx, [rsp + 24]
    mov edx, ecx                # x
    mov ecx, [rsp + 4]          # y
    mov r8d, [rsp + 32]
    sub r8d, [rip + g_mt + 4*MI_4]
    call draw_action
    inc dword ptr [rsp + 36]
    jmp 3b
31: M eax, MI_32
    add eax, [rip + g_mt + 4*MI_8]
    add [rsp + 4], eax
4:  # the groups
    mov edx, [rsp + 4]
    mov r8d, [rsp + 16]
    sub r8d, edx
    jle 9f
    xor r9d, r9d
    cmp dword ptr [rsp + 20], 0
    je 41f
    cmp dword ptr [r15 + SP_inbox], 0
    jne 41f
    mov r9d, 1
41: # a press in the tree takes the keyboard from the message box
    test dword ptr [rip + g_pressed], 1 << BTN_LEFT | 1 << BTN_RIGHT
    jz 42f
    cmp dword ptr [r15 + SP_inbox], 0
    je 42f
    mov [rsp + 40], edx
    mov [rsp + 44], r8d
    mov edi, [rsp]
    mov esi, edx
    mov edx, [rsp + 8]
    mov ecx, r8d
    call ui_in
    mov edx, [rsp + 40]
    mov r8d, [rsp + 44]
    test eax, eax
    jz 42f
    mov dword ptr [r15 + SP_inbox], 0
    mov r9d, 1
42: mov rdi, [r15 + SP_tree]
    mov esi, [rsp]
    mov ecx, [rsp + 8]
    call tree_draw
9:  EPILOGUE

# draw_action(sp, i, x, y, w): top-level action i as a button; a click runs it
draw_action:
    PROLOGUE 32
    mov r15, rdi
    mov [rsp], esi
    mov r12d, edx
    mov r13d, ecx
    mov r14d, r8d
    imul rbx, rsi, AC_SIZE
    add rbx, [r15 + SP_act + VEC_ptr]
    # its id: ID_SP + slot * 16 + i
    mov rax, r15
    lea rcx, [rip + sp_slots]
    sub rax, rcx
    xor edx, edx
    mov ecx, SP_SIZE
    div ecx
    shl eax, 4
    add eax, [rsp]
    lea edi, [rax + ID_SP]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    M r8d, MI_32
    call ui_btn
    mov [rsp + 4], eax
    COLOR eax, T_PANEL
    test dword ptr [rsp + 4], UB_HOVER
    jz 1f
    COLOR eax, T_HOVER
1:  push rax
    push rax
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    M ecx, MI_32
    M r8d, MI_RADIUS
    COLOR r9d, T_BORDER
    call gfx_frame
    add rsp, 16
    mov rdi, r15
    mov rsi, rbx
    call action_label
    COLOR eax, T_FG
    push rax
    push rax
    lea rdi, [rip + g_face_ui]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    M r8d, MI_32
    mov r9, [rip + tmp + SB_ptr]
    call ui_text_center
    add rsp, 16
    test dword ptr [rsp + 4], UB_CLICK
    jz 9f
    mov rdi, r15
    mov esi, [rsp]
    call run_action
9:  EPILOGUE

# action_label(sp, AC*): its label, or its command's title, in tmp as a cstr
action_label:
    PROLOGUE
    mov r15, rdi
    mov r12, rsi
    lea rdi, [rip + tmp]
    call sb_clear
    mov rdx, [r12 + AC_llen]
    test rdx, rdx
    jz 1f
    lea rdi, [rip + tmp]
    mov rsi, [r12 + AC_label]
    call sb_push
    jmp 8f
1:  mov rdi, [r15 + SP_ext]
    mov rsi, [r12 + AC_name]
    mov rdx, [r12 + AC_nlen]
    call ext_cmd_local
    test rax, rax
    jz 2f
    mov rsi, [rax + CMD_title]
    test rsi, rsi
    jz 2f
    lea rdi, [rip + tmp]
    call sb_push_cstr
    # the palette's " (TITLE)" after it is left out: the panel is the extension's own
    mov rdi, [r15 + SP_ext]
    mov rdi, [rdi + EXT_title]
    test rdi, rdi
    jz 8f
    call strlen
    mov r13, rax                # the title's length
    lea r14, [rax + 3]          # " (" TITLE ")"
    mov rax, [rip + tmp + SB_len]
    cmp rax, r14
    jbe 8f
    mov rdi, [rip + tmp + SB_ptr]
    add rdi, rax
    sub rdi, r14                # where " (" should start
    cmp word ptr [rdi], 0x2820  # " ("
    jne 8f
    cmp byte ptr [rdi + r14 - 1], ')'
    jne 8f
    add rdi, 2
    mov rsi, [r15 + SP_ext]
    mov rsi, [rsi + EXT_title]
    mov rdx, r13
    call memeq
    test eax, eax
    jz 8f
    sub [rip + tmp + SB_len], r14
    jmp 8f
2:  lea rdi, [rip + tmp]
    mov rsi, [r12 + AC_name]
    mov rdx, [r12 + AC_nlen]
    call sb_push
8:  lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    EPILOGUE

# run_action(sp, i): action i's command (FROM ref, its ARGS as the body)
run_action:
    PROLOGUE
    mov r15, rdi
    imul rbx, rsi, AC_SIZE
    add rbx, [r15 + SP_act + VEC_ptr]
    mov rdi, [r15 + SP_ext]
    mov rsi, [rbx + AC_name]
    mov rdx, [rbx + AC_nlen]
    mov rcx, [rbx + AC_args]
    mov r8, [rbx + AC_alen]
    call cmdref_new
    test rax, rax
    jz 9f
    mov r12, rax
    mov rdi, rax
    xor esi, esi
    call cmdref_invoke
    mov rdi, r12
    call cmdref_free
9:  EPILOGUE

# sp_key(sp, keysym, cp, mods) -> eax 1 when taken: the message box's while it has the keyboard
#   (Ctrl+Enter runs the first action, Escape leaves it), else the tree's
sp_key:
    PROLOGUE
    mov r15, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    cmp dword ptr [r15 + SP_inbox], 0
    je 5f
    cmp r12d, KEY_ESCAPE
    jne 1f
    mov dword ptr [r15 + SP_inbox], 0
    jmp 8f
1:  cmp r12d, KEY_RETURN
    je 2f
    cmp r12d, KEY_KP_ENTER
    jne 3f
2:  test r14d, MOD_CTRL
    jz 3f
    cmp dword ptr [r15 + SP_nact], 0
    je 8f
    mov rdi, r15
    xor esi, esi
    call run_action
    jmp 8f
3:  lea rdi, [r15 + SP_tf]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call ta_key
    test eax, eax
    jz 9f
8:  mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
5:  mov rdi, [r15 + SP_tree]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call tree_key
9:  EPILOGUE

# sp_focus(sp, on): the keyboard went: the message box lets go of it
sp_focus:
    test esi, esi
    jnz 1f
    mov dword ptr [rdi + SP_inbox], 0
1:  ret

# sp_activate(sp, tr, node): a resource's click runs its command, or opens the file
sp_activate:
    PROLOGUE
    mov r15, rdi
    mov rdi, rsi
    mov esi, edx
    call tree_user
    bt rax, 32
    jc 9f                       # a group
    mov rdi, r15
    mov rsi, rax
    call activate_res
9:  EPILOGUE

# activate_res(sp, resource index)
activate_res:
    PROLOGUE
    mov r15, rdi
    cmp rsi, [r15 + SP_res + VEC_len]
    jae 9f
    imul rbx, rsi, RS_SIZE
    add rbx, [r15 + SP_res + VEC_ptr]
    mov esi, [rbx + RS_cmd]
    test esi, esi
    js 1f
    mov rdi, r15
    call run_action
    jmp 9f
1:  # no command: the file's changes against the provider's quick-diff base, in a diff tab; the file
    # opens first when it is not open, and the diff follows when its base arrives
    mov rdi, r15
    mov rsi, rbx
    call res_abs
    mov r12, rax
    mov rdi, rax
    call open_doc_of
    test rax, rax
    jz 3f
    mov r13, rax
    cmp qword ptr [r13 + DOC_qbase], 0
    je 2f
    mov rdi, r15
    mov rsi, rbx
    mov rdx, r13
    call open_base_diff
    test eax, eax
    jnz 9f
    mov rdi, r12                # no changes: the file
    call app_open_file
    jmp 9f
2:  mov rdi, r12                # open, its base not here yet: the file, then the diff
    call app_open_file
    mov rax, r13
    jmp 5f
3:  mov rdi, r12
    call app_open_file
    test eax, eax
    js 4f
    mov edi, eax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 9f
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 9f
5:  mov rcx, [rax + DOC_id]
    mov [rip + diff_doc], rcx
    mov [rip + diff_sp], r15
    # the resource by its path: an update may replace the records before the base comes
    lea rdi, [rip + diff_path]
    mov rsi, [rbx + RS_path]
    mov rcx, [rbx + RS_plen]
    mov [rip + diff_plen], rcx
    rep movsb
    jmp 9f
4:  mov rdi, r12
    call app_open_path          # not a file it can open as text
9:  EPILOGUE

# open_doc_of(path cstr) -> rax the open text document of that file, or 0
open_doc_of:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    mov rdi, rbx
    inc rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov r13, [rax + TAB_doc]
    test r13, r13
    jz 1b
    mov rdi, [r13 + DOC_path]
    test rdi, rdi
    jz 1b
    mov rsi, r12
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rax, r13
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# open_base_diff(sp, RS*, doc) -> eax 1 when a diff tab shows the document's changes against its
#   quick-diff base ("NAME (LABEL)", read-only, as rhun's git changes look), 0 when they are equal
open_base_diff:
    PROLOGUE 32
    mov r15, rdi
    mov rbx, rsi
    mov r12, rdx
    # the file's path in the repository, a cstr, for the diff's headers
    mov rcx, [rbx + RS_plen]
    cmp rcx, 4095
    ja 8f
    lea rdi, [rip + dname]
    mov rsi, [rbx + RS_path]
    rep movsb
    mov byte ptr [rdi], 0
    mov rdi, r12
    call doc_text_copy
    mov r13, rax
    mov r14, rdx
    lea rdi, [rip + diffsb]
    call sb_clear
    lea rdi, [rip + diffsb]
    lea rsi, [rip + dname]
    mov rdx, [r12 + DOC_qbase]
    mov rcx, [r12 + DOC_qblen]
    mov r8, r13
    mov r9, r14
    call diff_unified
    mov rdi, r13
    call mem_free
    cmp qword ptr [rip + diffsb + SB_len], 0
    je 8f
    # "NAME (LABEL)": shown again when open
    mov rdi, [rbx + RS_path]
    mov rsi, [rbx + RS_plen]
    call path_basename
    lea rdi, [rip + tmp]
    mov [rsp], rax
    mov [rsp + 8], rdx
    call sb_clear
    lea rdi, [rip + tmp]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call sb_push
    lea rdi, [rip + tmp]
    lea rsi, [rip + .Lparen]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov rsi, [r15 + SP_label]
    call sb_push_cstr
    lea rdi, [rip + tmp]
    mov esi, ')'
    call sb_push_byte
    lea rdi, [rip + tmp]
    xor esi, esi
    call sb_push_byte
    # the tab this provider's click opened for this file, by that identity (titles may repeat)
    mov rdi, r15
    mov rsi, rbx
    call res_abs
    mov r14, rax
    xor r12d, r12d
1:  cmp r12, [rip + dtab_n]
    jae 3f
    imul r13, r12, 24
    lea rax, [rip + dtabs]
    add r13, rax
    inc r12
    cmp [r13 + 8], r15
    jne 1b
    mov rdi, [r13 + 16]
    mov rsi, r14
    call strcmp_eq
    test eax, eax
    jz 1b
    mov rdi, [r13]
    call tab_of_doc_id
    test eax, eax
    js 1b                       # closed since
    mov [rsp + 16], eax
    call tab_at
    mov rdi, [rax + TAB_doc]
    mov rsi, [rip + diffsb + SB_ptr]
    mov rdx, [rip + diffsb + SB_len]
    call wsdiff_show
    mov edi, [rsp + 16]
    call app_activate_tab
    jmp 7f
3:  mov rdi, [rip + tmp + SB_ptr]
    mov rsi, [rip + diffsb + SB_ptr]
    mov rdx, [rip + diffsb + SB_len]
    mov ecx, 1
    call wsdiff_tab
    mov rdi, rax
    mov rsi, r15
    mov rdx, r14
    call dtab_note
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax                # no changes (or a path too long): the caller opens the file
    EPILOGUE

# tab_of_doc_id(id) -> eax the tab showing that document, or -1
tab_of_doc_id:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + g_tabs + VEC_len]
    jae 8f
    mov rdi, rbx
    inc rbx
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne 1b
    mov rax, [rax + TAB_doc]
    test rax, rax
    jz 1b
    cmp [rax + DOC_id], r12
    jne 1b
    lea eax, [rbx - 1]
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# dtab_note(doc, sp, path cstr): remember which provider's file a new diff tab shows (32 kept: the
#   oldest goes)
dtab_note:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, r14
    call strlen
    mov rdi, r14
    mov rsi, rax
    call mem_dup
    mov r15, rax
    cmp qword ptr [rip + dtab_n], 32
    jb 1f
    mov rdi, [rip + dtabs + 16]
    call mem_free
    lea rdi, [rip + dtabs]
    lea rsi, [rip + dtabs + 24]
    mov ecx, 31 * 24
    rep movsb
    dec qword ptr [rip + dtab_n]
1:  mov rax, [rip + dtab_n]
    imul rax, rax, 24
    lea rcx, [rip + dtabs]
    add rax, rcx
    mov rdx, [r12 + DOC_id]
    mov [rax], rdx
    mov [rax + 8], r13
    mov [rax + 16], r15
    inc qword ptr [rip + dtab_n]
    EPILOGUE

# FN scmpanel_base_ready(doc): a quick-diff base came for the document (or none did, scmext.s): a click
#   that opened it to show its changes gets them now
FN scmpanel_base_ready
    PROLOGUE
    mov r12, rdi
    mov rax, [rip + diff_doc]
    test rax, rax
    jz 9f
    cmp rax, [r12 + DOC_id]
    jne 9f
    mov qword ptr [rip + diff_doc], 0
    mov r15, [rip + diff_sp]
    test r15, r15
    jz 9f
    cmp qword ptr [r12 + DOC_qbase], 0
    je 9f
    # the resource is found again by its path: the panel may have been updated meanwhile
    xor r13d, r13d
1:  cmp r13, [r15 + SP_res + VEC_len]
    jae 9f
    imul rbx, r13, RS_SIZE
    add rbx, [r15 + SP_res + VEC_ptr]
    inc r13
    mov rdx, [rbx + RS_plen]
    cmp rdx, [rip + diff_plen]
    jne 1b
    mov rdi, [rbx + RS_path]
    lea rsi, [rip + diff_path]
    call memeq
    test eax, eax
    jz 1b
    mov rdi, r15
    mov rsi, rbx
    mov rdx, r12
    call open_base_diff
9:  EPILOGUE

# FN scmpanel_field() -> rax the message box of the focused provider section while it has the
#   keyboard (clipboard routing, app.s), or 0
FN scmpanel_field
    PROLOGUE
    call place_focused
    mov edi, eax
    call place_at
    test rax, rax
    jz 8f
    mov rcx, [rax + PL_ops]
    lea rdx, [rip + sp_place_ops]
    cmp rcx, rdx
    jne 8f
    mov rax, [rax + PL_ctx]
    cmp qword ptr [rax + SP_ext], 0
    je 8f
    cmp dword ptr [rax + SP_inbox], 0
    je 8f
    add rax, SP_tf
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN scmpanel_paste(ptr, len) -> eax 1 when the text went into a provider's message box, line breaks
#   kept
FN scmpanel_paste
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    cmp dword ptr [rip + g_focus], FOCUS_VIEW
    jne 8f
    call scmpanel_field
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call ta_insert
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# sp_tree_action(sp, tr, node, key, keylen): one of a row's inline buttons ("aN": action N)
sp_tree_action:
    PROLOGUE
    mov r15, rdi
    cmp r8, 2
    jb 9f
    cmp byte ptr [rcx], 'a'
    jne 9f
    lea rdi, [rcx + 1]
    lea rsi, [r8 - 1]
    mov r12, rsi
    call parse_u64
    cmp rdx, r12
    jne 9f
    cmp rax, [r15 + SP_act + VEC_len]
    jae 9f
    mov rdi, r15
    mov rsi, rax
    call run_action
9:  EPILOGUE

# sp_title(sp, right, y, h) -> eax the x its header buttons start at: the extensions' scm_title items
#   for "scm OWNER/NAME ROOT" (menu.s)
sp_title:
    PROLOGUE 16
    mov r15, rdi
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    lea rdi, [rip + title_line]
    call sb_clear
    lea rdi, [rip + title_line]
    lea rsi, [rip + .Lscm_sp]
    call sb_push_cstr
    mov rdi, [r15 + SP_ext]
    call ext_full_name
    lea rdi, [rip + title_line]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + title_line]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + title_line]
    mov rsi, [r15 + SP_root]
    call sb_push_cstr
    # its widgets: ID_SP + slot * 16 + 8 .. 12
    mov rax, r15
    lea rcx, [rip + sp_slots]
    sub rax, rcx
    xor edx, edx
    mov ecx, SP_SIZE
    div ecx
    shl eax, 4
    lea r9d, [rax + ID_SP + 8]
    lea rdi, [rip + title_line]
    mov rsi, [rdi + SB_len]
    mov rdi, [rdi + SB_ptr]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    mov r8d, [rsp + 8]
    call menu_scm_title_buttons
    mov ecx, [rsp]
    sub ecx, eax
    mov eax, ecx
    EPILOGUE

# res_abs(sp, RS*) -> rax the resource's absolute path, a cstr in menu_path
res_abs:
    PROLOGUE
    mov r15, rdi
    mov rbx, rsi
    lea rdi, [rip + menu_path]
    call sb_clear
    lea rdi, [rip + menu_path]
    mov rsi, [r15 + SP_root]
    mov rdx, [r15 + SP_rootlen]
    call sb_push
    lea rdi, [rip + menu_path]
    mov esi, '/'
    call sb_push_byte
    lea rdi, [rip + menu_path]
    mov rsi, [rbx + RS_path]
    mov rdx, [rbx + RS_plen]
    call sb_push
    lea rdi, [rip + menu_path]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + menu_path + SB_ptr]
    EPILOGUE

# sp_menu(sp, tr, node, x, y): a group's or resource's actions as a menu (a resource also offers
#   Open File)
sp_menu:
    PROLOGUE 16
    mov r15, rdi
    mov [rsp], ecx
    mov [rsp + 4], r8d
    mov r12, rsi
    mov r13d, edx
    mov [rip + menu_sp], r15
    mov rax, [r15 + SP_gen]
    mov [rip + menu_gen], rax
    mov dword ptr [rip + menu_n], 0
    lea rdi, [rip + menu_path]
    call sb_clear
    mov rdi, r12
    mov esi, r13d
    call tree_user
    bt rax, 32
    jnc 1f
    mov eax, eax                # a group
    imul rcx, rax, GR_SIZE
    add rcx, [r15 + SP_grp + VEC_ptr]
    push rcx
    push rcx
    mov rdi, r15
    mov rsi, rcx
    xor edx, edx
    call menu_note
    pop rcx
    pop rcx
    mov edi, [rcx + GR_act0]
    mov esi, [rcx + GR_nact]
    call menu_fill
    jmp 5f
1:  cmp rax, [r15 + SP_res + VEC_len]
    jae 9f
    imul rbx, rax, RS_SIZE
    add rbx, [r15 + SP_res + VEC_ptr]
    mov esi, [rbx + RS_group]
    imul rsi, rsi, GR_SIZE
    add rsi, [r15 + SP_grp + VEC_ptr]
    mov rdi, r15
    mov rdx, rbx
    call menu_note
    mov rdi, r15
    mov rsi, rbx
    call res_abs
    mov edi, [rbx + RS_act0]
    mov esi, [rbx + RS_nact]
    call menu_fill
    # and Open File
    mov eax, [rip + menu_n]
    shl eax, 4
    lea rcx, [rip + menu_items]
    lea rdx, [rip + .Lm_open]
    mov [rcx + rax], rdx
    lea rdx, [rip + menu_open_file]
    mov [rcx + rax + 8], rdx
    inc dword ptr [rip + menu_n]
5:  mov eax, [rip + menu_n]
    shl eax, 4
    lea rcx, [rip + menu_items]
    mov qword ptr [rcx + rax], 0
    mov qword ptr [rcx + rax + 8], 0
    # the provider's actions, then other extensions' items for the location (menu.s)
    xor r8d, r8d
    cmp qword ptr [rip + menu_path + SB_len], 0
    je 6f
    mov r8, [rip + menu_path + SB_ptr]
6:  mov edi, [rip + g_scm_menu_loc]
    lea rsi, [rip + menu_items]
    mov rdx, [rip + g_scm_menu_target + SB_ptr]
    mov rcx, [rip + g_scm_menu_target + SB_len]
    call menu_open_scm
9:  EPILOGUE

# menu_note(sp, GR*, RS* or 0): the menu's target as rhun's own source control rows say it
#   (scmext.s: g_scm_menu_loc, g_scm_menu_target "group ID" or "resource ID PATH") and the context
#   keys scmProvider (OWNER/NAME), scmResourceGroup, scmResourceStatus
menu_note:
    PROLOGUE 16
    mov r15, rdi
    mov r12, rsi
    mov r13, rdx
    mov dword ptr [rip + g_scm_menu_loc], SL_SCM_GROUP
    test r13, r13
    jz 1f
    mov dword ptr [rip + g_scm_menu_loc], SL_SCM_RESOURCE
1:  mov rdi, [r15 + SP_ext]
    call ext_full_name
    mov rbx, rax
    mov rdi, rax
    call strlen
    mov edi, CTX_SCM_PROVIDER
    mov rsi, rbx
    mov rdx, rax
    call ctx_set
    mov edi, CTX_SCM_RESOURCE_GROUP
    mov rsi, [r12 + GR_id]
    mov rdx, [r12 + GR_idlen]
    call ctx_set
    xor edx, edx
    test r13, r13
    jz 2f
    mov eax, [r13 + RS_code]
    mov [rsp], al
    mov edx, 1
2:  mov edi, CTX_SCM_RESOURCE_STATUS
    lea rsi, [rsp]
    call ctx_set
    lea rdi, [rip + g_scm_menu_target]
    call sb_clear
    lea rsi, [rip + .Lt_group]
    test r13, r13
    jz 3f
    lea rsi, [rip + .Lt_resource]
3:  lea rdi, [rip + g_scm_menu_target]
    call sb_push_cstr
    lea rdi, [rip + g_scm_menu_target]
    mov rsi, [r12 + GR_id]
    mov rdx, [r12 + GR_idlen]
    call sb_push
    test r13, r13
    jz 4f
    lea rdi, [rip + g_scm_menu_target]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + g_scm_menu_target]
    mov rsi, [r13 + RS_path]
    mov rdx, [r13 + RS_plen]
    call sb_push
4:  lea rdi, [rip + g_scm_menu_target]
    xor esi, esi
    call sb_push_byte
    dec qword ptr [rip + g_scm_menu_target + SB_len]
    EPILOGUE

# menu_fill(first action, count): menu items for those actions of menu_sp (labels kept in menu_labels)
menu_fill:
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    xor r14d, r14d
1:  cmp r14d, r13d
    jae 9f
    cmp r14d, SP_ITEM_ACT_MAX
    jae 9f
    mov r15, [rip + menu_sp]
    lea eax, [r12 + r14]
    lea rcx, [rip + menu_act]
    mov [rcx + r14*4], eax
    imul rsi, rax, AC_SIZE
    add rsi, [r15 + SP_act + VEC_ptr]
    mov rdi, r15
    call action_label
    # its label, owned by the slot (the next menu replaces it)
    lea rbx, [rip + menu_labels]
    imul rax, r14, 64
    add rbx, rax
    mov rsi, [rip + tmp + SB_ptr]
    mov rdi, rbx
    mov ecx, 63
2:  mov al, [rsi]
    test al, al
    jz 3f
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz 2b
3:  mov byte ptr [rdi], 0
    mov eax, [rip + menu_n]
    shl eax, 4
    lea rcx, [rip + menu_items]
    mov [rcx + rax], rbx
    lea rdx, [rip + menu_handlers]
    mov rdx, [rdx + r14*8]
    mov [rcx + rax + 8], rdx
    inc dword ptr [rip + menu_n]
    inc r14d
    jmp 1b
9:  EPILOGUE

# the menu's handlers: action i of the menu, Open File
menu_act_0:
    xor eax, eax
    jmp menu_run
menu_act_1:
    mov eax, 1
    jmp menu_run
menu_act_2:
    mov eax, 2
    jmp menu_run
menu_act_3:
    mov eax, 3
    jmp menu_run
menu_act_4:
    mov eax, 4
    jmp menu_run
menu_act_5:
    mov eax, 5
    jmp menu_run
menu_act_6:
    mov eax, 6
    jmp menu_run
menu_act_7:
    mov eax, 7
menu_run:
    lea rcx, [rip + menu_act]
    mov esi, [rcx + rax*4]
    mov rdi, [rip + menu_sp]
    test rdi, rdi
    jz 9f
    cmp qword ptr [rdi + SP_ext], 0
    je 9f
    mov rax, [rdi + SP_gen]
    cmp rax, [rip + menu_gen]
    jne 9f                      # an update replaced the actions the menu showed
    cmp rsi, [rdi + SP_act + VEC_len]
    jae 9f
    jmp run_action
9:  ret
menu_open_file:
    mov rdi, [rip + menu_path + SB_ptr]
    test rdi, rdi
    jz 9f
    cmp byte ptr [rdi], 0
    je 9f
    jmp app_open_path
9:  ret

# ---------------- the life of providers ----------------

# sp_free(sp): everything it owns, and its slot
sp_free:
    PROLOGUE
    mov r15, rdi
    mov edi, [r15 + SP_place]
    test edi, edi
    js 1f
    call place_remove
1:  mov rdi, [r15 + SP_tree]
    call tree_free
    lea rdi, [r15 + SP_act]
    call vec_free
    lea rdi, [r15 + SP_grp]
    call vec_free
    lea rdi, [r15 + SP_res]
    call vec_free
    mov rdi, [r15 + SP_body]
    call mem_free
    mov rdi, [r15 + SP_ph]
    call mem_free
    mov rdi, [r15 + SP_tab]
    call mem_free
    mov rdi, [r15 + SP_root]
    call mem_free
    mov rdi, [r15 + SP_label]
    call mem_free
    mov rdi, [r15 + SP_ta]
    call mem_free
    mov rdi, [r15 + SP_tblob]
    call mem_free
    lea rdi, [r15 + SP_tf + TF_sb]
    call sb_free
    cmp [rip + diff_sp], r15
    jne 3f
    mov qword ptr [rip + diff_sp], 0
    mov qword ptr [rip + diff_doc], 0
3:
    # its diff tabs are no one's now (the slot may hold another provider later)
    xor ecx, ecx
4:  cmp rcx, [rip + dtab_n]
    jae 5f
    imul rax, rcx, 24
    lea rdx, [rip + dtabs]
    add rax, rdx
    inc rcx
    cmp [rax + 8], r15
    jne 4b
    mov qword ptr [rax + 8], 0
    jmp 4b
5:
    cmp [rip + menu_sp], r15
    jne 2f
    mov qword ptr [rip + menu_sp], 0
2:  mov rdi, r15
    xor esi, esi
    mov edx, SP_SIZE
    call memset
    mov dword ptr [r15 + SP_place], -1
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN scmpanel_ext_gone(ext): its providers' sections go
FN scmpanel_ext_gone
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + sp_slots]
    xor r13d, r13d
1:  cmp r13d, SP_MAX
    jae 9f
    imul r15, r13, SP_SIZE
    add r15, rbx
    inc r13d
    cmp [r15 + SP_ext], r12
    jne 1b
    mov rdi, r15
    call sp_free
    jmp 1b
9:  EPILOGUE

# ---------------- for the tests ----------------

# FN scmpanel_find(handle) -> rax its provider, or 0
FN scmpanel_find
    lea rax, [rip + sp_slots]
    xor ecx, ecx
1:  cmp ecx, SP_MAX
    jae 8f
    imul rdx, rcx, SP_SIZE
    add rdx, rax
    inc ecx
    cmp qword ptr [rdx + SP_ext], 0
    je 1b
    cmp [rdx + SP_handle], edi
    jne 1b
    mov rax, rdx
    ret
8:  xor eax, eax
    ret

# FN scmpanel_box_id(handle) -> eax its message box's widget id, or -1 (print-scm-box)
FN scmpanel_box_id
    PROLOGUE
    call scmpanel_find
    test rax, rax
    jz 8f
    mov eax, [rax + SP_tf + TF_id]
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# FN scmpanel_status_has(handle, ptr, len) -> eax 1 when that provider has sent an update whose status
#   line holds the text (any update for an empty text)
FN scmpanel_status_has
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call scmpanel_find
    test rax, rax
    jz 8f
    cmp qword ptr [rax + SP_body], 0
    je 8f
    mov rdi, [rax + SP_status]
    mov rsi, [rax + SP_statlen]
    mov rdx, r12
    mov rcx, r13
    call str_find
    test rax, rax
    js 8f
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN scmpanel_click(handle, group ptr, len, path ptr, len) -> eax 1 when that resource was clicked
FN scmpanel_click
    PROLOGUE 32
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov r13, rcx
    mov r14, r8
    call scmpanel_find
    test rax, rax
    jz 8f
    mov r15, rax
    xor ebx, ebx
1:  cmp rbx, [r15 + SP_res + VEC_len]
    jae 8f
    imul r12, rbx, RS_SIZE
    add r12, [r15 + SP_res + VEC_ptr]
    inc rbx
    cmp [r12 + RS_plen], r14
    jne 1b
    mov rdi, [r12 + RS_path]
    mov rsi, r13
    mov rdx, r14
    call memeq
    test eax, eax
    jz 1b
    mov eax, [r12 + RS_group]
    imul rcx, rax, GR_SIZE
    add rcx, [r15 + SP_grp + VEC_ptr]
    mov rax, [rcx + GR_idlen]
    cmp rax, [rsp + 8]
    jne 1b
    mov rdi, [rcx + GR_id]
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call memeq
    test eax, eax
    jz 1b
    lea rsi, [rbx - 1]
    mov rdi, r15
    call activate_res
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN scmpanel_action(handle, i) -> eax 1 when the top-level action ran
FN scmpanel_action
    PROLOGUE
    mov r12d, esi
    call scmpanel_find
    test rax, rax
    jz 8f
    cmp r12d, [rax + SP_nact]
    jae 8f
    mov rdi, rax
    mov esi, r12d
    call run_action
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN scmpanel_focus(handle) -> eax 1: its message box has the keyboard
FN scmpanel_focus
    PROLOGUE
    call scmpanel_find
    test rax, rax
    jz 8f
    cmp qword ptr [rax + SP_ph], 0
    je 8f
    mov rbx, rax
    mov edi, [rbx + SP_place]
    xor esi, esi
    call place_show
    mov edi, [rbx + SP_place]
    call place_focus
    mov dword ptr [rbx + SP_inbox], 1
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN scmpanel_menu(handle, node id ptr, len) -> eax 1 when that node's menu opened
FN scmpanel_menu
    PROLOGUE
    mov r12, rsi
    mov r13, rdx
    call scmpanel_find
    test rax, rax
    jz 8f
    mov r15, rax
    mov rdi, [r15 + SP_tree]
    mov rsi, r12
    mov rdx, r13
    call tree_find
    test eax, eax
    jle 8f
    mov rdi, r15
    mov rsi, [r15 + SP_tree]
    mov edx, eax
    mov ecx, 100
    mov r8d, 100
    call sp_menu
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN scmpanel_dump(sb): per provider "scm H OWNER/NAME ROOT label=L status=S input=TEXT actions=A,B",
#   then its tree's rows
FN scmpanel_dump
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + sp_slots]
    xor r13d, r13d
1:  cmp r13d, SP_MAX
    jae 9f
    imul r15, r13, SP_SIZE
    add r15, rbx
    inc r13d
    cmp qword ptr [r15 + SP_ext], 0
    je 1b
    mov rdi, r12
    lea rsi, [rip + .Ld_scm]
    call sb_push_cstr
    mov rdi, r12
    mov esi, [r15 + SP_handle]
    call sb_push_u64
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, [r15 + SP_ext]
    call ext_full_name
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    mov rsi, [r15 + SP_root]
    mov rdx, [r15 + SP_rootlen]
    call sb_push
    mov rdi, r12
    lea rsi, [rip + .Ld_label]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r15 + SP_label]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_status]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r15 + SP_status]
    mov rdx, [r15 + SP_statlen]
    call sb_push
    mov rdi, r12
    lea rsi, [rip + .Ld_input]
    call sb_push_cstr
    lea rdi, [r15 + SP_tf]
    call tf_text
    mov rdi, r12
    mov rsi, rax
    call sb_push
    mov rdi, r12
    lea rsi, [rip + .Ld_actions]
    call sb_push_cstr
    xor r14d, r14d
2:  cmp r14d, [r15 + SP_nact]
    jae 3f
    test r14d, r14d
    jz 21f
    mov rdi, r12
    mov esi, ','
    call sb_push_byte
21: imul rsi, r14, AC_SIZE
    add rsi, [r15 + SP_act + VEC_ptr]
    mov rdi, r15
    call action_label
    mov rdi, r12
    mov rsi, [rip + tmp + SB_ptr]
    call sb_push_cstr
    inc r14d
    jmp 2b
3:  mov rdi, r12
    mov esi, 10
    call sb_push_byte
    mov rdi, [r15 + SP_tree]
    mov rsi, r12
    call tree_dump
    jmp 1b
9:  EPILOGUE

.section .rodata
.Lok: .asciz "ok "
.Ldot_scm: .asciz ".scm."
.Lfile_pfx: .asciz "file:"
.Lsep: .asciz "  "
.Lm_open: .asciz "Open File"
.Linline: .asciz "inline "
.Lparen: .asciz " ("
.Lscm_sp: .asciz "scm "
.Lt_group: .asciz "group "
.Lt_resource: .asciz "resource "
.Le_unknown: .asciz "unknown no such request"
.Le_full: .asciz "toobig 4 providers per extension, 16 in all"
.Le_noscm: .asciz "refused no such provider"
.Ld_scm: .asciz "scm "
.Ld_label: .asciz " label="
.Ld_status: .asciz " status="
.Ld_input: .asciz " input="
.Ld_actions: .asciz " actions="
.Lc_added: .asciz "added"
.Lc_modified: .asciz "modified"
.Lc_deleted: .asciz "deleted"
.Lc_conflict: .asciz "conflict"
.Lc_untracked: .asciz "untracked"
.Lc_ignored: .asciz "ignored"
.p2align 3
color_names: .quad .Lc_added, T_GIT_ADD, .Lc_modified, T_GIT_MOD, .Lc_deleted, T_GIT_DEL
    .quad .Lc_conflict, T_ERROR, .Lc_untracked, T_GIT_ADD, .Lc_ignored, T_MUTED, 0, 0
menu_handlers: .quad menu_act_0, menu_act_1, menu_act_2, menu_act_3, menu_act_4, menu_act_5
    .quad menu_act_6, menu_act_7
sp_place_ops: .quad sp_draw, sp_key, sp_focus, 0, sp_title, 0
sp_tree_ops: .quad sp_activate, 0, 0, 0, sp_menu, 0, 0, 0, sp_tree_action

.bss
.p2align 3
menu_labels: .zero 64 * SP_ITEM_ACT_MAX
