# Settings protocol owns this opaque capsule. Only native code accesses its backing fields.
.equ ECNR_job, 0
.equ ECNR_context, 8
.equ ECNR_nonce, 16
.equ ECNR_SIZE, 32
.equ ESJ_SETTINGS, 3
# Persistent input ownership is disjoint from transient ESJ_work/native launch scratch.
.equ ECN_input, ESJ_SIZE
.equ ECN_event, ESJ_SIZE + 8
.equ ECN_operation, ESJ_SIZE + 16
.equ ECN_closing, ESJ_SIZE + 24
.equ ECN_length, ESJ_SIZE + 32
.equ ECN_offset, ESJ_SIZE + 40
.equ ECN_submitted, ESJ_SIZE + 48
.equ ECN_cleanup, ESJ_SIZE + 56
.equ ECN_write_error, ESJ_SIZE + 64
.equ ECN_request, ESJ_SIZE + 72
.equ ECN_debt, ESJ_SIZE + 80
.equ ECN_overlapped, ESJ_SIZE + 96
.equ ECN_security, ESJ_SIZE + 128
.equ ECN_pipe, ESJ_SIZE + 896
.equ ECN_chunk, ESJ_SIZE + 1408
.equ ECN_SIZE, ESJ_SIZE + 1408 + 65536
# start reports RDX primary/RCX secondary for NULL AND owned ABORTING capsule.
# free reports RDX consumed; actual child or unknown connect/write completion retains ownership.
# Failed known-unconsumed allocation/security disposal returns sticky cleanup/RDX0.
# The caller retains the opaque capsule and its entire reservation until consumed1.
# free RCX reason:0 consumed or live child/op/debt progress,1 retained cleanup-only.
# Every free exit initializes RCX. start keeps its separate RCX cleanup-error ABI.
