# Diagnostics for any file (feature file-diagnostics, docs/extensions/v1.1.md): an extension's
# diagnostics for a document or a file go into the Problems store (problems.s, the tasks group's),
# one source per extension and target, so a new set replaces the old one there; open documents
# show them as marks and files opened later get theirs then. The ids the records carry are kept for
# code actions (DIAGS).
.include "rhun.inc"

.equ FDG_PER_TARGET, 2000
.equ FDG_MSG_MAX, 4000
.equ FDG_ID_MAX, 64

# a diagnostic's id, for code-actions' DIAGS
STRUCT
F FDG_ps, 8                      # its source (PS*)
F FD_l1, 4
F FD_c1, 4
F FD_l2, 4
F FD_c2, 4
F FDG_id, 8                      # owned cstr
ENDSTRUCT FDG_SIZE

.bss
.p2align 3
fd_ids: .zero VEC_SIZE          # FD records
fd_key: .zero SB_SIZE           # a source's key being built
fd_path: .quad 0                # the target's path (owned)
fd_target: .quad 0              # the target's open document, or 0
fd_pr: .zero PR_SIZE            # the problem being added
fd_msg: .zero SB_SIZE
fd_code: .zero SB_SIZE
fd_tmp: .zero 32

.text

# fd_error(cstr): the reply to the request being handled
fd_error:
    push rdi
    call extproto_req_id
    pop rsi
    mov rdi, rax
    jmp extproto_error

# fd_source(ext, path) -> PS*: the extension's source for that target (made when new, and listed
# in EXT_fdsrc)
fd_source:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rip + fd_key]
    call sb_clear
    lea rdi, [rip + fd_key]
    lea rsi, [rip + .Lkey_prefix]
    call sb_push_cstr
    mov rdi, rbx
    call ext_full_name
    lea rdi, [rip + fd_key]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + fd_key]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + fd_key]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + fd_key]
    xor esi, esi
    call sb_push_byte
    mov rdi, rbx
    call ext_full_name
    mov rsi, rax
    mov rdi, [rip + fd_key + SB_ptr]
    call problems_source
    mov r13, rax
    # listed once
    xor ecx, ecx
1:  cmp rcx, [rbx + EXT_fdsrc + VEC_len]
    jae 2f
    mov rax, [rbx + EXT_fdsrc + VEC_ptr]
    cmp [rax + rcx*8], r13
    je 9f
    inc rcx
    jmp 1b
2:  lea rdi, [rbx + EXT_fdsrc]
    mov esi, 8
    call vec_push
    mov [rax], r13
9:  mov rax, r13
    EPILOGUE

# fd_forget_ids(PS*): its diagnostics' ids go
fd_forget_ids:
    PROLOGUE
    mov r12, rdi
    xor ebx, ebx
1:  cmp rbx, [rip + fd_ids + VEC_len]
    jae 9f
    imul r13, rbx, FDG_SIZE
    add r13, [rip + fd_ids + VEC_ptr]
    cmp [r13 + FDG_ps], r12
    je 2f
    inc rbx
    jmp 1b
2:  mov rdi, [r13 + FDG_id]
    call mem_free
    mov rax, [rip + fd_ids + VEC_len]
    dec rax
    mov [rip + fd_ids + VEC_len], rax
    imul rsi, rax, FDG_SIZE
    add rsi, [rip + fd_ids + VEC_ptr]
    cmp rsi, r13
    je 1b
    mov rdi, r13
    mov edx, FDG_SIZE
    call memcpy
    jmp 1b
9:  EPILOGUE

# fd_clear(PS*): its problems, marks and ids go
fd_clear:
    push rbx
    mov rbx, rdi
    call problems_clear
    mov rdi, rbx
    call fd_forget_ids
    pop rbx
    ret

