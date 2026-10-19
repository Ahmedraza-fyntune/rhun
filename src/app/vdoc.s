# URIs and virtual documents (feature uris, docs/extensions/v1.1.md): read-only documents an
# extension provides for a URI scheme it declares ([provides] schemes = NAME NAME-x): a macro's
# expansion, a file at a git revision, a generated view. One open per URI; it is a normal
# read-only document tab (DOC_uri set, DOC_path 0) with highlighting, find and selection, and the
# target of locations and open. Its text comes from the provider's answer to "ID content URI";
# "content-changed URI" asks again (a disk reload: cursor and scroll kept); closing its tab sends
# "0 content-closed URI". Never saved, never in the session; closed when the provider is removed
# or turned off (a stopped provider leaves them, and Reload File asks again and starts it).
#
# Local files stay paths everywhere: a file: URI is decoded to its path where one is accepted.
.include "rhun.inc"

.equ VD_MAX, 256                # open virtual documents, all providers
.equ VD_PER_PROVIDER, 64
.equ VD_TEXT_MAX, 4194304
.equ VD_WAIT_MS, 5000           # for the provider to start and answer
STRUCT
F VD_doc, 8             # its DOC, 0 for a free slot
F VD_ext, 8             # the provider
F VD_req, 8             # the content request waiting for its answer, 0 when none
F VD_since, 8           # time_ms the wait began (the provider starting, or the request)
F VD_title, 8           # owned title (DOC_name points at it), or 0
F VD_line, 4            # where open asked the cursor to be once the text is in (0: keep)
F VD_col, 4
F VD_state, 4           # VS_*
F VD_loaded, 4          # 1 once a text was in: later loads keep cursor and scroll
ENDSTRUCT VD_SIZE
.equ VS_WAIT, 0                 # the provider is not running yet
.equ VS_ASKED, 1                # the content request is out
.equ VS_LOADED, 2
.equ VS_ERROR, 3

.bss
.p2align 3
vd_slots: .zero VD_SIZE * VD_MAX
vd_line: .zero SB_SIZE
vd_err: .zero 256
vd_path: .zero 4100

.text

# ---------------- URIs ----------------

# FN uri_scheme_len(ptr, len) -> rax the scheme's length when the text is SCHEME:REST (SCHEME
# [a-z][a-z0-9+.-] 2 to 32 bytes, so "C:" stays a drive; REST 1 to 4095 bytes without LF, CR or
# NUL), else 0
FN uri_scheme_len
    xor eax, eax
    cmp rsi, 4
    jb 9f
    movzx ecx, byte ptr [rdi]
    sub ecx, 'a'
    cmp ecx, 25
    ja 9f
    mov eax, 1
1:  cmp rax, rsi
    jae 8f
    movzx ecx, byte ptr [rdi + rax]
    cmp ecx, ':'
    je 3f
    lea edx, [rcx - 'a']
    cmp edx, 25
    jbe 2f
    lea edx, [rcx - '0']
    cmp edx, 9
    jbe 2f
    cmp ecx, '+'
    je 2f
    cmp ecx, '.'
    je 2f
    cmp ecx, '-'
    jne 8f
2:  inc rax
    cmp rax, 32
    ja 8f
    jmp 1b
3:  cmp rax, 2
    jb 8f
    # the rest: 1 to 4095 bytes, no LF, CR or NUL
    mov rdx, rsi
    sub rdx, rax
    dec rdx
    jz 8f
    cmp rdx, 4095
    ja 8f
    lea rcx, [rax + 1]
4:  cmp rcx, rsi
    jae 9f
    movzx edx, byte ptr [rdi + rcx]
    inc rcx
    cmp edx, 10
    je 8f
    cmp edx, 13
    je 8f
    test edx, edx
    jz 8f
    jmp 4b
8:  xor eax, eax
9:  ret

