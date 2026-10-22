# gitdata: Git facts for extensions (protocol 1.1 feature git-data, docs/extensions/v1.1.md): the
# repository and its status, the blame of a document's current text, the history of a file or of some
# of its lines, a file at a revision, and rhun's diff view of two revisions. rhun runs git itself, in
# the background as for its own views, so the trust pause holds and the extension needs no `run = git`.
# After a status refresh that changed something, extensions hear "0 git changed".
.include "rhun.inc"

# a request waiting for git, or for the status refresh in progress
STRUCT
F GQ_ext, 8             # its extension; 0 once nobody waits for the answer
F GQ_job, 8             # the git job (git_start); 0 while it waits for the status
F GQ_id, 8              # the extension's request id
F GQ_deadline, 8        # time_ms when it gives up
F GQ_pid, 4             # the extension's process when it asked: a restarted one gets no old answers
F GQ_kind, 4            # GK_*
ENDSTRUCT GQ_SIZE

.equ GK_REPO, 1
.equ GK_STATUS, 2
.equ GK_BLAME, 3
.equ GK_LOG, 4
.equ GK_SHOW, 5

.equ GQ_MAX, 64                 # requests waiting, all extensions together
.equ GQ_EXT_MAX, 16             # requests waiting, one extension
.equ GQ_MS, 15000               # git's time for one answer
.equ BLAME_LINES, 100000
.equ BLAME_IN, 16777216         # a blamed document's text, at most
.equ BLAME_OUT, 67108864        # git's porcelain blame, at most
.equ LOG_MAX, 1000              # commits in one git-log answer
.equ LOG_OUT, 16777216
.equ SHOW_MAX, 4194304          # a file at a revision
.equ REPLY_MAX, 4194304         # any answer's body
.equ REV_MAX, 200

.bss
.p2align 3
pending: .zero VEC_SIZE         # GQ*, in the order they came
rb: .zero SB_SIZE               # an answer being sent
body: .zero SB_SIZE             # its body
cbuf: .zero SB_SIZE             # blame: the commits
runs: .zero SB_SIZE             # blame: the runs of lines
argv: .zero 8 * 20
last_sig: .quad 0               # what the last "0 git changed" was about (status, branch, upstream)
pbuf: .zero 4104                # a path argument as a cstr
rev1: .zero REV_MAX + 8
rev2: .zero REV_MAX + 8
nbuf: .zero 64                  # numbers made into arguments
lbuf: .zero 4400                # REV:PATH (200 + 1 + 4095 + NUL), -L L1,L2:PATH
head_moved: .long 0             # HEAD moved since the last "0 git changed"
ncommits: .long 0
nruns: .long 0
cm_reading: .long 0             # blame: 1 while a commit's key lines are being read
.p2align 3
cm_sha: .quad 0                 # blame: the current header's commit
cm_shalen: .quad 0
cm_author: .quad 0, 0           # the commit being read: ptr, len
cm_mail: .quad 0, 0
cm_time: .quad 0
cm_summary: .quad 0, 0

.text

# ---------------- requests (extproto.s's verb table) ----------------

# ID git-repo -> ROOT_LEN BRANCH_LEN UPSTREAM_LEN HEAD AHEAD BEHIND STATE LF <ROOT><BRANCH><UPSTREAM>
FN gitdata_h_repo
    mov edi, GK_REPO
    jmp settled_request
# ID git-status -> N LF, then N times XY PATH_LEN LF <PATH>
FN gitdata_h_status
    mov edi, GK_STATUS
settled_request:
    PROLOGUE 16
    mov [rsp], edi
    call req
    mov rbx, rax
    mov r12, rdx
    call gate
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 2
    jne 8f
    # answered from the status in memory once no refresh runs or waits
    call git_status_settled
    test eax, eax
    jz 1f
    mov edi, [rsp]
    call answer_settled
    jmp 9f
1:  call room
    test eax, eax
    jz 9f
    mov edi, [rsp]
    xor esi, esi
    call add_pending
9:  EPILOGUE
8:  call extproto_answer_syntax
    EPILOGUE

# ID git-blame DOC -> the blame of the document's current text (git blame --contents -)
FN gitdata_h_blame
    PROLOGUE 32
    call req
    mov rbx, rax
    mov r12, rdx
    call gate
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 3
    jne 8f
    mov edi, 2
    call extproto_field
    test edx, edx
    jz 8f
    mov rdi, rax
    call extproto_doc
    test rax, rax
    jz 81f
    mov r13, rax
    mov rdi, [r13 + DOC_path]
    test rdi, rdi
    jz 82f
    call git_rel
    test rax, rax
    jz 82f
    mov [rsp], rax              # the path in the work tree, a cstr (the end of DOC_path)
    cmp qword ptr [r13 + DOC_nlines], BLAME_LINES
    ja 83f
    mov rdi, r13
    call doc_len
    mov r14, rax
    mov r15, rax
    cmp dword ptr [r13 + DOC_crlf], 0
    je 1f
    add r15, rax                # each LF may become CRLF
1:  cmp r15, BLAME_IN
    ja 84f
    call room
    test eax, eax
    jz 9f
    # the text git would find on disk once saved: line ends as the file has them
    lea rdi, [r15 + 1]
    call mem_alloc
    mov r15, rax
    mov rdi, r13
    xor esi, esi
    mov rdx, r14
    mov rcx, r15
    call doc_copy
    cmp dword ptr [r13 + DOC_crlf], 0
    je 2f
    mov rdi, r15
    mov rsi, r14
    call crlf_expand
    mov r14, rax
2:  lea rax, [rip + .La_blame]
    mov [rip + argv], rax
    lea rax, [rip + .La_porcelain]
    mov [rip + argv + 8], rax
    lea rax, [rip + .La_no_textconv]
    mov [rip + argv + 16], rax
    lea rax, [rip + .La_contents]
    mov [rip + argv + 24], rax
    lea rax, [rip + .La_dash]
    mov [rip + argv + 32], rax
    lea rax, [rip + .La_dashdash]
    mov [rip + argv + 40], rax
    mov rax, [rsp]
    mov [rip + argv + 48], rax
    mov qword ptr [rip + argv + 56], 0
    mov edi, GK_BLAME
    mov rsi, r15
    mov rdx, r14
    mov ecx, BLAME_OUT
    call start_job
    mov rdi, r15
    call mem_free
9:  EPILOGUE
8:  call extproto_answer_syntax
    EPILOGUE
81: lea rsi, [rip + .Le_nodoc]
    jmp 89f
82: lea rsi, [rip + .Le_nopath]
    jmp 89f