# fd_sev(ptr, len) -> eax SEV_*, or -1
fd_sev:
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
1:  cmp ebx, 4
    jae 8f
    lea rax, [rip + fd_sevs]
    mov rdx, [rax + rbx*8]
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz 2f
    inc ebx
    jmp 1b
2:  mov eax, ebx
    EPILOGUE
8:  mov eax, -1
    EPILOGUE

# fd_num(ptr, end) -> rax value, rdx the next field (past one space), or rax -1: a decimal of at
# most 10 digits
fd_num:
    xor eax, eax
    xor ecx, ecx
1:  cmp rdi, rsi
    jae 3f
    movzx edx, byte ptr [rdi]
    cmp edx, ' '
    je 2f
    sub edx, '0'
    cmp edx, 9
    ja 8f
    imul rax, rax, 10
    add rax, rdx
    inc rdi
    inc ecx
    cmp ecx, 10
    ja 8f
    jmp 1b
2:  inc rdi
3:  test ecx, ecx
    jz 8f
    mov rdx, rdi
    ret
8:  mov rax, -1
    ret

# FN filediag_h_set(): ID file-diagnostics VERSION N TARGET_LEN LEN + TARGET + N records
#   L1 C1 L2 C2 SEVERITY MSG_LEN EXTRA_LEN LF + MESSAGE + EXTRA
FN filediag_h_set
    PROLOGUE 64
    call extproto_cur
    mov rbx, rax
    mov rdi, rbx
    mov esi, FEAT_FILE_DIAGNOSTICS
    call ext_feature
    test eax, eax
    jz .Lfs_unknown
    test dword ptr [rbx + EXT_needs], NEEDS_DOC_READ
    jz .Lfs_needs
    call extproto_nfields
    cmp rax, 6
    jne .Lfs_syntax
    mov edi, 3
    call extproto_field
    test edx, edx
    jz .Lfs_syntax
    cmp rax, FDG_PER_TARGET
    ja .Lfs_toobig
    mov r12, rax                # N
    mov edi, 4
    call extproto_field
    test edx, edx
    jz .Lfs_syntax
    mov r13, rax                # TARGET_LEN
    call extproto_body
    mov r14, rax
    mov r15, rdx
    cmp r13, r15
    ja .Lfs_syntax
    test r13, r13
    jz .Lfs_syntax
    cmp r13, 4096
    ja .Lfs_syntax
    # the target: #DOC (its version given) or an absolute path (VERSION -)
    mov rdi, [rip + fd_path]
    call mem_free
    mov qword ptr [rip + fd_path], 0
    mov qword ptr [rip + fd_target], 0
    cmp byte ptr [r14], '#'
    jne .Lfs_path
    lea rdi, [r14 + 1]
    lea rsi, [r14 + r13]
    call fd_num
    test rax, rax
    js .Lfs_syntax
    cmp rdx, rsi
    jne .Lfs_syntax
    mov rdi, rax
    call extproto_doc
    test rax, rax
    jz .Lfs_nodoc
    mov [rip + fd_target], rax
    mov [rsp], rax
    mov edi, 2
    call extproto_field
    test edx, edx
    jz .Lfs_syntax
    mov rcx, [rsp]
    cmp rax, [rcx + DOC_version]
    jne .Lfs_stale
    mov rdi, [rcx + DOC_path]
    test rdi, rdi
    jz .Lfs_untitled
    call dup_cstr
    mov [rip + fd_path], rax
    jmp .Lfs_records
