# workspace edits (docs/extensions/v1.md 12g; v1.1.md workspace-edits and file-operations): an
# extension's edit across documents and files, read and checked whole before anything changes,
# then made as one transaction (wstx.s) that undoes and redoes as one step. Without the features
# an edit keeps v1's behaviour: files that are not open open in tabs, unsaved.
.include "rhun.inc"

.equ WS_BODY_MAX, 4194304       # a workspace edit (12g)
.equ WS_ENTRIES_MAX, 1000       # its entries (files, file operations)
.equ WS_EDITS_MAX, 100000
.equ WS_LABEL_MAX, 200
.equ WSF_EDITS, 1               # ws_feats: the extension agreed workspace-edits
.equ WSF_OPS, 2                 # and file-operations

.bss
.p2align 3
.globl wg_vec, we_vec, ws_only, ws_act_data, ws_act_dlen, ws_req_id, ws_quiet, ws_feats, ws_ext
.globl ws_entry, ws_pathbuf, ws_confirm, ws_request_ext, ws_back, ws_code, ws_deflabel, ws_preserve_context, ws_body
wg_vec: .zero VEC_SIZE          # the workspace edit being made
we_vec: .zero VEC_SIZE
ws_only: .quad 0                # a document id: the edit may change that document only
ws_request_ext: .quad 0         # an extension's apply request: its permissions gate closed files
ws_ext: .quad 0                 # the extension whose agreed features decide the grammar, or 0
ws_feats: .quad 0               # WSF_*: the features the extension agreed
ws_deflabel: .quad 0            # the caller's name for the edit (cstr), or 0
ws_code: .quad 0                # the reply for the last failure ("CODE TEXT"; "CODE ENTRY TEXT")
ws_toast: .quad 0               # and its toast
ws_entry: .quad 0               # the entry being read or checked (1-based), 0 for none
ws_confirm: .quad 0             # the edit asked for the confirmation list
ws_body: .quad 0                # an owned copy of the body (the features: the edit may wait)
ws_back: .quad 0                # the document the user was in
ws_act_data: .quad 0            # a code action's DATA, sent once its edit is made, and its length
ws_act_dlen: .quad 0
ws_req_id: .quad 0              # an apply request's id (the reply may wait for the user)
ws_quiet: .long 0               # an extension's request: no toast
ws_preserve_context: .long 0    # restricted background edit: never activate or reveal a tab
.globl ws_wrote
ws_wrote: .long 0               # the last edit wrote files (no "save them" advice)
ws_pad: .long 0
ws_label: .zero SB_SIZE         # the edit's name: its label record, else the caller's
ws_codesb: .zero SB_SIZE
ws_rename: .zero SB_SIZE        # "Rename to 'NAME'"
ws_pathbuf: .zero 4100          # a path as a cstr

.text

# ---------------- entry points ----------------

# FN ws_apply(body, len) -> eax 1 when every edit was made, 0 when none was (a toast says why);
# v1's grammar (format answers, which change one document)
FN ws_apply
    mov qword ptr [rip + ws_ext], 0
    mov qword ptr [rip + ws_deflabel], 0
    jmp ws_run

# FN ws_apply_from(body, len, ext, label cstr or 0) -> eax 1 made, 0 not (a toast says why), 2
# waiting for the user's answer in the confirmation list; the extension's agreed features decide
# the grammar (a rename's answer, a code action's edit)
FN ws_apply_from
    mov [rip + ws_ext], rdx
    mov [rip + ws_deflabel], rcx
    jmp ws_run

# FN ws_apply_action(body, len, ext, title cstr, data, dlen) -> eax as ws_apply_from: a code
# action's edit; when the confirmation list waits, the action's DATA goes to the extension once
# the edit is made (with eax 1 the caller sends it)
FN ws_apply_action
    push rbx
    mov [rip + ws_ext], rdx
    mov [rip + ws_deflabel], rcx
    mov [rip + ws_act_data], r8
    mov [rip + ws_act_dlen], r9
    call ws_run
    mov qword ptr [rip + ws_act_dlen], 0
    pop rbx
    ret

# FN ws_rename_label(name ptr, len) -> rax "Rename to 'NAME'" (a cstr until the next call)
FN ws_rename_label
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + ws_rename]
    call sb_clear
    lea rdi, [rip + ws_rename]
    lea rsi, [rip + .Lrename_to]
    call sb_push_cstr
    cmp r12, 160
    jbe 1f
    mov r12d, 160
1:  lea rdi, [rip + ws_rename]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    lea rdi, [rip + ws_rename]
    mov esi, 39
    call sb_push_byte
    lea rdi, [rip + ws_rename]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + ws_rename + SB_ptr]
    pop r13
    pop r12
    pop rbx
    ret

# FN ws_apply_request(body, len, ext, id) -> eax 1 when every edit was made; 0 when none was, with
# rdx the error reply's text; 2 when the confirmation list waits for the user (the reply goes
# when the user answers). An extension's apply request: no toast, the extension hears why
FN ws_apply_request
    push rbx
    mov [rip + ws_req_id], rcx
    mov [rip + ws_request_ext], rdx
    mov [rip + ws_ext], rdx
    mov qword ptr [rip + ws_deflabel], 0
    mov dword ptr [rip + ws_quiet], 1
    call ws_run
    mov dword ptr [rip + ws_quiet], 0
    mov qword ptr [rip + ws_request_ext], 0
    mov qword ptr [rip + ws_req_id], 0
    mov rdx, [rip + ws_code]
    pop rbx
    ret

