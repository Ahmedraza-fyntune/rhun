# Codebase Insights: File, Folder & Project Statistics
# Features:
# - File-level statistics (name, type, size, lines: total/code/comment/blank, modified)
# - Folder-level aggregated statistics
# - Project-level insights (overview, file type distribution, largest files, largest directories)
# - Configurable exclusion rules (defaults: .git, node_modules, vendor, dist, build, .next, coverage, .cache, target, __pycache__)
# - Gitignore integration and hidden directory avoidance
# - Language-aware parsing and multiline/single-line comment handling
# - Binary file detection and handling
# - Caching and cancellation support
# - Explorer hover integration and interactive Markdown report tab

.include "rhun.inc"

# Structures

STRUCT
F IF_path, 8           # allocated full path cstr
F IF_relpath, 8        # allocated rel path cstr
F IF_name, 8           # allocated basename cstr
F IF_type, 8           # allocated or static type name cstr
F IF_ext, 8            # allocated or static extension cstr
F IF_size, 8           # size in bytes
F IF_mtime, 8          # modification timestamp
F IF_tot_lines, 8      # total lines
F IF_code_lines, 8     # code lines
F IF_comm_lines, 8     # comment lines
F IF_blank_lines, 8    # blank lines
F IF_is_binary, 4      # 1 = binary, 0 = text
F IF_status, 4         # 1 = valid
ENDSTRUCT IF_SIZE

STRUCT
F IS_files, 8          # included files
F IS_dirs, 8           # included directories
F IS_size, 8           # included total bytes
F IS_tot_lines, 8      # total lines across text files
F IS_code_lines, 8     # total code lines
F IS_comm_lines, 8     # total comment lines
F IS_blank_lines, 8    # total blank lines
F IS_text_files, 8     # text file count
F IS_bin_files, 8      # binary file count
F IS_excluded_files, 8 # excluded file count
F IS_excluded_dirs, 8  # excluded directory count
F IS_excluded_size, 8  # excluded size in bytes
ENDSTRUCT IS_SIZE

STRUCT
F IT_name, 8           # type / language name
F IT_ext, 8            # extension
F IT_files, 8          # count
F IT_size, 8           # total bytes
F IT_tot_lines, 8      # total lines
F IT_code_lines, 8     # code lines
F IT_comm_lines, 8     # comment lines
F IT_blank_lines, 8    # blank lines
ENDSTRUCT IT_SIZE

STRUCT
F ID_path, 8           # directory path cstr
F ID_size, 8           # total bytes in directory
F ID_files, 8          # files in directory
ENDSTRUCT ID_SIZE

.equ MAX_SCAN_DEPTH, 64
.equ MAX_FILE_READ, 10485760    # 10 MiB limit for line counting

.bss
.p2align 3
.globl insights_cache, insights_stats, insights_sb
insights_cache:       .zero VEC_SIZE
insights_files:       .zero VEC_SIZE    # pointers to IF_SIZE in cache
insights_types:       .zero VEC_SIZE    # IT_SIZE entries
insights_dirs:        .zero VEC_SIZE    # ID_SIZE entries
insights_stats:       .zero IS_SIZE
insights_sb:          .zero SB_SIZE
insights_scan_depth:  .long 0
insights_cancel_flag: .long 0

dir_cache_path:       .zero 1024
dir_cache_files:      .quad 0
dir_cache_dirs:       .quad 0
dir_cache_time:       .quad 0
dir_count_files:      .quad 0
dir_count_dirs:       .quad 0
dir_count_depth:      .long 0

.section .rodata
# Default excluded directories
.Ldef_git:         .asciz ".git"
.Ldef_node_mod:    .asciz "node_modules"
.Ldef_vendor:      .asciz "vendor"
.Ldef_dist:        .asciz "dist"
.Ldef_build:       .asciz "build"
.Ldef_next:        .asciz ".next"
.Ldef_coverage:    .asciz "coverage"
.Ldef_cache:       .asciz ".cache"
.Ldef_target:      .asciz "target"
.Ldef_pycache:     .asciz "__pycache__"

.p2align 3
default_exclusions:
    .quad .Ldef_git
    .quad .Ldef_node_mod
    .quad .Ldef_vendor
    .quad .Ldef_dist
    .quad .Ldef_build
    .quad .Ldef_next
    .quad .Ldef_coverage
    .quad .Ldef_cache
    .quad .Ldef_target
    .quad .Ldef_pycache
    .quad 0

# Binary file extensions
.Lbin_png:   .asciz "png"
.Lbin_jpg:   .asciz "jpg"
.Lbin_jpeg:  .asciz "jpeg"
.Lbin_gif:   .asciz "gif"
.Lbin_bmp:   .asciz "bmp"
.Lbin_ico:   .asciz "ico"
.Lbin_webp:  .asciz "webp"
.Lbin_tiff:  .asciz "tiff"
.Lbin_mp4:   .asciz "mp4"
.Lbin_mkv:   .asciz "mkv"
.Lbin_avi:   .asciz "avi"
.Lbin_mov:   .asciz "mov"
.Lbin_webm:  .asciz "webm"
.Lbin_mp3:   .asciz "mp3"
.Lbin_wav:   .asciz "wav"
.Lbin_ogg:   .asciz "ogg"
.Lbin_flac:  .asciz "flac"
.Lbin_exe:   .asciz "exe"
.Lbin_dll:   .asciz "dll"
.Lbin_so:    .asciz "so"
.Lbin_dylib: .asciz "dylib"
.Lbin_bin:   .asciz "bin"
.Lbin_o:     .asciz "o"
.Lbin_a:     .asciz "a"
.Lbin_obj:   .asciz "obj"
.Lbin_class: .asciz "class"
.Lbin_wasm:  .asciz "wasm"
.Lbin_pyc:   .asciz "pyc"
.Lbin_zip:   .asciz "zip"
.Lbin_tar:   .asciz "tar"
.Lbin_gz:    .asciz "gz"
.Lbin_bz2:   .asciz "bz2"
.Lbin_xz:    .asciz "xz"
.Lbin_7z:    .asciz "7z"
.Lbin_rar:   .asciz "rar"
.Lbin_pdf:   .asciz "pdf"
.Lbin_ttf:   .asciz "ttf"
.Lbin_otf:   .asciz "otf"
.Lbin_woff:  .asciz "woff"
.Lbin_woff2: .asciz "woff2"

.p2align 3
binary_extensions:
    .quad .Lbin_png, .Lbin_jpg, .Lbin_jpeg, .Lbin_gif, .Lbin_bmp, .Lbin_ico, .Lbin_webp, .Lbin_tiff
    .quad .Lbin_mp4, .Lbin_mkv, .Lbin_avi, .Lbin_mov, .Lbin_webm
    .quad .Lbin_mp3, .Lbin_wav, .Lbin_ogg, .Lbin_flac
    .quad .Lbin_exe, .Lbin_dll, .Lbin_so, .Lbin_dylib, .Lbin_bin, .Lbin_o, .Lbin_a, .Lbin_obj
    .quad .Lbin_class, .Lbin_wasm, .Lbin_pyc
    .quad .Lbin_zip, .Lbin_tar, .Lbin_gz, .Lbin_bz2, .Lbin_xz, .Lbin_7z, .Lbin_rar
    .quad .Lbin_pdf, .Lbin_ttf, .Lbin_otf, .Lbin_woff, .Lbin_woff2
    .quad 0

# Language fallback definitions: ext, name, single_comment, ml_start, ml_end
.Lext_py:   .asciz "py"
.Lt_py:     .asciz "Python"
.Lc_hash:   .asciz "#"
.Lml_py1:   .asciz "\"\"\""
.Lml_py2:   .asciz "'''"

.Lext_c:    .asciz "c"
.Lext_h:    .asciz "h"
.Lt_c:      .asciz "C"
.Lc_slash:  .asciz "//"
.Lml_c_s:   .asciz "/*"
.Lml_c_e:   .asciz "*/"

.Lext_cpp:  .asciz "cpp"
.Lext_hpp:  .asciz "hpp"
.Lext_cc:   .asciz "cc"
.Lext_cxx:  .asciz "cxx"
.Lt_cpp:    .asciz "C++"

.Lext_rs:   .asciz "rs"
.Lt_rs:     .asciz "Rust"

.Lext_go:   .asciz "go"
.Lt_go:     .asciz "Go"

.Lext_js:   .asciz "js"
.Lext_jsx:  .asciz "jsx"
.Lext_mjs:  .asciz "mjs"
.Lt_js:     .asciz "JavaScript"

.Lext_ts:   .asciz "ts"
.Lext_tsx:  .asciz "tsx"
.Lt_ts:     .asciz "TypeScript"

.Lext_s:    .asciz "s"
.Lext_asm:  .asciz "asm"
.Lt_asm:    .asciz "Assembly"
.Lc_semi:   .asciz ";"

.Lext_sh:   .asciz "sh"
.Lext_bash: .asciz "bash"
.Lt_sh:     .asciz "Shell"

.Lext_json: .asciz "json"
.Lt_json:   .asciz "JSON"

.Lext_md:   .asciz "md"
.Lt_md:     .asciz "Markdown"
.Lml_xml_s: .asciz "<!--"
.Lml_xml_e: .asciz "-->"

.Lext_html: .asciz "html"
.Lext_htm:  .asciz "htm"
.Lt_html:   .asciz "HTML"

.Lext_css:  .asciz "css"
.Lt_css:    .asciz "CSS"