.Lfs_path:
    mov edi, 2
    call extproto_field_at
    cmp rdx, 1
    jne .Lfs_syntax
    cmp byte ptr [rax], '-'
    jne .Lfs_syntax
    mov rdi, r14
    mov rsi, r13
    call mem_dup
    mov [rsp + 8], rax
    mov rdi, rax
    call path_rootlen
    test rax, rax
    jz .Lfs_path_bad
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call ext_open_path          # one it could open: the project, its read access, its state
    mov [rsp + 16], rax
    mov rdi, [rsp + 8]
    call mem_free
    mov rax, [rsp + 16]
    test rax, rax
    jz .Lfs_needs
    mov [rip + fd_path], rax
    # an open document: unmodified gets marks, modified is stale
    mov rdi, rax
    call app_find_tab
    test rax, rax
    js .Lfs_records
    mov rdi, rax
    call tab_at
    cmp qword ptr [rax + TAB_kind], TAB_DOC
    jne .Lfs_records
    mov rcx, [rax + TAB_doc]
    test rcx, rcx
    jz .Lfs_records
    mov [rip + fd_target], rcx
    mov rdi, rcx
    call doc_dirty
    test eax, eax
    jnz .Lfs_stale_target
.Lfs_records:
    # the records, checked whole before anything changes
    lea rax, [r14 + r13]
    mov [rsp + 24], rax         # the first record
    lea rax, [r14 + r15]
    mov [rsp + 32], rax         # the end
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    mov rdx, r12
    xor ecx, ecx                # check only
    call fd_records
    test eax, eax
    jnz .Lfs_syntax
    # this extension's set there is replaced
    mov rdi, rbx
    mov rsi, [rip + fd_path]
    call fd_source
    mov [rsp + 40], rax
    mov rdi, rax
    call fd_clear
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    mov rdx, r12
    mov rcx, [rsp + 40]
    call fd_records
    call extproto_req_id
    mov rdi, rax
    call extproto_ok
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
.Lfs_unknown:
    lea rdi, [rip + .Le_unknown]
    call fd_error
    EPILOGUE
.Lfs_needs:
    lea rdi, [rip + .Le_needs]
    call fd_error
    EPILOGUE
.Lfs_syntax:
    lea rdi, [rip + .Le_syntax]
    call fd_error
    EPILOGUE
.Lfs_toobig:
    lea rdi, [rip + .Le_toobig]
    call fd_error
    EPILOGUE
.Lfs_nodoc:
    lea rdi, [rip + .Le_nodoc]
    call fd_error
    EPILOGUE
.Lfs_untitled:
    lea rdi, [rip + .Le_untitled]
    call fd_error
    EPILOGUE
.Lfs_path_bad:
    mov rdi, [rsp + 8]
    call mem_free
    lea rdi, [rip + .Le_nofile]
    call fd_error
    EPILOGUE
.Lfs_stale_target:
    mov rcx, [rip + fd_target]
    mov [rsp], rcx
.Lfs_stale:
    call extproto_req_id
    mov rdi, rax
    lea rsi, [rip + .Le_stale]
    mov rcx, [rsp]
    mov rdx, [rcx + DOC_version]
    call extproto_error_u64
    EPILOGUE

# fd_records(ptr, end, n, PS* or 0) -> eax 0 when the n records fill [ptr, end) and are well
# formed (with a source: each is added to the store, its id kept); 1 otherwise
fd_records:
    PROLOGUE 48
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
.Lfr_next:
    test r14, r14
    jz .Lfr_end
    dec r14
    # the header line
    mov rbx, r12
1:  cmp rbx, r13
    jae .Lfr_bad
    cmp byte ptr [rbx], 10
    je 2f
    inc rbx
    jmp 1b
2:  lea rcx, [rip + fd_tmp]
    mov rdi, r12
    mov rsi, rbx
    xor r8d, r8d
3:  push rcx
    push r8
    call fd_num
    pop r8
    pop rcx
    test rax, rax
    js .Lfr_bad
    cmp rax, 0x7fffffff
    ja .Lfr_bad
    mov [rcx + r8*4], eax
    mov rdi, rdx
    inc r8
    cmp r8, 4
    jb 3b
    # SEVERITY
    mov rax, rdi
4:  cmp rax, rbx
    jae .Lfr_bad
    cmp byte ptr [rax], ' '
    je 5f
    inc rax
    jmp 4b
