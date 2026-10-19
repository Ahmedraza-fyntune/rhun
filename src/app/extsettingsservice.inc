# One owned settings domain. No EXT/SD or native capsule pointers in public input.
.include "app/extsettingscatalog.inc"
.include "app/extsettingsjob.inc"
.equ SVI_path, 0
.equ SVI_length, 8
.equ SVI_context, 16
.equ SVI_nonce, 24
.equ SVI_SIZE, 40
.if ESI_SIZE != 128
.error "settings INI cursor size changed by service constructor input"
.endif
.if ESI_error + 8 > ESI_SIZE
.error "settings INI cursor error field exceeds imported allocation size"
.endif
.if SVI_nonce + 16 != SVI_SIZE
.error "service constructor request size does not cover nonce"
.endif
.equ SVC_MAGIC, 0x31564353554e4852
.equ SV_magic, 0
.equ SV_refs, 8
.equ SV_next, 16
.equ SV_state, 24
.equ SV_path, 32
.equ SV_length, 40
.equ SV_context, 48
.equ SV_nonce, 56
.equ SV_queue, 72
.equ SV_source, 80
.equ SV_pending, 88
.equ SV_source_epoch, 96
.equ SV_pending_epoch, 104
.equ SV_job_serial, 112
.equ SV_sap_serial, 120
.equ SV_srt_serial, 128
.equ SV_batch, 136
.equ SV_batch_phase, 144
.equ SV_job, 152
.equ SV_frame, 160
.equ SV_release_frame, 168
.equ SV_delivery, 176
.equ SV_sap, 184
.equ SV_sap_ticket, 192
.equ SV_srt, 200
.equ SV_srt_ticket, 208
.equ SV_detached_model, 216
.equ SV_primary, 224
.equ SV_observation, 232
.equ SV_cleanup, 240
.equ SV_uncertain, 248
.equ SV_installed, 256
.equ SV_commit, 264
.equ SV_apply_error, 272
.equ SV_phase, 280
.equ SV_tag, 288
.equ SV_cursor, 320
.equ SV_mode, 384
.equ SV_now, 392
.equ SV_poll_due, 400
.equ SV_retry_due, 408
.equ SV_retry_delay, 416
.equ SV_retry_count, 424
.equ SV_final_state, 432
.equ SV_final_primary, 440
.equ SV_final_flags, 448
.equ SV_native_turn, 456
.equ SV_abort, 464
.equ SV_provisional, 472
.equ SV_final_observation, 480
.equ SV_conversion_tried, 488
.equ SV_control_sent, 496
.equ SV_retry_pending, 504
.equ SV_apply_rebuild, 512
.equ SV_apply_grant, 520
.equ SV_replaced_source, 528
.equ SV_SIZE, 544
.equ SVP_IDLE, 0
.equ SVP_BATCH, 1
.equ SVP_RELEASE, 2
.equ SVP_REQUEST, 3
.equ SVP_ENCODE, 4
.equ SVP_LAUNCH, 5
.equ SVP_ACTIVE, 6
.equ SVP_FINISH, 7
.equ SVP_FAILED, 8
.equ SVP_RETRY, 9
.equ SVB_NONE, 0
.equ SVB_SAVING, 1
.equ SVB_ACK_WAITING, 2
.equ SVB_ACKED, 3
.equ SVB_SELF_DEBT, 4
.if SV_cursor + 64 != SV_mode
.error "service REQUEST cursor overlaps engine fields"
.endif
.if SV_replaced_source + 16 != SV_SIZE
.error "service engine fields exceed owned allocation"
.endif
.equ SV_UNPUBLISHED, 0
.equ SV_LIVE, 1
.equ SV_PREPARE_CLOSE, 2
.equ SV_SHUTTING, 3
.equ SV_DETACHED, 4
.equ SV_RETIRED, 5
