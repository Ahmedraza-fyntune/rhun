# testing: the commands (Run All Tests, Re-run Failed Tests, Run Test at Cursor ...), the selected
# item, and the headless controls that drive and print the test model (control.s calls the
# testctl_* functions with its output buffer and the command's arguments).
.include "rhun.inc"

.bss
.p2align 3
.globl g_tv_ext, g_tv_item
g_tv_ext: .quad 0               # the selected item: its controller's EXT (0: none), index, gen
g_tv_item: .quad 0
g_tv_gen: .quad 0
ids: .zero SB_SIZE              # ids collected for a run
nids: .quad 0
cur_line: .quad 0               # Run at Cursor: the cursor, one-based
cur_col: .quad 0
best_depth: .quad 0
best_item: .quad 0
cur_path: .quad 0

.text

# testview_forget(ext): the extension's tests are gone: nothing of it stays selected
FN testview_forget
    cmp [rip + g_tv_ext], rdi
    jne 1f
    mov qword ptr [rip + g_tv_ext], 0
1:  ret

# testview_selected() -> rax TSC*, rdx index of the selected item, rax 0 when nothing (still) is
FN testview_selected
    push rbx
    mov rdi, [rip + g_tv_ext]
    test rdi, rdi
    jz 8f
    call testmodel_ctrl
    test rax, rax
    jz 8f
    mov rbx, rax
    mov rdi, rax
    mov rsi, [rip + g_tv_item]
    mov rdx, [rip + g_tv_gen]
    call testmodel_live
    test eax, eax
    jz 8f
    mov rax, rbx
    mov rdx, [rip + g_tv_item]
    pop rbx
    ret
8:  xor eax, eax
    xor edx, edx
    pop rbx
    ret

# testview_select(tsc, index): that item is the selected one
FN testview_select
    push rbx
    mov rbx, rdi
    mov rax, [rdi + TSC_ext]
    mov [rip + g_tv_ext], rax
    mov [rip + g_tv_item], rsi
    call testmodel_item
    mov eax, [rax + TSI_gen]
    mov [rip + g_tv_gen], rax
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# testing_sync(): every extension that declares [provides] tests has its controller row, and an
#   idle one starts (its roots come once it agreed tests)
FN testing_sync
    PROLOGUE
    xor r12d, r12d
1:  cmp r12, [rip + g_exts + VEC_len]
    jae 9f
    imul rbx, r12, EXT_SIZE
    add rbx, [rip + g_exts + VEC_ptr]
    inc r12
    cmp qword ptr [rbx + EXT_pv_tests], 0
    je 1b
    cmp dword ptr [rbx + EXT_manifest_ok], 0
    je 1b
    cmp dword ptr [rbx + EXT_status], ES_REMOVED
    je 1b
    cmp dword ptr [rbx + EXT_status], ES_DISABLED
    je 1b
    mov rdi, rbx
    call testmodel_ctrl_make
    cmp dword ptr [rbx + EXT_status], ES_IDLE
    jne 1b
    mov rdi, rbx
    call ext_start
    jmp 1b
9:  EPILOGUE

# ---------------- running ----------------

# run_ctrl(tsc, profile): one run of everything the controller has (when it offers the profile)
run_ctrl:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov rdi, [rbx + TSC_ext]
    call offers
    test eax, eax
    jz 9f
    mov rdi, [rbx + TSC_ext]
    mov esi, r12d
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call testproto_run
9:  EPILOGUE

# offers(ext, profile) -> eax 1 when the controller offers that run kind; else a toast says so
offers:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    call testproto_profiles
    bt eax, r12d
    jc 7f
    lea rdi, [rip + .Lm_no_profile]
    call app_toast
    xor eax, eax
    EPILOGUE
7:  mov eax, 1
    EPILOGUE

# run_all(profile): one run per controller
run_all:
    PROLOGUE
    mov r13d, edi
    call testing_sync
    lea rbx, [rip + g_ts_ctrls]
    xor r12d, r12d
1:  cmp qword ptr [rbx + TSC_ext], 0
    je 2f
    mov rdi, rbx
    mov esi, r13d
    call run_ctrl
2:  add rbx, TSC_SIZE
    inc r12d
    cmp r12d, TS_CTRL_MAX
    jb 1b
    EPILOGUE