5:  mov [rsp], rax
    mov rsi, rax
    sub rsi, rdi
    call fd_sev
    test eax, eax
    js .Lfr_bad
    mov [rsp + 8], eax
    mov rdi, [rsp]
    inc rdi
    mov rsi, rbx
    call fd_num
    test rax, rax
    js .Lfr_bad
    cmp rax, FDG_MSG_MAX
    ja .Lfr_bad
    test rax, rax
    jz .Lfr_bad
    mov [rsp + 16], rax         # MSG_LEN
    mov rdi, rdx
    mov rsi, rbx
    call fd_num
    test rax, rax
    js .Lfr_bad
    cmp rdx, rbx
    jne .Lfr_bad
    mov [rsp + 24], rax         # EXTRA_LEN
    lea r12, [rbx + 1]          # the message
    mov rax, r13
    sub rax, r12
    mov rcx, [rsp + 16]
    add rcx, [rsp + 24]
    cmp rcx, rax
    ja .Lfr_bad
    # the range: L1 C1 before L2 C2, all positive
    lea rcx, [rip + fd_tmp]
    cmp dword ptr [rcx], 0
    je .Lfr_bad
    cmp dword ptr [rcx + 4], 0
    je .Lfr_bad
    cmp dword ptr [rcx + 8], 0
    je .Lfr_bad
    cmp dword ptr [rcx + 12], 0
    je .Lfr_bad
    mov eax, [rcx]
    cmp eax, [rcx + 8]
    ja .Lfr_bad
    jb 6f
    mov eax, [rcx + 4]
    cmp eax, [rcx + 12]
    ja .Lfr_bad
6:  # the extra records: whole, and their id, code, source
    mov rdi, r12
    add rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call fd_extra
    test eax, eax
    jnz .Lfr_bad
    test r15, r15
    jz .Lfr_skip
    call fd_add
.Lfr_skip:
    add r12, [rsp + 16]
    add r12, [rsp + 24]
    jmp .Lfr_next
.Lfr_end:
    cmp r12, r13
    jne .Lfr_bad
    xor eax, eax
    EPILOGUE
.Lfr_bad:
    mov eax, 1
    EPILOGUE

# fd_add(): fd_records' current record into the store: r12 its message, r15 the source, the
# severity and the message's length at fd_records' [rsp + 8] and [rsp + 16], fd_tmp the range, fe_*
# what its extra records said
fd_add:
    PROLOGUE
    lea rdi, [rip + fd_pr]
    xor esi, esi
    mov edx, PR_SIZE
    call memset
    mov rax, [rip + fd_path]
    mov [rip + fd_pr + PR_path], rax
    lea rcx, [rip + fd_tmp]
    mov eax, [rcx]
    mov [rip + fd_pr + PR_line], eax
    mov eax, [rcx + 4]
    mov [rip + fd_pr + PR_col], eax
    mov eax, [rcx + 8]
    mov [rip + fd_pr + PR_endline], eax
    mov eax, [rcx + 12]
    mov [rip + fd_pr + PR_endcol], eax
    mov eax, [rbp + 16 + 8]
    mov [rip + fd_pr + PR_sev], eax
    # the message as a cstr
    lea rdi, [rip + fd_msg]
    call sb_clear
    lea rdi, [rip + fd_msg]
    mov rsi, r12
    mov rdx, [rbp + 16 + 16]
    call sb_push
    lea rdi, [rip + fd_msg]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + fd_msg + SB_ptr]
    mov [rip + fd_pr + PR_msg], rax
    # the code: "source(code)", "source", "code" or none
    lea rdi, [rip + fd_code]
    call sb_clear
    mov rdx, [rip + fe_srclen]
    test rdx, rdx
    jz 1f
    lea rdi, [rip + fd_code]
    mov rsi, [rip + fe_src]
    call sb_push