83: lea rsi, [rip + .Le_lines]
    jmp 89f
84: lea rsi, [rip + .Le_text]
89: call send_error
    EPILOGUE

# ID git-log MAX L1 L2 LEN + path -> the commits that touched the path (L1 L2 0 0), or lines L1 to L2 of
#   it at HEAD (git log -L); no path: the history of HEAD
FN gitdata_h_log
    PROLOGUE 32
    call req
    mov rbx, rax
    mov r12, rdx
    call gate
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 6
    jne 8f
    mov edi, 2
    call extproto_field
    test edx, edx
    jz 8f
    test rax, rax
    jz 8f
    cmp rax, LOG_MAX
    ja 8f
    mov r13, rax                # MAX
    mov edi, 3
    call extproto_field
    test edx, edx
    jz 8f
    mov r14, rax                # L1
    mov edi, 4
    call extproto_field
    test edx, edx
    jz 8f
    mov r15, rax                # L2
    test r14, r14
    jnz 1f
    test r15, r15
    jnz 8f
    jmp 2f
1:  cmp r15, r14
    jb 8f
    cmp r15, 100000000
    ja 8f
2:  call extproto_body
    mov [rsp], rdx
    test rdx, rdx
    jz 3f
    mov rdi, rax
    mov rsi, rdx
    call path_arg
    test rax, rax
    jz 9f
    mov [rsp + 8], rax
    jmp 4f
3:  test r14, r14               # lines need a file
    jnz 8f
4:  call room
    test eax, eax
    jz 9f
    # git log -s --no-color --no-ext-diff --format=... -nMAX [--follow -- PATH | -L L1,L2:PATH]
    lea rdi, [rip + nbuf]
    mov word ptr [rdi], 0x6e2d   # "-n"
    lea rdi, [rip + nbuf + 2]
    mov rsi, r13
    call fmt_u64
    lea rcx, [rip + nbuf + 2]
    mov byte ptr [rcx + rax], 0
    lea rax, [rip + .La_log]
    mov [rip + argv], rax
    lea rax, [rip + .La_s]
    mov [rip + argv + 8], rax
    lea rax, [rip + .La_no_color]
    mov [rip + argv + 16], rax
    lea rax, [rip + .La_no_ext]
    mov [rip + argv + 24], rax
    lea rax, [rip + .La_log_format]
    mov [rip + argv + 32], rax
    lea rax, [rip + nbuf]
    mov [rip + argv + 40], rax
    mov ecx, 6
    cmp qword ptr [rsp], 0
    je 7f
    test r14, r14
    jnz 5f
    lea rax, [rip + .La_follow]
    mov [rip + argv + 48], rax
    lea rax, [rip + .La_dashdash]
    mov [rip + argv + 56], rax
    mov rax, [rsp + 8]
    mov [rip + argv + 64], rax
    mov ecx, 9
    jmp 7f
5:  # -L "L1,L2:PATH"
    lea rdi, [rip + lbuf]
    mov rsi, r14
    call fmt_u64
    lea rdi, [rip + lbuf]
    add rdi, rax
    mov byte ptr [rdi], ','
    inc rdi
    mov [rsp + 16], rdi
    mov rsi, r15
    call fmt_u64
    mov rdi, [rsp + 16]
    add rdi, rax
    mov byte ptr [rdi], ':'
    inc rdi
    mov rsi, [rsp + 8]
1:  lodsb
    stosb
    test al, al
    jnz 1b
    lea rax, [rip + .La_dash_l]
    mov [rip + argv + 48], rax
    lea rax, [rip + lbuf]
    mov [rip + argv + 56], rax
    mov ecx, 8
7:  lea rax, [rip + argv]
    mov qword ptr [rax + rcx*8], 0
    mov edi, GK_LOG
    xor esi, esi
    xor edx, edx
    mov ecx, LOG_OUT
    call start_job
9:  EPILOGUE
8:  call extproto_answer_syntax
    EPILOGUE

# ID git-show REV LEN + path -> the file's bytes at REV
FN gitdata_h_show
    PROLOGUE 16
    call req
    mov rbx, rax
    mov r12, rdx
    call gate
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 4
    jne 8f
    mov edi, 2
    lea rsi, [rip + rev1]
    call rev_arg
    test eax, eax
    jz 8f
    call extproto_body
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call path_arg
    test rax, rax
    jz 9f
    mov r13, rax
    call room
    test eax, eax
    jz 9f
    # git cat-file blob REV:PATH
    lea rdi, [rip + lbuf]
    lea rsi, [rip + rev1]
1:  lodsb
    test al, al
    jz 2f
    stosb
    jmp 1b
2:  mov al, ':'
    stosb
    mov rsi, r13
3:  lodsb
    stosb
    test al, al
    jnz 3b
    lea rax, [rip + .La_cat_file]
    mov [rip + argv], rax
    lea rax, [rip + .La_blob]
    mov [rip + argv + 8], rax
    lea rax, [rip + lbuf]
    mov [rip + argv + 16], rax
    mov qword ptr [rip + argv + 24], 0
    mov edi, GK_SHOW
    xor esi, esi
    xor edx, edx
    mov ecx, SHOW_MAX
    call start_job
9:  EPILOGUE
8:  call extproto_answer_syntax
    EPILOGUE

# ID git-diff-open REV1 REV2 LEN + path -> ok ID: rhun's read-only diff view of the file from REV1 to
#   REV2 (REV2 "-": the file in the work tree)
FN gitdata_h_diff_open
    PROLOGUE 16
    call req
    mov rbx, rax
    mov r12, rdx
    call gate
    test eax, eax
    jz 9f
    call extproto_nfields
    cmp rax, 5
    jne 8f
    mov edi, 2
    lea rsi, [rip + rev1]
    call rev_arg
    test eax, eax
    jz 8f
    xor r14d, r14d
    mov edi, 3
    call extproto_field_at
    cmp rdx, 1
    jne 1f
    cmp byte ptr [rax], '-'
    je 2f
1:  mov edi, 3
    lea rsi, [rip + rev2]
    call rev_arg
    test eax, eax
    jz 8f
    lea r14, [rip + rev2]
2:  call extproto_body
    test rdx, rdx
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call path_arg
    test rax, rax
    jz 9f
    mov r13, rax
    mov r15, rdx
    lea rdi, [rip + rev1]
    mov rsi, r14
    mov rdx, r13
    mov rcx, r15
    call git_open_diff2
    call send_ok_plain
9:  EPILOGUE
8:  call extproto_answer_syntax
    EPILOGUE