# ids_begin(), ids_add(tsc, index): the list of ids a run asks for
ids_begin:
    lea rdi, [rip + ids]
    mov qword ptr [rip + nids], 0
    jmp sb_clear
ids_add:
    push rbx
    call testmodel_item
    mov rbx, rax
    lea rdi, [rip + ids]
    mov rsi, [rbx + TSI_id]
    mov edx, [rbx + TSI_idlen]
    call sb_push
    lea rdi, [rip + ids]
    mov esi, 10
    call sb_push_byte
    inc qword ptr [rip + nids]
    pop rbx
    ret

# run_ids(ext, profile): a run of the collected ids, when there are any
run_ids:
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    cmp qword ptr [rip + nids], 0
    je 9f
    mov rdi, rbx
    mov esi, r12d
    call offers
    test eax, eax
    jz 9f
    mov rdi, rbx
    mov esi, r12d
    mov rdx, [rip + ids + SB_ptr]
    mov rcx, [rip + ids + SB_len]
    mov r8, [rip + nids]
    call testproto_run
9:  EPILOGUE

# testview_run_item(tsc, index, profile): a run of that item (its controller's row: everything)
FN testview_run_item
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    test r12, r12
    jnz 1f
    mov rdi, rbx
    mov esi, r13d
    call run_ctrl
    EPILOGUE
1:  call ids_begin
    mov rdi, rbx
    mov rsi, r12
    call ids_add
    mov rdi, [rbx + TSC_ext]
    mov esi, r13d
    call run_ids
    EPILOGUE

FN cmd_test_run_all
    xor edi, edi
    jmp run_all

FN cmd_test_coverage_all
    mov edi, TSP_COVERAGE
    jmp run_all

# cmd_test_rerun_failed: the failed and errored leaves, a run per controller
FN cmd_test_rerun_failed
    PROLOGUE
    lea rbx, [rip + g_ts_ctrls]
    xor r12d, r12d
1:  cmp qword ptr [rbx + TSC_ext], 0
    je 4f
    call ids_begin
    mov r13d, 1
2:  cmp r13, [rbx + TSC_items + VEC_len]
    jae 3f
    mov rdi, rbx
    mov rsi, r13
    call testmodel_item
    cmp qword ptr [rax + TSI_id], 0
    je 21f
    mov ecx, [rax + TSI_own]
    cmp ecx, TSS_FAILED
    je 20f
    cmp ecx, TSS_ERRORED
    jne 21f
20: mov rdi, rbx
    mov rsi, r13
    call testmodel_leaf
    test eax, eax
    jz 21f
    mov rdi, rbx
    mov rsi, r13
    call ids_add
21: inc r13
    jmp 2b
3:  mov rdi, [rbx + TSC_ext]
    xor esi, esi
    call run_ids
4:  add rbx, TSC_SIZE
    inc r12d
    cmp r12d, TS_CTRL_MAX
    jb 1b
    EPILOGUE

# cmd_test_rerun_last: the newest run again (its controller, kind and items)
FN cmd_test_rerun_last
    PROLOGUE
    lea rcx, [rip + g_ts_runs]
    xor edx, edx
    xor ebx, ebx
1:  cmp qword ptr [rcx + TSR_ext], 0
    je 2f
    test rbx, rbx
    jz 11f
    mov rax, [rcx + TSR_num]
    cmp rax, [rbx + TSR_num]
    jbe 2f
11: mov rbx, rcx
2:  add rcx, TSR_SIZE
    inc edx
    cmp edx, TS_RUNS_MAX
    jb 1b
    test rbx, rbx
    jz 9f
    # copied first: a new run may take the old one's slot
    lea rdi, [rip + ids]
    call sb_clear
    lea rdi, [rip + ids]
    mov rsi, [rbx + TSR_ids + SB_ptr]
    mov rdx, [rbx + TSR_ids + SB_len]
    call sb_push
    mov eax, [rbx + TSR_nids]
    mov [rip + nids], rax
    mov rdi, [rbx + TSR_ext]
    mov esi, [rbx + TSR_profile]
    mov rdx, [rip + ids + SB_ptr]
    mov rcx, [rip + ids + SB_len]
    mov r8, [rip + nids]
    call testproto_run
9:  EPILOGUE

# cmd_test_cancel: every queued or running run is cancelled
FN cmd_test_cancel
    PROLOGUE
    lea rbx, [rip + g_ts_runs]
    xor r12d, r12d