.Lext_yaml: .asciz "yaml"
.Lext_yml:  .asciz "yml"
.Lt_yaml:   .asciz "YAML"

.Lext_toml: .asciz "toml"
.Lt_toml:   .asciz "TOML"

.Lext_xml:  .asciz "xml"
.Lt_xml:    .asciz "XML"

.Lext_sql:  .asciz "sql"
.Lt_sql:    .asciz "SQL"
.Lc_dash:   .asciz "--"

.Lext_txt:  .asciz "txt"
.Lt_text:   .asciz "Plain Text"
.Lt_binary: .asciz "Binary"

.p2align 3
language_defs:
    # ext, name, single_comment, ml_start, ml_end
    .quad .Lext_py,   .Lt_py,   .Lc_hash,  .Lml_py1,  .Lml_py1
    .quad .Lext_c,    .Lt_c,    .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_h,    .Lt_c,    .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_cpp,  .Lt_cpp,  .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_hpp,  .Lt_cpp,  .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_cc,   .Lt_cpp,  .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_cxx,  .Lt_cpp,  .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_rs,   .Lt_rs,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_go,   .Lt_go,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_js,   .Lt_js,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_jsx,  .Lt_js,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_mjs,  .Lt_js,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_ts,   .Lt_ts,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_tsx,  .Lt_ts,   .Lc_slash, .Lml_c_s,  .Lml_c_e
    .quad .Lext_s,    .Lt_asm,  .Lc_hash,  .Lml_c_s,  .Lml_c_e
    .quad .Lext_asm,  .Lt_asm,  .Lc_semi,  .Lml_c_s,  .Lml_c_e
    .quad .Lext_sh,   .Lt_sh,   .Lc_hash,  0,         0
    .quad .Lext_bash, .Lt_sh,   .Lc_hash,  0,         0
    .quad .Lext_json, .Lt_json, 0,         0,         0
    .quad .Lext_md,   .Lt_md,   0,         .Lml_xml_s,.Lml_xml_e
    .quad .Lext_html, .Lt_html, 0,         .Lml_xml_s,.Lml_xml_e
    .quad .Lext_htm,  .Lt_html, 0,         .Lml_xml_s,.Lml_xml_e
    .quad .Lext_css,  .Lt_css,  0,         .Lml_c_s,  .Lml_c_e
    .quad .Lext_yaml, .Lt_yaml, .Lc_hash,  0,         0
    .quad .Lext_yml,  .Lt_yaml, .Lc_hash,  0,         0
    .quad .Lext_toml, .Lt_toml, .Lc_hash,  0,         0
    .quad .Lext_xml,  .Lt_xml,  0,         .Lml_xml_s,.Lml_xml_e
    .quad .Lext_sql,  .Lt_sql,  .Lc_dash,  .Lml_c_s,  .Lml_c_e
    .quad .Lext_txt,  .Lt_text, 0,         0,         0
    .quad 0

# UI & Markdown report strings
.Lstr_title:         .asciz "# Codebase Insights\n\n"
.Lstr_sec_overview:  .asciz "## Project Overview\n\n"
.Lstr_root_lbl:      .asciz "- **Root Path**: `"
.Lstr_files_lbl:     .asciz "- **Total Files**: "
.Lstr_text_lbl:      .asciz " (Text: "
.Lstr_bin_lbl:       .asciz ", Binary: "
.Lstr_dirs_lbl:      .asciz "- **Total Directories**: "
.Lstr_size_lbl:      .asciz "- **Total Storage Size**: "
.Lstr_tot_lines_lbl: .asciz "- **Total Lines**: "
.Lstr_code_lines_lbl:.asciz "- **Code Lines**: "
.Lstr_comm_lines_lbl:.asciz "- **Comment Lines**: "
.Lstr_blank_lines_lbl:.asciz "- **Blank Lines**: "
.Lstr_excl_lbl:      .asciz "- **Excluded Items**: "
.Lstr_excl_dirs_lbl: .asciz " directories, "
.Lstr_excl_files_lbl:.asciz " files ("
.Lstr_excl_bytes_lbl:.asciz " skipped)\n\n"

.Lstr_sec_dist:      .asciz "## File Type Distribution\n\n"
.Lstr_dist_hdr:      .asciz "| File Type | Extension | Files | Size | Code Lines | Comment Lines | Blank Lines | % Code |\n| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |\n"

.Lstr_sec_large_f:   .asciz "\n## Largest Files\n\n"
.Lstr_large_f_hdr:   .asciz "| # | File Path | Size | Lines | Type |\n| ---: | :--- | ---: | ---: | :--- |\n"

.Lstr_sec_large_d:   .asciz "\n## Largest Directories\n\n"
.Lstr_large_d_hdr:   .asciz "| # | Directory Path | Total Size | Files |\n| ---: | :--- | ---: | ---: |\n"

.Lstr_sec_excl:      .asciz "\n## Exclusion Rules\n\n"
.Lstr_excl_def:      .asciz "- **Default Excluded**: `.git`, `node_modules`, `vendor`, `dist`, `build`, `.next`, `coverage`, `.cache`, `target`, `__pycache__`\n"
.Lstr_excl_git:      .asciz "- **.gitignore Rules**: Active (respects repository and nested `.gitignore` files)\n"
.Lstr_excl_hidden:   .asciz "- **Hidden Directories**: Skipped by default\n"
.Lstr_excl_conf:     .asciz "- **Configured Exclusions**: "
.Lstr_none:          .asciz "None\n"

.Lstr_doc_title:     .asciz "Codebase Insights"
.Lstr_markdown_lang: .asciz "markdown"
.Lstr_empty:         .asciz ""
.Lstr_space:         .asciz " "
.Lstr_newline:       .asciz "\n"
.Lstr_slash:         .asciz "/"
.Lstr_dot:           .asciz "."
.Lstr_bytes:         .asciz " bytes"
.Lstr_unit_b:        .asciz " B"
.Lstr_unit_kb:       .asciz " KB"
.Lstr_unit_mb:       .asciz " MB"
.Lstr_unit_gb:       .asciz " GB"

.text

# ---------------- Initialization & Cleanup ----------------

# insights_init()
FN insights_init
    PROLOGUE
    mov qword ptr [rip + insights_cache + VEC_len], 0
    mov qword ptr [rip + insights_files + VEC_len], 0
    mov qword ptr [rip + insights_types + VEC_len], 0
    mov qword ptr [rip + insights_dirs + VEC_len], 0
    mov dword ptr [rip + insights_cancel_flag], 0
    mov byte ptr [rip + dir_cache_path], 0
    mov qword ptr [rip + dir_cache_time], 0
    lea rdi, [rip + insights_sb]
    call sb_clear
    EPILOGUE

# insights_clear_dirs()
FN insights_clear_dirs
    PROLOGUE
    mov r8, [rip + insights_dirs + VEC_ptr]
    mov r9, [rip + insights_dirs + VEC_len]
1:  test r9, r9
    jz 2f
    dec r9
    imul rax, r9, ID_SIZE
    mov rdi, [r8 + rax + ID_path]
    test rdi, rdi
    jz 1b
    call mem_free
    jmp 1b
2:  mov qword ptr [rip + insights_dirs + VEC_len], 0
    EPILOGUE

# insights_clear_cache()
FN insights_clear_cache
    PROLOGUE
    mov r8, [rip + insights_cache + VEC_ptr]
    mov r9, [rip + insights_cache + VEC_len]
1:  test r9, r9
    jz 2f
    dec r9
    imul rax, r9, IF_SIZE
    lea r12, [r8 + rax]
    mov rdi, [r12 + IF_path]
    call mem_free
    mov rdi, [r12 + IF_relpath]
    call mem_free
    mov rdi, [r12 + IF_name]
    call mem_free
    jmp 1b
2:  mov qword ptr [rip + insights_cache + VEC_len], 0
    EPILOGUE

# insights_free()
FN insights_free
    PROLOGUE
    call insights_clear_cache
    call insights_clear_dirs
    lea rdi, [rip + insights_cache]
    call vec_free
    lea rdi, [rip + insights_files]
    call vec_free
    lea rdi, [rip + insights_types]
    call vec_free
    lea rdi, [rip + insights_dirs]
    call vec_free
    lea rdi, [rip + insights_sb]
    call sb_free
    EPILOGUE

# insights_cancel()
FN insights_cancel
    mov dword ptr [rip + insights_cancel_flag], 1
    ret

# ---------------- Exclusion Rules ----------------

# insights_is_excluded(rel_path, rel_len, name, is_dir) -> eax 1 if excluded, 0 if included
FN insights_is_excluded
    PROLOGUE 48
    mov [rsp], rdi              # rel_path
    mov [rsp + 8], rsi          # rel_len
    mov [rsp + 16], rdx         # name
    mov [rsp + 24], ecx         # is_dir

    # 1. Hidden system directories (starts with '.' and is_dir)
    test ecx, ecx
    jz .Lie_check_defaults
    mov rax, [rsp + 16]
    cmp byte ptr [rax], '.'
    je .Lie_excluded

.Lie_check_defaults:
    # 2. Check default exclusions list
    lea r12, [rip + default_exclusions]
1:  mov rsi, [r12]
    test rsi, rsi
    jz .Lie_check_config
    mov rdi, [rsp + 16]
    call strcmp_eq
    test eax, eax
    jnz .Lie_excluded
    add r12, 8
    jmp 1b

