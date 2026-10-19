# Included in extproto.s: access its bounded parsed fields and reply builders.
.text
h_watch_workspace:
    PROLOGUE
    cmp qword ptr [rip + nfields], 2
    jne .Lewp_bad
    mov rdi, [rip + cur]
    FEAT_TEST rdi, FEAT_WORKSPACE_WATCH
    jz .Lewp_feature_failed
    call extwatch_add
    test rax, rax
    js .Lewp_failed
    mov rsi, rax
    mov rdi, [rip + cur_id]
    call reply_ok_u64
    EPILOGUE
.Lewp_failed:
    lea rsi, [rip + .Lewp_unavailable]
    cmp rax, -2
    jne 1f
    lea rsi, [rip + .Lewp_no_project]
1:  cmp rax, -28
    jne 2f
    lea rsi, [rip + .Lewp_limit]
2:  cmp rax, -12
    jne 3f
    lea rsi, [rip + .Lewp_memory]
3:  mov rdi, [rip + cur_id]
    call reply_error
    EPILOGUE
.Lewp_feature_failed:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lewp_feature_error]
    call reply_error
    EPILOGUE
.Lewp_bad:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lewp_syntax]
    call reply_error
    EPILOGUE
h_unwatch_workspace:
    PROLOGUE
    cmp qword ptr [rip + nfields], 3
    jne .Lewp_bad
    mov edi, 2
    call field_u64
    test edx, edx
    jz .Lewp_bad
    test rax, rax
    jz .Lewp_bad
    mov rsi, rax
    mov rdi, [rip + cur]
    call extwatch_remove
    test eax, eax
    jz .Lewp_missing
    mov rdi, [rip + cur_id]
    call reply_ok
    EPILOGUE
.Lewp_missing:
    mov rdi, [rip + cur_id]
    lea rsi, [rip + .Lewp_unknown]
    call reply_error
    EPILOGUE

# extproto_watch_event(ext, handle, rescan): one bounded invalidation line.
FN extproto_watch_event
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ext_has_metadata
    test eax, eax
    jz 9f
    cmp dword ptr [rbx + EXT_status], ES_RUNNING
    jne 9f
    mov [rip + cur], rbx
    call out_begin
    lea rdi, [rip + .Lewp_event]
    call out_cstr
    mov rdi, r12
    call out_u64
    lea rdi, [rip + .Lewp_changed]
    test r13, r13
    jz 1f
    lea rdi, [rip + .Lewp_rescan]
1:  call out_cstr
    mov edi, 10
    call out_byte
    call out_end
9:  EPILOGUE
.section .rodata
.Lewp_event: .asciz "0 watch "
.Lewp_changed: .asciz " changed"
.Lewp_rescan: .asciz " rescan"
.Lewp_unavailable: .asciz "needs project read permission for workspace watch"
.Lewp_feature_error: .asciz "unknown workspace_watch feature was not agreed"
.Lewp_no_project: .asciz "nofile workspace watch needs a workspace"
.Lewp_limit: .asciz "toobig workspace watch limit reached"
.Lewp_memory: .asciz "busy cannot allocate workspace watch"
.Lewp_unknown: .asciz "unknown workspace watch"
.Lewp_syntax: .asciz "syntax invalid workspace watch request"
.text