1:  mov rdx, [rip + fe_codelen]
    test rdx, rdx
    jz 3f
    cmp qword ptr [rip + fe_srclen], 0
    je 2f
    lea rdi, [rip + fd_code]
    mov esi, '('
    call sb_push_byte
2:  lea rdi, [rip + fd_code]
    mov rsi, [rip + fe_code]
    mov rdx, [rip + fe_codelen]
    call sb_push
    cmp qword ptr [rip + fe_srclen], 0
    je 3f
    lea rdi, [rip + fd_code]
    mov esi, ')'
    call sb_push_byte
3:  lea rdi, [rip + fd_code]
    xor esi, esi
    call sb_push_byte
    mov rax, [rip + fd_code + SB_ptr]
    mov [rip + fd_pr + PR_code], rax
    mov rdi, r15
    lea rsi, [rip + fd_pr]
    call problems_add
    # its id, for code actions
    mov rdx, [rip + fe_idlen]
    test rdx, rdx
    jz 9f
    mov rdi, [rip + fe_id]
    mov rsi, rdx
    call mem_dup
    mov rbx, rax
    lea rdi, [rip + fd_ids]
    mov esi, FDG_SIZE
    call vec_push
    mov [rax + FDG_ps], r15
    mov [rax + FDG_id], rbx
    lea rcx, [rip + fd_tmp]
    mov edx, [rcx]
    mov [rax + FD_l1], edx
    mov edx, [rcx + 4]
    mov [rax + FD_c1], edx
    mov edx, [rcx + 8]
    mov [rax + FD_l2], edx
    mov edx, [rcx + 12]
    mov [rax + FD_c2], edx
9:  EPILOGUE

# fd_extra(ptr, len) -> eax 0 when the bytes are whole records ("NAME ARGS... LEN" LF + bytes)
# with valid id, code, href and source; fe_* get the id, code and source (0 length when absent)
fd_extra:
    PROLOGUE
    mov qword ptr [rip + fe_idlen], 0
    mov qword ptr [rip + fe_codelen], 0
    mov qword ptr [rip + fe_srclen], 0
    mov r12, rdi
    lea r13, [rdi + rsi]
.Lfx_next:
    cmp r12, r13
    jae .Lfx_ok
    mov rbx, r12
1:  cmp rbx, r13
    jae .Lfx_bad
    cmp byte ptr [rbx], 10
    je 2f
    inc rbx
    jmp 1b
2:  # its last word is its length
    mov rcx, rbx
3:  cmp rcx, r12
    je .Lfx_bad
    cmp byte ptr [rcx - 1], ' '
    je 4f
    dec rcx
    jmp 3b
4:  mov rdi, rcx
    mov rsi, rbx
    push rcx
    push rcx
    call fd_num
    pop rcx
    pop rcx
    test rax, rax
    js .Lfx_bad
    # related L1 C1 L2 C2 PATH_LEN MSG_LEN: the path's bytes and the message's follow
    push rax
    push rcx
    mov rdi, r12
    mov rsi, rbx
    sub rsi, r12
    lea rdx, [rip + .Lx_related_sp]
    mov ecx, 8
    call str_starts
    mov r8d, eax
    pop rcx
    pop rax
    test r8d, r8d
    jz 41f
    lea rsi, [rcx - 1]          # PATH_LEN: the word before the last
    mov rdi, rsi
42: cmp rdi, r12
    je .Lfx_bad
    cmp byte ptr [rdi - 1], ' '
    je 43f
    dec rdi
    jmp 42b
43: push rax
    push rax
    call fd_num
    mov rdx, rax
    pop rax
    pop rcx
    test rdx, rdx
    js .Lfx_bad
    add rax, rdx
41: lea r14, [rbx + 1]          # its bytes
    lea r15, [r14 + rax]
    cmp r15, r13
    ja .Lfx_bad
    # its name: up to the first space
    mov rsi, r12