.Lie_check_config:
    # 3. Check user-configured additional exclusions (cfg_insights_exclude)
    mov rax, [rip + cfg_insights_exclude]
    test rax, rax
    jz .Lie_check_gitignore
    mov rdi, rax
    call strlen
    test rax, rax
    jz .Lie_check_gitignore

    mov r12, [rip + cfg_insights_exclude]
2:  mov rdi, r12
    call strlen
    test rax, rax
    jz .Lie_check_gitignore
    mov rdi, r12
    mov rsi, rax
    call next_word
    test rdx, rdx
    jz .Lie_check_gitignore
    lea r12, [rax + rdx]

    # Compare word (rax, rdx) with basename
    mov r14, rax                # word ptr
    mov r15, rdx                # word len
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rsp + 16]         # name cstr
    call str_eq_cstr
    test eax, eax
    jnz .Lie_excluded

    # Compare word (r14, r15) with relpath ([rsp], [rsp + 8])
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    call str_eq
    test eax, eax
    jnz .Lie_excluded
    jmp 2b

.Lie_check_gitignore:
    # 4. Respect gitignore rules if available
    mov rdi, [rsp]              # rel_path
    mov rsi, [rsp + 8]          # rel_len
    mov rdx, [rsp + 16]         # name
    mov ecx, [rsp + 24]         # is_dir
    call gitignore_is_ignored
    test eax, eax
    jnz .Lie_excluded

    xor eax, eax
    EPILOGUE

.Lie_excluded:
    mov eax, 1
    EPILOGUE

# ---------------- Binary & Language Detection ----------------

# insights_is_binary_file(path, path_len, buf, buf_len) -> eax 1 if binary, 0 if text
FN insights_is_binary_file
    PROLOGUE 32
    mov [rsp], rdi              # path
    mov [rsp + 8], rsi          # path_len
    mov [rsp + 16], rdx         # buf
    mov [rsp + 24], rcx         # buf_len

    # Check extension against binary extensions
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call path_ext
    test rdx, rdx
    jz .Lib_check_nul

    mov r12, rax                # ext ptr
    mov r13, rdx                # ext len
    lea r14, [rip + binary_extensions]
1:  mov rdx, [r14]
    test rdx, rdx
    jz .Lib_check_nul
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz .Lib_is_bin
    add r14, 8
    jmp 1b

.Lib_check_nul:
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    test rdi, rdi
    jz .Lib_is_text
    test rsi, rsi
    jz .Lib_is_text

    call doc_is_binary
    test eax, eax
    jnz .Lib_is_bin

.Lib_is_text:
    xor eax, eax
    EPILOGUE

.Lib_is_bin:
    mov eax, 1
    EPILOGUE

# insights_detect_type(path, buf, len, out_rec)
FN insights_detect_type
    PROLOGUE 48
    mov [rsp], rdi              # path
    mov [rsp + 8], rsi          # buf
    mov [rsp + 16], rdx         # len
    mov [rsp + 24], rcx         # out_rec

    # Zero output record
    mov rdi, rcx
    xor eax, eax
    mov ecx, 10
    rep stosq

    mov rdi, [rsp]
    call strlen
    mov [rsp + 32], rax         # path_len

    # Check binary
    mov rdi, [rsp]
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 8]
    mov rcx, [rsp + 16]
    call insights_is_binary_file
    test eax, eax
    jz .Ldt_text

    # Binary file
    mov rbx, [rsp + 24]
    mov dword ptr [rbx + 48], 1
    lea rax, [rip + .Lt_binary]
    mov [rbx], rax

    # Get ext
    mov rdi, [rsp]
    mov rsi, [rsp + 32]
    call path_ext
    test rdx, rdx
    jz .Ldt_done
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov rbx, [rsp + 24]
    mov [rbx + 8], rax
    jmp .Ldt_done

.Ldt_text:
    # Text file: try syntax_detect
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    call syntax_detect
    test rax, rax
    jz .Ldt_fallback

    # Syntax detected!
    mov r12, rax                # GR*
    mov rbx, [rsp + 24]
    mov rax, [r12 + GR_name]
    mov [rbx], rax
    mov rax, [r12 + GR_comment]
    mov [rbx + 16], rax
    mov rax, [r12 + GR_commentlen]
    mov [rbx + 24], rax

    # Check GR_regions for multiline comment
    mov r13, [r12 + GR_regions + VEC_len]
    test r13, r13
    jz .Ldt_ext
    mov r14, [r12 + GR_regions + VEC_ptr]
3:  test r13, r13
    jz .Ldt_ext
    dec r13
    imul rax, r13, REG_SIZE
    lea r15, [r14 + rax]
    cmp byte ptr [r15 + REG_class], C_COMMENT
    jne 3b
    cmp byte ptr [r15 + REG_multi], 0
    je 3b
    lea rax, [r15 + REG_start]
    mov [rbx + 32], rax
    lea rax, [r15 + REG_end]
    mov [rbx + 40], rax
    jmp .Ldt_ext

.Ldt_fallback:
    mov rdi, [rsp]
    mov rsi, [rsp + 32]
    call path_ext
    test rdx, rdx
    jz .Ldt_plain

    mov r12, rax                # ext ptr
    mov r13, rdx                # ext len
    lea r14, [rip + language_defs]
4:  mov rdx, [r14]
    test rdx, rdx
    jz .Ldt_plain
    mov rdi, r12
    mov rsi, r13
    call str_eq_cstr
    test eax, eax
    jnz .Ldt_def_found
    add r14, 40
    jmp 4b

.Ldt_def_found:
    mov rbx, [rsp + 24]
    mov rax, [r14 + 8]          # name
    mov [rbx], rax
    mov rax, [r14 + 16]         # single_comment
    mov [rbx + 16], rax
    test rax, rax
    jz 6f
    mov rdi, rax
    call strlen
    mov [rbx + 24], rax
6:  mov rax, [r14 + 24]         # ml_start
    mov [rbx + 32], rax
    mov rax, [r14 + 32]         # ml_end
    mov [rbx + 40], rax
    jmp .Ldt_ext

.Ldt_plain:
    mov rbx, [rsp + 24]
    lea rax, [rip + .Lt_text]
    mov [rbx], rax

.Ldt_ext:
    mov rdi, [rsp]
    mov rsi, [rsp + 32]
    call path_ext
    test rdx, rdx
    jz .Ldt_done
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov rbx, [rsp + 24]
    mov [rbx + 8], rax

.Ldt_done:
    EPILOGUE

# ---------------- Line Counting ----------------

# insights_count_lines(buf, len, comment_token, comment_token_len, ml_start, ml_end)
# Returns:
# rax = total_lines
# rdx = code_lines
# rcx = comment_lines
# r8  = blank_lines
FN insights_count_lines
    PROLOGUE 96
    mov [rsp], rdi              # buf
    mov [rsp + 8], rsi          # len
    mov [rsp + 16], rdx         # comment_token
    mov [rsp + 24], rcx         # comment_token_len
    mov [rsp + 32], r8          # ml_start
    mov [rsp + 40], r9          # ml_end

    # ml_start_len
    mov qword ptr [rsp + 48], 0
    test r8, r8
    jz 1f
    mov rdi, r8
    call strlen
    mov [rsp + 48], rax
1:
    # ml_end_len
    mov qword ptr [rsp + 56], 0
    mov rax, [rsp + 40]
    test rax, rax
    jz 2f
    mov rdi, rax
    call strlen
    mov [rsp + 56], rax
2:
    xor r12, r12                # total_lines
    xor r13, r13                # code_lines
    xor r14, r14                # comment_lines
    xor r15, r15                # blank_lines
    xor ebx, ebx                # in_multiline (0 or 1)

    mov rax, [rsp]
    mov [rsp + 64], rax         # cur
    mov rax, [rsp]
    add rax, [rsp + 8]
    mov [rsp + 72], rax         # buf_end

.Lcl_loop:
    mov r8, [rsp + 64]
    cmp r8, [rsp + 72]
    jae .Lcl_finish

    inc r12                     # total_lines++
    mov r10, r8                 # line_start

    # Find line_end (\n or \r or end of buffer)
3:  cmp r8, [rsp + 72]
    jae 4f
    mov al, [r8]
    cmp al, 10                  # LF
    je 5f
    cmp al, 13                  # CR
    je 6f
    inc r8
    jmp 3b

6:  # CR: check if CRLF
    mov [rsp + 80], r8          # line_end
    inc r8
    cmp r8, [rsp + 72]
    jae 7f
    cmp byte ptr [r8], 10       # LF after CR
    jne 7f
    inc r8
    jmp 7f

5:  # LF
    mov [rsp + 80], r8          # line_end
    inc r8
    jmp 7f

4:  # Buffer end without newline
    mov [rsp + 80], r8

7:  mov [rsp + 64], r8          # save cur for next iteration

    # Check if blank (all whitespace)
    mov rcx, r10
.Lcl_blank_check:
    cmp rcx, [rsp + 80]
    jae .Lcl_is_blank
    movzx eax, byte ptr [rcx]
    cmp al, ' '
    je 8f
    cmp al, 9                   # tab
    je 8f
    cmp al, 13                  # cr
    je 8f
    cmp al, 10                  # lf
    je 8f
    # Found non-whitespace!
    jmp .Lcl_has_content
8:  inc rcx
    jmp .Lcl_blank_check

.Lcl_is_blank:
    inc r15                     # blank_lines++
    jmp .Lcl_loop