# FN ws_apply_document(body, len, doc id, quiet): one already open document, with no
# activation, tab creation, or cursor reveal. Restore caller state on every outcome.
FN ws_apply_document
    PROLOGUE 48
    mov [rsp + 16], rdi
    mov [rsp + 24], rsi
    mov [rsp + 32], rdx
    mov [rsp + 40], ecx
    mov rdi, rdx
    call extproto_doc
    test rax, rax
    jz 8f
    mov rax, [rip + ws_only]
    mov [rsp], rax
    mov eax, [rip + ws_quiet]
    mov [rsp + 8], eax
    mov eax, [rip + ws_preserve_context]
    mov [rsp + 12], eax
    mov rdx, [rsp + 32]
    mov [rip + ws_only], rdx
    mov ecx, [rsp + 40]
    mov [rip + ws_quiet], ecx
    mov dword ptr [rip + ws_preserve_context], 1
    mov qword ptr [rip + ws_ext], 0
    mov qword ptr [rip + ws_deflabel], 0
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call ws_run
    mov rdx, [rsp]
    mov [rip + ws_only], rdx
    mov edx, [rsp + 8]
    mov [rip + ws_quiet], edx
    mov edx, [rsp + 12]
    mov [rip + ws_preserve_context], edx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- the run ----------------

# ws_run(body, len) -> eax 1 made, 0 not, 2 waiting for the confirmation list
ws_run:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov qword ptr [rip + wg_vec + VEC_len], 0
    mov qword ptr [rip + we_vec + VEC_len], 0
    mov qword ptr [rip + ws_confirm], 0
    mov qword ptr [rip + ws_entry], 0
    mov qword ptr [rip + ws_body], 0
    mov dword ptr [rip + ws_wrote], 0
    lea rdi, [rip + ws_label]
    call sb_clear
    mov rax, [rip + g_doc]
    mov [rip + ws_back], rax
    call ws_parked              # another edit waits for the user: this one is busy
    test eax, eax
    jnz .Lwr_busy
    # the grammar: the features the extension agreed (a restricted edit keeps v1's)
    xor eax, eax
    mov rcx, [rip + ws_ext]
    test rcx, rcx
    jz 1f
    cmp qword ptr [rip + ws_only], 0
    jne 1f
    FEAT_TEST rcx, FEAT_WORKSPACE_EDITS
    jz 1f
    mov eax, WSF_EDITS
    FEAT_TEST rcx, FEAT_FILE_OPERATIONS
    jz 1f
    or eax, WSF_OPS
1:  mov [rip + ws_feats], rax
    cmp r13, WS_BODY_MAX
    ja .Lwr_big
    test rax, rax
    jz 2f
    # the edit may wait for the user: it reads from a copy of its own
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [rip + ws_body], rax
    mov r12, rax
2:  mov rdi, r12
    mov rsi, r13
    call ws_parse
    test eax, eax
    jz .Lwr_fail
    call ws_resolve
    test eax, eax
    jz .Lwr_fail
    call ws_check
    test eax, eax
    jz .Lwr_fail
    cmp qword ptr [rip + ws_feats], 0
    je 3f
    # workspace-edits: closed files edited in their hidden documents; the confirmation list
    # when the edit writes to disk without the extension's permission (wsconfirm.s)
    call ws_disk_prepare
    call ws_gate
    test eax, eax
    jz .Lwr_fail
    cmp eax, 2
    jne 3f
    EPILOGUE                    # waiting for the user: the plan stays as it is
3:  call ws_commit
    test eax, eax
    jz .Lwr_fail
    call ws_finish
    mov eax, 1
    EPILOGUE
.Lwr_big:
    lea rdi, [rip + .Lwc_big]
    lea rsi, [rip + .Lws_e_big]
    call ws_err
.Lwr_fail:
    call ws_unwind
    xor eax, eax
    EPILOGUE
.Lwr_busy:
    mov qword ptr [rip + ws_feats], 0   # nothing of the waiting plan is touched
    lea rdi, [rip + .Lwc_busy]
    lea rsi, [rip + .Lws_e_busy]
    call ws_err
    cmp dword ptr [rip + ws_quiet], 0
    jne 4f
    mov rdi, [rip + ws_toast]
    call app_toast
4:  xor eax, eax
    EPILOGUE

# FN ws_err(reply "CODE TEXT", toast) -> eax 0: the failure's reply and toast; with workspace-edits
# agreed the reply names the entry at fault: "CODE ENTRY TEXT"
FN ws_err
    PROLOGUE
    mov rbx, rdi
    mov [rip + ws_toast], rsi
    mov [rip + ws_code], rdi
    cmp qword ptr [rip + ws_feats], 0
    je 9f
    lea rdi, [rip + ws_codesb]
    call sb_clear
    xor r12d, r12d
1:  cmp byte ptr [rbx + r12], ' '
    je 2f
    cmp byte ptr [rbx + r12], 0
    je 2f
    inc r12
    jmp 1b
2:  lea rdi, [rip + ws_codesb]
    mov rsi, rbx
    mov rdx, r12
    call sb_push
    lea rdi, [rip + ws_codesb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + ws_codesb]
    mov rsi, [rip + ws_entry]
    call sb_push_u64
    lea rdi, [rip + ws_codesb]
    lea rsi, [rbx + r12]
    call sb_push_cstr
    lea rdi, [rip + ws_codesb]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + ws_codesb + SB_ptr]
    mov [rip + ws_code], rax
9:  xor eax, eax
    EPILOGUE

# FN ws_unwind(): nothing changed: the tabs this edit opened close, the hidden documents go, the
# user's document is active again, a toast says why (unless quiet)
FN ws_unwind
    PROLOGUE
    cmp dword ptr [rip + ws_quiet], 0
    jne 1f
    mov rdi, [rip + ws_toast]
    test rdi, rdi
    jz 1f
    call app_toast
1:  call ws_release
    cmp dword ptr [rip + ws_preserve_context], 0
    jne 3f                      # restricted resolution opened nothing; keep current interaction
    mov rbx, [rip + wg_vec + VEC_len]
2:  test rbx, rbx
    jz 4f
    dec rbx
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    cmp qword ptr [r12 + WG_opened], 0
    je 2b
    mov qword ptr [r12 + WG_opened], 0
    mov rdi, [r12 + WG_doc]
    call doc_tab
    test rax, rax
    js 2b
    mov rdi, rax
    call app_close_tab_now
    jmp 2b
