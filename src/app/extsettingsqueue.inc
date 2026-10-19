# Owned exact settings intent. No process, metadata, protocol or filesystem references.
.include "app/extchoices.inc"
.equ EQ_MAX, 512
.equ EQ_CAP, 67108864
.equ EQ_seq, 0
.equ EQ_epoch, 8
.equ EQ_count, 16
.equ EQ_payload, 24
.equ EQ_charge, 32
.equ EQ_batch, 40
.equ EQ_head, 48
.equ EQ_tail, 56
.equ EQ_retired, 64
.equ EQ_retired_tail, 72
.equ EQ_retired_count, 80
.equ EQ_cursor, 88
.equ EQ_slots, 96
.equ EQ_SLOT, 24
.equ EQS_cell, 0
.equ EQS_prev, 8
.equ EQS_next, 16
.equ EQ_SIZE, EQ_slots + EQ_MAX * EQ_SLOT
# Cell begins with EC56, then immutable sequence and lifecycle accounting.
.equ EQC_seq, 56
.equ EQC_refs, 64
.equ EQC_charge, 72
.equ EQC_next, 80
.equ EQC_hash, 88
.equ EQC_SIZE, 96
.equ EQB_queue, 0
.equ EQB_count, 8
.equ EQB_charge, 16
.equ EQB_rows, 24
.equ EQB_ROW, 24
.equ EQBR_slot, 0
.equ EQBR_cell, 8
.equ EQBR_seq, 16
.equ EQB_SIZE, EQB_rows + EC_BATCH * EQB_ROW

.if EQC_next + 8 > EQC_hash
.error "queue next overlaps cached identity hash"
.endif
.if EQC_hash + 8 > EQC_SIZE
.error "queue cached identity hash exceeds cell header"
.endif