.Lcl_has_content:
    mov [rsp + 88], rcx         # save p
    test ebx, ebx
    jz .Lcl_not_in_ml

    # Currently inside multiline comment
    mov rdx, [rsp + 40]         # ml_end
    test rdx, rdx
    jz .Lcl_still_ml_comment

    # Search for ml_end between p and line_end
    mov rdi, [rsp + 88]         # hay = p
    mov rsi, [rsp + 80]
    sub rsi, rdi                # hlen
    mov rdx, [rsp + 40]         # needle
    mov rcx, [rsp + 56]         # nlen
    call str_find
    test rax, rax
    js .Lcl_still_ml_comment

    # Found ml_end!
    xor ebx, ebx                # out of multiline
    mov rdx, [rsp + 88]
    add rdx, rax                # match ptr
    add rdx, [rsp + 56]         # past ml_end

.Lcl_check_after_ml:
    cmp rdx, [rsp + 80]
    jae .Lcl_ml_only_comment
    mov al, [rdx]
    cmp al, ' '
    je 9f
    cmp al, 9
    je 9f
    cmp al, 13
    je 9f
    # Found code after ml_end!
    inc r13                     # code_lines++
    jmp .Lcl_loop
9:  inc rdx
    jmp .Lcl_check_after_ml

.Lcl_ml_only_comment:
    inc r14                     # comment_lines++
    jmp .Lcl_loop

.Lcl_still_ml_comment:
    inc r14                     # comment_lines++
    jmp .Lcl_loop

.Lcl_not_in_ml:
    # Check single-line comment
    mov rdx, [rsp + 16]         # comment_token
    test rdx, rdx
    jz .Lcl_check_ml_start
    mov rcx, [rsp + 24]         # comment_token_len
    test rcx, rcx
    jz .Lcl_check_ml_start
    mov rax, [rsp + 80]
    sub rax, [rsp + 88]         # rem_len = line_end - p
    cmp rax, rcx
    jb .Lcl_check_ml_start
    mov rdi, [rsp + 88]         # p
    mov rsi, rcx                # alen = comment_token_len
    # rdx = comment_token, rcx = comment_token_len
    call str_eq
    test eax, eax
    jnz .Lcl_is_comment_line

.Lcl_check_ml_start:
    # Check multiline comment start
    mov rdx, [rsp + 32]         # ml_start
    test rdx, rdx
    jz .Lcl_is_code_line
    mov rcx, [rsp + 48]         # ml_start_len
    test rcx, rcx
    jz .Lcl_is_code_line
    mov rax, [rsp + 80]
    sub rax, [rsp + 88]         # rem_len = line_end - p
    cmp rax, rcx
    jb .Lcl_is_code_line
    mov rdi, [rsp + 88]         # p
    mov rsi, rcx                # alen = ml_start_len
    # rdx = ml_start, rcx = ml_start_len
    call str_eq
    test eax, eax
    jz .Lcl_is_code_line

    # Starts multiline comment!
    mov rdi, [rsp + 88]
    add rdi, [rsp + 48]         # hay = p + ml_start_len
    mov [rsp + 88], rdi         # save hay
    mov rdx, [rsp + 40]         # ml_end
    test rdx, rdx
    jz .Lcl_starts_ml

    mov rsi, [rsp + 80]
    sub rsi, rdi                # hlen = line_end - hay
    mov rcx, [rsp + 56]         # nlen = ml_end_len
    call str_find
    test rax, rax
    js .Lcl_starts_ml

    # ml_end found on same line
    mov rdx, [rsp + 88]
    add rdx, rax                # match ptr
    add rdx, [rsp + 56]         # past ml_end
.Lcl_check_same_line_after:
    cmp rdx, [rsp + 80]
    jae .Lcl_is_comment_line
    mov al, [rdx]
    cmp al, ' '
    je 10f
    cmp al, 9
    je 10f
    cmp al, 13
    je 10f
    inc r13                     # code_lines++
    jmp .Lcl_loop
10: inc rdx
    jmp .Lcl_check_same_line_after

.Lcl_starts_ml:
    mov ebx, 1                  # in_multiline = 1
    inc r14                     # comment_lines++
    jmp .Lcl_loop

.Lcl_is_comment_line:
    inc r14                     # comment_lines++
    jmp .Lcl_loop

.Lcl_is_code_line:
    inc r13                     # code_lines++
    jmp .Lcl_loop

.Lcl_finish:
    mov rax, r12                # total_lines
    mov rdx, r13                # code_lines
    mov rcx, r14                # comment_lines
    mov r8, r15                 # blank_lines
    EPILOGUE

# ---------------- Caching and File Scanning ----------------

# insights_scan_file(abs_path, rel_path) -> rax pointer to IF_SIZE struct (or 0 on error)
FN insights_scan_file
    PROLOGUE 176
    mov [rsp], rdi              # abs_path
    mov [rsp + 8], rsi          # rel_path

    # Check file exists and get stamp
    mov rdi, [rsp]
    call file_stamp
    test rax, rax
    jz .Lsf_fail
    mov [rsp + 16], rdx         # size
    mov [rsp + 24], rcx         # mtime_ns

    mov rdi, [rsp]
    call file_mtime
    mov [rsp + 32], rax         # mtime seconds

    # Check cache
    mov rbx, [rip + insights_cache + VEC_ptr]
    mov r12, [rip + insights_cache + VEC_len]
1:  test r12, r12
    jz .Lsf_cache_miss
    dec r12
    imul rax, r12, IF_SIZE
    lea r13, [rbx + rax]
    mov rdi, [r13 + IF_path]
    mov rsi, [rsp]
    call strcmp_eq
    test eax, eax
    jz 1b

    # Found in cache! Check freshness
    mov rax, [rsp + 16]
    cmp [r13 + IF_size], rax
    jne .Lsf_reparse
    mov rax, [rsp + 32]
    cmp [r13 + IF_mtime], rax
    jne .Lsf_reparse

    # Cache hit!
    mov rax, r13
    mov rdx, r12                # r12 = cache index
    EPILOGUE

.Lsf_reparse:
    mov [rsp + 40], r13
    mov [rsp + 144], r12
    jmp .Lsf_do_parse

.Lsf_cache_miss:
    mov rax, [rip + insights_cache + VEC_len]
    mov [rsp + 144], rax        # index
    lea rdi, [rip + insights_cache]
    mov esi, IF_SIZE
    call vec_push
    mov [rsp + 40], rax
    mov r13, rax

    # Copy paths
    mov rdi, [rsp]
    call strlen
    mov rdi, [rsp]
    mov rsi, rax
    call mem_dup
    mov [r13 + IF_path], rax

    mov rdi, [rsp + 8]
    call strlen
    mov rdi, [rsp + 8]
    mov rsi, rax
    call mem_dup
    mov [r13 + IF_relpath], rax

    # Basename
    mov rdi, [rsp]
    call strlen
    mov rdi, [rsp]
    mov rsi, rax
    call path_basename
    mov rdi, rax
    mov rsi, rdx
    call mem_dup
    mov [r13 + IF_name], rax

.Lsf_do_parse:
    mov r13, [rsp + 40]
    mov rax, [rsp + 16]
    mov [r13 + IF_size], rax
    mov rax, [rsp + 32]
    mov [r13 + IF_mtime], rax

    # Read file contents (limited to MAX_FILE_READ)
    mov rdi, [rsp]
    mov rsi, MAX_FILE_READ
    call file_read_limited
    mov [rsp + 48], rax         # buf
    mov [rsp + 56], rdx         # len

    # Detect type
    mov rdi, [rsp]
    mov rsi, [rsp + 48]
    mov rdx, [rsp + 56]
    lea rcx, [rsp + 64]         # out_rec (80 bytes)
    call insights_detect_type

    # Save type & ext
    mov rax, [rsp + 64]         # type_name
    mov [r13 + IF_type], rax
    mov rax, [rsp + 72]         # ext
    mov [r13 + IF_ext], rax
    mov eax, [rsp + 112]        # is_binary
    mov [r13 + IF_is_binary], eax

    test eax, eax
    jnz .Lsf_binary_file

    # Count lines for text file
    mov rdi, [rsp + 48]         # buf
    mov rsi, [rsp + 56]         # len
    mov rdx, [rsp + 80]         # single_comment
    mov rcx, [rsp + 88]         # single_comment_len
    mov r8, [rsp + 96]          # ml_start
    mov r9, [rsp + 104]         # ml_end
    call insights_count_lines
    mov [r13 + IF_tot_lines], rax
    mov [r13 + IF_code_lines], rdx
    mov [r13 + IF_comm_lines], rcx
    mov [r13 + IF_blank_lines], r8
    jmp .Lsf_parse_done

.Lsf_binary_file:
    mov qword ptr [r13 + IF_tot_lines], 0
    mov qword ptr [r13 + IF_code_lines], 0
    mov qword ptr [r13 + IF_comm_lines], 0
    mov qword ptr [r13 + IF_blank_lines], 0

.Lsf_parse_done:
    mov dword ptr [r13 + IF_status], 1

    # Free read buffer
    mov rdi, [rsp + 48]
    test rdi, rdi
    jz 2f
    call mem_free
2:
    mov rax, [rsp + 40]
    mov rdx, [rsp + 144]
    EPILOGUE

.Lsf_fail:
    xor eax, eax
    EPILOGUE

# ---------------- Directory Walking & Project Insights ----------------