4:  call ws_go_back
3:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ws_go_back(): the document the user was in is active again
ws_go_back:
    push rbx
    mov rdi, [rip + ws_back]
    test rdi, rdi
    jz 9f
    call doc_tab
    test rax, rax
    js 9f
    mov rdi, rax
    call app_activate_tab
9:  pop rbx
    ret

# ws_release(): what the run owns goes: hidden documents, read originals, paths, the body copy
FN ws_release
    PROLOGUE
    xor ebx, ebx
1:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 2f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    cmp qword ptr [r12 + WG_hidden], 0
    je 11f
    mov qword ptr [r12 + WG_hidden], 0
    mov rdi, [r12 + WG_doc]
    mov qword ptr [r12 + WG_doc], 0
    call doc_free
11: mov rdi, [r12 + WG_orig]
    mov qword ptr [r12 + WG_orig], 0
    call mem_free
    mov rdi, [r12 + WG_new]
    mov qword ptr [r12 + WG_new], 0
    call mem_free
    mov rdi, [r12 + WG_real]
    mov qword ptr [r12 + WG_real], 0
    call mem_free
    jmp 1b
2:  mov rdi, [rip + ws_body]
    mov qword ptr [rip + ws_body], 0
    call mem_free
    EPILOGUE

# FN ws_finish(): a made edit: back to the user's document, the run's leftovers go
FN ws_finish
    PROLOGUE
    call ws_release
    cmp dword ptr [rip + ws_preserve_context], 0
    jne 1f
    call ws_go_back
1:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# ---------------- reading ----------------

# ws_parse(body, len) -> eax 1 with wg_vec and we_vec filled (pointing into the body), 0 when it
# breaks the grammar (ws_code says how)
ws_parse:
    PROLOGUE 16
    mov edx, 0x7fffffff
    call lf_head
    test rax, rax
    js .Lwp_bad
    cmp rax, WS_ENTRIES_MAX
    ja .Lwp_big
    mov r15, rax                # entries left
.Lwp_entry:
    test r15, r15
    jz .Lwp_records
    dec r15
    inc qword ptr [rip + ws_entry]
    call ps_line
    test eax, eax
    jz .Lwp_bad
    # a file operation (file-operations) or a text group
    test qword ptr [rip + ws_feats], WSF_OPS
    jz .Lwp_text
    mov rax, [rip + ps_ptr]
    mov rcx, [rip + ps_lend]
    sub rcx, rax
    cmp rcx, 7
    jb .Lwp_text
    cmp byte ptr [rax + 6], ' '
    jne .Lwp_text
    mov rdi, rax
    mov esi, 6
    lea rdx, [rip + .Lk_create]
    call str_eq_cstr
    mov ebx, WK_CREATE
    test eax, eax
    jnz .Lwp_op
    mov rdi, [rip + ps_ptr]
    mov esi, 6
    lea rdx, [rip + .Lk_rename]
    call str_eq_cstr
    mov ebx, WK_RENAME
    test eax, eax
    jnz .Lwp_op
    mov rdi, [rip + ps_ptr]
    mov esi, 6
    lea rdx, [rip + .Lk_delete]
    call str_eq_cstr
    mov ebx, WK_DELETE
    test eax, eax
    jnz .Lwp_op
.Lwp_text:
    # PATH_LEN PRE M, then the path
    call ps_num
    test edx, edx
    jz .Lwp_bad
    test rax, rax
    jz .Lwp_bad
    cmp rax, 4096
    ja .Lwp_bad
    mov r12, rax                # the path's length
    call ps_word
    mov rdi, rax
    mov rsi, rdx
    call ws_pre
    test eax, eax
    jz .Lwp_bad
    mov [rsp], rdx              # its kind and version or hash
    mov [rsp + 8], rcx
    call ps_num
    test edx, edx
    jz .Lwp_bad
    mov r14, rax                # the edits
    call ps_eol
    test eax, eax
    jz .Lwp_bad
    mov rdi, r12
    call lf_take
    test rax, rax
    jz .Lwp_bad
    mov rbx, rax
    lea rdi, [rip + wg_vec]
    mov esi, WG_SIZE
    call vec_push
    mov r13, rax
    mov rdi, rax
    xor esi, esi
    mov edx, WG_SIZE
    call memset
    mov qword ptr [r13 + WG_kind], WK_TEXT
    mov [r13 + WG_path], rbx
    mov [r13 + WG_plen], r12
    mov rax, [rsp]
    mov [r13 + WG_pre], rax
    mov rax, [rsp + 8]
    mov [r13 + WG_version], rax
    mov [r13 + WG_hash], rax
    cmp qword ptr [r13 + WG_pre], WP_HASH
    je 1f
    cmp qword ptr [r13 + WG_pre], WP_VERSION
    je 1f
    mov qword ptr [r13 + WG_version], -1
1:  mov rcx, [rip + we_vec + VEC_len]
    mov [r13 + WG_first], rcx
    mov [r13 + WG_count], r14
    add rcx, r14
    cmp rcx, WS_EDITS_MAX
    ja .Lwp_big
.Lwp_edit:
    test r14, r14
    jz .Lwp_entry
    dec r14
    call ps_line
    test eax, eax
    jz .Lwp_bad
    call lf_four
    test eax, eax
    jz .Lwp_bad
    call ps_num
    test edx, edx
    jz .Lwp_bad
    mov r12, rax
    call ps_eol
    test eax, eax
    jz .Lwp_bad
    mov rdi, r12
    call lf_take
    test rax, rax
    jz .Lwp_bad
    mov rbx, rax
    lea rdi, [rip + we_vec]
    mov esi, WE_SIZE
    call vec_push
    lea rcx, [rip + lf_tmp4]
    mov edx, [rcx]
    mov [rax + WE_l1], edx
    mov edx, [rcx + 4]
    mov [rax + WE_c1], edx
    mov edx, [rcx + 8]
    mov [rax + WE_l2], edx
    mov edx, [rcx + 12]
    mov [rax + WE_c2], edx
    mov [rax + WE_text], rbx
    mov [rax + WE_len], r12
    jmp .Lwp_edit
