.equ VT_records, 0
.equ VT_paths, 8
.equ VT_pathused, 16
.equ VT_count, 24
.equ VT_files, 32
.equ VT_dirs, 40
.equ VT_bytes, 48
.equ VT_depth, 56
.equ VT_dir, 64
.equ VT_prefix, 72
.equ VT_pathbytes, 80
.equ VT_sources, 88
.equ VT_nsource, 96
.equ VT_seen, 104
.equ VT_cleanup, 112
.equ VT_bound, 120
.equ VT_path, 128
.equ VT_buffer, VT_path + 4096
.equ VT_sha, VT_buffer + 65536
.equ VT_SIZE, VT_sha + SH256_SIZE
.equ VR_path, 0
.equ VR_len, 8
.equ VR_kind, 16
.equ VR_size, 24
.equ VR_exec, 32
.equ VR_hash, 40
.equ VR_SIZE, 72