# req() -> rax the extension being served, rdx its request id
req:
    push rbx
    call extproto_cur
    mov rbx, rax
    call extproto_req_id
    mov rdx, rax
    mov rax, rbx
    pop rbx
    ret

# gate() -> eax 1 when the extension (rbx, request r12) may have Git data now; else it was answered
gate:
    PROLOGUE
    lea rsi, [rip + .Le_unknown]
    FEAT_TEST rbx, FEAT_GIT_DATA
    jz 8f
    lea rsi, [rip + .Le_needs]
    test dword ptr [rbx + EXT_needs], NEEDS_GIT_READ
    jz 8f
    lea rsi, [rip + .Le_paused]
    cmp dword ptr [rip + g_git_paused], 0
    jne 8f
    call git_common_dir
    lea rsi, [rip + .Le_norepo]
    test rax, rax
    jz 8f
    lea rsi, [rip + .Le_off]
    cmp dword ptr [rip + g_git_on], 0
    je 8f
    mov eax, 1
    EPILOGUE
8:  call send_error
    xor eax, eax
    EPILOGUE

# room() -> eax 1 when the extension (rbx, request r12) may have one more request waiting; else it was
#   answered busy
room:
    PROLOGUE
    mov rcx, [rip + pending + VEC_len]
    cmp rcx, GQ_MAX
    jae 8f
    xor edx, edx
    xor r8d, r8d
1:  cmp r8, rcx
    jae 2f
    mov rax, [rip + pending + VEC_ptr]
    mov rax, [rax + r8*8]
    inc r8
    cmp [rax + GQ_ext], rbx
    jne 1b
    inc edx
    jmp 1b
2:  cmp edx, GQ_EXT_MAX
    jae 8f
    mov eax, 1
    EPILOGUE
8:  lea rsi, [rip + .Le_busy]
    call send_error
    xor eax, eax
    EPILOGUE

# rev_arg(field, dest) -> eax 1 when the field is a revision rhun hands git (copied into dest as a cstr):
#   1 to REV_MAX bytes of letters, digits and . _ / ~ ^ @ { } + -, not starting with -
rev_arg:
    PROLOGUE
    mov r13, rsi
    call extproto_field_at
    test rdx, rdx
    jz 8f
    cmp rdx, REV_MAX
    ja 8f
    cmp byte ptr [rax], '-'
    je 8f
    xor ecx, ecx
1:  cmp rcx, rdx
    jae 3f
    movzx r8d, byte ptr [rax + rcx]
    mov r9d, r8d
    or r9d, 0x20
    cmp r9d, 'a'
    jb 11f
    cmp r9d, 'z'
    jbe 2f
11: cmp r8d, '0'
    jb 12f
    cmp r8d, '9'
    jbe 2f
12: lea rsi, [rip + .Lrev_chars]
13: cmp byte ptr [rsi], 0
    je 8f
    cmp [rsi], r8b
    je 2f
    inc rsi
    jmp 13b
2:  mov [r13 + rcx], r8b
    inc rcx
    jmp 1b
3:  mov byte ptr [r13 + rcx], 0
    mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# path_arg(ptr, len) -> rax the path inside the work tree as a cstr (in pbuf), rdx its length; 0 after
#   answering when it is not one. Absolute paths must lie in the work tree; others are relative to it
path_arg:
    PROLOGUE
    mov r13, rdi
    mov r14, rsi
    cmp r14, 4095
    ja 7f
    xor ecx, ecx
1:  cmp rcx, r14
    jae 2f
    movzx eax, byte ptr [r13 + rcx]
    inc rcx
    test eax, eax
    jz 7f
    cmp eax, 10
    je 7f
    cmp eax, 13
    je 7f
    jmp 1b
2:  lea rdi, [rip + pbuf]
    mov rsi, r13
    mov rdx, r14
    call memcpy
    lea rax, [rip + pbuf]
    mov byte ptr [rax + r14], 0
    lea rdi, [rip + pbuf]
    call path_rootlen
    test eax, eax
    jz 3f
    lea rdi, [rip + pbuf]
    call git_rel
    test rax, rax
    jz 6f
    EPILOGUE
3:  # relative: no segment ".." leads up and out of it
    test r14, r14
    jz 6f
    lea r8, [rip + pbuf]
    xor ecx, ecx                # the segment's start
4:  mov rdx, rcx
41: cmp rdx, r14
    jae 42f
    cmp byte ptr [r8 + rdx], '/'
    je 42f
    inc rdx
    jmp 41b
42: mov rax, rdx
    sub rax, rcx
    cmp rax, 2
    jne 43f
    cmp word ptr [r8 + rcx], 0x2e2e
    je 6f
43: lea rcx, [rdx + 1]
    cmp rdx, r14
    jb 4b
    lea rax, [rip + pbuf]
    mov rdx, r14
    EPILOGUE
6:  lea rsi, [rip + .Le_outside]
    call send_error
    xor eax, eax
    EPILOGUE
7:  call extproto_answer_syntax
    xor eax, eax
    EPILOGUE

# crlf_expand(buf, len) -> the new length: each LF becomes CR LF, in place (buf has room for twice len)
crlf_expand:
    xor ecx, ecx
    xor edx, edx
1:  cmp rcx, rsi
    jae 2f
    cmp byte ptr [rdi + rcx], 10
    jne 11f
    inc rdx
11: inc rcx
    jmp 1b
2:  lea rax, [rsi + rdx]
    mov r8, rax                 # write position + 1
3:  test rsi, rsi
    jz 9f
    dec rsi
    mov cl, [rdi + rsi]
    dec r8
    mov [rdi + r8], cl
    cmp cl, 10
    jne 3b
    dec r8
    mov byte ptr [rdi + r8], 13
    jmp 3b
9:  ret

# start_job(kind, input ptr, input len, cap): git argv for the extension's request (rbx, r12); answered
#   when git is done
start_job:
    PROLOGUE 32
    mov [rsp], edi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    mov edi, GQ_SIZE
    call mem_alloc
    mov r13, rax
    call fill_gq
    mov eax, [rsp]
    mov [r13 + GQ_kind], eax
    lea rdi, [rip + argv]
    lea rsi, [rip + on_answer]
    mov rdx, r13
    mov rcx, [rsp + 8]
    mov r8, [rsp + 16]
    mov r9, [rsp + 24]
    call git_start
    test rax, rax
    jz 8f                       # git_start freed the request
    mov [r13 + GQ_job], rax
    lea rdi, [rip + pending]
    mov esi, 8
    call vec_push
    mov [rax], r13
    EPILOGUE
