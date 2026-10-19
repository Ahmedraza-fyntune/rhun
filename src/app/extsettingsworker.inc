.include "app/extsettingswire.inc"
.include "app/extchoices.inc"
.equ SWR_mode, 0
.equ SWR_count, 8
.equ SWR_flags, 16
.equ SWR_exists, 24
.equ SWR_digest, 32
.equ SWR_path, 64
.equ SWR_delta, 4160
.equ SWR_SIZE, SWR_delta + EC_BATCH * EC_SIZE
.include "app/extchoicesdisk.inc"
.equ SW_tag, 0
.equ SW_header, 32
.equ SW_encoder, 96
.equ SW_io, 128
.equ SW_guard, 152
.equ SW_candidate, 160
.equ SW_snapshot, 168
.equ SW_body, 176
.equ SW_length, 184
.equ SW_kind, 192
.equ SW_round, 200
.equ SW_mode, 208
.equ SW_result, 216
.equ SW_state, 216
.equ SW_primary, 224
.equ SW_cleanup, 232
.equ SW_observation, 240
.equ SW_deadline, 248
.equ SW_idle_hold, 256
.equ SW_frame_round, 264
.equ SW_transport_failed, 272
.equ SW_announced_exists, 280
.equ SW_announced_length, 288
.equ SW_announced_digest, 296
.equ SW_request, 328
.equ SW_SIZE, SW_request + SWR_SIZE
.equ SW_READ_OK, 1
.equ SW_PRECOMMIT_FAILED, 2
.equ SW_COMMITTED, 3
.equ SW_UNCERTAIN, 4
.equ SW_CANCELED, 5
.equ SW_DISCARDED, 6