.Lwp_op:
    # create PATH_LEN FLAGS | rename FROM_LEN TO_LEN FLAGS | delete PATH_LEN FLAGS
    call ps_word                # the kind
    lea rdi, [rip + wg_vec]
    mov esi, WG_SIZE
    call vec_push
    mov r13, rax
    mov rdi, rax
    xor esi, esi
    mov edx, WG_SIZE
    call memset
    mov [r13 + WG_kind], rbx
    mov qword ptr [r13 + WG_version], -1
    call ps_num
    test edx, edx
    jz .Lwp_bad
    test rax, rax
    jz .Lwp_bad
    cmp rax, 4096
    ja .Lwp_bad
    mov [r13 + WG_plen], rax
    cmp rbx, WK_RENAME
    jne 2f
    call ps_num
    test edx, edx
    jz .Lwp_bad
    test rax, rax
    jz .Lwp_bad
    cmp rax, 4096
    ja .Lwp_bad
    mov [r13 + WG_plen2], rax
2:  call ps_word
    mov rdi, rax
    mov rsi, rdx
    mov edx, ebx
    call ws_flags
    test eax, eax
    jz .Lwp_bad
    mov [r13 + WG_flags], rdx
    call ps_eol
    test eax, eax
    jz .Lwp_bad
    mov rdi, [r13 + WG_plen]
    call lf_take
    test rax, rax
    jz .Lwp_bad
    mov [r13 + WG_path], rax
    cmp rbx, WK_RENAME
    jne .Lwp_entry
    mov rdi, [r13 + WG_plen2]
    call lf_take
    test rax, rax
    jz .Lwp_bad
    mov [r13 + WG_path2], rax
    jmp .Lwp_entry
.Lwp_records:
    mov qword ptr [rip + ws_entry], 0
    test qword ptr [rip + ws_feats], WSF_EDITS
    jz .Lwp_end
    # extra records: NAME ARGS... LEN, then LEN bytes
.Lwp_record:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jae .Lwp_ok
    call ps_line
    test eax, eax
    jz .Lwp_bad
    call ps_word
    test rdx, rdx
    jz .Lwp_bad
    mov rbx, rax                # the name
    mov r14, rdx
    xor r12d, r12d              # the last word: LEN
    xor r13d, r13d
3:  mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_lend]
    jae 4f
    call ps_word
    test rdx, rdx
    jz .Lwp_bad
    mov r12, rax
    mov r13, rdx
    jmp 3b
4:  test r13, r13
    jz .Lwp_bad
    cmp r13, 10
    ja .Lwp_bad
    mov rdi, r12
    mov rsi, r13
    call parse_u64
    cmp rdx, r13
    jne .Lwp_bad
    mov r12, rax                # LEN
    call ps_eol
    test eax, eax
    jz .Lwp_bad
    mov rdi, r12
    call lf_take
    test rax, rax
    jz .Lwp_bad
    mov r13, rax                # its bytes
    mov rdi, rbx
    mov rsi, r14
    lea rdx, [rip + .Lr_label]
    call str_eq_cstr
    test eax, eax
    jz 5f
    # label: one line, at most 200 bytes (cut at a character)
    xor ecx, ecx
41: cmp rcx, r12
    jae 42f
    cmp byte ptr [r13 + rcx], 10
    je 42f
    cmp byte ptr [r13 + rcx], 13
    je 42f
    inc rcx
    jmp 41b
42: mov rdi, rcx
    mov rsi, r13
    mov edx, WS_LABEL_MAX
    call utf8_cut
    mov rdx, rax
    lea rdi, [rip + ws_label]
    call sb_clear
    lea rdi, [rip + ws_label]
    mov rsi, r13
    call sb_push
    jmp .Lwp_record
5:  mov rdi, rbx
    mov rsi, r14
    lea rdx, [rip + .Lr_confirm]
    call str_eq_cstr
    test eax, eax
    jz .Lwp_record              # unknown: skipped
    mov qword ptr [rip + ws_confirm], 1
    jmp .Lwp_record
.Lwp_end:
    mov rax, [rip + ps_ptr]
    cmp rax, [rip + ps_end]
    jne .Lwp_bad
.Lwp_ok:
    mov eax, 1
    EPILOGUE
.Lwp_bad:
    lea rdi, [rip + .Lwc_bad]
    lea rsi, [rip + .Lws_e_bad]
    call ws_err
    EPILOGUE
.Lwp_big:
    lea rdi, [rip + .Lwc_big]
    lea rsi, [rip + .Lws_e_big]
    call ws_err
    EPILOGUE

# ws_pre(word, len) -> eax 1 with rdx the PRE kind (WP_*) and rcx the version or hash: a version
# (at most 18 digits), "-", or with workspace-edits "fnv1a64:" and 16 lowercase hex digits
ws_pre:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 8f
    cmp r12, 1
    jne 1f
    cmp byte ptr [rbx], '-'
    jne 1f
    mov edx, WP_DASH
    mov rcx, -1
    jmp 9f
1:  test qword ptr [rip + ws_feats], WSF_EDITS
    jz 3f
    cmp r12, 24
    jne 3f
    mov rdi, rbx
    mov esi, 8
    lea rdx, [rip + .Lfnv_prefix]
    call str_eq_cstr
    test eax, eax
    jz 3f
    xor eax, eax
    mov ecx, 8
2:  cmp ecx, 24
    jae 21f
    movzx edx, byte ptr [rbx + rcx]
    lea r8d, [rdx - '0']
    cmp r8d, 9
    jbe 22f
    lea r8d, [rdx - 'a']
    cmp r8d, 5
    ja 8f
    add r8d, 10