# FN uri_file_path(ptr, len) -> rax the path of a file: URI (file:///p, file://localhost/p,
# file:///C:/p on Windows), percent-decoded, NUL-terminated in a buffer of this module (valid until
# the next call), rdx its length; 0 when it is not a file: URI or decodes to nothing usable
FN uri_file_path
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp r12, 8
    jb 8f
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + .Lfile_slashes]
    mov ecx, 7
    call str_starts
    test eax, eax
    jz 8f
    lea r13, [rbx + 7]          # after "file://"
    lea r14, [rbx + r12]
    mov rdi, r13
    mov rsi, r14
    sub rsi, r13
    lea rdx, [rip + .Llocalhost]
    mov ecx, 9
    call str_starts
    test eax, eax
    jz 1f
    add r13, 9
1:  cmp r13, r14
    jae 8f
    cmp byte ptr [r13], '/'
    jne 8f                      # a host: not a local file
.ifdef WINDOWS
    # /C:/p is C:/p
    lea rax, [r13 + 3]
    cmp rax, r14
    ja 11f
    cmp byte ptr [r13 + 2], ':'
    jne 11f
    inc r13
11:
.endif
    lea r15, [rip + vd_path]
    xor ebx, ebx                # bytes written
2:  cmp r13, r14
    jae 7f
    cmp rbx, 4096
    jae 8f
    movzx eax, byte ptr [r13]
    inc r13
    cmp eax, '%'
    jne 3f
    lea rcx, [r13 + 2]
    cmp rcx, r14
    ja 8f
    movzx edi, byte ptr [r13]
    call hex_val
    test eax, eax
    js 8f
    mov ecx, eax
    shl ecx, 4
    push rcx
    movzx edi, byte ptr [r13 + 1]
    call hex_val
    pop rcx
    test eax, eax
    js 8f
    or eax, ecx
    add r13, 2
    test eax, eax
    jz 8f                       # %00
3:  mov [r15 + rbx], al
    inc rbx
    jmp 2b
7:  mov byte ptr [r15 + rbx], 0
    mov rax, r15
    mov rdx, rbx
    EPILOGUE
8:  xor eax, eax
    xor edx, edx
    EPILOGUE

# hex_val(c) -> eax 0-15, or -1
hex_val:
    lea eax, [rdi - '0']
    cmp eax, 9
    jbe 9f
    or edi, 0x20
    lea eax, [rdi - 'a']
    cmp eax, 5
    ja 8f
    add eax, 10
    ret
8:  mov eax, -1
9:  ret

# FN uri_last_segment(uri cstr) -> rax its last segment: after the last "/", else after the
# scheme's ":" (what [subscribe] patterns and the title use)
FN uri_last_segment
    mov rax, rdi
    mov rcx, rdi
    xor edx, edx                # seen a ':'
1:  movzx r8d, byte ptr [rcx]
    test r8d, r8d
    jz 9f
    inc rcx
    cmp r8d, '/'
    je 2f
    cmp r8d, ':'
    jne 1b
    test edx, edx
    jnz 1b
    mov edx, 1
2:  mov rax, rcx
    jmp 1b
9:  ret

# scheme_reserved(ptr, len) -> eax 1 for a scheme no extension may provide
scheme_reserved:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea r13, [rip + reserved]
1:  mov rdx, [r13]
    test rdx, rdx
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call str_eq_cstr
    test eax, eax
    jnz 9f
    add r13, 8
    jmp 1b
8:  xor eax, eax
9:  EPILOGUE

# FN vdoc_provider(scheme ptr, len) -> rax the extension that provides the scheme (the first in
# owner/name order among those declaring it, not removed), or 0
FN vdoc_provider
    PROLOGUE 16
    mov r14, rdi
    mov r15, rsi
    xor ebx, ebx                # the best so far
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul r13, r12, EXT_SIZE
    add r13, [rip + g_exts + VEC_ptr]
    inc r12
    cmp dword ptr [r13 + EXT_status], ES_REMOVED
    je 1b
    mov rdi, r13
    call extres_row
    test rax, rax
    jz 1b
    mov rsi, [rax + EL_schemes]
    test rsi, rsi
    jz 1b
    # the scheme as a word of the list
    mov [rsp], rsi
    mov rdi, r14
    mov rsi, r15
    call mem_dup
    mov [rsp + 8], rax
    mov rdi, rax
    mov rsi, [rsp]
    call list_has_word
    push rax
    push rax
    mov rdi, [rsp + 24]
    call mem_free
    pop rax
    pop rax
    test eax, eax
    jz 1b
    test rbx, rbx
    jz 2f
    mov rdi, r13
    mov rsi, rbx
    call ext_name_before
    test eax, eax
    jz 1b