1:  cmp qword ptr [rbx + TSR_ext], 0
    je 2f
    mov rdi, rbx
    call testproto_cancel
2:  add rbx, TSR_SIZE
    inc r12d
    cmp r12d, TS_RUNS_MAX
    jb 1b
    EPILOGUE

# cmd_test_run_file: the active file's items (not those whose ancestor is in it too)
FN cmd_test_run_file
    xor edi, edi
    xor esi, esi
    jmp run_doc

# cmd_test_run_cursor, cmd_test_debug_cursor: the deepest item whose range holds the cursor, else
#   the file's items
FN cmd_test_run_cursor
    mov edi, 1
    xor esi, esi
    jmp run_doc

FN cmd_test_debug_cursor
    mov edi, 1
    mov esi, TSP_DEBUG
    jmp run_doc

# run_doc(at cursor, profile): a run per controller of the active document's items
run_doc:
    PROLOGUE
    mov r14d, edi
    mov r15d, esi
    call testing_sync
    mov rbx, [rip + g_doc]
    test rbx, rbx
    jz 9f
    mov rax, [rbx + DOC_path]
    test rax, rax
    jz 9f
    mov [rip + cur_path], rax
    mov rdi, rbx
    mov rsi, [rbx + DOC_cur]
    call doc_line_of
    mov r12, rax
    lea rcx, [rax + 1]
    mov [rip + cur_line], rcx
    mov rdi, rbx
    mov rsi, r12
    call doc_line_start
    mov rcx, [rbx + DOC_cur]
    sub rcx, rax
    inc rcx
    mov [rip + cur_col], rcx
    lea rbx, [rip + g_ts_ctrls]
    xor r12d, r12d
1:  cmp qword ptr [rbx + TSC_ext], 0
    je 8f
    call ids_begin
    test r14d, r14d
    jz 3f
    # at the cursor: the deepest item holding it
    mov qword ptr [rip + best_item], 0
    mov qword ptr [rip + best_depth], 0
    mov r13d, 1
2:  cmp r13, [rbx + TSC_items + VEC_len]
    jae 21f
    mov rdi, rbx
    mov rsi, r13
    call holds_cursor
    test rax, rax
    jz 20f
    cmp rax, [rip + best_depth]
    jbe 20f
    mov [rip + best_depth], rax
    mov [rip + best_item], r13
20: inc r13
    jmp 2b
21: mov rsi, [rip + best_item]
    test rsi, rsi
    jz 3f
    mov rdi, rbx
    call ids_add
    jmp 7f
3:  # the file's items: in the file, with no ancestor in it
    mov r13d, 1
4:  cmp r13, [rbx + TSC_items + VEC_len]
    jae 7f
    mov rdi, rbx
    mov rsi, r13
    call in_file
    test eax, eax
    jz 6f
    mov rdi, rbx
    mov rsi, r13
    call testmodel_item
    movsxd r8, dword ptr [rax + TSI_parent]
5:  test r8, r8
    jle 51f
    mov rdi, rbx
    mov rsi, r8
    push r8
    push r8
    call in_file
    pop r8
    pop r8
    test eax, eax
    jnz 6f
    mov rdi, rbx
    mov rsi, r8
    call testmodel_item
    movsxd r8, dword ptr [rax + TSI_parent]
    jmp 5b
51: mov rdi, rbx
    mov rsi, r13
    call ids_add
6:  inc r13
    jmp 4b
7:  mov rdi, [rbx + TSC_ext]
    mov esi, r15d
    call run_ids
8:  add rbx, TSC_SIZE
    inc r12d
    cmp r12d, TS_CTRL_MAX
    jb 1b
9:  EPILOGUE

# in_file(tsc, index) -> eax 1 for a live item whose file is the active document's
in_file:
    push rbx
    call testmodel_item
    cmp qword ptr [rax + TSI_id], 0
    je 8f
    mov rdi, [rax + TSI_path]
    test rdi, rdi
    jz 8f
    mov rsi, [rip + cur_path]
    call strcmp_eq
    pop rbx
    ret
8:  xor eax, eax
    pop rbx
    ret