8:  lea rsi, [rip + .Le_start]
    call send_error
    EPILOGUE

# fill_gq(): the request r13 for rbx's request r12, due in GQ_MS
fill_gq:
    push rbx
    mov [r13 + GQ_ext], rbx
    mov [r13 + GQ_id], r12
    mov eax, [rbx + EXT_pid]
    mov [r13 + GQ_pid], eax
    mov qword ptr [r13 + GQ_job], 0
    call time_ms
    add rax, GQ_MS
    mov [r13 + GQ_deadline], rax
    pop rbx
    ret

# add_pending(kind, job): a request of rbx's (id r12) waits
add_pending:
    PROLOGUE
    mov r14d, edi
    mov r15, rsi
    mov edi, GQ_SIZE
    call mem_alloc
    mov r13, rax
    call fill_gq
    mov [r13 + GQ_kind], r14d
    mov [r13 + GQ_job], r15
    lea rdi, [rip + pending]
    mov esi, 8
    call vec_push
    mov [rax], r13
    EPILOGUE

# ---------------- answers ----------------

# send_ok(): "ok ID LEN" and the body to rbx's request r12
send_ok:
    mov eax, 1
    jmp 2f
# send_ok_plain(): "ok ID" to rbx's request r12
send_ok_plain:
    xor eax, eax
2:  PROLOGUE
    mov r13d, eax
    lea rdi, [rip + rb]
    call sb_clear
    lea rdi, [rip + rb]
    lea rsi, [rip + .Lok]
    call sb_push_cstr
    lea rdi, [rip + rb]
    mov rsi, r12
    call sb_push_u64
    test r13d, r13d
    jz 1f
    lea rdi, [rip + rb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + rb]
    mov rsi, [rip + body + SB_len]
    call sb_push_u64
    lea rdi, [rip + rb]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + rb]
    mov rsi, [rip + body + SB_ptr]
    mov rdx, [rip + body + SB_len]
    call sb_push
    jmp 2f
1:  lea rdi, [rip + rb]         # a plain "ok ID": no body
    mov esi, 10
    call sb_push_byte
2:
    mov rdi, rbx
    mov rsi, [rip + rb + SB_ptr]
    mov rdx, [rip + rb + SB_len]
    call ext_send_checked
    EPILOGUE

# send_error(text): "error ID TEXT" to rbx's request r12
send_error:
    PROLOGUE
    mov r13, rsi
    lea rdi, [rip + rb]
    call sb_clear
    lea rdi, [rip + rb]
    lea rsi, [rip + .Lerror]
    call sb_push_cstr
    lea rdi, [rip + rb]
    mov rsi, r12
    call sb_push_u64
    lea rdi, [rip + rb]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + rb]
    mov rsi, r13
    call sb_push_cstr
    lea rdi, [rip + rb]
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + rb + SB_ptr]
    mov rdx, [rip + rb + SB_len]
    call ext_send_checked
    EPILOGUE

# send_body(): send_ok, or toobig when the body went over REPLY_MAX
send_body:
    cmp qword ptr [rip + body + SB_len], REPLY_MAX
    jbe send_ok
    lea rsi, [rip + .Le_toobig]
    jmp send_error

# alive(gq) -> eax 1 when its extension still waits: the same process, running
alive:
    xor eax, eax
    mov rcx, [rdi + GQ_ext]
    test rcx, rcx
    jz 9f
    cmp dword ptr [rcx + EXT_status], ES_RUNNING
    jne 9f
    mov edx, [rcx + EXT_pid]
    cmp edx, [rdi + GQ_pid]
    jne 9f
    mov eax, 1
9:  ret

# unlist(gq): out of the pending list (if there)
unlist:
    mov rcx, [rip + pending + VEC_len]
    mov rax, [rip + pending + VEC_ptr]
    xor edx, edx
1:  cmp rdx, rcx
    jae 9f
    cmp [rax + rdx*8], rdi
    je 2f
    inc rdx
    jmp 1b
2:  push rbx
    lea rdi, [rax + rdx*8]
    lea rsi, [rdi + 8]
    sub rcx, rdx
    dec rcx
    lea rdx, [rcx*8]
    call memmove
    dec qword ptr [rip + pending + VEC_len]
    pop rbx
9:  ret

# on_answer(gq, ptr, len, status): git is done with an extension's request
on_answer:
    PROLOGUE 16
    mov r15, rdi
    mov r13, rsi
    mov r14, rdx
    mov [rsp], ecx
    call unlist
    mov rdi, r15
    call alive
    test eax, eax
    jz 9f
    mov rbx, [r15 + GQ_ext]
    mov r12, [r15 + GQ_id]
    lea rsi, [rip + .Le_toobig]
    cmp dword ptr [rsp], -1
    je 8f
    mov eax, [r15 + GQ_kind]
    cmp eax, GK_BLAME
    je .Loa_blame
    cmp eax, GK_LOG
    je .Loa_log
    # git-show: the bytes as they are
    lea rsi, [rip + .Le_show]
    cmp dword ptr [rsp], 0
    jne 8f
    lea rdi, [rip + body]
    call sb_clear
    lea rdi, [rip + body]
    mov rsi, r13
    mov rdx, r14
    call sb_push
    call send_body
    jmp 9f
.Loa_blame:
    lea rsi, [rip + .Le_blame]
    cmp dword ptr [rsp], 0
    jne 8f
    mov rdi, r13
    mov rsi, r14
    call blame_body
    call send_body
    jmp 9f
.Loa_log:
    lea rsi, [rip + .Le_log]
    cmp dword ptr [rsp], 0
    jne 8f
    mov rdi, r13
    mov rsi, r14
    call log_body
    call send_body
    jmp 9f
8:  call send_error
9:  call shrink
    EPILOGUE

# shrink(): the answer buffers give back what a large answer took
shrink:
    push rbx
    lea rbx, [rip + body]
    call 1f
    lea rbx, [rip + rb]
    call 1f
    lea rbx, [rip + cbuf]
    call 1f
    lea rbx, [rip + runs]
    call 1f
    pop rbx
    ret
1:  cmp qword ptr [rbx + SB_cap], 1048576
    jbe 2f
    mov rdi, rbx
    jmp sb_free
2:  ret