2:  mov rbx, r13
    jmp 1b
9:  mov rax, rbx
    EPILOGUE

# ext_name_before(a, b) -> eax 1 when a's owner/name sorts before b's
ext_name_before:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx + EXT_owner]
    mov rsi, [r12 + EXT_owner]
    call cstr_cmp
    test eax, eax
    jnz 1f
    mov rdi, [rbx + EXT_name]
    mov rsi, [r12 + EXT_name]
    call cstr_cmp
1:  shr eax, 31                 # negative: before
    EPILOGUE

# cstr_cmp(a, b) -> eax < 0, 0, > 0 by bytes
cstr_cmp:
1:  movzx eax, byte ptr [rdi]
    movzx ecx, byte ptr [rsi]
    sub eax, ecx
    jnz 9f
    test ecx, ecx
    jz 9f
    inc rdi
    inc rsi
    jmp 1b
9:  ret

# ---------------- the documents ----------------

# vd_of_doc(doc) -> rax its slot, or 0
vd_of_doc:
    lea rax, [rip + vd_slots]
    mov ecx, VD_MAX
1:  cmp [rax + VD_doc], rdi
    je 9f
    add rax, VD_SIZE
    dec ecx
    jnz 1b
    xor eax, eax
9:  ret

# vd_of_uri(ext, ptr, len) -> rax the slot of that provider's document for the URI, or 0
vd_of_uri:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea r14, [rip + vd_slots]
    mov r15d, VD_MAX
1:  mov rax, [r14 + VD_doc]
    test rax, rax
    jz 2f
    test rbx, rbx
    jz 3f
    cmp [r14 + VD_ext], rbx
    jne 2f
3:  mov rdi, r12
    mov rsi, r13
    mov rdx, [rax + DOC_uri]
    call str_eq_cstr
    test eax, eax
    jnz 8f
2:  add r14, VD_SIZE
    dec r15d
    jnz 1b
    xor eax, eax
    EPILOGUE
8:  mov rax, r14
    EPILOGUE

# tab_of_doc(doc) -> rax its tab index, or -1
tab_of_doc:
    xor ecx, ecx
1:  cmp rcx, [rip + g_tabs + VEC_len]
    jae 8f
    imul rax, rcx, TAB_SIZE
    add rax, [rip + g_tabs + VEC_ptr]
    cmp [rax + TAB_doc], rdi
    je 9f
    inc rcx
    jmp 1b
8:  mov rax, -1
    ret
9:  mov rax, rcx
    ret

# FN vdoc_open(requester ext, uri ptr, len, line, col) -> rax the DOC, or a negative error:
# -2 nofile (no provider, a reserved scheme), -27 toobig (too many open). The document opens in
# a tab at once and activates; its text follows the provider's answer.
FN vdoc_open
    PROLOGUE 32
    mov [rsp], rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov rdi, r12
    mov rsi, r13
    call uri_scheme_len
    test rax, rax
    jz .Lvo_nofile
    mov r14, rax
    mov rdi, r12
    mov rsi, r14
    call scheme_reserved
    test eax, eax
    jnz .Lvo_nofile
    mov rdi, r12
    mov rsi, r14
    call vdoc_provider
    test rax, rax
    jz .Lvo_nofile
    mov rbx, rax                # the provider
    # already open: its tab
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call vd_of_uri
    test rax, rax
    jz 1f
    mov r15, rax
    mov rdi, [r15 + VD_doc]
    call tab_of_doc
    test rax, rax
    js 0f
    mov rdi, rax
    call app_activate_tab
0:  mov rdi, [r15 + VD_doc]
    mov esi, [rsp + 8]
    mov edx, [rsp + 12]
    call vd_place_cursor
    mov rax, [r15 + VD_doc]
    EPILOGUE
1:  # room: VD_MAX in all, VD_PER_PROVIDER each
    xor ecx, ecx
    xor edx, edx
    xor r15d, r15d
    lea rax, [rip + vd_slots]
