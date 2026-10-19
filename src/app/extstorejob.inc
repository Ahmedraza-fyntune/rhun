# Current-executable anchored helper transport. Caller owns ESJ until consumed free.
.equ ESJR_purpose, 0
.equ ESJR_anchor, 8
.equ ESJR_guard, 16
.equ ESJR_tag, 24
.equ ESJR_dir, 88
.equ ESJR_owner, 96
.equ ESJR_name, 104
.equ ESJR_source, 112
.equ ESJR_cancel, 120
.equ ESJR_user, 128
.equ ESJR_now, 136
.equ ESJR_SIZE, 144
.equ ESJ_purpose, 0
.equ ESJ_anchor, 8
.equ ESJ_guard, 16
.equ ESJ_tag, 24
.equ ESJ_dir, 88
.equ ESJ_owner, 96
.equ ESJ_name, 104
.equ ESJ_source, 112
.equ ESJ_cancel, 120
.equ ESJ_user, 128
.equ ESJ_deadline, 136
.equ ESJ_error, 144
.equ ESJ_secondary, 152
.equ ESJ_authority, 160
.equ ESJ_process, 168
.equ ESJ_killed, 176
.equ ESJ_terminal, 184
.equ ESJ_result, 192
.equ ESJ_wire, 200
.equ ESJ_used, 208
.equ ESJ_cap, 216
.equ ESJ_stdout, 224
.equ ESJ_stderr, 232
.equ ESJ_launch, 240
.equ ESJ_eof, 248
.equ ESJ_exit, 256
.equ ESJ_work, 264
.equ ESJ_argv, 272
.equ ESJ_exe, 400
.equ ESJ_dirbuf, 4496
.equ ESJ_ownerbuf, 8592
.equ ESJ_namebuf, 8696
.equ ESJ_sourcebuf, 8800
.equ ESJ_rawtext, 8864
.equ ESJ_epochtext, 8896
.equ ESJ_jobtext, 8928
.equ ESJ_noncehex, 8960
.equ ESJ_sourcehex, 8993
.equ ESJ_native, 9072
.equ ESJ_scratch, 9600
.equ ESJ_identity, 13704
.equ ESJ_SIZE, 13744
.equ ESJ_SNAPSHOT, 1
.equ ESJ_VALIDATOR, 2
.equ ESJ_NONE, 0
.equ ESJ_OWNED, 1
.equ ESJ_REAPED, 2
.equ ESJ_LOST, 3
# native slots0..7 are temporary handle/FD sources, initialized to -1.
# native64..104 source remap qwords, native112 launch errno bytes, native120 launch used.
# Backend spawn records owned process before any fallible parent cleanup.
# Backend read(raw,buf,count)->bytes/0EOF/-EAGAIN/-errno, never blocks.
# Backend poll(job) updates actual child authority and normalized exit.
# step has a combined <=64KiB/16 native pipe call budget and one child poll.
# free -> RAX cleanup status, RDX consumed. OWNED child returns -EBUSY/0.
# Registry is nonowning. Borrowed guard lives until free, and across bound ESS/ESW use.

# start may return a retained owner with negative RDX primary/RCX cleanup, including NONE.
# The caller must keep that owner and borrowed guard until consumed free.
# native_free -> RAX first local cleanup, RDX1 scratch memory consumed or0 retained.
# free returns sticky cleanup/RDX0 while any known-unconsumed allocation remains.
# ELC borrowed cwd survives every unconsumed free; registry capacity releases only consumed1.