# answer_settled(kind): git-repo or git-status for rbx's request r12, from the status in memory
answer_settled:
    PROLOGUE
    mov r13d, edi
    lea rdi, [rip + body]
    call sb_clear
    cmp r13d, GK_STATUS
    je 5f
    # git-repo
    mov rdi, [rip + g_git_root]
    call strlen
    mov r13, rax
    lea rdi, [rip + g_branch]
    call strlen
    mov r14, rax
    lea rdi, [rip + g_git_upstream]
    call strlen
    mov r15, rax
    mov rdi, r13
    call push_num
    mov rdi, r14
    call push_num
    mov rdi, r15
    call push_num
    lea rsi, [rip + .Lh_branch]
    cmp dword ptr [rip + g_git_head], HD_DETACHED
    jne 1f
    lea rsi, [rip + .Lh_detached]
1:  cmp dword ptr [rip + g_git_head], HD_UNBORN
    jne 2f
    lea rsi, [rip + .Lh_unborn]
2:  call push_word
    mov edi, [rip + g_git_ahead]
    call push_num
    mov edi, [rip + g_git_behind]
    call push_num
    call repo_state
    mov rsi, rax
    lea rdi, [rip + body]
    call sb_push_cstr
    lea rdi, [rip + body]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + body]
    mov rsi, [rip + g_git_root]
    mov rdx, r13
    call sb_push
    lea rdi, [rip + body]
    lea rsi, [rip + g_branch]
    mov rdx, r14
    call sb_push
    lea rdi, [rip + body]
    lea rsi, [rip + g_git_upstream]
    mov rdx, r15
    call sb_push
    call send_ok
    EPILOGUE
5:  call status_body
    call send_body
    EPILOGUE

# push_num(v) / push_word(cstr): onto the body, then a space
push_num:
    mov rsi, rdi
    lea rdi, [rip + body]
    call sb_push_u64
    jmp 1f
push_word:
    lea rdi, [rip + body]
    call sb_push_cstr
1:  lea rdi, [rip + body]
    mov esi, ' '
    jmp sb_push_byte

# repo_state() -> rax "merging", "rebasing", "dirty" or "clean"
repo_state:
    PROLOGUE
    call git_gitdir
    mov rbx, rax
    lea r12, [rip + .Lst_merging]
    lea rsi, [rip + .Lf_merge_head]
    call in_gitdir
    test eax, eax
    jnz 8f
    lea r12, [rip + .Lst_rebasing]
    lea rsi, [rip + .Lf_rebase_merge]
    call in_gitdir
    test eax, eax
    jnz 8f
    lea rsi, [rip + .Lf_rebase_apply]
    call in_gitdir
    test eax, eax
    jnz 8f
    lea r12, [rip + .Lst_dirty]
    cmp dword ptr [rip + g_git_changes], 0
    jne 8f
    lea r12, [rip + .Lst_clean]
8:  mov rax, r12
    EPILOGUE

# in_gitdir(name) -> eax 1 when rbx (the git directory) holds that name
in_gitdir:
    PROLOGUE
    xor eax, eax
    test rbx, rbx
    jz 9f
    mov rdi, rbx
    call path_join
    mov r13, rax
    mov rdi, rax
    call file_missing
    mov r14d, eax
    mov rdi, r13
    call mem_free
    xor eax, eax
    test r14d, r14d
    sete al
9:  EPILOGUE

# status_body(): the status records (git status --porcelain -z) as N, then XY PATH_LEN LF PATH
status_body:
    PROLOGUE
    lea rdi, [rip + cbuf]
    call sb_clear
    xor r15d, r15d              # entries
    call git_status_records
    mov r12, rax
    lea r13, [rax + rdx]
    test r12, r12
    jz 8f
1:  lea rax, [r12 + 3]
    cmp rax, r13
    ja 8f
    movzx r14d, byte ptr [r12]
    movzx ebx, byte ptr [r12 + 1]
    lea rdi, [r12 + 3]
    mov r12, rdi
    call strlen
    mov rcx, rax
    cmp r14d, '!'
    je 4f
    inc r15d
    mov edi, r14d
    call status_char
    lea rdi, [rip + cbuf]
    mov esi, eax
    call sb_push_byte
    mov edi, ebx
    call status_char
    lea rdi, [rip + cbuf]
    mov esi, eax
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov esi, ' '
    call sb_push_byte
    mov rdi, r12
    call strlen
    lea rdi, [rip + cbuf]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + cbuf]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov rsi, r12
    call sb_push_cstr
4:  mov rdi, r12
    call strlen
    lea r12, [r12 + rax + 1]
    cmp r14d, 'R'
    je 5f
    cmp r14d, 'C'
    jne 1b
5:  cmp r12, r13                # the name it had before
    jae 8f
    mov rdi, r12
    call strlen
    lea r12, [r12 + rax + 1]
    jmp 1b
8:  lea rdi, [rip + body]
    call sb_clear
    lea rdi, [rip + body]
    mov esi, r15d
    call sb_push_u64
    lea rdi, [rip + body]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + body]
    mov rsi, [rip + cbuf + SB_ptr]
    mov rdx, [rip + cbuf + SB_len]
    call sb_push
    EPILOGUE

# status_char(c) -> eax: a status column, an unchanged side as "." (git status --porcelain=v2)
status_char:
    mov eax, edi
    cmp eax, ' '
    jne 1f
    mov eax, '.'
1:  ret

# blame_body(ptr, len): git blame --porcelain into NC NR LF, NC commits SHA TIME AUTHOR_LEN MAIL_LEN
#   SUMMARY_LEN LF <AUTHOR><MAIL><SUMMARY>, then NR runs SHA L1 L2 ORIG_L1 LF
#   Porcelain gives each line a header "SHA ORIG FINAL [N]" (N on a group's first line), the first time
#   a commit appears its "key value" lines, then the line itself after a tab.
blame_body:
    PROLOGUE 32
    mov r12, rdi
    lea r13, [rdi + rsi]
    lea rdi, [rip + cbuf]
    call sb_clear
    lea rdi, [rip + runs]
    call sb_clear
    mov dword ptr [rip + ncommits], 0
    mov dword ptr [rip + nruns], 0
    mov dword ptr [rip + cm_reading], 0
    call commit_clear
.Lbb_line:
    cmp r12, r13
    jae .Lbb_end
    mov r14, r12
1:  cmp r14, r13
    jae 2f
    cmp byte ptr [r14], 10
    je 2f
    inc r14
    jmp 1b
2:  lea rax, [r14 + 1]
    mov [rsp], rax              # the next line
    mov r15, r14
    sub r15, r12                # this line's length
    jz .Lbb_next
    cmp byte ptr [r12], 9
    je .Lbb_text
    mov rdi, r12
    mov rsi, r15
    call hex_run
    cmp eax, 40
    je .Lbb_header
    cmp eax, 64
    je .Lbb_header
    # a key line: only a new commit has them, starting with its author
    cmp dword ptr [rip + cm_reading], 0
    jne 3f
    mov rdi, r12
    mov rsi, r15
    lea rdx, [rip + .Lk_author]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz .Lbb_next
    mov dword ptr [rip + cm_reading], 1