5:  cmp byte ptr [rsi], ' '
    je 6f
    inc rsi
    jmp 5b
6:  mov [rip + fe_name], r12
    sub rsi, r12
    mov [rip + fe_namelen], rsi
    mov [rip + fe_len], rax
    lea rdi, [rip + .Lx_id]
    call fe_is
    test eax, eax
    jz 7f
    mov rax, [rip + fe_len]
    test rax, rax
    jz .Lfx_bad
    cmp rax, FDG_ID_MAX
    ja .Lfx_bad
    mov rdi, r14
    mov rsi, rax
    call fd_token
    test eax, eax
    jz .Lfx_bad
    mov [rip + fe_id], r14
    mov rax, [rip + fe_len]
    mov [rip + fe_idlen], rax
    jmp 9f
7:  lea rdi, [rip + .Lx_code]
    call fe_is
    test eax, eax
    jz 8f
    cmp qword ptr [rip + fe_len], 100
    ja .Lfx_bad
    mov [rip + fe_code], r14
    mov rax, [rip + fe_len]
    mov [rip + fe_codelen], rax
    jmp 9f
8:  lea rdi, [rip + .Lx_source]
    call fe_is
    test eax, eax
    jz 81f
    cmp qword ptr [rip + fe_len], 100
    ja .Lfx_bad
    mov [rip + fe_src], r14
    mov rax, [rip + fe_len]
    mov [rip + fe_srclen], rax
    jmp 9f
81: lea rdi, [rip + .Lx_href]
    call fe_is
    test eax, eax
    jz 9f
    cmp qword ptr [rip + fe_len], 1000
    ja .Lfx_bad
9:  mov r12, r15
    jmp .Lfx_next
.Lfx_ok:
    xor eax, eax
    EPILOGUE
.Lfx_bad:
    mov eax, 1
    EPILOGUE

fe_is:
    mov rdx, rdi
    mov rdi, [rip + fe_name]
    mov rsi, [rip + fe_namelen]
    jmp str_eq_cstr

# fd_token(ptr, len) -> eax 1 for [A-Za-z0-9_.:-]
fd_token:
    test rsi, rsi
    jz 9f
1:  movzx eax, byte ptr [rdi]
    inc rdi
    cmp eax, '_'
    je 2f
    cmp eax, '.'
    je 2f
    cmp eax, ':'
    je 2f
    cmp eax, '-'
    je 2f
    mov ecx, eax
    sub ecx, '0'
    cmp ecx, 9
    jbe 2f
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 25
    ja 8f
2:  dec rsi
    jnz 1b
9:  mov eax, 1
    ret
8:  xor eax, eax
    ret

# FN filediag_h_reset(): ID file-diagnostics-reset: all of this extension's diagnostics go
FN filediag_h_reset
    PROLOGUE
    call extproto_cur
    mov rbx, rax
    mov rdi, rbx
    mov esi, FEAT_FILE_DIAGNOSTICS
    call ext_feature
    test eax, eax
    jz 8f
    mov rdi, rbx
    call filediag_ext_gone
    call extproto_req_id
    mov rdi, rax
    call extproto_ok
    EPILOGUE
8:  lea rdi, [rip + .Le_unknown]
    call fd_error
    EPILOGUE

# FN filediag_ext_gone(ext): every set of the extension goes (it stopped, or reset)
FN filediag_ext_gone
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx + EXT_fdsrc + VEC_len]
    jae 2f
    mov rax, [rbx + EXT_fdsrc + VEC_ptr]
    mov rdi, [rax + r12*8]
    inc r12
    call fd_clear
    jmp 1b
2:  mov qword ptr [rbx + EXT_fdsrc + VEC_len], 0
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# FN filediag_ids(ext, path, l1, c1, l2, c2, sb) -> eax how many: the comma-separated ids of the
# extension's diagnostics in that file that intersect the range (at most 64), into sb
FN filediag_ids
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov [rsp + 4], ecx
    mov [rsp + 8], r8d
    mov [rsp + 12], r9d
    mov rax, [rbp + 16]
    mov [rsp + 16], rax         # sb
    mov dword ptr [rsp + 24], 0 # count
    test r12, r12
    jz 9f
    xor r13d, r13d