# dir_scan_callback(ctx, name, is_dir)
FN dir_scan_callback
    PROLOGUE 48
    mov [rsp], rdi              # abs_parent
    mov [rsp + 8], rsi          # name
    mov [rsp + 16], edx         # is_dir

    # Check cancellation
    cmp dword ptr [rip + insights_cancel_flag], 0
    jne .Ldsc_ret

    mov rdi, [rsp + 8]
    call strlen
    mov [rsp + 24], rax         # name_len

    # Build full abs path
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call path_join
    mov [rsp + 40], rax         # full_abs

    # Determine relative path from project root
    mov rsi, rax
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 1f
    mov rdi, [rsp]              # fallback
1:  call strlen
    lea rdx, [rsi + rax]
    cmp byte ptr [rdx], '/'
    jne 2f
    inc rdx
2:  # rdx = rel_path ptr
    mov [rsp + 24], rdx         # rel_path
    mov rdi, rdx
    call strlen
    mov [rsp + 32], rax         # rel_len

    # Check exclusion
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 8]          # name
    mov ecx, [rsp + 16]         # is_dir
    call insights_is_excluded
    test eax, eax
    jz .Ldsc_included

    # Excluded!
    cmp dword ptr [rsp + 16], 0
    je 3f
    inc qword ptr [rip + insights_stats + IS_excluded_dirs]
    jmp .Ldsc_cleanup
3:  inc qword ptr [rip + insights_stats + IS_excluded_files]
    mov rdi, [rsp + 40]
    call file_mtime
    test rax, rax
    jz .Ldsc_cleanup
    mov rdi, [rsp + 40]
    call file_stamp
    add [rip + insights_stats + IS_excluded_size], rdx
    jmp .Ldsc_cleanup

.Ldsc_included:
    cmp dword ptr [rsp + 16], 0
    jne .Ldsc_dir

    # File included!
    mov rdi, [rsp + 40]         # abs_path
    mov rsi, [rsp + 24]         # rel_path
    call insights_scan_file
    test rax, rax
    jz .Ldsc_cleanup

    mov r12, rax                # IF* entry
    mov r13, rdx                # cache_idx

    # Aggregate stats
    inc qword ptr [rip + insights_stats + IS_files]
    mov rax, [r12 + IF_size]
    add [rip + insights_stats + IS_size], rax

    cmp dword ptr [r12 + IF_is_binary], 0
    jne 4f
    inc qword ptr [rip + insights_stats + IS_text_files]
    mov rax, [r12 + IF_tot_lines]
    add [rip + insights_stats + IS_tot_lines], rax
    mov rax, [r12 + IF_code_lines]
    add [rip + insights_stats + IS_code_lines], rax
    mov rax, [r12 + IF_comm_lines]
    add [rip + insights_stats + IS_comm_lines], rax
    mov rax, [r12 + IF_blank_lines]
    add [rip + insights_stats + IS_blank_lines], rax
    jmp 5f
4:  inc qword ptr [rip + insights_stats + IS_bin_files]

5:  # Track file in insights_files vector for largest files (16 bytes: size, cache_idx)
    lea rdi, [rip + insights_files]
    mov esi, 16
    call vec_push
    mov rcx, [r12 + IF_size]
    mov [rax], rcx
    mov [rax + 8], r13

    # Update file type distribution
    mov rdi, r12
    call insights_update_type_stats
    jmp .Ldsc_cleanup

.Ldsc_dir:
    # Directory included!
    inc qword ptr [rip + insights_stats + IS_dirs]

    # Recurse into subdirectory
    mov rdi, [rsp + 40]
    call insights_walk_dir

.Ldsc_cleanup:
    mov rdi, [rsp + 40]
    call mem_free

.Ldsc_ret:
    EPILOGUE

# insights_walk_dir(abs_dir)
FN insights_walk_dir
    PROLOGUE 48
    mov [rsp], rdi              # abs_dir

    mov eax, [rip + insights_scan_depth]
    cmp eax, MAX_SCAN_DEPTH
    jae .Lwd_done
    inc dword ptr [rip + insights_scan_depth]

    # Enter gitignore
    mov rdi, [rsp]
    mov rsi, [rsp]
    xor edx, edx
    mov ecx, [rip + insights_scan_depth]
    call gitignore_enter_dir

    # Snapshot current size and files before scanning children
    mov rax, [rip + insights_stats + IS_size]
    mov [rsp + 8], rax
    mov rax, [rip + insights_stats + IS_files]
    mov [rsp + 16], rax

    # Enumerate directory
    mov rdi, [rsp]
    lea rsi, [rip + dir_scan_callback]
    mov rdx, [rsp]
    call dir_each

    # Leave gitignore
    mov edi, [rip + insights_scan_depth]
    call gitignore_leave_dir
    dec dword ptr [rip + insights_scan_depth]

    # Compute delta size and files for this directory
    mov rax, [rip + insights_stats + IS_size]
    sub rax, [rsp + 8]
    mov [rsp + 24], rax         # dir_size
    mov rax, [rip + insights_stats + IS_files]
    sub rax, [rsp + 16]
    mov [rsp + 32], rax         # dir_files

    # Determine relative path from project root
    mov rsi, [rsp]              # abs_dir
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + .Lstr_dot]
1:  call strlen
    lea rdx, [rsi + rax]
    cmp byte ptr [rdx], '/'
    jne 2f
    inc rdx
2:  # rdx = rel_path ptr
    mov rdi, rdx
    call strlen
    test rax, rax
    jz .Lwd_skip_record
    cmp byte ptr [rdx], '.'
    jne .Lwd_record
    cmp byte ptr [rdx + 1], 0
    je .Lwd_skip_record

.Lwd_record:
    # Only record directory if it contains at least 1 file
    cmp qword ptr [rsp + 32], 0
    je .Lwd_skip_record

    mov rdi, rdx
    mov rsi, rax
    call mem_dup
    mov r12, rax                # path cstr

    lea rdi, [rip + insights_dirs]
    mov esi, ID_SIZE
    call vec_push
    mov [rax + ID_path], r12
    mov rcx, [rsp + 24]
    mov [rax + ID_size], rcx
    mov rcx, [rsp + 32]
    mov [rax + ID_files], rcx

.Lwd_skip_record:
.Lwd_done:
    EPILOGUE

# insights_update_type_stats(IF*)
FN insights_update_type_stats
    PROLOGUE
    mov r12, rdi                # IF*

    mov r13, [r12 + IF_type]
    test r13, r13
    jnz 1f
    lea r13, [rip + .Lt_text]
1:
    mov rbx, [rip + insights_types + VEC_ptr]
    mov r14, [rip + insights_types + VEC_len]
2:  test r14, r14
    jz .Luts_new
    dec r14
    imul rax, r14, IT_SIZE
    lea r15, [rbx + rax]
    mov rdi, [r15 + IT_name]
    mov rsi, r13
    call strcmp_eq
    test eax, eax
    jnz .Luts_add
    jmp 2b

.Luts_new:
    lea rdi, [rip + insights_types]
    mov esi, IT_SIZE
    call vec_push
    mov r15, rax
    mov [r15 + IT_name], r13
    mov rax, [r12 + IF_ext]
    mov [r15 + IT_ext], rax

.Luts_add:
    inc qword ptr [r15 + IT_files]
    mov rax, [r12 + IF_size]
    add [r15 + IT_size], rax
    mov rax, [r12 + IF_tot_lines]
    add [r15 + IT_tot_lines], rax
    mov rax, [r12 + IF_code_lines]
    add [r15 + IT_code_lines], rax
    mov rax, [r12 + IF_comm_lines]
    add [r15 + IT_comm_lines], rax
    mov rax, [r12 + IF_blank_lines]
    add [r15 + IT_blank_lines], rax

    EPILOGUE

# insights_scan_project(project_path)
FN insights_scan_project
    PROLOGUE 16
    mov [rsp], rdi
    mov dword ptr [rip + insights_cancel_flag], 0
    mov dword ptr [rip + insights_scan_depth], 0

    mov qword ptr [rip + insights_files + VEC_len], 0
    mov qword ptr [rip + insights_types + VEC_len], 0
    call insights_clear_dirs

    lea rdi, [rip + insights_stats]
    xor eax, eax
    mov ecx, IS_SIZE / 8
    rep stosq

    call gitignore_init

    mov rdi, [rsp]
    call insights_walk_dir

    call gitignore_free
    call insights_sort_files
    call insights_sort_dirs
    call insights_sort_types

    EPILOGUE

# ---------------- Sorting Helpers ----------------

# insights_sort_files(): sorts insights_files descending by file size (item size = 16 bytes: size, cache_idx)
FN insights_sort_files
    PROLOGUE
    mov r8, [rip + insights_files + VEC_ptr]
    mov r9, [rip + insights_files + VEC_len]
    cmp r9, 2
    jb .Lsf_sort_done

    xor ebx, ebx
1:  inc rbx
    cmp rbx, r9
    jae .Lsf_sort_done
    imul rax, rbx, 16
    mov r12, [r8 + rax]         # key size
    mov r13, [r8 + rax + 8]     # key cache_idx
    mov r14, rbx
2:  test r14, r14
    jz 3f
    dec r14
    imul rax, r14, 16
    cmp [r8 + rax], r12
    jae 4f
    # swap slot r14 with r14+1
    mov rcx, [r8 + rax]
    mov rdx, [r8 + rax + 8]
    mov [r8 + rax + 16], rcx
    mov [r8 + rax + 24], rdx
    jmp 2b