3:  mov rdi, r12
    mov rsi, r15
    lea rdx, [rip + .Lk_author]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz 4f
    lea rax, [r12 + 7]
    mov [rip + cm_author], rax
    lea rax, [r15 - 7]
    mov [rip + cm_author + 8], rax
    jmp .Lbb_next
4:  mov rdi, r12
    mov rsi, r15
    lea rdx, [rip + .Lk_mail]
    mov ecx, 12
    call str_starts
    test eax, eax
    jz 5f
    lea rax, [r12 + 12]
    lea rcx, [r15 - 12]
    test rcx, rcx               # without its angle brackets
    jz 41f
    cmp byte ptr [rax], '<'
    jne 41f
    inc rax
    dec rcx
    test rcx, rcx
    jz 41f
    cmp byte ptr [rax + rcx - 1], '>'
    jne 41f
    dec rcx
41: mov [rip + cm_mail], rax
    mov [rip + cm_mail + 8], rcx
    jmp .Lbb_next
5:  mov rdi, r12
    mov rsi, r15
    lea rdx, [rip + .Lk_time]
    mov ecx, 12
    call str_starts
    test eax, eax
    jz 6f
    lea rdi, [r12 + 12]
    lea rsi, [r15 - 12]
    call parse_u64
    mov [rip + cm_time], rax
    jmp .Lbb_next
6:  mov rdi, r12
    mov rsi, r15
    lea rdx, [rip + .Lk_summary]
    mov ecx, 8
    call str_starts
    test eax, eax
    jz .Lbb_next
    lea rax, [r12 + 8]
    mov [rip + cm_summary], rax
    lea rax, [r15 - 8]
    mov [rip + cm_summary + 8], rax
    jmp .Lbb_next
.Lbb_header:
    mov [rsp + 8], eax
    call commit_flush
    mov eax, [rsp + 8]
    mov [rip + cm_sha], r12
    mov [rip + cm_shalen], rax
    # ORIG FINAL [N]
    lea rdi, [r12 + rax + 1]
    lea rsi, [r12 + r15]
    call next_number
    mov [rsp + 16], rax         # orig
    mov rdi, rdx
    lea rsi, [r12 + r15]
    call next_number
    mov rbx, rax                # final
    mov rdi, rdx
    lea rsi, [r12 + r15]
    call next_number
    test rax, rax               # no N: a later line of the group
    jz .Lbb_next
    # a run: SHA FINAL FINAL+N-1 ORIG
    mov r15, rax
    inc dword ptr [rip + nruns]
    lea rdi, [rip + runs]
    mov rsi, [rip + cm_sha]
    mov rdx, [rip + cm_shalen]
    call sb_push
    lea rdi, [rip + runs]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + runs]
    mov rsi, rbx
    call sb_push_u64
    lea rdi, [rip + runs]
    mov esi, ' '
    call sb_push_byte
    lea rsi, [rbx + r15 - 1]
    lea rdi, [rip + runs]
    call sb_push_u64
    lea rdi, [rip + runs]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + runs]
    mov rsi, [rsp + 16]
    call sb_push_u64
    lea rdi, [rip + runs]
    mov esi, 10
    call sb_push_byte
    jmp .Lbb_next
.Lbb_text:
    call commit_flush
.Lbb_next:
    mov r12, [rsp]
    jmp .Lbb_line
.Lbb_end:
    call commit_flush
    lea rdi, [rip + body]
    call sb_clear
    lea rdi, [rip + body]
    mov esi, [rip + ncommits]
    call sb_push_u64
    lea rdi, [rip + body]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + body]
    mov esi, [rip + nruns]
    call sb_push_u64
    lea rdi, [rip + body]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + body]
    mov rsi, [rip + cbuf + SB_ptr]
    mov rdx, [rip + cbuf + SB_len]
    call sb_push
    lea rdi, [rip + body]
    mov rsi, [rip + runs + SB_ptr]
    mov rdx, [rip + runs + SB_len]
    call sb_push
    EPILOGUE

# commit_flush(): the commit whose key lines were read onto cbuf
commit_flush:
    PROLOGUE
    cmp dword ptr [rip + cm_reading], 0
    je 9f
    mov dword ptr [rip + cm_reading], 0
    inc dword ptr [rip + ncommits]
    lea rdi, [rip + cbuf]
    mov rsi, [rip + cm_sha]
    mov rdx, [rip + cm_shalen]
    call sb_push
    lea rbx, [rip + cm_time]
    call num_sp
    lea rbx, [rip + cm_author + 8]
    call num_sp
    lea rbx, [rip + cm_mail + 8]
    call num_sp
    lea rbx, [rip + cm_summary + 8]
    call num_sp
    lea rdi, [rip + cbuf]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov rsi, [rip + cm_author]
    mov rdx, [rip + cm_author + 8]
    call sb_push
    lea rdi, [rip + cbuf]
    mov rsi, [rip + cm_mail]
    mov rdx, [rip + cm_mail + 8]
    call sb_push
    lea rdi, [rip + cbuf]
    mov rsi, [rip + cm_summary]
    mov rdx, [rip + cm_summary + 8]
    call sb_push
    call commit_clear
9:  EPILOGUE