1:  cmp r13, [rip + fd_ids + VEC_len]
    jae 9f
    imul r14, r13, FDG_SIZE
    add r14, [rip + fd_ids + VEC_ptr]
    inc r13
    cmp dword ptr [rsp + 24], 64
    jae 9f
    # its source is this extension's for this path
    mov r15, [r14 + FDG_ps]
    xor ecx, ecx
2:  cmp rcx, [rbx + EXT_fdsrc + VEC_len]
    jae 1b
    mov rax, [rbx + EXT_fdsrc + VEC_ptr]
    cmp [rax + rcx*8], r15
    je 3f
    inc rcx
    jmp 2b
3:  call fd_source_path_is      # r15 the source, r12 the path
    test eax, eax
    jz 1b
    # intersects: its start not after the range's end, its end not before the range's start
    mov eax, [r14 + FD_l1]
    cmp eax, [rsp + 8]
    ja 1b
    jb 4f
    mov eax, [r14 + FD_c1]
    cmp eax, [rsp + 12]
    ja 1b
4:  mov eax, [r14 + FD_l2]
    cmp eax, [rsp]
    jb 1b
    ja 5f
    mov eax, [r14 + FD_c2]
    cmp eax, [rsp + 4]
    jb 1b
5:  cmp dword ptr [rsp + 24], 0
    je 6f
    mov rdi, [rsp + 16]
    mov esi, ','
    call sb_push_byte
6:  mov rdi, [rsp + 16]
    mov rsi, [r14 + FDG_id]
    call sb_push_cstr
    inc dword ptr [rsp + 24]
    jmp 1b
9:  mov eax, [rsp + 24]
    EPILOGUE

# fd_source_path_is() -> eax 1 when source r15's key names path r12 ("langfeat owner/name PATH")
fd_source_path_is:
    PROLOGUE
    mov rdi, [r15 + PS_key]
    mov rbx, rdi
    call strlen
    mov r13, rax
    mov rdi, r12
    call strlen
    cmp rax, r13
    ja 8f
    mov rdi, rbx
    add rdi, r13
    sub rdi, rax
    cmp byte ptr [rdi - 1], ' '
    jne 8f
    mov rsi, r12
    call strcmp_eq
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

.bss
.p2align 3
fe_name: .quad 0                # fd_extra: the current record's name and length
fe_namelen: .quad 0
fe_len: .quad 0
fe_id: .quad 0                  # and what it found
fe_idlen: .quad 0
fe_code: .quad 0
fe_codelen: .quad 0
fe_src: .quad 0
fe_srclen: .quad 0

.section .rodata
.Lkey_prefix: .asciz "langfeat "
.Le_unknown: .asciz "unknown"
.Le_needs: .asciz "needs documents = read, and a file the extension could open"
.Le_syntax: .asciz "syntax"
.Le_toobig: .asciz "toobig 2000 diagnostics per target"
.Le_nodoc: .asciz "nodoc no such document"
.Le_untitled: .asciz "nofile an untitled document takes v1 diagnostics"
.Le_nofile: .asciz "nofile not an absolute path"
.Le_stale: .asciz "stale "
.Lx_related_sp: .ascii "related "
.Lx_id: .asciz "id"
.Lx_code: .asciz "code"
.Lx_source: .asciz "source"
.Lx_href: .asciz "href"
.Ls_error: .asciz "error"
.Ls_warning: .asciz "warning"
.Ls_info: .asciz "info"
.Ls_hint: .asciz "hint"
.p2align 3
fd_sevs: .quad .Ls_error, .Ls_warning, .Ls_info, .Ls_hint