# holds_cursor(tsc, index) -> rax the item's depth (1 for a root) when it is in the active file and
#   its range holds the cursor, else 0
holds_cursor:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call in_file
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov rsi, r12
    call testmodel_item
    mov r13, rax
    mov ecx, [r13 + TSI_l1]
    test ecx, ecx
    jz 8f
    mov rax, [rip + cur_line]
    cmp rax, rcx
    jb 8f
    ja 1f
    mov ecx, [r13 + TSI_c1]
    cmp [rip + cur_col], rcx
    jb 8f
1:  mov ecx, [r13 + TSI_l2]
    cmp rax, rcx
    ja 8f
    jb 2f
    mov ecx, [r13 + TSI_c2]
    cmp [rip + cur_col], rcx
    ja 8f
2:  xor r14d, r14d
    mov r15, r12
3:  test r15, r15
    jle 4f
    inc r14
    mov rdi, rbx
    mov rsi, r15
    call testmodel_item
    movsxd r15, dword ptr [rax + TSI_parent]
    jmp 3b
4:  mov rax, r14
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# ---------------- headless controls ----------------

# item_arg(rest, len) -> rax TSC*, rdx index for "OWNER/NAME ID" (no ID: the controller's row), or
#   rax 0
item_arg:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, r12
    call next_word
    test rdx, rdx
    jz 8f
    add rbx, rcx
    sub r12, rcx
    mov rdi, rax
    mov rsi, rdx
    call ext_by_name
    test rax, rax
    jz 8f
    mov rdi, rax
    call testmodel_ctrl
    test rax, rax
    jz 8f
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    call trim
    test rdx, rdx
    jz 7f
    mov rdi, r13
    mov rsi, rax
    call testmodel_find
    test rax, rax
    js 8f
    mov rdx, rax
    mov rax, r13
    EPILOGUE
7:  mov rax, r13
    xor edx, edx
    EPILOGUE
8:  xor eax, eax
    EPILOGUE

# testctl_select(sb, rest, len): test-select OWNER/NAME [ID]
FN testctl_select
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call item_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    call testview_select
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lm_no_item]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# testctl_expand(sb, rest, len, open): test-expand / test-collapse OWNER/NAME [ID]; expanding a lazy
#   item asks its controller for its children
FN testctl_expand
    PROLOGUE
    mov rbx, rdi
    mov r15d, ecx
    mov rdi, rsi
    mov rsi, rdx
    call item_arg
    test rax, rax
    jz 8f
    mov rdi, rax
    mov rsi, rdx
    mov edx, r15d
    call testview_expand
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lm_no_item]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# testview_expand(tsc, index, open): the item shows its children (or not); a lazy one is resolved
FN testview_expand
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call testmodel_item
    and dword ptr [rax + TSI_flags], ~TSF_EXPANDED
    test r13d, r13d
    jz 9f
    or dword ptr [rax + TSI_flags], TSF_EXPANDED
    test dword ptr [rax + TSI_flags], TSF_LAZY
    jz 9f
    mov rdi, [rbx + TSC_ext]
    mov rsi, rbx
    mov rdx, r12
    call testproto_resolve
9:  mov dword ptr [rip + g_ts_dirty], 1
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# testctl_action(sb, rest, len): test-action run|debug|coverage|cancel on the selected item
FN testctl_action
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call testview_selected
    test rax, rax
    jz 8f
    mov r14, rax
    mov r15, rdx
    mov rdi, r12
    mov rsi, r13
    call trim
    mov r12, rax
    mov r13, rdx
    xor ecx, ecx
1:  lea rax, [rip + ts_profile_words]
    mov rdx, [rax + rcx*8]
    test rdx, rdx
    jz 2f
    push rcx
    push rcx
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    pop rcx
    pop rcx
    test eax, eax
    jnz 11f
    inc ecx
    jmp 1b
11: mov rdi, r14
    mov rsi, r15
    mov edx, ecx
    call testview_run_item
    xor eax, eax
    EPILOGUE
2:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + .La_cancel]
    call str_eq_cstr
    test eax, eax
    jz 3f
    mov rdi, [r14 + TSC_ext]
    call cancel_ext
    xor eax, eax
    EPILOGUE
3:  mov rdi, r14
    mov rsi, r15
    mov rdx, r12
    mov rcx, r13
    call testview_action        # the view's (goto, diff, output)
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lm_no_item]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# cancel_ext(ext): its runs are cancelled
cancel_ext:
    PROLOGUE
    mov r13, rdi
    lea rbx, [rip + g_ts_runs]
    xor r12d, r12d