4:  inc r14
3:  imul rax, r14, 16
    mov [r8 + rax], r12
    mov [r8 + rax + 8], r13
    jmp 1b

.Lsf_sort_done:
    EPILOGUE

# insights_sort_dirs(): sorts insights_dirs descending by directory size (ID_SIZE = 24)
FN insights_sort_dirs
    PROLOGUE
    mov r8, [rip + insights_dirs + VEC_ptr]
    mov r9, [rip + insights_dirs + VEC_len]
    cmp r9, 2
    jb .Lsd_done

    xor r12, r12                # i = 0
.Lsd_outer:
    cmp r12, r9
    jae .Lsd_done
    lea r13, [r12 + 1]          # j = i + 1
.Lsd_inner:
    cmp r13, r9
    jae .Lsd_outer_next

    imul rax, r12, ID_SIZE
    lea r14, [r8 + rax]         # item i
    imul rax, r13, ID_SIZE
    lea r15, [r8 + rax]         # item j

    mov rax, [r15 + 8]          # j->size
    cmp rax, [r14 + 8]          # compare with i->size
    jbe .Lsd_inner_next

.Lsd_swap:
    # swap 3 quadwords between r14 and r15
    mov rax, [r14]
    mov rdx, [r15]
    mov [r14], rdx
    mov [r15], rax

    mov rax, [r14 + 8]
    mov rdx, [r15 + 8]
    mov [r14 + 8], rdx
    mov [r15 + 8], rax

    mov rax, [r14 + 16]
    mov rdx, [r15 + 16]
    mov [r14 + 16], rdx
    mov [r15 + 16], rax

.Lsd_inner_next:
    inc r13
    jmp .Lsd_inner

.Lsd_outer_next:
    inc r12
    jmp .Lsd_outer

.Lsd_done:
    EPILOGUE

# insights_sort_types(): sorts insights_types descending by code lines, then files
FN insights_sort_types
    PROLOGUE
    mov r8, [rip + insights_types + VEC_ptr]
    mov r9, [rip + insights_types + VEC_len]
    cmp r9, 2
    jb .Lst_done

    xor r12, r12                # i = 0
.Lst_outer:
    cmp r12, r9
    jae .Lst_done
    lea r13, [r12 + 1]          # j = i + 1
.Lst_inner:
    cmp r13, r9
    jae .Lst_outer_next

    imul rax, r12, IT_SIZE
    lea r14, [r8 + rax]         # item i
    imul rax, r13, IT_SIZE
    lea r15, [r8 + rax]         # item j

    # compare IT_code_lines (offset 40)
    mov rax, [r15 + 40]         # j->code_lines
    cmp rax, [r14 + 40]         # compare with i->code_lines
    ja .Lst_swap
    jb .Lst_inner_next

    # if equal, compare IT_files (offset 16)
    mov rax, [r15 + 16]         # j->files
    cmp rax, [r14 + 16]         # compare with i->files
    jbe .Lst_inner_next

.Lst_swap:
    # swap 8 quadwords between r14 and r15
    xor ecx, ecx
1:  mov rax, [r14 + rcx*8]
    mov rdx, [r15 + rcx*8]
    mov [r14 + rcx*8], rdx
    mov [r15 + rcx*8], rax
    inc ecx
    cmp ecx, 8
    jb 1b

.Lst_inner_next:
    inc r13
    jmp .Lst_inner

.Lst_outer_next:
    inc r12
    jmp .Lst_outer

.Lst_done:
    EPILOGUE

# ---------------- Formatting Utilities ----------------

# insights_format_size(sb, bytes)
FN insights_format_size
    PROLOGUE 32
    mov rbx, rdi                # sb
    mov r12, rsi                # bytes

    mov rax, 1073741824
    cmp r12, rax
    jb .Lfs_check_mb
    xor edx, edx
    mov rax, r12
    mov rcx, 1073741824
    div rcx
    mov [rsp], rax              # whole
    imul rdx, rdx, 10
    mov rax, rdx
    xor edx, edx
    div rcx
    mov [rsp + 8], rax          # decimal

    mov rdi, rbx
    mov rsi, [rsp]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_dot]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_unit_gb]
    call sb_push_cstr
    jmp .Lfs_done

.Lfs_check_mb:
    mov rax, 1048576
    cmp r12, rax
    jb .Lfs_check_kb
    xor edx, edx
    mov rax, r12
    mov rcx, 1048576
    div rcx
    mov [rsp], rax
    imul rdx, rdx, 10
    mov rax, rdx
    xor edx, edx
    div rcx
    mov [rsp + 8], rax

    mov rdi, rbx
    mov rsi, [rsp]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_dot]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_unit_mb]
    call sb_push_cstr
    jmp .Lfs_done

.Lfs_check_kb:
    cmp r12, 1024
    jb .Lfs_bytes
    xor edx, edx
    mov rax, r12
    mov ecx, 1024
    div rcx
    mov [rsp], rax
    imul rdx, rdx, 10
    mov rax, rdx
    xor edx, edx
    div rcx
    mov [rsp + 8], rax

    mov rdi, rbx
    mov rsi, [rsp]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_dot]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rsp + 8]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_unit_kb]
    call sb_push_cstr
    jmp .Lfs_done

.Lfs_bytes:
    mov rdi, rbx
    mov rsi, r12
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_unit_b]
    call sb_push_cstr

.Lfs_done:
    EPILOGUE

# insights_format_timestamp(sb, ts_seconds) -> formats "YYYY-MM-DD HH:MM:SS"
FN insights_format_timestamp
    PROLOGUE 64
    mov rbx, rdi                # sb
    mov r12, rsi                # ts

    xor edx, edx
    mov rax, r12
    mov ecx, 86400
    div rcx
    mov [rsp], rax              # days since epoch
    mov [rsp + 8], rdx          # sec of day

    xor edx, edx
    mov rax, [rsp + 8]
    mov ecx, 3600
    div rcx
    mov [rsp + 16], rax         # hours
    mov rax, rdx
    xor edx, edx
    mov ecx, 60
    div rcx
    mov [rsp + 24], rax         # minutes
    mov [rsp + 32], rdx         # seconds

    mov rax, [rsp]
    add rax, 719468
    mov [rsp + 40], rax         # days_shifted

    xor edx, edx
    mov rcx, 146097
    div rcx
    mov r13, rax                # era
    mov r14, rdx                # doe

    mov rax, r14
    xor edx, edx
    mov ecx, 1460
    div rcx
    mov r8, rax

    mov rax, r14
    xor edx, edx
    mov ecx, 36524
    div rcx
    mov r9, rax

    mov rax, r14
    xor edx, edx
    mov ecx, 146096
    div rcx
    mov r10, rax

    mov rax, r14
    sub rax, r8
    add rax, r9
    sub rax, r10
    xor edx, edx
    mov ecx, 365
    div rcx
    mov r15, rax                # yoe

    imul rax, r13, 400
    add rax, r15
    mov [rsp + 48], rax         # y

    imul rax, r15, 365
    mov rcx, r15
    shr rcx, 2
    add rax, rcx
    mov rcx, r15
    xor edx, edx
    push rax
    mov rax, rcx
    mov ecx, 100
    div rcx
    mov rcx, rax
    pop rax
    sub rax, rcx
    mov rcx, r14
    sub rcx, rax                # rcx = doy

    imul rax, rcx, 5
    add rax, 2
    xor edx, edx
    mov esi, 153
    div rsi
    mov r8, rax                 # mp

    imul rax, r8, 153
    add rax, 2
    xor edx, edx
    mov esi, 5
    div rsi
    mov r9, rcx
    sub r9, rax
    inc r9                      # r9 = day

    cmp r8, 10
    jae 1f
    lea rax, [r8 + 3]
    jmp 2f
1:  lea rax, [r8 - 9]
2:  mov r10, rax                # r10 = month

    cmp r10, 2
    ja 3f
    inc qword ptr [rsp + 48]
3:
    mov rdi, rbx
    mov rsi, [rsp + 48]
    call sb_push_u64
    mov rdi, rbx
    mov esi, '-'
    call sb_push_byte

    cmp r10, 10
    jae 4f
    mov rdi, rbx
    mov esi, '0'
    call sb_push_byte
4:  mov rdi, rbx
    mov rsi, r10
    call sb_push_u64
    mov rdi, rbx
    mov esi, '-'
    call sb_push_byte

    cmp r9, 10
    jae 5f
    mov rdi, rbx
    mov esi, '0'
    call sb_push_byte
5:  mov rdi, rbx
    mov rsi, r9
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte

    mov rax, [rsp + 16]
    cmp rax, 10
    jae 6f
    mov rdi, rbx
    mov esi, '0'
    call sb_push_byte
6:  mov rdi, rbx
    mov rsi, [rsp + 16]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ':'
    call sb_push_byte

    mov rax, [rsp + 24]
    cmp rax, 10
    jae 7f
    mov rdi, rbx
    mov esi, '0'
    call sb_push_byte
7:  mov rdi, rbx
    mov rsi, [rsp + 24]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ':'
    call sb_push_byte

    mov rax, [rsp + 32]
    cmp rax, 10
    jae 8f
    mov rdi, rbx
    mov esi, '0'
    call sb_push_byte
8:  mov rdi, rbx
    mov rsi, [rsp + 32]
    call sb_push_u64

    EPILOGUE

# ---------------- File Explorer Tooltip & Hover Integration ----------------

