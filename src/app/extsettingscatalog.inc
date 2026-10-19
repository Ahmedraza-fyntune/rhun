.include "app/extsettingsview.inc"
# Public whole final set request, stable historical slots, caller-owned inputs.
.equ ECSCP_source, 0
.equ ECSCP_rows, 8
.equ ECSCP_count, 16
.equ ECSCP_registry, 24
.equ ECSCP_dirty, 32
.equ ECSCP_model, 40
.equ ECSCP_SIZE, 48
.equ ECSR_view, 0
.equ ECSR_slot, 8
.equ ECSR_owner, 16
.equ ECSR_name, 24
.equ ECSR_SIZE, 32
# Private plan rows borrow identity bytes only from their own retained ready view.
.equ CP_refs, 0
.equ CP_next, 8
.equ CP_model, 16
.equ CP_source, 24
.equ CP_oldmodel, 32
.equ CP_cursor, 40
.equ CP_provider, 48
.equ CP_baseline, 56
.equ CP_context, 64
.equ CP_registry, 72
.equ CP_dirty, 80
.equ CP_epoch, 88
.equ CP_providerepoch, 96
.equ CP_newregistry, 104
.equ CP_newepoch, 112
.equ CP_newprovider, 120
.equ CP_phase, 128
.equ CP_error, 136
.equ CP_cleanup, 144
.equ CP_count, 152
.equ CP_index, 160
.equ CP_slotbits, 168
.equ CP_published, 184
.equ CP_namelen, 192
.equ CP_oldref, 200
.equ CP_workflags, 208
.equ CP_rowindex, 216
.equ CP_hash, 224
.equ CP_scanpos, 232
.equ CP_matchpos, 240
.equ CP_probe, 248
.equ CP_ppphase, 256
.equ CP_pptarget, 264
.equ CP_ppindex, 272
.equ CP_ppsourceindex, 280
.equ CP_ppoldrow, 288
.equ CP_ppkind, 296
.equ CP_pplanglen, 304
.equ CP_ppownerlen, 312
.equ CP_ppinputtype, 320
.equ CP_ppdirtyslot, 328
.equ CP_ppdirtyseq, 336
.equ CP_ppraw, 344
.equ CP_bytesleft, 400
.equ CP_phasesleft, 408
.equ CP_allocsleft, 416
.equ CP_gcindex, 424
.equ CP_gcphase, 432
.equ CP_ppremove, 440
.equ CP_ppexpectedhash, 448
.equ CP_ppcompare, 456
.equ CP_ppdiff, 464
.equ CP_ppinitrow, 472
.equ CP_ppfallbackindex, 480
.equ CP_ppinvalid, 488
.equ CP_kind, 504
.equ CP_sequence, 512
.equ CP_rows, 520
.equ CPR_view, 0
.equ CPR_slot, 8
.equ CPR_SIZE, 16
.equ CP_buckets, CP_rows + 128 * CPR_SIZE
.equ CP_hashes, CP_buckets + 512 * 8
.equ CP_SIZE, CP_hashes + 128 * 8
.equ CPP_MODEL_ALLOC, 1
.equ CPP_MODEL_SOURCE, 2
.equ CPP_SLOTS, 3
.equ CPP_ID_HASH, 4
.equ CPP_ID_INSERT, 5
.equ CPP_ID_COMPARE, 6
.equ CPP_PROVIDERS, 7
.equ CPP_FINAL, 8
.equ CPP_READY, 9
.equ CPP_FAILED, 10
# One allocation owns a PP24-compatible vector and every copied provider byte.
.equ PB_count, 0
.equ PB_active, 8
.equ PB_invalid, 16
.equ PB_rows, 64
.equ PBR_kind, 0
.equ PBR_language, 8
.equ PBR_owner, 16
.equ PBR_SIZE, 24
.equ PB_meta, PB_rows + 512 * PBR_SIZE
.equ PBM_hash, 0
.equ PBM_langlen, 8
.equ PBM_ownerlen, 16
.equ PBM_flags, 24
.equ PBM_SIZE, 32
.equ PB_buckets, PB_meta + 512 * PBM_SIZE
.equ PB_language, PB_buckets + 1024 * 8
.equ PB_owner, PB_language + 512 * 129
.equ PB_SIZE, PB_owner + 512 * 202
.equ PPS_BASE_ALLOC, 0
.equ PPS_BASE_COPY, 1
.equ PPS_BASE_REBASE, 2
.equ PPS_DIRTY_NEXT, 3
.equ PPS_SECTION, 4
.equ PPS_KEY, 5
.equ PPS_LANGUAGE, 6
.equ PPS_OWNER, 7
.equ PPS_LOOKUP, 8
.equ PPS_MATCH, 9
.equ PPS_LANG_COPY, 10
.equ PPS_OWNER_COPY, 11
.equ PPS_INSTALL, 12
.equ PPS_CAND_ALLOC, 13
.equ PPS_CURSOR_ALLOC, 14
.equ PPS_RAW_NEXT, 15
.equ PPS_COMPARE_BEGIN, 16
.equ PPS_COMPARE_NEXT, 17
.equ PPS_COMPARE_LOOKUP, 18
.equ PPS_COMPARE_LANG, 19
.equ PPS_COMPARE_OWNER, 20
.equ PPF_DIRTY, 1
.equ PPF_FALLBACK, 2
.equ PPF_BAD, 4
.equ PPF_LOOKBASE, 8
.equ PPF_NEW, 16
.equ PBMF_RAW, 1
.equ PBMF_DIRTY, 2
.equ PBMF_FALLBACK, 4
.equ CP_ppprefix, 496

.if CP_ppprefix + 8 > CP_kind
.error "provider prefix overlaps plan kind"
.endif
.if CP_kind + 8 > CP_sequence
.error "plan kind overlaps sequence"
.endif
.if CP_sequence + 8 > CP_rows
.error "plan sequence overlaps rows"
.endif
.if CP_rows + 128 * CPR_SIZE > CP_buckets
.error "plan rows overlap identity buckets"
.endif
.if CP_buckets + 512 * 8 > CP_hashes
.error "plan identity buckets overlap hashes"
.endif
.if CP_hashes + 128 * 8 > CP_SIZE
.error "plan identity hashes overflow allocation"
.endif