2:  cmp qword ptr [rax + VD_doc], 0
    jne 3f
    test r15, r15
    jnz 4f
    mov r15, rax
    jmp 4f
3:  cmp [rax + VD_ext], rbx
    jne 4f
    inc edx
4:  add rax, VD_SIZE
    inc ecx
    cmp ecx, VD_MAX
    jb 2b
    test r15, r15
    jz .Lvo_toobig
    cmp edx, VD_PER_PROVIDER
    jae .Lvo_toobig
    # the document: read-only, named by the URI's last segment until a title comes
    call doc_new
    mov r14, rax
    mov rdi, r12
    mov rsi, r13
    call mem_dup
    mov [r14 + DOC_uri], rax
    mov rdi, rax
    call uri_last_segment
    mov [r14 + DOC_name], rax
    or dword ptr [r14 + DOC_flags], DF_READONLY
    mov [r15 + VD_doc], r14
    mov [r15 + VD_ext], rbx
    mov qword ptr [r15 + VD_req], 0
    mov qword ptr [r15 + VD_title], 0
    mov eax, [rsp + 8]
    mov [r15 + VD_line], eax
    mov eax, [rsp + 12]
    mov [r15 + VD_col], eax
    mov dword ptr [r15 + VD_loaded], 0
    mov dword ptr [r15 + VD_state], VS_WAIT
    call time_ms
    mov [r15 + VD_since], rax
    mov rdi, r14
    lea rsi, [rip + .Lt_loading]
    mov edx, 10                 # "Loading…"
    call doc_replace_all
    mov rdi, r14
    call vd_detect_lang
    mov rdi, r14
    mov esi, TAB_DOC
    call app_add_tab
    mov rdi, r15
    call vd_ask
    mov dword ptr [rip + g_dirty], 1
    mov rax, r14
    EPILOGUE
.Lvo_nofile:
    mov rax, -2
    EPILOGUE
.Lvo_toobig:
    mov rax, -27
    EPILOGUE

# vd_detect_lang(doc): the grammar for the URI's last segment, as for a file of that name
vd_detect_lang:
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + DOC_uri]
    call uri_last_segment
    mov r12, rax
    mov rdi, rax
    call strlen
    mov rdi, r12
    mov rsi, rax
    call syntax_for_name
    test rax, rax
    jz 9f
    mov rdx, [rax + GR_name]
    mov rdi, rbx
    mov esi, DL_NAMED
    call doc_language_set
9:  EPILOGUE

# vd_ask(vd): the content request, once the provider runs (vdoc_tick starts it and waits)
vd_ask:
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + VD_ext]
    mov eax, [r12 + EXT_status]
    cmp eax, ES_RUNNING
    je 2f
    cmp eax, ES_IDLE
    je 1f
    cmp eax, ES_STARTING
    je 9f
    cmp eax, ES_STOPPED
    je 1f
    cmp eax, ES_CRASHED
    je 1f
    lea rsi, [rip + .Le_cannot_start]
    jmp .Lva_error
1:  # it starts; vdoc_tick asks once it said hello
    cmp eax, ES_IDLE
    je 11f
    mov rdi, r12
    call ext_restart
    jmp 12f
11: mov rdi, r12
    call ext_start
12: mov dword ptr [rbx + VD_state], VS_WAIT
    call time_ms
    mov [rbx + VD_since], rax
    jmp 9f
2:  mov rdi, r12
    mov esi, FEAT_URIS
    call ext_feature
    test eax, eax
    jnz 3f
    lea rsi, [rip + .Le_no_uris]
    jmp .Lva_error
3:  # "ID content URI"
    lea rdi, [rip + vd_line]
    call sb_clear
    lea rdi, [rip + vd_line]
    lea rsi, [rip + .Lcontent]
    call sb_push_cstr
    mov rax, [rbx + VD_doc]
    lea rdi, [rip + vd_line]
    mov rsi, [rax + DOC_uri]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [rip + vd_line + SB_ptr]
    mov rdx, [rip + vd_line + SB_len]
    call extproto_host_line
    test rax, rax
    jz .Lva_failed
    mov [rbx + VD_req], rax
    mov dword ptr [rbx + VD_state], VS_ASKED
    call time_ms
    mov [rbx + VD_since], rax