.section .rodata
.Ltip_file_prefix:  .asciz "File: "
.Ltip_folder_prefix:.asciz "Folder: "
.Ltip_dot_sep:      .asciz "  \302\267  "
.Ltip_open_paren:   .asciz " ("
.Ltip_close_paren:  .asciz ")"
.Ltip_lines_suf:    .asciz " lines ("
.Ltip_code_suf:     .asciz " code, "
.Ltip_comm_suf:     .asciz " comment, "
.Ltip_blank_suf:    .asciz " blank)"
.Ltip_bin_file:     .asciz "Binary ("
.Ltip_empty_folder: .asciz "Empty"
.Ltip_files_suf_cnt:.asciz " files"
.Ltip_file_suf_cnt: .asciz " file"
.Ltip_comma_space:  .asciz ", "
.Ltip_folders_suf:  .asciz " folders"
.Ltip_folder_suf:   .asciz " folder"

.text

# dir_count_cb(ctx, name, is_dir)
FN dir_count_cb
    PROLOGUE 32
    mov [rsp], rdi              # abs_parent
    mov [rsp + 8], rsi          # name
    mov [rsp + 16], edx         # is_dir

    # Skip hidden entries (starting with '.')
    mov rax, [rsp + 8]
    cmp byte ptr [rax], '.'
    je .Ldccb_ret

    # Check default exclusions
    lea r12, [rip + default_exclusions]
1:  mov rsi, [r12]
    test rsi, rsi
    jz .Ldccb_check_type
    mov rdi, [rsp + 8]
    call strcmp_eq
    test eax, eax
    jnz .Ldccb_ret
    add r12, 8
    jmp 1b

.Ldccb_check_type:
    cmp dword ptr [rsp + 16], 0
    je .Ldccb_is_file

    # Directory
    inc qword ptr [rip + dir_count_dirs]

    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call path_join
    mov r12, rax

    mov rdi, r12
    call insights_walk_dir_count

    mov rdi, r12
    call mem_free
    jmp .Ldccb_ret

.Ldccb_is_file:
    inc qword ptr [rip + dir_count_files]

.Ldccb_ret:
    EPILOGUE

# insights_walk_dir_count(abs_path)
FN insights_walk_dir_count
    PROLOGUE 16
    mov [rsp], rdi

    mov eax, [rip + dir_count_depth]
    cmp eax, 16
    jae .Lwdc_done
    inc dword ptr [rip + dir_count_depth]

    mov rdi, [rsp]
    lea rsi, [rip + dir_count_cb]
    mov rdx, [rsp]
    call dir_each

    dec dword ptr [rip + dir_count_depth]
.Lwdc_done:
    EPILOGUE

# insights_count_dir_contents(abs_path) -> rax: files, rdx: dirs
FN insights_count_dir_contents
    PROLOGUE 16
    mov [rsp], rdi              # abs_path

    # Check cache
    lea rdi, [rip + dir_cache_path]
    mov rsi, [rsp]
    call strcmp_eq
    test eax, eax
    jz .Lcdc_miss

    call time_ms
    sub rax, [rip + dir_cache_time]
    cmp rax, 2000
    jae .Lcdc_miss

    mov rax, [rip + dir_cache_files]
    mov rdx, [rip + dir_cache_dirs]
    EPILOGUE

.Lcdc_miss:
    # Copy path to dir_cache_path
    mov rdi, [rsp]
    call strlen
    mov rcx, rax
    cmp rcx, 1023
    jbe 1f
    mov rcx, 1023
1:  lea rdi, [rip + dir_cache_path]
    mov rsi, [rsp]
    mov r8, rcx
2:  test r8, r8
    jz 3f
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec r8
    jmp 2b
3:  mov byte ptr [rdi], 0

    mov qword ptr [rip + dir_count_files], 0
    mov qword ptr [rip + dir_count_dirs], 0
    mov dword ptr [rip + dir_count_depth], 0

    mov rdi, [rsp]
    call insights_walk_dir_count

    call time_ms
    mov [rip + dir_cache_time], rax
    mov rax, [rip + dir_count_files]
    mov [rip + dir_cache_files], rax
    mov rdx, [rip + dir_count_dirs]
    mov [rip + dir_cache_dirs], rdx
    EPILOGUE

# insights_explorer_hover(node, id, x, y_bottom, w, flags)
FN insights_explorer_hover
    PROLOGUE 48
    mov [rsp], rdi              # node
    mov [rsp + 8], esi          # id
    mov [rsp + 16], edx         # x
    mov [rsp + 24], ecx         # y_bottom
    mov [rsp + 32], r8d         # w
    mov [rsp + 40], r9d         # flags

    cmp dword ptr [rip + cfg_tooltips], 0
    je .Leh_done

    mov rbx, rdi
    test rbx, rbx
    jz .Leh_done

    mov r12, [rbx + 8]          # N_path (offset 8)
    test r12, r12
    jz .Leh_done

    lea rdi, [rip + insights_sb]
    call sb_clear

    cmp dword ptr [rbx + 48], 0 # N_dir (offset 48)
    jne .Leh_dir

    # File hover: scan or lookup file
    mov rdi, r12
    mov rsi, r12
    call insights_scan_file
    test rax, rax
    jz .Leh_done
    mov r13, rax                # IF*

    # File: <name>
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_file_prefix]
    call sb_push_cstr
    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_name]
    call sb_push_cstr

    # Dot separator
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_dot_sep]
    call sb_push_cstr

    # Binary or Language Type
    cmp dword ptr [r13 + IF_is_binary], 0
    jne .Leh_file_bin

    # Language Type
    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_type]
    call sb_push_cstr
    jmp .Leh_file_size

.Leh_file_bin:
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_bin_file]
    call sb_push_cstr
    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_type]
    call sb_push_cstr
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_close_paren]
    call sb_push_cstr

.Leh_file_size:
    # Dot separator
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_dot_sep]
    call sb_push_cstr

    # Formatted Size
    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_size]
    call insights_format_size

    # Size in bytes: (X bytes)
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_open_paren]
    call sb_push_cstr
    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_size]
    call sb_push_u64
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Lstr_bytes]
    call sb_push_cstr
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_close_paren]
    call sb_push_cstr

    # Lines for text file: "  ·  X lines (Y code, Z comment, W blank)"
    cmp dword ptr [r13 + IF_is_binary], 0
    jne .Leh_file_mod

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_dot_sep]
    call sb_push_cstr

    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_tot_lines]
    call sb_push_u64

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_lines_suf]
    call sb_push_cstr

    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_code_lines]
    call sb_push_u64

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_code_suf]
    call sb_push_cstr

    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_comm_lines]
    call sb_push_u64

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_comm_suf]
    call sb_push_cstr

    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_blank_lines]
    call sb_push_u64

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_blank_suf]
    call sb_push_cstr

.Leh_file_mod:
    # Dot separator & Modified timestamp
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_dot_sep]
    call sb_push_cstr

    lea rdi, [rip + insights_sb]
    mov rsi, [r13 + IF_mtime]
    call insights_format_timestamp
    jmp .Leh_show_tip

.Leh_dir:
    # Folder hover tooltip: show folder name, files count, and folders count if present
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_folder_prefix]
    call sb_push_cstr
    lea rdi, [rip + insights_sb]
    mov rsi, [rbx]              # N_name (offset 0)
    call sb_push_cstr

    # Count contents of folder
    mov rdi, r12                # N_path (offset 8)
    call insights_count_dir_contents
    mov r14, rax                # files count
    mov r15, rdx                # dirs count

    # Dot separator
    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_dot_sep]
    call sb_push_cstr

    # Check if empty (both files and dirs are 0)
    mov rax, r14
    or rax, r15
    jnz .Leh_dir_has_content

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_empty_folder]
    call sb_push_cstr
    jmp .Leh_show_tip

.Leh_dir_has_content:
    # Files count: X file / X files
    lea rdi, [rip + insights_sb]
    mov rsi, r14
    call sb_push_u64

    lea rdi, [rip + insights_sb]
    cmp r14, 1
    je 1f
    lea rsi, [rip + .Ltip_files_suf_cnt]   # " files"
    jmp 2f
1:  lea rsi, [rip + .Ltip_file_suf_cnt]    # " file"
2:  call sb_push_cstr

    # Folders count if dirs > 0: ", Y folder" / ", Y folders"
    test r15, r15
    jz .Leh_show_tip

    lea rdi, [rip + insights_sb]
    lea rsi, [rip + .Ltip_comma_space]     # ", "
    call sb_push_cstr

    lea rdi, [rip + insights_sb]
    mov rsi, r15
    call sb_push_u64

    lea rdi, [rip + insights_sb]
    cmp r15, 1
    je 3f
    lea rsi, [rip + .Ltip_folders_suf]     # " folders"
    jmp 4f
3:  lea rsi, [rip + .Ltip_folder_suf]      # " folder"
4:  call sb_push_cstr
    jmp .Leh_show_tip

.Leh_show_tip:
    lea rdi, [rip + insights_sb]
    xor esi, esi
    call sb_push_byte

    # Call tip_note_text(id, x, y_bottom, w, flags, cstr)
    mov edi, [rsp + 8]          # id
    mov esi, [rsp + 16]         # x
    mov edx, [rsp + 24]         # y_bottom
    mov ecx, [rsp + 32]         # w
    mov r8d, [rsp + 40]         # flags
    mov r9, [rip + insights_sb + SB_ptr]
    call tip_note_text

.Leh_done:
    mov eax, [rsp + 40]
    EPILOGUE

