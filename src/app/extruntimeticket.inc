# Owned canonical registration request, before publication or reply acceptance.
.equ RTQ_ordinal, 0
.equ RTQ_session, 8
.equ RTQ_id, 16
.equ RTQ_key, 24
.equ RTQ_keyLen, 32
.equ RTQ_title, 40
.equ RTQ_titleLen, 48
.equ RTQ_keys, 56
.equ RTQ_keysLen, 64
.equ RTQ_kind, 72
.equ RTQ_SIZE, 80
.equ RTQ_REGISTER, 1
.equ RTQ_UNREGISTER, 2
.equ RTT_role, 40
.equ RTT_phase, 48
.equ RTT_ro, 56
.equ RTT_ea, 64
.equ RTT_ordinal, 72
.equ RTT_session, 80
.equ RTT_requestID, 88
.equ RTT_acceptSequence, 96
.equ RTT_reservedRow, 104
.equ RTT_keyLen, 112
.equ RTT_titleLen, 120
.equ RTT_keysLen, 128
.equ RTT_keyOffset, 136
.equ RTT_titleOffset, 144
.equ RTT_keysOffset, 152
.equ RTT_copyCursor, 160
.equ RTT_semanticCursor, 168
.equ RTT_primary, 176
.equ RTT_cleanup, 184
.equ RTT_orphanEO, 192
.equ RTT_fixedBytes, 200
.equ RTT_HEADER_SIZE, 256
.equ RTT_MAX_SIZE, RTT_HEADER_SIZE + 41 + 81 + 65537
.equ RTT_BUILDING, 0
.equ RTT_CAPTURED, 1
.equ RTT_PENDING, 2
.if RTT_MAX_SIZE != 65915
.error "runtime ticket maximum"
.endif