# num_sp(): a space and the number at [rbx] onto cbuf
num_sp:
    lea rdi, [rip + cbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov rsi, [rbx]
    jmp sb_push_u64

# commit_clear(): no commit being read
commit_clear:
    lea rdi, [rip + cm_author]
    xor eax, eax
    mov ecx, 56
    rep stosb
    ret

# hex_run(ptr, len) -> eax how many hex digits it starts with, when a space follows them; else 0
hex_run:
    xor eax, eax
1:  cmp rax, rsi
    jae 8f
    movzx ecx, byte ptr [rdi + rax]
    cmp ecx, ' '
    je 9f
    or ecx, 0x20
    cmp ecx, '0'
    jb 8f
    cmp ecx, '9'
    jbe 2f
    cmp ecx, 'a'
    jb 8f
    cmp ecx, 'f'
    ja 8f
2:  inc rax
    jmp 1b
8:  xor eax, eax
9:  ret

# next_number(ptr, end) -> rax the decimal number after the spaces at ptr (0 when none), rdx after it
next_number:
1:  cmp rdi, rsi
    jae 8f
    cmp byte ptr [rdi], ' '
    jne 2f
    inc rdi
    jmp 1b
2:  push rdi
    sub rsi, rdi
    call parse_u64
    pop rdi
    add rdx, rdi
    ret
8:  xor eax, eax
    mov rdx, rdi
    ret

# log_body(ptr, len): records "\1SHA\0PARENTS\0TIME\0AUTHOR\0SUBJECT\0" (anything between them, as the
#   patches of an older git log -L, is skipped) into N LF, then SHA PARENTS TIME AUTHOR_LEN SUBJECT_LEN LF
#   <AUTHOR><SUBJECT>; PARENTS joined by commas, "-" for none
log_body:
    PROLOGUE 80                 # the five fields' starts, then their lengths
    mov r12, rdi
    lea r13, [rdi + rsi]
    lea rdi, [rip + cbuf]
    call sb_clear
    xor r15d, r15d
.Llb_find:
    cmp r12, r13
    jae .Llb_end
    cmp byte ptr [r12], 1
    je 1f
    inc r12
    jmp .Llb_find
1:  inc r12
    # five fields, each ending in NUL
    xor ebx, ebx
2:  mov rdi, r12
3:  cmp rdi, r13
    jae .Llb_end
    cmp byte ptr [rdi], 0
    je 4f
    inc rdi
    jmp 3b
4:  mov [rsp + rbx*8], r12      # field start
    mov rax, rdi
    sub rax, r12
    mov [rsp + 40 + rbx*8], rax
    lea r12, [rdi + 1]
    inc ebx
    cmp ebx, 5
    jb 2b
    inc r15d
    lea rdi, [rip + cbuf]
    mov rsi, [rsp]
    mov rdx, [rsp + 40]
    call sb_push
    lea rdi, [rip + cbuf]
    mov esi, ' '
    call sb_push_byte
    # parents
    mov rcx, [rsp + 48]
    test rcx, rcx
    jnz 5f
    lea rdi, [rip + cbuf]
    mov esi, '-'
    call sb_push_byte
    jmp 7f
5:  mov rbx, [rsp + 8]
    mov r14, rbx
    add r14, [rsp + 48]
6:  cmp rbx, r14
    jae 7f
    movzx esi, byte ptr [rbx]
    cmp esi, ' '
    jne 61f
    mov esi, ','
61: lea rdi, [rip + cbuf]
    call sb_push_byte
    inc rbx
    jmp 6b
7:  lea rdi, [rip + cbuf]
    mov esi, ' '
    call sb_push_byte
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 56]
    call parse_u64
    lea rdi, [rip + cbuf]
    mov rsi, rax
    call sb_push_u64
    lea rdi, [rip + cbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov rsi, [rsp + 64]
    call sb_push_u64
    lea rdi, [rip + cbuf]
    mov esi, ' '
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov rsi, [rsp + 72]
    call sb_push_u64
    lea rdi, [rip + cbuf]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + cbuf]
    mov rsi, [rsp + 24]
    mov rdx, [rsp + 64]
    call sb_push
    lea rdi, [rip + cbuf]
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 72]
    call sb_push
    jmp .Llb_find
.Llb_end:
    lea rdi, [rip + body]
    call sb_clear
    lea rdi, [rip + body]
    mov esi, r15d
    call sb_push_u64
    lea rdi, [rip + body]
    mov esi, 10
    call sb_push_byte
    lea rdi, [rip + body]
    mov rsi, [rip + cbuf + SB_ptr]
    mov rdx, [rip + cbuf + SB_len]
    call sb_push
    EPILOGUE

# ---------------- the life of requests ----------------

# gitdata_status_done(): a status refresh ended (git.s): requests that waited for it are answered, and
#   extensions hear "0 git changed" when the status, branch or upstream changed or HEAD moved
FN gitdata_status_done
    PROLOGUE
    call git_status_settled
    test eax, eax
    jz 5f
    xor r15d, r15d
1:  cmp r15, [rip + pending + VEC_len]
    jae 5f
    mov rax, [rip + pending + VEC_ptr]
    mov r13, [rax + r15*8]
    cmp qword ptr [r13 + GQ_job], 0
    je 2f
    inc r15
    jmp 1b
2:  mov rdi, r13
    call unlist
    mov rdi, r13
    call alive
    test eax, eax
    jz 3f
    mov rbx, [r13 + GQ_ext]
    mov r12, [r13 + GQ_id]
    mov edi, [r13 + GQ_kind]
    call answer_settled
3:  mov rdi, r13
    call mem_free
    jmp 1b
5:  call status_sig
    cmp rax, [rip + last_sig]
    jne 6f
    cmp dword ptr [rip + head_moved], 0
    je 9f
6:  mov [rip + last_sig], rax
    mov dword ptr [rip + head_moved], 0
    call announce
9:  call shrink
    EPILOGUE

# status_sig() -> a hash of the status records, branch, HEAD kind, upstream, ahead and behind (never 0)
status_sig:
    PROLOGUE
    call git_status_records
    mov rdi, rax
    mov rsi, rdx
    call hash_line
    mov rbx, rax
    lea rdi, [rip + g_branch]
    call strlen
    lea rdi, [rip + g_branch]
    mov rsi, rax
    call hash_line
    imul rbx, rbx, 31
    xor rbx, rax
    lea rdi, [rip + g_git_upstream]
    call strlen
    lea rdi, [rip + g_git_upstream]
    mov rsi, rax
    call hash_line
    imul rbx, rbx, 31
    xor rbx, rax
    mov eax, [rip + g_git_ahead]
    shl rax, 32
    mov ecx, [rip + g_git_behind]
    or rax, rcx
    imul rbx, rbx, 31
    xor rbx, rax
    mov eax, [rip + g_git_head]
    imul rbx, rbx, 31
    xor rbx, rax
    or rbx, 1
    mov rax, rbx
    EPILOGUE

# announce(): "0 git changed" to every running extension that agreed git-data and may read Git data
announce:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 1b
    FEAT_TEST rbx, FEAT_GIT_DATA
    jz 1b
    test dword ptr [rbx + EXT_needs], NEEDS_GIT_READ
    jz 1b
    mov rdi, rbx
    lea rsi, [rip + .Lev_changed]
    mov edx, .Lev_changed_end - .Lev_changed
    call ext_send_checked
    jmp 1b
9:  EPILOGUE

# gitdata_head_moved(): HEAD moved (git.s); the next status refresh announces it even when the status
#   stayed the same
FN gitdata_head_moved
    mov dword ptr [rip + head_moved], 1
    ret