# ---------------- Report Generation ----------------

# insights_generate_report(target_path, sb)
FN insights_generate_report
    PROLOGUE 48
    mov [rsp], rdi              # target_path
    mov [rsp + 8], rsi          # sb

    # Scan project/folder
    mov rdi, [rsp]
    call insights_scan_project

    mov rbx, [rsp + 8]          # sb

    # Title
    mov rdi, rbx
    lea rsi, [rip + .Lstr_title]
    call sb_push_cstr

    # Section 1: Project Overview
    mov rdi, rbx
    lea rsi, [rip + .Lstr_sec_overview]
    call sb_push_cstr

    # Root Path
    mov rdi, rbx
    lea rsi, [rip + .Lstr_root_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rsp]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Total Files (Text / Binary)
    mov rdi, rbx
    lea rsi, [rip + .Lstr_files_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_files]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_text_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_text_files]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_bin_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_bin_files]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Ltip_close_paren]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Total Directories
    mov rdi, rbx
    lea rsi, [rip + .Lstr_dirs_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_dirs]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Total Storage Size
    mov rdi, rbx
    lea rsi, [rip + .Lstr_size_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_size]
    call insights_format_size
    mov rdi, rbx
    lea rsi, [rip + .Ltip_open_paren]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_size]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_bytes]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Ltip_close_paren]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Total Lines
    mov rdi, rbx
    lea rsi, [rip + .Lstr_tot_lines_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_tot_lines]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Code Lines
    mov rdi, rbx
    lea rsi, [rip + .Lstr_code_lines_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_code_lines]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Comment Lines
    mov rdi, rbx
    lea rsi, [rip + .Lstr_comm_lines_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_comm_lines]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Blank Lines
    mov rdi, rbx
    lea rsi, [rip + .Lstr_blank_lines_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_blank_lines]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr

    # Excluded Items Summary
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_excluded_dirs]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_dirs_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_excluded_files]
    call sb_push_u64
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_files_lbl]
    call sb_push_cstr
    mov rdi, rbx
    mov rsi, [rip + insights_stats + IS_excluded_size]
    call insights_format_size
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_bytes_lbl]
    call sb_push_cstr

    # Section 2: File Type Distribution Table
    mov rdi, rbx
    lea rsi, [rip + .Lstr_sec_dist]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_dist_hdr]
    call sb_push_cstr

    mov r12, [rip + insights_types + VEC_ptr]
    mov r13, [rip + insights_types + VEC_len]
    xor r14, r14
1:  cmp r14, r13
    jae .Lgr_files_sec
    imul rax, r14, IT_SIZE
    lea r15, [r12 + rax]
    inc r14

    # Row: | Type | Ext | Files | Size | Code | Comm | Blank | % Code |
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte

    mov rdi, rbx
    mov rsi, [r15 + IT_name]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_space]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Ext
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rax, [r15 + IT_ext]
    test rax, rax
    jz 2f
    mov rdi, rbx
    mov esi, '.'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IT_ext]
    call sb_push_cstr
    jmp 3f
2:  mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
3:  mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Files
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IT_files]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Size
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IT_size]
    call insights_format_size
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Code Lines
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IT_code_lines]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Comment Lines
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IT_comm_lines]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Blank Lines
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IT_blank_lines]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # % Code
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rax, [rip + insights_stats + IS_code_lines]
    test rax, rax
    jz 4f
    mov rax, [r15 + IT_code_lines]
    imul rax, rax, 100
    xor edx, edx
    div qword ptr [rip + insights_stats + IS_code_lines]
    mov rdi, rbx
    mov rsi, rax
    call sb_push_u64
    mov rdi, rbx
    mov esi, '%'
    call sb_push_byte
    jmp 5f
4:  mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
5:  mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr
    jmp 1b

.Lgr_files_sec:
    # Section 3: Largest Files
    mov rdi, rbx
    lea rsi, [rip + .Lstr_sec_large_f]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_large_f_hdr]
    call sb_push_cstr

    # Display Top 15 largest files
    mov r12, [rip + insights_files + VEC_ptr]
    mov r13, [rip + insights_files + VEC_len]
    cmp r13, 15
    jbe 6f
    mov r13, 15
6:  xor r14, r14                # rank
7:  cmp r14, r13
    jae .Lgr_dirs_sec
    inc r14
    mov rax, r14
    dec rax
    imul rax, rax, 16
    mov rcx, [r12 + rax + 8]    # cache_idx
    imul rcx, rcx, IF_SIZE
    mov r15, [rip + insights_cache + VEC_ptr]
    add r15, rcx                # r15 = IF*

    # Row: | # | Path | Size | Lines | Type |
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r14
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Path
    mov rdi, rbx
    lea rsi, [rip + .Lstr_space]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IF_relpath]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Size
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IF_size]
    call insights_format_size
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Lines
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    cmp dword ptr [r15 + IF_is_binary], 0
    jne 8f
    mov rdi, rbx
    mov rsi, [r15 + IF_tot_lines]
    call sb_push_u64
    jmp 9f
8:  mov rdi, rbx
    mov esi, '-'
    call sb_push_byte
9:  mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Type
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + IF_type]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr
    jmp 7b

.Lgr_dirs_sec:
    # Section 4: Largest Directories
    mov rdi, rbx
    lea rsi, [rip + .Lstr_sec_large_d]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_large_d_hdr]
    call sb_push_cstr

    # Display Top 10 largest directories
    mov r12, [rip + insights_dirs + VEC_ptr]
    mov r13, [rip + insights_dirs + VEC_len]
    cmp r13, 10
    jbe 10f
    mov r13, 10
10: xor r14, r14                # rank
11: cmp r14, r13
    jae .Lgr_excl_sec
    inc r14
    mov rax, r14
    dec rax
    imul rax, rax, ID_SIZE
    lea r15, [r12 + rax]        # r15 = ID*

    # Row: | # | Directory Path | Total Size | Files |
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, r14
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Path
    mov rdi, rbx
    lea rsi, [rip + .Lstr_space]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + ID_path]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Size
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + ID_size]
    call insights_format_size
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte

    # Files
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [r15 + ID_files]
    call sb_push_u64
    mov rdi, rbx
    mov esi, ' '
    call sb_push_byte
    mov rdi, rbx
    mov esi, '|'
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr
    jmp 11b

.Lgr_excl_sec:
    # Section 5: Exclusion Rules
    mov rdi, rbx
    lea rsi, [rip + .Lstr_sec_excl]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_def]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_git]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_hidden]
    call sb_push_cstr
    mov rdi, rbx
    lea rsi, [rip + .Lstr_excl_conf]
    call sb_push_cstr

    mov rax, [rip + cfg_insights_exclude]
    test rax, rax
    jz 10f
    mov rdi, rax
    call strlen
    test rax, rax
    jz 10f
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    mov rsi, [rip + cfg_insights_exclude]
    call sb_push_cstr
    mov rdi, rbx
    mov esi, '`'
    call sb_push_byte
    mov rdi, rbx
    lea rsi, [rip + .Lstr_newline]
    call sb_push_cstr
    jmp .Lgr_done
10: mov rdi, rbx
    lea rsi, [rip + .Lstr_none]
    call sb_push_cstr

.Lgr_done:
    EPILOGUE

# ---------------- Interactive Commands ----------------

# cmd_codebase_insights(): command palette command
FN cmd_codebase_insights
    PROLOGUE 32
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + .Lstr_dot]
1:  mov [rsp], rdi

    lea rdi, [rip + insights_sb]
    call sb_clear
    mov rdi, [rsp]
    lea rsi, [rip + insights_sb]
    call insights_generate_report

    call doc_new
    mov rbx, rax

    lea rax, [rip + .Lstr_doc_title]
    mov [rbx + DOC_name], rax
    or dword ptr [rbx + DOC_flags], DF_READONLY

    mov rdi, rbx
    mov rsi, DL_NAMED
    lea rdx, [rip + .Lstr_markdown_lang]
    call doc_language_set

    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + insights_sb + SB_ptr]
    mov rcx, [rip + insights_sb + SB_len]
    xor r8d, r8d
    call doc_insert

    mov rdi, rbx
    mov esi, TAB_DOC
    call app_add_tab

    EPILOGUE

# cmd_codebase_insights_target(): context menu command for selected folder/file
FN cmd_codebase_insights_target
    PROLOGUE 32
    mov rdi, [rip + g_explorer_target]
    test rdi, rdi
    jnz 1f
    mov rdi, [rip + g_project]
    test rdi, rdi
    jnz 1f
    lea rdi, [rip + .Lstr_dot]
1:  mov [rsp], rdi

    lea rdi, [rip + insights_sb]
    call sb_clear
    mov rdi, [rsp]
    lea rsi, [rip + insights_sb]
    call insights_generate_report

    call doc_new
    mov rbx, rax

    lea rax, [rip + .Lstr_doc_title]
    mov [rbx + DOC_name], rax
    or dword ptr [rbx + DOC_flags], DF_READONLY

    mov rdi, rbx
    mov rsi, DL_NAMED
    lea rdx, [rip + .Lstr_markdown_lang]
    call doc_language_set

    mov rdi, rbx
    xor esi, esi
    mov rdx, [rip + insights_sb + SB_ptr]
    mov rcx, [rip + insights_sb + SB_len]
    xor r8d, r8d
    call doc_insert

    mov rdi, rbx
    mov esi, TAB_DOC
    call app_add_tab

    EPILOGUE
