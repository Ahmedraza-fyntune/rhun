# Complete managed snapshot owner. Root guard is borrowed through all authoritative users.
.equ ED_snapshot, 0
.equ ED_guard, 8
.equ ED_epoch, 16
.equ ED_state, 24
.equ ED_cursor, 32
.equ ED_count, 40
.equ ED_rows, 48
.equ ED_rootpath, 56
.equ ED_error, 64
.equ ED_SIZE, 96
.equ ED_BUILDING, 0
.equ ED_READY, 1
.equ ED_FAILED, 2
.equ ED_DETACHED, 3
.equ EDR_record, 0
.equ EDR_path, 8
.equ EDR_SIZE, 16
.equ EDC_guard, 0
.equ EDC_epoch, 8
.equ EDC_lease, 16
.equ EDC_payload, 24
.equ EDC_owner, 32
.equ EDC_name, 136
.equ EDC_expected, 240
.equ EDC_id, 400
.equ EDC_path, 472
.equ EDC_rootid, 4568
.equ EDC_payloadid, 4600
.equ EDC_flags, 4632
.equ EDC_SIZE, 4640
.equ EH_root, 0
.equ EH_lease, 8
.equ EH_dir, 16
.equ EH_owner, 24
.equ EH_name, 32
.equ EH_SIZE, 40
# begin takes ESS only on success. ED/EDC never own the guard.
# candidate_take checks freshness then transfers only its lease, output unchanged on error.
# Caller rechecks candidate_check immediately before EP begin, without yield/reentry.
# EDC remains alive through EP and helper payload borrows; transferred lease belongs to caller/EP.
# candidate_free ALWAYS consumes; RAX/RDX first/second cleanup errors, NOT a consumed bit.