1:  cmp [rbx + TSR_ext], r13
    jne 2f
    mov rdi, rbx
    call testproto_cancel
2:  add rbx, TSR_SIZE
    inc r12d
    cmp r12d, TS_RUNS_MAX
    jb 1b
    EPILOGUE

# testview_action(tsc, index, word, len): goto, diff, output on an item (the Testing tab's; T4/T5)
FN testview_action
    ret

# testctl_wait(sb): wait-tests: until no run is queued or running (30 s at most), then
#   "tests=idle" (or "tests=busy")
FN testctl_wait
    PROLOGUE
    mov rbx, rdi
    call time_ms
    lea r12, [rax + 30000]
1:  xor edi, edi
    call testmodel_active
    test eax, eax
    jz 2f
    call time_ms
    cmp rax, r12
    jae 3f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 1b
2:  mov rdi, rbx
    lea rsi, [rip + .Lm_idle]
    call sb_push_cstr
    EPILOGUE
3:  mov rdi, rbx
    lea rsi, [rip + .Lm_busy]
    call sb_push_cstr
    EPILOGUE

# testctl_wait_items(sb, rest, len): wait-test-items N: until the controllers hold at least N items
#   and no tests-resolve is out (10 s at most), then "items=N"
FN testctl_wait_items
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call parse_u64
    mov r13, rax
    call time_ms
    lea r12, [rax + 10000]
1:  mov rax, [rip + g_ts_items_all]
    cmp rax, r13
    jb 2f
    call testproto_resolving
    test eax, eax
    jz 3f
2:  call time_ms
    cmp rax, r12
    jae 3f
    mov edi, 20
    call loop_poll
    call app_tick
    jmp 1b
3:  mov rdi, rbx
    lea rsi, [rip + .Lm_items]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + g_ts_items_all]
    call sb_push_u64
    mov rdi, rbx
    mov esi, 10
    call sb_push_byte
    EPILOGUE

# testctl_print(sb, rest, len): print-tests [all]
FN testctl_print
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    xor ecx, ecx
    test rdx, rdx
    jz 1f
    mov ecx, 1
1:  mov rdi, rbx
    mov esi, ecx
    call testmodel_dump
    xor eax, eax
    EPILOGUE

# testctl_result(sb, rest, len): print-test-result OWNER/NAME ID
FN testctl_result
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call item_arg
    test rax, rax
    jz 8f
    mov rdi, rbx
    mov rsi, rax
    call testmodel_dump_result
    xor eax, eax
    EPILOGUE
8:  mov rdi, rbx
    lea rsi, [rip + .Lm_no_item]
    call sb_push_cstr
    xor eax, eax
    EPILOGUE

# testctl_runs(sb): print-test-runs, then the processes
FN testctl_runs
    PROLOGUE
    mov rbx, rdi
    call testmodel_dump_runs
    mov rdi, rbx
    call testexec_dump
    xor eax, eax
    EPILOGUE

# testctl_coverage(sb, rest, len): print-coverage PATH
FN testctl_coverage
    PROLOGUE
    mov rbx, rdi
    mov rdi, rsi
    mov rsi, rdx
    call trim
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov r12, rax
    mov rdi, rbx
    mov rsi, r12
    call testcover_dump
    mov rdi, r12
    call mem_free
    xor eax, eax
    EPILOGUE

.section .rodata
.Lm_no_item: .asciz "no such test item\n"
.Lm_no_profile: .asciz "The test controller does not offer that kind of run"
.Lm_idle: .asciz "tests=idle\n"
.Lm_busy: .asciz "tests=busy\n"
.Lm_items: .asciz "items="
.La_cancel: .asciz "cancel"

.text
# cmd_testing: Testing: controllers start and show their tests
FN cmd_testing
    push rbx
    call testing_sync
    mov dword ptr [rip + g_dirty], 1
    pop rbx
    ret

# cmd_test_coverage_toggle: coverage tints on or off
FN cmd_test_coverage_toggle
    xor dword ptr [rip + g_cov_on], 1
    mov dword ptr [rip + g_dirty], 1
    ret

# cmd_test_next_failure: the next failure's place in the editor (testgutter.s)
FN cmd_test_next_failure
    ret
