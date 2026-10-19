# Private owned command and binding generation. Public PO/CMD/KB payloads retain their layout.
.equ CS_target, 0
.equ CS_ordinal, 8
.equ CS_ep, 16
.equ CS_owner, 24
.equ CS_name, 32
.equ CS_ownerlen, 40
.equ CS_namelen, 48
.equ CS_first, 56
.equ CS_count, 64
.equ CS_runtime, 72
.equ CS_SIZE, 80
.equ CG_intent, 40
.equ CG_keyepoch, 48
.equ CG_visibility, 56
.equ CG_nslots, 64
.equ CG_nruntimes, 72
.equ CG_nkeys, 80
.equ CG_nmanifest, 88
.equ CG_ncommands, 96
.equ CG_phase, 104
.equ CG_commands, 112
.equ CG_owners, 136
.equ CG_authority, 160
.equ CG_bindings, 184
.equ CG_metadata, 208
.equ CG_qualified, 216
.equ CG_owned, 224
.equ CG_routecap, 232
.equ CG_bindingmap, 240
.equ CG_openkey, 248
.equ CG_combolen, 256
.equ CG_commandlen, 264
.equ CG_keycursor, 272
.equ CG_keybytes, 280
.equ CG_retirephase, 288
.equ CG_retirecursor, 296
.equ CG_row, 304
.equ CG_slot, 312
.equ CG_runtime, 320
.equ CG_scanfield, 328
.equ CG_scanoffset, 336
.equ CG_source, 344
.equ CG_sourcelen, 352
.equ CG_hashkind, 360
.equ CG_hashoffset, 368
.equ CG_mapkind, 376
.equ CG_probe, 384
.equ CG_comparerow, 392
.equ CG_compareoffset, 400
.equ CG_wordsource, 408
.equ CG_wordlength, 416
.equ CG_wordcursor, 424
.equ CG_wordstart, 432
.equ CG_wordsize, 440
.equ CG_wordmode, 448
.equ CG_currentcmd, 456
.equ CG_userindex, 464
.equ CG_resolverphase, 472
.equ CG_slash, 480
.equ CG_dot, 488
.equ CG_resolvercursor, 496
.equ CG_resolved, 504
.equ CG_packed, 512
.equ CG_bindingcmd, 520
.equ CG_bindingindex, 528
.equ CG_defaultbytes, 536
.equ CG_wordtokens, 544
.equ CG_title, 552
.equ CG_label, 560
.equ CG_labellen, 568
.equ CG_titleoffset, 576
.equ CG_kc, 584
.equ CG_sha, 680
.equ CG_digest, 808
.equ CG_slots, 840
.equ CG_runtimes, CG_slots + 128 * CS_SIZE
.equ CG_keylines, CG_runtimes + 8192 * 16
.equ CG_defaultmeta, CG_keylines + 4096 * 32
.equ CG_defaultnodes, CG_defaultmeta + 8
.equ CG_defaultcapacity, CG_defaultnodes + 8
.equ CG_defaultcount, CG_defaultcapacity + 8
.equ CG_SIZE, CG_defaultcount + 8
.equ CG_DEFAULT_NODE_CAP, 262144
.equ CG_DEFAULT_USER_BIT, 63
.equ CG_DEFAULT_ALLOC_META, 41
.equ CG_DEFAULT_ALLOC_NODES, 42
.if CG_defaultmeta != (CG_keylines + 4096 * 32)
.error "default metadata overlaps owned input rows"
.endif
.if CG_SIZE != (CG_keylines + 4096 * 32 + 32)
.error "invalid appended command generation size"
.endif
.equ CG_INPUT, 0
.equ CG_ALLOC, 1
.equ CG_READY, 100
.equ CG_SLOT_CAP, 128
.equ CG_RUNTIME_CAP, 8192
.equ CG_COMMAND_CAP, 32768
.equ CG_KEY_CAP, 4096
.equ CG_KEY_BYTES_CAP, 1024 * 1024
.equ CG_STRING_CAP, 1024 * 1024
.equ CG_BINDING_CAP, 65536
.equ CG_BINDING_MAP_CAP, 131072
.equ CM_wirelen, 0
.equ CM_keylen, 8
.equ CM_keyslen, 16
.equ CM_qualifiedhash, 24
.equ CM_ownedhash, 32
.equ CM_slot, 40
.equ CM_SIZE, 64

.equ KB_mods, 0
.equ KB_key, 4
.equ KB_cmd, 8
.equ KB_SIZE, 16