9:  EPILOGUE
.Lva_failed:
    lea rsi, [rip + .Le_send]
.Lva_error:
    mov rdi, rbx
    call vd_error
    EPILOGUE

# vd_error(vd, reason cstr): the document says why it has no text; Reload File asks again
vd_error:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov dword ptr [rbx + VD_state], VS_ERROR
    mov qword ptr [rbx + VD_req], 0
    lea rdi, [rip + vd_line]
    call sb_clear
    lea rdi, [rip + vd_line]
    lea rsi, [rip + .Lt_no_text]
    call sb_push_cstr
    mov rdi, [rbx + VD_ext]
    call ext_full_name
    lea rdi, [rip + vd_line]
    mov rsi, rax
    call sb_push_cstr
    lea rdi, [rip + vd_line]
    lea rsi, [rip + .Lt_colon]
    call sb_push_cstr
    lea rdi, [rip + vd_line]
    mov rsi, r12
    call sb_push_cstr
    lea rdi, [rip + vd_line]
    lea rsi, [rip + .Lt_retry]
    call sb_push_cstr
    mov rdi, [rbx + VD_doc]
    mov rsi, [rip + vd_line + SB_ptr]
    mov rdx, [rip + vd_line + SB_len]
    call doc_replace_all
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# vd_place_cursor(doc, line, col): one-based; 0 0 keeps it
vd_place_cursor:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    test r12d, r12d
    jz 9f
    cmp r12, [rbx + DOC_nlines]
    jbe 1f
    mov r12, [rbx + DOC_nlines]
    mov r13d, 0x7fffffff
1:  lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_line_start
    mov r14, rax
    lea rsi, [r12 - 1]
    mov rdi, rbx
    call doc_line_end
    sub rax, r14
    lea rcx, [r13 - 1]
    test r13d, r13d
    jz 2f
    cmp rcx, rax
    jbe 3f
2:  mov rcx, rax
3:  lea rsi, [r14 + rcx]
    mov rdi, rbx
    xor edx, edx
    call ed_set_cursor
9:  EPILOGUE

# FN vdoc_reply(ext, id, ok, body ptr, len) -> eax 1 when it answered a content request: the
# text goes in (LANG_LEN TITLE_LEN TEXT_LEN LF, the three, then extra records it skips), or the
# error shows
FN vdoc_reply
    PROLOGUE 32
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], edx
    mov r13, rcx
    mov r14, r8
    test r12, r12
    jz 8f
    lea r15, [rip + vd_slots]
    mov ecx, VD_MAX
1:  cmp qword ptr [r15 + VD_doc], 0
    je 2f
    cmp [r15 + VD_req], r12
    jne 2f
    cmp [r15 + VD_ext], rbx
    je 3f
2:  add r15, VD_SIZE
    dec ecx
    jnz 1b
8:  xor eax, eax
    EPILOGUE
3:  mov qword ptr [r15 + VD_req], 0
    cmp dword ptr [rsp], 0
    jne 4f
    # error ID CODE TEXT: the code and text (r13, r14)
    lea rdi, [rip + vd_err]
    xor esi, esi
    mov edx, 256
    call memset
    mov rdx, r14
    cmp rdx, 200
    jbe 31f
    mov edx, 200
31: lea rdi, [rip + vd_err]
    mov rsi, r13
    test rsi, rsi
    jz 32f
    call memcpy
32: mov rdi, r15
    lea rsi, [rip + vd_err]
    call vd_error
    jmp 9f
4:  # the header line
    xor ecx, ecx
41: cmp rcx, r14
    jae .Lvr_bad
    cmp byte ptr [r13 + rcx], 10
    je 42f
    inc rcx
    jmp 41b