22: shl rax, 4
    or rax, r8
    inc ecx
    jmp 2b
21: mov edx, WP_HASH
    mov rcx, rax
    jmp 9f
3:  cmp r12, 18
    ja 8f
    mov rdi, rbx
    mov rsi, r12
    call parse_u64
    cmp rdx, r12
    jne 8f
    mov edx, WP_VERSION
    mov rcx, rax
9:  mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
8:  xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

# ws_flags(word, len, kind) -> eax 1 with rdx the WF_* bits: "-" or a comma-separated list of the
# flags the kind takes; an unknown one is 0
ws_flags:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor r14d, r14d              # the bits
    test r12, r12
    jz 8f
    cmp r12, 1
    jne 1f
    cmp byte ptr [rbx], '-'
    je 9f
1:  # each name up to a comma
    xor r15d, r15d              # its start
2:  mov rcx, r15
3:  cmp rcx, r12
    jae 4f
    cmp byte ptr [rbx + rcx], ','
    je 4f
    inc rcx
    jmp 3b
4:  mov [rsp], rcx
    lea rdi, [rbx + r15]
    mov rsi, rcx
    sub rsi, r15
    call ws_flag_bit
    test eax, eax
    jz 8f
    or r14d, eax
    mov rcx, [rsp]
    cmp rcx, r12
    jae 9f
    lea r15, [rcx + 1]
    jmp 2b
9:  mov rdx, r14
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ws_flag_bit(name, len) -> eax the WF_* bit of a flag the kind (r13d of ws_flags) takes, or 0
ws_flag_bit:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    cmp r13d, WK_DELETE
    je 2f
    lea rdx, [rip + .Lf_overwrite]
    call str_eq_cstr
    mov ecx, WF_OVERWRITE
    test eax, eax
    jnz 7f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lf_ignore_existing]
    call str_eq_cstr
    mov ecx, WF_IGNORE_EXISTING
    test eax, eax
    jnz 7f
    jmp 8f
2:  lea rdx, [rip + .Lf_recursive]
    call str_eq_cstr
    mov ecx, WF_RECURSIVE
    test eax, eax
    jnz 7f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lf_ignore_missing]
    call str_eq_cstr
    mov ecx, WF_IGNORE_MISSING
    test eax, eax
    jnz 7f
8:  xor eax, eax
    jmp 9f
7:  mov eax, ecx
9:  add rsp, 8
    pop r12
    pop rbx
    ret

# ---------------- resolving ----------------

# FN ws_path(WG*, second) -> eax 1 with its path (a rename's TO when second is 1) in ws_pathbuf as a
# cstr, 0 when it holds a NUL or is too long
FN ws_path
    mov r8, [rdi + WG_path]
    mov rcx, [rdi + WG_plen]
    test esi, esi
    jz 1f
    mov r8, [rdi + WG_path2]
    mov rcx, [rdi + WG_plen2]
1:  cmp rcx, 4096
    ja 8f
    lea rdx, [rip + ws_pathbuf]
    xor eax, eax
2:  cmp rax, rcx
    jae 3f
    movzx esi, byte ptr [r8 + rax]
    test esi, esi
    jz 8f
    mov [rdx + rax], sil
    inc rax
    jmp 2b
3:  mov byte ptr [rdx + rax], 0
    mov eax, 1
    ret
8:  xor eax, eax
    ret

# ws_resolve() -> eax 1 with each text group's document: an open one by id or path at its
# version; a file that is not open opens in a tab of its own (v1) or is read into a hidden
# document (workspace-edits); 0 when one cannot be (ws_code says why)
ws_resolve:
    PROLOGUE 16
    xor ebx, ebx
.Lwv_find:
    cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lwv_open
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne .Lwv_find               # file operations: the disk pass (wsdisk.s)
    mov qword ptr [r12 + WG_doc], 0
    mov qword ptr [r12 + WG_opened], 0
    mov rdi, r12
    xor esi, esi
    call ws_path
    test eax, eax
    jz .Lwv_badpath
    cmp byte ptr [rip + ws_pathbuf], '#'
    jne 4f
    cmp qword ptr [r12 + WG_pre], WP_HASH
    je .Lwv_bad                 # a document by its id is named at a version
    lea rdi, [rip + ws_pathbuf]
    call lf_doc_ref
    test rax, rax
    js .Lwv_badpath
    mov rdi, rax
    call extproto_doc
    test rax, rax
    jz .Lwv_gone
    mov [r12 + WG_doc], rax
    jmp 5f
4:  lea rdi, [rip + ws_pathbuf]
    call lf_is_abs
    test eax, eax
    jz .Lwv_badpath
    lea rdi, [rip + ws_pathbuf]
    call app_find_tab
    test rax, rax
    jns 42f
    cmp qword ptr [rip + ws_only], 0
    jne .Lwv_badpath            # restricted edits never open an unrecognized file
    mov rdi, [rip + ws_request_ext]
    lea rsi, [rip + ws_pathbuf]
    call ext_open_path
    test rax, rax
    jz 41f                      # the open pass distinguishes missing and forbidden files
    mov r13, rax
    lea rdi, [rip + ws_pathbuf]
    mov rsi, r13
    call cstr_copy
    mov rdi, r13
    call mem_free
    lea rdi, [rip + ws_pathbuf]
    call app_find_tab
    test rax, rax
    js 41f
42: mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lwv_badpath
    mov rax, [rax + TAB_doc]
    mov [r12 + WG_doc], rax
    jmp 5f
41: cmp qword ptr [r12 + WG_pre], WP_VERSION
    je .Lwv_gone                # it was open when the edit was made
    jmp .Lwv_find
5:  mov rax, [r12 + WG_doc]
    mov rcx, [rip + ws_only]
    test rcx, rcx
    jz 50f
    cmp rcx, [rax + DOC_id]
    jne .Lwv_badpath            # reject before the disk/tab opening pass
