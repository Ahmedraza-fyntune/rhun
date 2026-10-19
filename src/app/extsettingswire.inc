# Private settings worker frames. All integers are little endian on supported hosts.
.equ EW_HEADER, 64
.equ EW_LIMIT, 1064960
.equ EW_REQUEST, 1
.equ EW_SNAPSHOT, 2
.equ EW_DELTA, 3
.equ EW_PREPARED, 4
.equ EW_COMMIT, 5
.equ EW_COMMITTED, 6
.equ EW_RELEASE, 7
.equ EW_RESULT, 8
.equ EW_ABORT, 9
.equ EW_DISCARDED, 10
# EWT32 matches the opaque native constructor's ECNR32 correlation tuple.
.equ EWT_job, 0
.equ EWT_context, 8
.equ EWT_nonce, 16
.equ EWT_SIZE, 32
# Caller-owned encoder descriptor, containing a borrowed immutable tag pointer.
.equ EWE_tag, 0
.equ EWE_kind, 8
.equ EWE_length, 16
.equ EWE_round, 24
.equ EWE_SIZE, 32