42: lea rax, [rcx + 1]
    mov [rsp + 8], rax          # the bytes after the header
    # three numbers
    mov rdi, r13
    mov rsi, rcx
    call next_word
    mov [rsp + 16], rcx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov [rsp + 24], rax         # LANG_LEN
    mov rdi, r13
    add rdi, [rsp + 16]
    mov rsi, [rsp + 8]
    sub rsi, [rsp + 16]
    call next_word
    add [rsp + 16], rcx
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov r12, rax                # TITLE_LEN
    mov rdi, r13
    add rdi, [rsp + 16]
    mov rsi, [rsp + 8]
    sub rsi, [rsp + 16]
    call next_word
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov rbx, rax                # TEXT_LEN
    # they fit the body, the text within its cap
    mov rax, [rsp + 24]
    cmp rax, 255
    ja .Lvr_bad
    cmp r12, 255
    ja .Lvr_bad
    cmp rbx, VD_TEXT_MAX
    ja .Lvr_big
    mov rax, [rsp + 8]
    add rax, [rsp + 24]
    add rax, r12
    add rax, rbx
    cmp rax, r14
    ja .Lvr_bad
    mov rdi, r13
    add rdi, [rsp + 8]
    add rdi, [rsp + 24]
    add rdi, r12
    mov rsi, rbx
    mov [rsp + 16], rdi         # the text
    call snippet_utf8_valid
    test eax, eax
    jz .Lvr_utf8
    # the title
    test r12, r12
    jz 5f
    mov rdi, r13
    add rdi, [rsp + 8]
    add rdi, [rsp + 24]
    mov rsi, r12
    call mem_dup
    mov rdi, [r15 + VD_title]
    mov [r15 + VD_title], rax
    mov rcx, [r15 + VD_doc]
    mov [rcx + DOC_name], rax
    call mem_free
5:  # the language, as a grammar name with spaces as "_"
    mov rcx, [rsp + 24]
    test rcx, rcx
    jz 6f
    mov rdi, r13
    add rdi, [rsp + 8]
    mov rsi, rcx
    call mem_dup
    mov r12, rax
    mov rcx, rax
51: cmp byte ptr [rcx], 0
    je 52f
    cmp byte ptr [rcx], '_'
    jne 53f
    mov byte ptr [rcx], ' '
53: inc rcx
    jmp 51b
52: mov rdi, [r15 + VD_doc]
    mov esi, DL_NAMED
    mov rdx, r12
    call doc_language_set
    mov rdi, r12
    call mem_free
6:  # the text: a first load puts the cursor where open asked; a reload keeps cursor and scroll
    mov r12, [r15 + VD_doc]
    mov r13, [r12 + DOC_cur]
    mov r14, [r12 + DOC_scrolly]
    mov rdi, r12
    mov rsi, [rsp + 16]
    mov rdx, rbx
    call doc_replace_all
    cmp dword ptr [r15 + VD_loaded], 0
    je 7f
    mov rdi, r12
    call doc_len
    cmp r13, rax
    cmova r13, rax
    mov [r12 + DOC_cur], r13
    mov [r12 + DOC_anchor], r13
    mov [r12 + DOC_scrolly], r14
    jmp 71f
7:  mov qword ptr [r12 + DOC_cur], 0
    mov qword ptr [r12 + DOC_anchor], 0
    mov qword ptr [r12 + DOC_scrolly], 0
    mov rdi, r12
    mov esi, [r15 + VD_line]
    mov edx, [r15 + VD_col]
    call vd_place_cursor
71: mov dword ptr [r15 + VD_loaded], 1
    mov dword ptr [r15 + VD_state], VS_LOADED
    mov dword ptr [rip + g_dirty], 1
9:  mov eax, 1
    EPILOGUE
.Lvr_bad:
    lea rsi, [rip + .Le_bad]
    jmp .Lvr_error
.Lvr_big:
    lea rsi, [rip + .Le_big]
    jmp .Lvr_error
.Lvr_utf8:
    lea rsi, [rip + .Le_utf8]
.Lvr_error:
    mov rdi, r15
    call vd_error
    mov eax, 1
    EPILOGUE

# FN vdoc_changed(ext, uri ptr, len) -> eax 1 when the extension provides an open document for the
# URI: it is asked again (content-changed)
FN vdoc_changed
    PROLOGUE
    call vd_of_uri
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp qword ptr [rbx + VD_req], 0
    jne 9f                      # an answer is coming; it is the new text or near enough
    mov rdi, rbx
    call vd_ask
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN vdoc_retry(doc) -> eax 1 for a virtual document: its provider is asked again (Reload File)
FN vdoc_retry
    PROLOGUE
    call vd_of_doc
    test rax, rax
    jz 8f
    mov rbx, rax
    cmp qword ptr [rbx + VD_req], 0
    jne 9f
    mov rdi, rbx
    call vd_ask
9:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# FN vdoc_doc_freed(doc): its tab closed (doc_free): the provider hears content-closed, the URI and
# title go
FN vdoc_doc_freed
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + DOC_uri], 0
    je 9f
    mov rdi, rbx
    call vd_of_doc
    test rax, rax
    jz 8f
    mov r12, rax
    mov r13, [r12 + VD_ext]
    mov rsi, [r12 + VD_req]
    test rsi, rsi
    jz 1f
    cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 1f
    mov rdi, r13
    call extproto_send_cancel
1:  cmp dword ptr [r13 + EXT_status], ES_RUNNING
    jne 2f
    mov rdi, r13
    mov esi, FEAT_URIS
    call ext_feature
    test eax, eax
    jz 2f
    mov rdi, r13
    mov rsi, [rbx + DOC_uri]
    call extproto_content_closed
2:  mov rdi, [r12 + VD_title]
    call mem_free
    mov qword ptr [r12 + VD_doc], 0
    mov qword ptr [r12 + VD_title], 0
8:  mov rdi, [rbx + DOC_uri]
    call mem_free
    mov qword ptr [rbx + DOC_uri], 0
9:  EPILOGUE

# FN vdoc_ext_gone(ext): the provider was removed or turned off: its documents close
FN vdoc_ext_gone
    PROLOGUE
    mov rbx, rdi
    lea r12, [rip + vd_slots]
    mov r13d, VD_MAX
1:  mov rdi, [r12 + VD_doc]
    test rdi, rdi
    jz 2f
    cmp [r12 + VD_ext], rbx
    jne 2f
    call tab_of_doc
    test rax, rax
    js 2f
    mov rdi, rax
    call app_close_tab_now
2:  add r12, VD_SIZE
    dec r13d
    jnz 1b
    EPILOGUE

# FN vdoc_ext_exited(ext): its program is gone: an answer it owed will not come
FN vdoc_ext_exited
    PROLOGUE
    mov rbx, rdi
    lea r12, [rip + vd_slots]
    mov r13d, VD_MAX
1:  cmp qword ptr [r12 + VD_doc], 0
    je 2f
    cmp [r12 + VD_ext], rbx
    jne 2f
    cmp dword ptr [r12 + VD_state], VS_ASKED
    jne 2f
    mov rdi, r12
    lea rsi, [rip + .Le_stopped]
    call vd_error
2:  add r12, VD_SIZE
    dec r13d
    jnz 1b
    EPILOGUE

# FN vdoc_tick(): providers that started are asked; waits past VD_WAIT_MS end in an error
FN vdoc_tick
    PROLOGUE
    call time_ms
    mov r14, rax
    lea r12, [rip + vd_slots]
    mov r13d, VD_MAX
1:  cmp qword ptr [r12 + VD_doc], 0
    je 4f
    mov eax, [r12 + VD_state]
    cmp eax, VS_WAIT
    je 2f
    cmp eax, VS_ASKED
    jne 4f
    mov rax, r14
    sub rax, [r12 + VD_since]
    cmp rax, VD_WAIT_MS
    jb 4f
    mov rbx, [r12 + VD_ext]
    mov rsi, [r12 + VD_req]
    mov rdi, rbx
    call extproto_send_cancel
    mov rdi, r12
    lea rsi, [rip + .Le_timeout]
    call vd_error
    jmp 4f
2:  mov rbx, [r12 + VD_ext]
    mov eax, [rbx + EXT_status]
    cmp eax, ES_RUNNING
    je 3f
    mov rax, r14
    sub rax, [r12 + VD_since]
    cmp rax, VD_WAIT_MS
    jb 31f
    mov rdi, r12
    lea rsi, [rip + .Le_timeout]
    call vd_error
    jmp 4f
31: mov eax, [rbx + EXT_status]
    cmp eax, ES_STARTING
    je 4f
    cmp eax, ES_IDLE
    je 4f
    mov rdi, r12
    lea rsi, [rip + .Le_cannot_start]
    call vd_error
    jmp 4f