50: mov rdi, rax
    call doc_dirty
    xor ecx, ecx
    test eax, eax
    sete cl
    mov [r12 + WG_clean], rcx
    mov rax, [r12 + WG_doc]
    mov rcx, [rax + DOC_version]
    mov [r12 + WG_ver0], rcx
    cmp qword ptr [r12 + WG_pre], WP_VERSION
    je 51f
    # made from the file on disk: right for an open document only while it has no changes
    cmp qword ptr [r12 + WG_clean], 0
    je .Lwv_stale
    cmp qword ptr [r12 + WG_pre], WP_HASH
    jne .Lwv_find
    # and the file still hashes as the extension says
    mov rdi, r12
    call ws_disk_hash_open
    test eax, eax
    jz .Lwv_fail
    jmp .Lwv_find
51: mov rcx, [r12 + WG_version]
    cmp rcx, [rax + DOC_version]
    jne .Lwv_stale
    jmp .Lwv_find
.Lwv_open:
    # files that are not open
    test qword ptr [rip + ws_feats], WSF_EDITS
    jz 60f
    call ws_disk_resolve        # read into hidden documents, file operations checked (wsdisk.s)
    test eax, eax
    jz .Lwv_fail
    jmp .Lwv_done
60: # v1: they open in tabs of their own
    xor ebx, ebx
6:  cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lwv_done
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_doc], 0
    jne 6b
    mov rdi, r12
    xor esi, esi
    call ws_path
    lea rdi, [rip + ws_pathbuf]
    call file_type
    cmp eax, 0x8000
    jne .Lwv_unreadable         # missing (it would open empty), a folder, a device
    # Every edit resolves existing aliases; only unsolicited edits gate disk roots.
    mov rdi, [rip + ws_request_ext]
    lea rsi, [rip + ws_pathbuf]
    call ext_open_path
    test rax, rax
    jz .Lwv_denied
    mov r13, rax
    lea rdi, [rip + ws_pathbuf]
    mov rsi, r13
    call cstr_copy
    mov rdi, r13
    call mem_free
    lea rdi, [rip + ws_pathbuf]
    call app_find_tab
    test rax, rax
    js 62f
    # Another group may already have opened this canonical path. Never own its rollback.
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lwv_badpath
    mov rdi, [rax + TAB_doc]
    mov [r12 + WG_doc], rdi
    call doc_dirty
    test eax, eax
    jnz .Lwv_stale
    jmp 6b
62: mov dword ptr [rip + g_open_keep_tab], 1
    lea rdi, [rip + ws_pathbuf]
    call app_open_file
    mov dword ptr [rip + g_open_keep_tab], 0
    test rax, rax
    js .Lwv_unreadable
    mov [rsp], rax
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    je 61f
    mov rdi, [rsp]              # an image: its tab goes again
    call app_close_tab_now
    jmp .Lwv_unreadable
61: mov rax, [rax + TAB_doc]
    mov [r12 + WG_doc], rax
    mov qword ptr [r12 + WG_opened], 1
    mov rcx, [rax + DOC_version]
    mov [r12 + WG_ver0], rcx
    jmp 6b
.Lwv_done:
    mov qword ptr [rip + ws_entry], 0
    mov eax, 1
    EPILOGUE
.Lwv_fail:
    xor eax, eax
    EPILOGUE
.Lwv_bad:
    lea rdi, [rip + .Lwc_bad]
    lea rsi, [rip + .Lws_e_bad]
    jmp .Lwv_err
.Lwv_badpath:
    lea rdi, [rip + .Lwc_path]
    lea rsi, [rip + .Lws_e_path]
    jmp .Lwv_err
.Lwv_denied:
    lea rdi, [rip + .Lwc_denied]
    lea rsi, [rip + .Lws_e_path]
    jmp .Lwv_err
.Lwv_gone:
    lea rdi, [rip + .Lwc_gone]
    lea rsi, [rip + .Lws_e_gone]
    jmp .Lwv_err
.Lwv_stale:
    lea rdi, [rip + .Lwc_stale]
    lea rsi, [rip + .Lws_e_stale]
    jmp .Lwv_err
.Lwv_unreadable:
    lea rdi, [rip + .Lwc_open]
    lea rsi, [rip + .Lws_e_open]
.Lwv_err:
    call ws_err
    EPILOGUE

# ---------------- checking ----------------

# ws_check() -> eax 1 when every range is in its text, in order, none over another, every
# document editable and named once; 0 otherwise (ws_code says why)
ws_check:
    PROLOGUE 16
    xor ebx, ebx
7:  cmp rbx, [rip + wg_vec + VEC_len]
    jae .Lwk_ok
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov [rip + ws_entry], rbx
    cmp qword ptr [r12 + WG_kind], WK_TEXT
    jne 7b
    mov r13, [r12 + WG_doc]
    test r13, r13
    jz 7b                       # a group for a file an earlier create makes (wsdisk.s)
    mov rax, [rip + ws_only]
    test rax, rax
    jz 75f
    cmp rax, [r13 + DOC_id]
    jne .Lwk_badpath            # a format edit for another document
75: # a document named twice (by id and by path) would get edits made for a text it no longer has
    mov rcx, [rip + wg_vec + VEC_ptr]
73: cmp rcx, r12
    jae 74f
    cmp [rcx + WG_doc], r13
    je .Lwk_bad
    add rcx, WG_SIZE
    jmp 73b
74: test dword ptr [r13 + DOC_flags], DF_READONLY
    jnz .Lwk_readonly
    mov r14, [r12 + WG_first]
    mov r15, r14
    add r15, [r12 + WG_count]
