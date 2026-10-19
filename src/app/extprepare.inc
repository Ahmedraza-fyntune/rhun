# Private managed preparation ownership and immutable product views.
.equ EO_refs, 0
.equ EO_used, 8
.equ EO_cap, 16
.equ EO_error, 24
.equ EO_lease, 32
.equ EO_deferred, 40
.equ EO_SIZE, 48
.equ PO_refs, 0
.equ PO_eo, 8
.equ PO_allocs, 16
.equ PO_error, 24
.equ PO_ready, 32
.equ PO_SIZE, 40
.equ AO_next, 0
.equ AO_charge, 8
.equ AO_SIZE, 16
.equ GP_warnings, 40
.equ GP_rules, 48
.equ GP_name_len, 56
.equ GP_it, 64
.equ GP_legacy, GP_it
.equ GP_gr, GP_it + INI_SIZE
.equ GP_SIZE, GP_gr + GR_SIZE
.equ PC_owner, CMD_SIZE
.equ PC_extension, CMD_SIZE + 8
.equ PC_key, CMD_SIZE + 16
.equ PC_SIZE, CMD_SIZE + 24
.equ PT_palette, TH_SIZE
.equ PT_defined, PT_palette + 4 * T_COUNT
.equ PT_SIZE, (PT_defined + 16 + 7) & -8
.equ SR_path, 0
.equ SR_len, 8
.equ SR_size, 16
.equ SR_exec, 24
.equ SR_hash, 32
.equ SR_roles, 64
.equ SR_SIZE, 72
.equ SR_MANIFEST, 1
.equ SR_LAUNCH, 2
.equ SR_GRAMMAR, 4
.equ SR_THEME, 8
.equ SR_EXTERNAL, 16
.equ PREP_CAP, 64 * 1024 * 1024
# EP owns a private EXT and immutable contributions, never a registry slot.
.equ EP_root, 40
.equ EP_syntax, 48
.equ EP_themes, 56
.equ EP_commands, 64
.equ EP_grammars, EP_commands + VEC_SIZE
.equ EP_themeviews, EP_grammars + VEC_SIZE
.equ EP_plan, EP_themeviews + VEC_SIZE
.equ EP_sources, EP_plan + VEC_SIZE
.equ EP_next, EP_sources + VEC_SIZE
.equ EP_assetbytes, EP_next + 8
.equ EP_valuecharge, EP_assetbytes + 8
.equ EP_manifest, EP_valuecharge + 8
.equ EP_manifestlen, EP_manifest + 8
.equ EP_raw, EP_manifestlen + 8
.equ EP_ext, EP_raw + 8
.equ EP_cleanup, EP_ext + EXT_SIZE
.equ EP_capture_handle, EP_cleanup + 8
.equ EP_capture_size, EP_capture_handle + 8
.equ EP_capture_exec, EP_capture_size + 8
.equ EP_native, EP_capture_exec + 8
.equ EP_capture_ranges, EP_native + 8
.equ EP_kind, EP_capture_ranges + VEC_SIZE
.equ EP_legacy_import, EP_kind + 8
.equ EP_legacy_wire, EP_legacy_import + 8
.equ EP_legacy_wirelen, EP_legacy_wire + 8
.equ EP_legacy_drive, EP_legacy_wirelen + 8
.equ EP_legacy_source, EP_legacy_drive + 8
.equ EP_legacy_cwd, EP_legacy_source + 32
.equ EP_legacy_rootlen, EP_legacy_cwd + 8
.equ EP_SIZE, EP_legacy_rootlen + 8
.equ CR_offset, 0
.equ CR_len, 8
.equ CR_bytes, 16
.equ CR_SIZE, 528
.equ AP_path, 0
.equ AP_len, 8
.equ AP_kind, 16
.equ AP_size, 24
.equ AP_exec, 32
.equ AP_name, 40
.equ AP_bytes, 48
.equ AP_byteslen, 56
.equ AP_SIZE, 64
.equ AP_GRAMMAR, 1
.equ AP_THEME, 2
