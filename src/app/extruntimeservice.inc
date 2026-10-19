# Native runtime service layouts. Kind8 PO roles share one checked dispatcher.
.equ RT_KIND, 8
.equ RT_role, 40
.equ RT_TABLE_ROLE, 1
.equ RT_TICKET_ROLE, 2
.equ RT_PROMPT_ROLE, 3
.equ RT_HEADER_SIZE, 1024
.equ RT_SLOT_COUNT, 128
.equ RT_SLOT_SIZE, 320
.equ RT_ROW_COUNT, 8192
.equ RT_ROW_SIZE, 64
.equ RT_DISCARD_SIZE, 64
.equ RT_slots, 1024
.equ RT_rows, RT_slots + RT_SLOT_COUNT * RT_SLOT_SIZE
.equ RT_pending, RT_rows + RT_ROW_COUNT * RT_ROW_SIZE
.equ RT_discards, RT_pending + RT_SLOT_COUNT * 8
.equ RT_TABLE_SIZE, RT_discards + RT_SLOT_COUNT * RT_DISCARD_SIZE
.equ RT_flags, 48
.equ RT_mutation, 56
.equ RT_nlive, 64
.equ RT_nreserved, 72
.equ RT_npending, 80
.equ RT_liveHead, 88
.equ RT_liveTail, 96
.equ RT_freeHead, 104
.equ RT_debtHead, 112
.equ RT_replyCursor, 120
.equ RT_cleanupCursor, 128
.equ RT_phase, 136
.equ RT_serviceCG, 144
.equ RT_baseCG, 152
.equ RT_capturedActiveCG, 160
.equ RT_capturedCommandEpoch, 168
.equ RT_capturedRegistryEpoch, 176
.equ RT_capturedMutationEpoch, 184
.equ RT_futureCommandEpoch, 192
.equ RT_futureKeyEpoch, 200
.equ RT_futureRegistryEpoch, 208
.equ RT_sourceSlotCursor, 216
.equ RT_sourceRowCursor, 224
.equ RT_batchCount, 232
.equ RT_batchMask, 240
.equ RT_batchCursor, 248
.equ RT_retiredActiveCG, 256
.equ RT_retiredBaseCG, 264
.equ RT_abortedCG, 272
.equ RT_heldKSI, 280
.equ RT_retiredKSI, 288
.equ RT_retryDue, 296
.equ RT_backoff, 304
.equ RT_sourceCopyCursor, 312
.equ RT_publicationRecord, 320
.equ RT_scratch, 328
.equ RT_invalidationCount, 464
.equ RT_classTurn, 472
.equ RT_classRuntimeCount, 480
.equ RT_barrierState, 488
.equ RT_barrierToken, 496
.equ RT_initCursor, 504
.equ RT_retirePhase, 512
.equ RT_capturedAuthorityEpoch, 520
.equ RT_nextAuthorityEpoch, 528
.equ RT_stableExtBase, 536
.equ RT_stableExtCount, 544
.equ RT_promptActive, 552
.equ RT_promptWire, 560
.equ RT_promptRetired, 568
.equ RT_builderEO, 576
.equ RT_discardBuffer, 584
.equ RT_selected0, 336
.equ RT_selected1, 344
.equ RT_selected2, 352
.equ RT_selected3, 360
.equ RT_selected4, 368
.equ RT_selected5, 376
.equ RT_selected6, 384
.equ RT_selected7, 392
.equ RT_selected8, 400
.equ RT_selected9, 408
.equ RT_selected10, 416
.equ RT_selected11, 424
.equ RT_selected12, 432
.equ RT_selected13, 440
.equ RT_selected14, 448
.equ RT_selected15, 456
.equ RTS_ea, 0
.equ RTS_session, 8
.equ RTS_state, 16
.equ RTS_nlive, 24
.equ RTS_ticket, 32
.equ RTS_flags, 40
.equ RTS_replyID, 48
.equ RTS_outcome, 56
.equ RTS_delivery, 64
.equ RTS_replyLen, 72
.equ RTS_retryDue, 80
.equ RTS_backoff, 88
.equ RTS_stallDeadline, 96
.equ RTS_orphanEO, 104
.equ RTS_failedPO, 112
.equ RTS_expectedKeeper, 120
.equ RTS_reply, 128
.equ RTS_liveHead, 256
.equ RTS_ndebt, 264
.equ RTS_nreserved, 272
.equ RTS_opKind, 280
.equ RTS_opStart, 288
.equ RTS_promptID, 296
.equ RTS_hi, 304
.equ RTS_grantSession, 312
.equ RTR_ro, 0
.equ RTR_ordinal, 8
.equ RTR_session, 16
.equ RTR_next, 24
.equ RTR_prev, 32
.equ RTR_acceptSequence, 40
.equ RTR_state, 48
.equ RTR_slotNext, 56
.equ RTD_session, 0
.equ RTD_remaining, 8
.equ RTD_deadline, 16
.equ RTD_state, 24
.equ RTD_reason, 32
.equ RTD_received, 40
.equ RTD_kind, 48
.equ RTD_rejectedRequestID, 56
.equ RTF_BUILDING, 1
.equ RTF_CLOSED, 2
.equ RTF_MEMORY_ONLY, 4
.equ RTS_FREE, 0
.equ RTS_ACTIVE, 1
.equ RTS_DRAINING, 2
.equ RTSF_STOP_REQUIRED, 1
.equ RTSF_PARSER_PAUSED, 2
.equ RTSF_OP_CREDIT, 4
.equ RTSF_ID_IN_USE, 8
.equ RTSF_REPLY_ATTEMPTED, 16
.equ RTSF_CHANNEL_BOUND, 32
.equ RTR_FREE, 0
.equ RTR_RESERVED, 1
.equ RTR_LIVE, 2
.equ RTR_DEBT, 3
.equ RTC_owner, 0
.equ RTC_orphanEO, 8
.equ RTC_primary, 16
.equ RTC_cleanup, 24
.equ RTC_SIZE, 32
.if RT_rows != 41984
.error "runtime row layout"
.endif
.if RT_pending != 566272
.error "runtime pending layout"
.endif
.if RT_discards != 567296
.error "runtime discard layout"
.endif
.if RT_TABLE_SIZE != 575488
.error "runtime allocation layout"
.endif
.if RTS_grantSession + 8 != RT_SLOT_SIZE
.error "runtime slot span"
.endif
.if RTR_slotNext + 8 != RT_ROW_SIZE
.error "runtime row span"
.endif
.if RTD_rejectedRequestID + 8 != RT_DISCARD_SIZE
.error "runtime discard span"
.endif

# By-value synchronous action revocation before later prompt cleanup.
.equ RTP_role, 40
.equ RTP_ordinal, 72
.equ RTP_session, 80
.equ RTP_flags, 176
.equ RTP_FRAME_CAP, 1048576
.equ RTP_HEADER_SIZE, 256
.equ RTPF_ACTION_REVOKED, 1