71: cmp r14, r15
    jae 72f
    imul rax, r14, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    mov [rsp], rax
    mov rdi, r13
    mov esi, [rax + WE_l1]
    mov edx, [rax + WE_c1]
    call lf_pos
    test rax, rax
    js .Lwk_badrange
    mov rcx, [rsp]
    mov [rcx + WE_start], rax
    mov rdi, r13
    mov esi, [rcx + WE_l2]
    mov edx, [rcx + WE_c2]
    call lf_pos
    test rax, rax
    js .Lwk_badrange
    mov rcx, [rsp]
    mov [rcx + WE_end], rax
    cmp rax, [rcx + WE_start]
    jb .Lwk_badrange
    inc r14
    jmp 71b
72: mov rdi, r12
    call ws_sort
    mov rdi, r12
    call ws_overlap
    test eax, eax
    jnz .Lwk_overlap
    jmp 7b
.Lwk_ok:
    mov qword ptr [rip + ws_entry], 0
    mov eax, 1
    EPILOGUE
.Lwk_bad:
    lea rdi, [rip + .Lwc_bad]
    lea rsi, [rip + .Lws_e_bad]
    jmp .Lwk_err
.Lwk_badpath:
    lea rdi, [rip + .Lwc_path]
    lea rsi, [rip + .Lws_e_path]
    jmp .Lwk_err
.Lwk_readonly:
    lea rdi, [rip + .Lwc_readonly]
    lea rsi, [rip + .Lws_e_readonly]
    jmp .Lwk_err
.Lwk_badrange:
    lea rdi, [rip + .Lwc_range]
    lea rsi, [rip + .Lws_e_range]
    jmp .Lwk_err
.Lwk_overlap:
    lea rdi, [rip + .Lwc_overlap]
    lea rsi, [rip + .Lws_e_overlap]
.Lwk_err:
    call ws_err
    EPILOGUE

# ws_sort(WG*): its edits by start (an insertion keeps its place among equals)
ws_sort:
    PROLOGUE
    mov rbx, [rdi + WG_first]
    mov r12, [rdi + WG_count]
    # already in order (by we_cmp: a replacement listed before an insertion at its start is not)?
    mov r13, 1
1:  cmp r13, r12
    jae 8f
    lea rax, [rbx + r13]
    imul rax, rax, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    lea rdi, [rax - WE_SIZE]
    mov rsi, rax
    call we_cmp
    test eax, eax
    jg 2f
    inc r13
    jmp 1b
2:  imul rdi, rbx, WE_SIZE
    add rdi, [rip + we_vec + VEC_ptr]
    mov rsi, r12
    mov edx, WE_SIZE
    lea rcx, [rip + we_cmp]
    call lf_msort
8:  EPILOGUE

# we_cmp(a, b) -> eax < 0 when edit a goes first: by start, then by end (an insertion before a
# replacement that starts where it is); equal ones keep their order
we_cmp:
    mov rax, [rdi + WE_start]
    cmp rax, [rsi + WE_start]
    jb 8f
    ja 9f
    mov rax, [rdi + WE_end]
    cmp rax, [rsi + WE_end]
    jb 8f
    ja 9f
    xor eax, eax
    ret
8:  mov eax, -1
    ret
9:  mov eax, 1
    ret

# ws_overlap(WG*) -> eax 1 when one of its (sorted) edits starts inside the one before
ws_overlap:
    mov rsi, [rdi + WG_first]
    mov rcx, 1
1:  cmp rcx, [rdi + WG_count]
    jae 8f
    lea rax, [rsi + rcx]
    imul rax, rax, WE_SIZE
    add rax, [rip + we_vec + VEC_ptr]
    mov rdx, [rax - WE_SIZE + WE_end]
    cmp rdx, [rax + WE_start]
    ja 9f
    inc rcx
    jmp 1b
8:  xor eax, eax
    ret
9:  mov eax, 1
    ret

# ---------------- making it ----------------

# FN ws_tx_label() -> rax ptr, rdx len of the edit's name: its label record, the caller's, or
# "Edit from EXTENSION"
FN ws_tx_label
    push rbx
    cmp qword ptr [rip + ws_label + SB_len], 0
    jne 3f
    mov rsi, [rip + ws_deflabel]
    test rsi, rsi
    jz 1f
    lea rdi, [rip + ws_label]
    call sb_push_cstr
    jmp 3f
1:  lea rdi, [rip + ws_label]
    lea rsi, [rip + .Ledit_from]
    call sb_push_cstr
    mov rax, [rip + ws_ext]
    lea rsi, [rip + .Lan_extension]
    test rax, rax
    jz 2f
    mov rsi, [rax + EXT_title]
2:  lea rdi, [rip + ws_label]
    call sb_push_cstr
3:  mov rax, [rip + ws_label + SB_ptr]
    mov rdx, [rip + ws_label + SB_len]
    pop rbx
    ret

# FN ws_buf_parts() -> rax the open documents the edit changes (text groups with edits)
FN ws_buf_parts
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, [rip + wg_vec + VEC_len]
    jae 9f
    imul rdx, rcx, WG_SIZE
    add rdx, [rip + wg_vec + VEC_ptr]
    inc rcx
    cmp qword ptr [rdx + WG_kind], WK_TEXT
    jne 1b
    cmp qword ptr [rdx + WG_hidden], 0
    jne 1b
    cmp qword ptr [rdx + WG_doc], 0
    je 1b
    cmp qword ptr [rdx + WG_count], 0
    je 1b
    inc rax
    jmp 1b
9:  ret

# FN ws_commit() -> eax 1 when the edit was made (0 with ws_code when the disk refused and it was
# put back): a transaction when it touches disk or several documents
FN ws_commit
    PROLOGUE
    call ws_disk_needed         # files on disk to write, create, rename or delete (wsdisk.s)
    test eax, eax
    jnz .Lwc_disk
    call ws_buf_parts
    xor r13d, r13d              # the transaction, or 0
    cmp rax, 2
    jb 1f
    call ws_tx_label
    mov rdi, rax
    mov rsi, rdx
    call tx_new
    mov r13, rax
