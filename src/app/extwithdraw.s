# Fixed logical borrower invalidation within the coordinator's nonyielding publication.
.include "rhun.inc"
.text
FN ext_catalog_borrowers_invalidate_pure
    PROLOGUE
    call extpage_catalog_invalidate_pure
    call extbar_catalog_invalidate_pure
    call ext_remove_catalog_invalidate_pure
    call extproto_prompt_catalog_invalidate_pure
    call palette_close_extensions_pure
    call ext_provider_catalog_invalidate_pure
    call complete_catalog_invalidate_pure
    call langfeat_catalog_invalidate_pure
    call ext_hover_catalog_invalidate_pure
    call ext_options_apply
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