# gitdata_reset(): the project's repository changes: requests end with "cancelled"; jobs still running
#   free theirs when they end, unanswered
FN gitdata_reset
    PROLOGUE
    lea r14, [rip + .Le_project]
    xor r15d, r15d
    call end_all
    mov qword ptr [rip + last_sig], 0
    mov dword ptr [rip + head_moved], 0
    EPILOGUE

# scm_ext_gone(ext): an extension stopped or went away: its source control requests end unanswered
FN scm_ext_gone
    PROLOGUE
    mov r15, rdi
    xor r14d, r14d
    call end_all
    mov rdi, r15
    call scmext_ext_gone
    mov rdi, r15
    call scmpanel_ext_gone
    EPILOGUE

# end_all(): every request of extension r15 (0: of all) ends; answered "error ID r14" when r14 is not 0
end_all:
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + pending + VEC_len]
    jae 9f
    mov rax, [rip + pending + VEC_ptr]
    mov r13, [rax + r12*8]
    test r15, r15
    jz 2f
    cmp [r13 + GQ_ext], r15
    je 2f
    inc r12
    jmp 1b
2:  mov rdi, r13
    call end_one
    jmp 1b
9:  EPILOGUE

# end_one(gq): out of the list, answered "error ID r14" when r14 is not 0 and its extension waits; its
#   job ends (and frees it), or it is freed
end_one:
    PROLOGUE
    mov r13, rdi
    call unlist
    test r14, r14
    jz 1f
    mov rdi, r13
    call alive
    test eax, eax
    jz 1f
    mov rbx, [r13 + GQ_ext]
    mov r12, [r13 + GQ_id]
    mov rsi, r14
    call send_error
1:  mov qword ptr [r13 + GQ_ext], 0
    mov rdi, [r13 + GQ_job]
    test rdi, rdi
    jz 2f
    call git_job_kill
    EPILOGUE
2:  mov rdi, r13
    call mem_free
    EPILOGUE

# gitdata_tick(): requests past their time end with "cancelled"
FN gitdata_tick
    PROLOGUE
    cmp qword ptr [rip + pending + VEC_len], 0
    je 9f
    call time_ms
    mov rbx, rax
    lea r14, [rip + .Le_timeout]
    xor r15d, r15d
1:  cmp r15, [rip + pending + VEC_len]
    jae 9f
    mov rax, [rip + pending + VEC_ptr]
    mov rdi, [rax + r15*8]
    cmp rbx, [rdi + GQ_deadline]
    jae 2f
    inc r15
    jmp 1b
2:  call end_one
    jmp 1b
9:  EPILOGUE

# gitdata_timeout() -> ms until the first request's time is up, or -1
FN gitdata_timeout
    PROLOGUE
    mov eax, -1
    mov rcx, [rip + pending + VEC_len]
    test rcx, rcx
    jz 9f
    mov rbx, -1
    xor edx, edx
1:  cmp rdx, rcx
    jae 2f
    mov rax, [rip + pending + VEC_ptr]
    mov rax, [rax + rdx*8]
    mov rax, [rax + GQ_deadline]
    cmp rax, rbx
    cmovb rbx, rax
    inc rdx
    jmp 1b
2:  call time_ms
    sub rbx, rax
    mov eax, ebx
    test rbx, rbx
    jns 9f
    xor eax, eax
9:  EPILOGUE

# ---------------- for the tests ----------------

# gitdata_dump(sb): "git-data pending=N", then "git-data sig=N", the signature of the status now
#   (print-git-data)
FN gitdata_dump
    PROLOGUE
    mov rbx, rdi
    lea rsi, [rip + .Ld_pending]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + pending + VEC_len]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Ld_sig]
    call sb_push_cstr
    call status_sig
    mov rdi, rbx
    mov rsi, rax
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

.section .rodata
.Lok: .asciz "ok "
.Lerror: .asciz "error "
.Lev_changed: .ascii "0 git changed\n"
.Lev_changed_end:
.Le_unknown: .asciz "unknown no such request"
.Le_needs: .asciz "needs git=read"
.Le_paused: .asciz "refused git is paused in this folder"
.Le_norepo: .asciz "nofile not in a Git repository"
.Le_off: .asciz "refused git is off"
.Le_busy: .asciz "busy too many Git requests"
.Le_nodoc: .asciz "nodoc no such document"
.Le_nopath: .asciz "nofile the document has no file in the repository"
.Le_lines: .asciz "toobig more than 100000 lines"
.Le_text: .asciz "toobig the document is over 16 MiB"
.Le_toobig: .asciz "toobig the answer is over its limit"
.Le_start: .asciz "busy git could not start"
.Le_blame: .asciz "nofile git cannot blame the file (is it committed?)"
.Le_log: .asciz "nofile git cannot list the file's history"
.Le_show: .asciz "nofile no such file at that revision"
.Le_timeout: .asciz "cancelled git took longer than 15 seconds"
.Le_project: .asciz "cancelled the project changed"
.Le_outside: .asciz "nofile the path is outside the repository"
.Lrev_chars: .asciz "._/~^@{}+-"
.Lh_branch: .asciz "branch"
.Lh_detached: .asciz "detached"
.Lh_unborn: .asciz "unborn"
.Lst_merging: .asciz "merging"
.Lst_rebasing: .asciz "rebasing"
.Lst_dirty: .asciz "dirty"
.Lst_clean: .asciz "clean"
.Lf_merge_head: .asciz "MERGE_HEAD"
.Lf_rebase_merge: .asciz "rebase-merge"
.Lf_rebase_apply: .asciz "rebase-apply"
.Lk_author: .ascii "author "
.Lk_mail: .ascii "author-mail "
.Lk_time: .ascii "author-time "
.Lk_summary: .ascii "summary "
.La_blame: .asciz "blame"
.La_porcelain: .asciz "--porcelain"
.La_no_textconv: .asciz "--no-textconv"
.La_contents: .asciz "--contents"
.La_dash: .asciz "-"
.La_dashdash: .asciz "--"
.La_log: .asciz "log"
.La_s: .asciz "-s"
.La_no_color: .asciz "--no-color"
.La_no_ext: .asciz "--no-ext-diff"
.La_log_format: .asciz "--format=%x01%H%x00%P%x00%at%x00%an%x00%s%x00"
.La_follow: .asciz "--follow"
.La_dash_l: .asciz "-L"
.La_cat_file: .asciz "cat-file"
.La_blob: .asciz "blob"
.Ld_pending: .asciz "git-data pending="
.Ld_sig: .asciz "git-data sig="
