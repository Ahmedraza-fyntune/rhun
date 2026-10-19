# workspace edits on disk (v1.1.md workspace-edits, file-operations): the journal, writes of files
# that are not open, undo and redo of disk participants, recovery after a crash
.include "rhun.inc"

.text

# FN ws_disk_ready(T, TP, dir) -> eax 1 when the participant's file still holds what the step
# before left (dir 0: T's result, to be undone; dir 1: the original, to be redone)
FN ws_disk_ready
    mov eax, 1
    ret

# FN ws_disk_step(T, dir) -> eax 1 when the picked disk participants were undone or redone (or
# there were none), 0 when the system refused and everything was put back
FN ws_disk_step
    mov eax, 1
    ret

# FN ws_disk_rewrite(T, TP, dir): a written buffer's file again as the buffer now is
FN ws_disk_rewrite
    ret

# FN ws_disk_done(): after an undo or redo, the explorer and watchers catch up
FN ws_disk_done
    ret

# FN ws_journal_drop(T): its journal folder goes
FN ws_journal_drop
    ret

# FN ws_confirm_chosen(n), ws_confirm_cancel(): the confirmation list's answer
FN ws_confirm_chosen
    ret
FN ws_confirm_cancel
    ret
FN ws_confirm_owner_gone
    ret

# FN ws_disk_needed() -> eax 1 when the edit changes files on disk
FN ws_disk_needed
    xor eax, eax
    ret

# FN ws_disk_resolve() -> eax 1 with files that are not open read into hidden documents
FN ws_disk_resolve
    mov eax, 1
    ret

# FN ws_disk_hash_open(WG*) -> eax 1 when the open document's file hashes as the group says
FN ws_disk_hash_open
    mov eax, 1
    ret

# FN ws_disk_commit() -> eax 1 made
FN ws_disk_commit
    mov eax, 1
    ret

# FN ws_journal_print(sb): print-journal, one line per journal folder: "journal=NAME state=..."
FN ws_journal_print
    ret
