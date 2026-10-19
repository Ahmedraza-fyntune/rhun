.equ MV_root, 64
.equ MV_dir, 72
.equ MV_owner, 80
.equ MV_name, 88
.equ MV_buffer, 96
.equ MV_len, 104
.equ MV_flags, 112
.equ MV_nsettings, 120
.equ MV_top, 128
.equ MV_settings, 336
.equ MV_SETTING_SIZE, 144
.equ MV_ext, MV_settings + 256 * MV_SETTING_SIZE
.equ MV_SIZE, MV_ext + EXT_SIZE
.equ MT_OWNER, 0
.equ MT_NAME, 1
.equ MT_TITLE, 2
.equ MT_VERSION, 3
.equ MT_PROTOCOL, 4
.equ MT_TARGET, 5
.equ MT_RUNTIME, 6
.equ MT_RUN, 7