1:  xor ebx, ebx
2:  cmp rbx, [rip + wg_vec + VEC_len]
    jae 8f
    imul r12, rbx, WG_SIZE
    add r12, [rip + wg_vec + VEC_ptr]
    inc rbx
    mov rdi, r12
    mov rsi, r13
    call ws_buf_group
    jmp 2b
8:  mov eax, 1
    EPILOGUE
.Lwc_disk:
    call ws_disk_commit         # the journal, then everything, rolled back whole on a failure
    EPILOGUE

# FN ws_buf_group(WG*, T or 0): an open document's group made as one undo step, the step a
# participant of T
FN ws_buf_group
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rbx + WG_kind], WK_TEXT
    jne 9f
    cmp qword ptr [rbx + WG_hidden], 0
    jne 9f
    mov r13, [rbx + WG_doc]
    test r13, r13
    jz 9f
    cmp qword ptr [rbx + WG_count], 0
    je 9f
    mov rdi, rbx
    call ws_apply_group
    test r12, r12
    jz 9f
    mov rdi, r12
    mov rsi, r13
    call tx_tag
    mov rdi, r12
    mov esi, TPK_BUF
    call tx_add
    mov [rax + TP_doc], r13
9:  EPILOGUE

# FN ws_apply_group(WG*): its edits made, as one undo step (the cursor and the selection move with
# the text around them: doc_insert and doc_delete move them)
FN ws_apply_group
    PROLOGUE 16
    mov r12, rdi
    mov rbx, [r12 + WG_doc]
    cmp qword ptr [r12 + WG_count], 0
    je 9f
    mov rdi, rbx
    call doc_begin_group
    mov r13, [r12 + WG_count]
1:  test r13, r13
    jz 8f
    dec r13
    mov rax, [r12 + WG_first]
    add rax, r13
    imul r14, rax, WE_SIZE
    add r14, [rip + we_vec + VEC_ptr]
    mov rdx, [r14 + WE_end]
    sub rdx, [r14 + WE_start]
    jz 2f
    mov rdi, rbx
    mov rsi, [r14 + WE_start]
    mov ecx, EK_OTHER
    call doc_delete
2:  cmp qword ptr [r14 + WE_len], 0
    je 1b
    mov rdi, rbx
    mov rsi, [r14 + WE_start]
    mov rdx, [r14 + WE_text]
    mov rcx, [r14 + WE_len]
    mov r8d, EK_OTHER
    call doc_insert
    jmp 1b
8:  mov rdi, rbx
    call doc_end_group
    cmp qword ptr [r12 + WG_hidden], 0
    jne 9f                      # never on screen
    cmp dword ptr [rip + ws_preserve_context], 0
    je 8f
    mov dword ptr [rip + g_dirty], 1
    jmp 9f
8:  call ed_touch
9:  EPILOGUE

# FN ws_features_agreed(ext): after hello: the features of this work whose host side is not in
# yet are not agreed, and file-operations only together with workspace-edits
FN ws_features_agreed
    FEAT_TEST rdi, FEAT_WORKSPACE_EDITS
    jnz 1f
    FEAT_CLEAR rdi, FEAT_FILE_OPERATIONS
1:  FEAT_CLEAR rdi, FEAT_WORKSPACE_EDITS       # not yet
    FEAT_CLEAR rdi, FEAT_FILE_OPERATIONS
    FEAT_CLEAR rdi, FEAT_SELECTIONS
    FEAT_CLEAR rdi, FEAT_REVEAL
    FEAT_CLEAR rdi, FEAT_DIFF
    FEAT_CLEAR rdi, FEAT_LINKED_EDITING
    ret

# FN ws_ext_gone(ext): an extension stopped: an edit of its that waits for the user is cancelled
FN ws_ext_gone
    jmp ws_confirm_owner_gone

.section .rodata
.Lk_create: .asciz "create"
.Lk_rename: .asciz "rename"
.Lk_delete: .asciz "delete"
.Lr_label: .asciz "label"
.Lr_confirm: .asciz "confirm"
.Lfnv_prefix: .asciz "fnv1a64:"
.Lf_overwrite: .asciz "overwrite"
.Lf_ignore_existing: .asciz "ignore-existing"
.Lf_recursive: .asciz "recursive"
.Lf_ignore_missing: .asciz "ignore-missing"
.Lrename_to: .asciz "Rename to '"
.Ledit_from: .asciz "Edit from "
.Lan_extension: .asciz "an extension"
.Lws_e_bad: .asciz "The extension's edit could not be read: nothing changed"
.Lws_e_path: .asciz "The extension's edit names a file it cannot: nothing changed"
.Lws_e_gone: .asciz "A document the edit was made for is closed: nothing changed"
.Lws_e_stale: .asciz "A document changed since the edit was made: nothing changed"
.Lws_e_open: .asciz "A file the edit changes cannot be opened: nothing changed"
.Lws_e_readonly: .asciz "A file the edit changes is read-only: nothing changed"
.Lws_e_range: .asciz "The edit's ranges are not in the text: nothing changed"
.Lws_e_overlap: .asciz "The edit's ranges overlap: nothing changed"
.Lws_e_big: .asciz "The extension's edit is too big: nothing changed"
.Lwc_bad: .asciz "syntax the edit cannot be read"
.Lwc_big: .asciz "toobig over 4 MB, 1000 files or 100000 edits"
.Lwc_path: .asciz "nofile a path is not absolute or not a document"
.Lwc_denied: .asciz "needs the file is outside the extension's read permissions"
.Lwc_gone: .asciz "nodoc a document it names is closed"
.Lwc_stale: .asciz "stale a document changed since the edit was made"
.Lwc_open: .asciz "nofile a file cannot be opened"
.Lwc_readonly: .asciz "readonly a document cannot be edited"
.Lwc_range: .asciz "badpos a range is outside its text or inside a character"
.Lwc_overlap: .asciz "badpos two edits overlap"
.Lwc_busy: .asciz "busy another workspace edit waits for the user"
.Lws_e_busy: .asciz "Another workspace edit waits for your answer: nothing changed"