3:  mov rdi, r12
    call vd_ask
4:  add r12, VD_SIZE
    dec r13d
    jnz 1b
    EPILOGUE

# FN vdoc_waiting() -> eax 1 while a virtual document waits (the loop comes back for it)
FN vdoc_waiting
    lea rax, [rip + vd_slots]
    mov ecx, VD_MAX
1:  cmp qword ptr [rax + VD_doc], 0
    je 2f
    cmp dword ptr [rax + VD_state], VS_WAIT
    je 8f
    cmp dword ptr [rax + VD_state], VS_ASKED
    je 8f
2:  add rax, VD_SIZE
    dec ecx
    jnz 1b
    xor eax, eax
    ret
8:  mov eax, 1
    ret

# FN vdoc_dump(sb): print-vdocs: "vdoc doc=ID uri=URI provider=OWNER/NAME state=S name=N" per line
FN vdoc_dump
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + vd_slots]
    mov r13d, VD_MAX
1:  mov r14, [rbx + VD_doc]
    test r14, r14
    jz 2f
    mov rdi, r12
    lea rsi, [rip + .Ld_doc]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + DOC_id]
    call sb_push_u64
    mov rdi, r12
    lea rsi, [rip + .Ld_uri]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + DOC_uri]
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_provider]
    call sb_push_cstr
    mov rdi, [rbx + VD_ext]
    call ext_full_name
    mov rdi, r12
    mov rsi, rax
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_state]
    call sb_push_cstr
    mov eax, [rbx + VD_state]
    lea rcx, [rip + state_words]
    mov rsi, [rcx + rax*8]
    mov rdi, r12
    call sb_push_cstr
    mov rdi, r12
    lea rsi, [rip + .Ld_name]
    call sb_push_cstr
    mov rdi, r12
    mov rsi, [r14 + DOC_name]
    call sb_push_cstr
    mov rdi, r12
    mov esi, 10
    call sb_push_byte
2:  add rbx, VD_SIZE
    dec r13d
    jnz 1b
    EPILOGUE

# c_print_vdocs(out, args, len)
FN c_print_vdocs
    push rbx
    call vdoc_dump
    xor eax, eax
    pop rbx
    ret

.section .rodata
.p2align 3
reserved: .quad .Ls_file, .Ls_untitled, .Ls_rhun, .Ls_http, .Ls_https, .Ls_mailto, .Ls_data
    .quad .Ls_git, .Ls_remote, 0
state_words: .quad .Lw_wait, .Lw_asked, .Lw_loaded, .Lw_error
.Ls_file: .asciz "file"
.Ls_untitled: .asciz "untitled"
.Ls_rhun: .asciz "rhun"
.Ls_http: .asciz "http"
.Ls_https: .asciz "https"
.Ls_mailto: .asciz "mailto"
.Ls_data: .asciz "data"
.Ls_git: .asciz "git"
.Ls_remote: .asciz "remote"
.Lw_wait: .asciz "starting"
.Lw_asked: .asciz "loading"
.Lw_loaded: .asciz "loaded"
.Lw_error: .asciz "error"
.Lfile_slashes: .asciz "file://"
.Llocalhost: .asciz "localhost"
.Lcontent: .asciz "content "
.Lt_loading: .ascii "Loading\xe2\x80\xa6"
.Lt_no_text: .asciz "This document could not be read from "
.Lt_colon: .asciz ": "
.Lt_retry: .asciz ".\nReload File asks again.\n"
.Le_cannot_start: .asciz "the extension is not running"
.Le_no_uris: .asciz "the extension does not provide documents (it did not agree uris)"
.Le_send: .asciz "the request could not be sent"
.Le_timeout: .asciz "no answer within 5 seconds"
.Le_stopped: .asciz "the extension stopped"
.Le_bad: .asciz "the answer is not a document (LANG_LEN TITLE_LEN TEXT_LEN)"
.Le_big: .asciz "the text is over 4 MiB"
.Le_utf8: .asciz "the text is not UTF-8"
.Ld_doc: .asciz "vdoc doc="
.Ld_uri: .asciz " uri="
.Ld_provider: .asciz " provider="
.Ld_state: .asciz " state="
.Ld_name: .asciz " name="
