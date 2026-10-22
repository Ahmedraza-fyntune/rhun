# formatters.s: built-in formatters for JSON, XML, SQL, PHP, and INI
.include "rhun.inc"

.equ FMT_JSON, 1
.equ FMT_XML,  2
.equ FMT_SQL,  3
.equ FMT_PHP,  4
.equ FMT_INI,  5

.section .rdata,"dr"
.Lfmt_s_json:       .asciz "JSON"
.Lfmt_s_xml:        .asciz "XML"
.Lfmt_s_html:       .asciz "HTML"
.Lfmt_s_svg:        .asciz "SVG"
.Lfmt_s_sql:        .asciz "SQL"
.Lfmt_s_php:        .asciz "PHP"
.Lfmt_s_ini:        .asciz "INI"
.Lfmt_s_properties: .asciz "Properties"

.Lext_json:         .asciz "json"
.Lext_jsonc:        .asciz "jsonc"
.Lext_json5:        .asciz "json5"
.Lext_xml:          .asciz "xml"
.Lext_svg:          .asciz "svg"
.Lext_html:         .asciz "html"
.Lext_htm:          .asciz "htm"
.Lext_xaml:         .asciz "xaml"
.Lext_plist:        .asciz "plist"
.Lext_xsd:          .asciz "xsd"
.Lext_xsl:          .asciz "xsl"
.Lext_sql:          .asciz "sql"
.Lext_psql:         .asciz "psql"
.Lext_ddl:          .asciz "ddl"
.Lext_php:          .asciz "php"
.Lext_phtml:        .asciz "phtml"
.Lext_ini:          .asciz "ini"
.Lext_cfg:          .asciz "cfg"
.Lext_conf:         .asciz "conf"
.Lext_theme:        .asciz "theme"

.Lt_already:        .asciz "Already formatted"
.Lt_ok_json:        .asciz "Formatted JSON"
.Lt_ok_xml:         .asciz "Formatted XML"
.Lt_ok_sql:         .asciz "Formatted SQL"
.Lt_ok_php:         .asciz "Formatted PHP"
.Lt_ok_ini:         .asciz "Formatted INI"
.Lt_err_json:       .asciz "JSON formatting failed: syntax error"
.Lt_err_xml:        .asciz "XML formatting failed: syntax error"
.Lt_err_nodoc:      .asciz "No editable document"

# SQL Keywords for upper-casing and line breaks
.Lsql_select:       .asciz "SELECT"
.Lsql_from:         .asciz "FROM"
.Lsql_where:        .asciz "WHERE"
.Lsql_group:        .asciz "GROUP"
.Lsql_order:        .asciz "ORDER"
.Lsql_having:       .asciz "HAVING"
.Lsql_limit:        .asciz "LIMIT"
.Lsql_offset:       .asciz "OFFSET"
.Lsql_join:         .asciz "JOIN"
.Lsql_left:         .asciz "LEFT"
.Lsql_right:        .asciz "RIGHT"
.Lsql_inner:        .asciz "INNER"
.Lsql_outer:        .asciz "OUTER"
.Lsql_cross:        .asciz "CROSS"
.Lsql_union:        .asciz "UNION"
.Lsql_insert:       .asciz "INSERT"
.Lsql_into:         .asciz "INTO"
.Lsql_values:       .asciz "VALUES"
.Lsql_update:       .asciz "UPDATE"
.Lsql_set:          .asciz "SET"
.Lsql_delete:       .asciz "DELETE"
.Lsql_create:       .asciz "CREATE"
.Lsql_alter:        .asciz "ALTER"
.Lsql_drop:         .asciz "DROP"
.Lsql_table:        .asciz "TABLE"
.Lsql_and:          .asciz "AND"
.Lsql_or:           .asciz "OR"
.Lsql_on:           .asciz "ON"
.Lsql_as:           .asciz "AS"
.Lsql_in:           .asciz "IN"
.Lsql_is:           .asciz "IS"
.Lsql_not:          .asciz "NOT"
.Lsql_null:         .asciz "NULL"
.Lsql_by:           .asciz "BY"
.Lsql_distinct:     .asciz "DISTINCT"
.Lsql_case:         .asciz "CASE"
.Lsql_when:         .asciz "WHEN"
.Lsql_then:         .asciz "THEN"
.Lsql_else:         .asciz "ELSE"
.Lsql_end_kw:       .asciz "END"
.Lsql_asc:          .asciz "ASC"
.Lsql_desc:         .asciz "DESC"

.Lini_eq_str:       .asciz " = "

.text

# -------------------------------------------------------------
# fmt_push_indent(sb, depth, tab_width, insert_spaces)
# -------------------------------------------------------------
FN fmt_push_indent
    PROLOGUE 16
    test esi, esi
    jle .Lpi_done
    mov r12, rdi                # sb
    mov r13d, esi               # depth
    mov r14d, edx               # tab_width
    mov r15d, ecx               # insert_spaces
    test r15d, r15d
    jz .Lpi_tabs
    imul r13d, r14d             # total spaces = depth * tab_width
.Lpi_sp_loop:
    test r13d, r13d
    jle .Lpi_done
    mov rdi, r12
    mov esi, ' '
    call sb_push_byte
    dec r13d
    jmp .Lpi_sp_loop
.Lpi_tabs:
    test r13d, r13d
    jle .Lpi_done
    mov rdi, r12
    mov esi, 9                  # '\t'
    call sb_push_byte
    dec r13d
    jmp .Lpi_tabs
.Lpi_done:
    EPILOGUE

# -------------------------------------------------------------
# fmt_is_space(char in edi) -> eax (1 if space/tab/cr/lf, 0 otherwise)
# -------------------------------------------------------------
FN fmt_is_space
    cmp edi, ' '
    je 1f
    cmp edi, 9
    je 1f
    cmp edi, 10
    je 1f
    cmp edi, 13
    je 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

# -------------------------------------------------------------
# fmt_is_ident(char in edi) -> eax (1 if [a-zA-Z0-9_$], 0 otherwise)
# -------------------------------------------------------------
FN fmt_is_ident
    cmp edi, 'a'
    jb 1f
    cmp edi, 'z'
    jbe 9f
1:  cmp edi, 'A'
    jb 2f
    cmp edi, 'Z'
    jbe 9f
2:  cmp edi, '0'
    jb 3f
    cmp edi, '9'
    jbe 9f
3:  cmp edi, '_'
    je 9f
    cmp edi, '$'
    je 9f
    xor eax, eax
    ret
9:  mov eax, 1
    ret

# -------------------------------------------------------------
# fmt_doc_options() -> eax tab_width, edx insert_spaces
# -------------------------------------------------------------
FN fmt_doc_options
    mov eax, [rip + g_tab_width]
    test eax, eax
    jnz 1f
    mov eax, [rip + cfg_tab_width]
    test eax, eax
    jnz 1f
    mov eax, 4
1:  mov edx, [rip + g_insert_spaces]
    ret

# =============================================================
# JSON FORMATTER
# format_json(src, len, sb, tab_width, insert_spaces) -> eax 1 on ok, 0 on err
# =============================================================
FN format_json
    PROLOGUE 32
    mov r12, rdi                # src
    mov r13, rsi                # len
    mov r14, rdx                # sb
    mov [rsp], ecx              # tab_width
    mov [rsp + 4], r8d          # insert_spaces
    mov dword ptr [rsp + 8], 0  # depth
    xor r15, r15                # src index

.Ljson_loop:
    cmp r15, r13
    jae .Ljson_end
    movzx ebx, byte ptr [r12 + r15]

    # Check for whitespace
    mov edi, ebx
    call fmt_is_space
    test eax, eax
    jz .Ljson_not_space
    inc r15
    jmp .Ljson_loop

.Ljson_not_space:
    # String literal?
    cmp bl, '"'
    jne .Ljson_not_string
    mov rdi, r14
    mov esi, '"'
    call sb_push_byte
    inc r15
.Ljson_str_loop:
    cmp r15, r13
    jae .Ljson_err
    movzx ebx, byte ptr [r12 + r15]
    inc r15
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    cmp bl, '\\'
    jne .Ljson_str_quote
    # Escaped next char
    cmp r15, r13
    jae .Ljson_err
    movzx ebx, byte ptr [r12 + r15]
    inc r15
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    jmp .Ljson_str_loop
.Ljson_str_quote:
    cmp bl, '"'
    jne .Ljson_str_loop
    jmp .Ljson_loop

.Ljson_not_string:
    # Open brace '{' or bracket '['
    cmp bl, '{'
    je .Ljson_open
    cmp bl, '['
    jne .Ljson_not_open
.Ljson_open:
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    inc r15
    # Peek next non-whitespace char for empty container "{}" or "[]"
    mov rcx, r15
.Ljson_peek_empty:
    cmp rcx, r13
    jae .Ljson_open_expand
    movzx edi, byte ptr [r12 + rcx]
    call fmt_is_space
    test eax, eax
    jz .Ljson_peek_check
    inc rcx
    jmp .Ljson_peek_empty
.Ljson_peek_check:
    cmp bl, '{'
    jne 1f
    cmp byte ptr [r12 + rcx], '}'
    jne .Ljson_open_expand
    mov rdi, r14
    mov esi, '}'
    call sb_push_byte
    lea r15, [rcx + 1]
    jmp .Ljson_loop
1:  cmp bl, '['
    jne .Ljson_open_expand
    cmp byte ptr [r12 + rcx], ']'
    jne .Ljson_open_expand
    mov rdi, r14
    mov esi, ']'
    call sb_push_byte
    lea r15, [rcx + 1]
    jmp .Ljson_loop

.Ljson_open_expand:
    mov rdi, r14
    mov esi, 10                 # '\n'
    call sb_push_byte
    inc dword ptr [rsp + 8]     # depth++
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    jmp .Ljson_loop

.Ljson_not_open:
    # Close brace '}' or bracket ']'
    cmp bl, '}'
    je .Ljson_close
    cmp bl, ']'
    jne .Ljson_not_close
.Ljson_close:
    mov eax, [rsp + 8]
    test eax, eax
    jle .Ljson_err
    dec dword ptr [rsp + 8]     # depth--
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je 2f
1:  mov rdi, r14
    mov esi, 10
    call sb_push_byte
2:  mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    inc r15
    jmp .Ljson_loop

.Ljson_not_close:
    # Comma ','
    cmp bl, ','
    jne .Ljson_not_comma
    mov rdi, r14
    mov esi, ','
    call sb_push_byte
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    inc r15
    jmp .Ljson_loop

.Ljson_not_comma:
    # Colon ':'
    cmp bl, ':'
    jne .Ljson_not_colon
    mov rdi, r14
    mov esi, ':'
    call sb_push_byte
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    inc r15
    jmp .Ljson_loop

.Ljson_not_colon:
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    inc r15
    jmp .Ljson_loop

.Ljson_end:
    cmp dword ptr [rsp + 8], 0
    jne .Ljson_err
    mov rax, [r14 + SB_len]
    test rax, rax
    jz .Ljson_ok
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je .Ljson_ok
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
.Ljson_ok:
    mov eax, 1
    EPILOGUE
.Ljson_err:
    xor eax, eax
    EPILOGUE

# =============================================================
# XML FORMATTER
# format_xml(src, len, sb, tab_width, insert_spaces) -> eax 1 on ok, 0 on err
# =============================================================
FN format_xml
    PROLOGUE 48
    mov r12, rdi                # src
    mov r13, rsi                # len
    mov r14, rdx                # sb
    mov [rsp], ecx              # tab_width
    mov [rsp + 4], r8d          # insert_spaces
    mov dword ptr [rsp + 8], 0  # depth
    xor r15, r15                # src index

.Lxml_loop:
    cmp r15, r13
    jae .Lxml_end

    movzx edi, byte ptr [r12 + r15]
    call fmt_is_space
    test eax, eax
    jz .Lxml_has_token
    inc r15
    jmp .Lxml_loop

.Lxml_has_token:
    cmp byte ptr [r12 + r15], '<'
    jne .Lxml_text

    # Comment? <!--
    lea rax, [r15 + 4]
    cmp rax, r13
    ja .Lxml_tag
    cmp byte ptr [r12 + r15 + 1], '!'
    jne .Lxml_tag
    cmp byte ptr [r12 + r15 + 2], '-'
    jne .Lxml_check_cdata
    cmp byte ptr [r12 + r15 + 3], '-'
    jne .Lxml_tag
    call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rbx, r15
.Lxml_comment_scan:
    cmp r15, r13
    jae .Lxml_err
    lea rax, [r15 + 3]
    cmp rax, r13
    ja .Lxml_err
    cmp byte ptr [r12 + r15], '-'
    jne 1f
    cmp byte ptr [r12 + r15 + 1], '-'
    jne 1f
    cmp byte ptr [r12 + r15 + 2], '>'
    je .Lxml_comment_found
1:  inc r15
    jmp .Lxml_comment_scan
.Lxml_comment_found:
    add r15, 3
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lxml_loop

.Lxml_check_cdata:
    # <![CDATA[
    lea rax, [r15 + 9]
    cmp rax, r13
    ja .Lxml_tag
    cmp byte ptr [r12 + r15 + 2], '['
    jne .Lxml_tag
    call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rbx, r15
.Lxml_cdata_scan:
    cmp r15, r13
    jae .Lxml_err
    lea rax, [r15 + 3]
    cmp rax, r13
    ja .Lxml_err
    cmp byte ptr [r12 + r15], ']'
    jne 1f
    cmp byte ptr [r12 + r15 + 1], ']'
    jne 1f
    cmp byte ptr [r12 + r15 + 2], '>'
    je .Lxml_cdata_found
1:  inc r15
    jmp .Lxml_cdata_scan
.Lxml_cdata_found:
    add r15, 3
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lxml_loop

.Lxml_tag:
    # Closing tag </tag> ?
    lea rax, [r15 + 2]
    cmp rax, r13
    ja .Lxml_err
    cmp byte ptr [r12 + r15 + 1], '/'
    jne .Lxml_open_or_pi

    mov rbx, r15
.Lxml_close_scan:
    cmp r15, r13
    jae .Lxml_err
    mov al, [r12 + r15]
    inc r15
    cmp al, '>'
    jne .Lxml_close_scan

    cmp dword ptr [rsp + 8], 0
    jle 1f
    dec dword ptr [rsp + 8]
1:  call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lxml_loop

.Lxml_open_or_pi:
    cmp byte ptr [r12 + r15 + 1], '?'
    je .Lxml_pi
    cmp byte ptr [r12 + r15 + 1], '!'
    je .Lxml_pi
    jmp .Lxml_opening_tag

.Lxml_pi:
    mov rbx, r15
.Lxml_pi_scan:
    cmp r15, r13
    jae .Lxml_err
    mov al, [r12 + r15]
    inc r15
    cmp al, '>'
    jne .Lxml_pi_scan
    call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lxml_loop

.Lxml_opening_tag:
    mov rbx, r15
    xor ecx, ecx
.Lxml_open_scan:
    cmp r15, r13
    jae .Lxml_err
    movzx eax, byte ptr [r12 + r15]
    inc r15
    test ecx, ecx
    jz 1f
    cmp eax, ecx
    jne .Lxml_open_scan
    xor ecx, ecx
    jmp .Lxml_open_scan
1:  cmp eax, '"'
    je 2f
    cmp eax, '\''
    je 2f
    cmp eax, '>'
    je .Lxml_open_found
    jmp .Lxml_open_scan
2:  mov ecx, eax
    jmp .Lxml_open_scan

.Lxml_open_found:
    lea rax, [r15 - 2]
    cmp rax, rbx
    jb .Lxml_regular_open
    cmp byte ptr [r12 + r15 - 2], '/'
    jne .Lxml_regular_open

    # Self closing
    call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lxml_loop

.Lxml_regular_open:
    call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    inc dword ptr [rsp + 8]     # depth++
    jmp .Lxml_loop

.Lxml_text:
    mov [rsp + 16], r15         # text start
.Lxml_text_scan:
    cmp r15, r13
    jae .Lxml_text_done
    cmp byte ptr [r12 + r15], '<'
    je .Lxml_text_done
    inc r15
    jmp .Lxml_text_scan
.Lxml_text_done:
    mov rax, r15
    sub rax, [rsp + 16]
    mov [rsp + 24], rax         # text len

    # Trim leading
.Lxml_tl:
    cmp qword ptr [rsp + 24], 0
    je .Lxml_loop
    mov rax, [rsp + 16]
    movzx edi, byte ptr [r12 + rax]
    call fmt_is_space
    test eax, eax
    jz .Lxml_tr
    inc qword ptr [rsp + 16]
    dec qword ptr [rsp + 24]
    jmp .Lxml_tl

    # Trim trailing
.Lxml_tr:
    cmp qword ptr [rsp + 24], 0
    je .Lxml_loop
    mov rax, [rsp + 16]
    add rax, [rsp + 24]
    dec rax
    movzx edi, byte ptr [r12 + rax]
    call fmt_is_space
    test eax, eax
    jz .Lxml_emit_text
    dec qword ptr [rsp + 24]
    jmp .Lxml_tr

.Lxml_emit_text:
    call .Lxml_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    mov rax, [rsp + 16]
    lea rsi, [r12 + rax]
    mov rdx, [rsp + 24]
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lxml_loop

.Lxml_ensure_nl:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je 1f
    push rdi
    push rsi
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    pop rsi
    pop rdi
1:  ret

.Lxml_end:
    call .Lxml_ensure_nl
    mov eax, 1
    EPILOGUE
.Lxml_err:
    xor eax, eax
    EPILOGUE

# =============================================================
# INI FORMATTER
# format_ini(src, len, sb, tab_width, insert_spaces) -> eax 1 on ok, 0 on err
# =============================================================
FN format_ini
    PROLOGUE 48
    mov r12, rdi                # src
    mov r13, rsi                # len
    mov r14, rdx                # sb
    xor r15, r15                # src index
    mov dword ptr [rsp], 0      # last_was_empty

.Lini_line_loop:
    cmp r15, r13
    jae .Lini_end

    mov rbx, r15                # line start
.Lini_find_eol:
    cmp r15, r13
    jae .Lini_got_eol
    cmp byte ptr [r12 + r15], 10
    je .Lini_got_eol
    inc r15
    jmp .Lini_find_eol

.Lini_got_eol:
    mov [rsp + 8], r15          # line end
    cmp r15, r13
    jae 1f
    inc r15                     # skip '\n'
1:  # Trim CR if present
    mov rax, [rsp + 8]
    cmp rax, rbx
    jbe .Lini_line_empty
    cmp byte ptr [r12 + rax - 1], 13
    jne 2f
    dec qword ptr [rsp + 8]
2:  # Trim leading spaces
    mov rax, [rsp + 8]
    cmp rbx, rax
    jae .Lini_line_empty
    movzx edi, byte ptr [r12 + rbx]
    cmp edi, ' '
    je 3f
    cmp edi, 9
    jne 4f
3:  inc rbx
    jmp 2b
4:  # Trim trailing spaces
    mov rax, [rsp + 8]
    cmp rax, rbx
    jbe .Lini_line_empty
    movzx edi, byte ptr [r12 + rax - 1]
    cmp edi, ' '
    je 5f
    cmp edi, 9
    jne 6f
5:  dec qword ptr [rsp + 8]
    jmp 4b
6:  mov rax, [rsp + 8]
    cmp rbx, rax
    jae .Lini_line_empty

    # Line has content
    movzx eax, byte ptr [r12 + rbx]
    cmp al, ';'
    je .Lini_comment_line
    cmp al, '#'
    je .Lini_comment_line
    cmp al, '['
    je .Lini_section_line

    # Search for '='
    mov rcx, rbx
.Lini_find_eq:
    cmp rcx, [rsp + 8]
    jae .Lini_plain_line
    cmp byte ptr [r12 + rcx], '='
    je .Lini_found_eq
    inc rcx
    jmp .Lini_find_eq

.Lini_found_eq:
    mov r8, rcx                 # eq pos
.Lini_trim_key_trail:
    cmp r8, rbx
    jbe .Lini_key_done
    movzx edi, byte ptr [r12 + r8 - 1]
    cmp edi, ' '
    je 7f
    cmp edi, 9
    jne .Lini_key_done
7:  dec r8
    jmp .Lini_trim_key_trail
.Lini_key_done:
    lea r9, [rcx + 1]           # val start
.Lini_trim_val_lead:
    cmp r9, [rsp + 8]
    jae .Lini_val_lead_done
    movzx edi, byte ptr [r12 + r9]
    cmp edi, ' '
    je 8f
    cmp edi, 9
    jne .Lini_val_lead_done
8:  inc r9
    jmp .Lini_trim_val_lead
.Lini_val_lead_done:
    mov dword ptr [rsp], 0
    mov [rsp + 16], r9          # val start
    mov [rsp + 24], r8          # key end

    # Emit key
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, [rsp + 24]
    sub rdx, rbx
    call sb_push

    # Emit " = "
    mov rdi, r14
    lea rsi, [rip + .Lini_eq_str]
    call sb_push_cstr

    # Emit value
    mov rdi, r14
    mov rax, [rsp + 16]
    lea rsi, [r12 + rax]
    mov rdx, [rsp + 8]
    sub rdx, rax
    call sb_push

    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lini_line_loop

.Lini_section_line:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    cmp dword ptr [rsp], 1
    je 1f
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
1:  mov dword ptr [rsp], 0
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, [rsp + 8]
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lini_line_loop

.Lini_comment_line:
.Lini_plain_line:
    mov dword ptr [rsp], 0
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, [rsp + 8]
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lini_line_loop

.Lini_line_empty:
    cmp dword ptr [rsp], 1
    je .Lini_line_loop
    mov rax, [r14 + SB_len]
    test rax, rax
    jz .Lini_line_loop
    mov dword ptr [rsp], 1
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lini_line_loop

.Lini_end:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz .Lini_ok
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je .Lini_ok
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
.Lini_ok:
    mov eax, 1
    EPILOGUE

# =============================================================
# SQL FORMATTER
# format_sql(src, len, sb, tab_width, insert_spaces) -> eax 1 on ok, 0 on err
# =============================================================
FN format_sql
    PROLOGUE 48
    mov r12, rdi                # src
    mov r13, rsi                # len
    mov r14, rdx                # sb
    mov [rsp], ecx              # tab_width
    mov [rsp + 4], r8d          # insert_spaces
    mov dword ptr [rsp + 8], 0  # depth
    xor r15, r15                # src index

.Lsql_loop:
    cmp r15, r13
    jae .Lsql_finish

    movzx edi, byte ptr [r12 + r15]
    call fmt_is_space
    test eax, eax
    jz .Lsql_has_token
    inc r15
    jmp .Lsql_loop

.Lsql_has_token:
    movzx ebx, byte ptr [r12 + r15]

    # Comment? --
    cmp bl, '-'
    jne .Lsql_check_block_comment
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .Lsql_single_char
    cmp byte ptr [r12 + r15 + 1], '-'
    jne .Lsql_single_char
    call .Lsql_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rbx, r15
.Lsql_lc_scan:
    cmp r15, r13
    jae .Lsql_lc_done
    cmp byte ptr [r12 + r15], 10
    je .Lsql_lc_done
    inc r15
    jmp .Lsql_lc_scan
.Lsql_lc_done:
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    jmp .Lsql_loop

.Lsql_check_block_comment:
    cmp bl, '/'
    jne .Lsql_check_string
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .Lsql_single_char
    cmp byte ptr [r12 + r15 + 1], '*'
    jne .Lsql_single_char
    mov rbx, r15
    add r15, 2
.Lsql_bc_scan:
    cmp r15, r13
    jae .Lsql_bc_done
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .Lsql_bc_done
    cmp byte ptr [r12 + r15], '*'
    jne 1f
    cmp byte ptr [r12 + r15 + 1], '/'
    je .Lsql_bc_found
1:  inc r15
    jmp .Lsql_bc_scan
.Lsql_bc_found:
    add r15, 2
.Lsql_bc_done:
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    jmp .Lsql_loop

.Lsql_check_string:
    cmp bl, '\''
    je .Lsql_string
    cmp bl, '"'
    je .Lsql_string
    jmp .Lsql_check_punct

.Lsql_string:
    call .Lsql_add_space_if_needed
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    inc r15
.Lsql_str_scan:
    cmp r15, r13
    jae .Lsql_loop
    movzx eax, byte ptr [r12 + r15]
    inc r15
    mov rdi, r14
    mov esi, eax
    call sb_push_byte
    cmp al, bl
    jne .Lsql_str_scan
    # Check for escaped quote ''
    cmp r15, r13
    jae .Lsql_loop
    cmp byte ptr [r12 + r15], bl
    jne .Lsql_loop
    inc r15
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    jmp .Lsql_str_scan

.Lsql_check_punct:
    cmp bl, ';'
    jne .Lsql_check_comma
    mov rdi, r14
    mov esi, ';'
    call sb_push_byte
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    inc r15
    jmp .Lsql_loop

.Lsql_check_comma:
    cmp bl, ','
    jne .Lsql_check_paren_open
    mov rdi, r14
    mov esi, ','
    call sb_push_byte
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    mov rdi, r14
    mov esi, [rsp + 8]
    inc esi
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    inc r15
    jmp .Lsql_loop

.Lsql_check_paren_open:
    cmp bl, '('
    jne .Lsql_check_paren_close
    call .Lsql_add_space_if_needed
    mov rdi, r14
    mov esi, '('
    call sb_push_byte
    inc dword ptr [rsp + 8]     # depth++
    inc r15
    jmp .Lsql_loop

.Lsql_check_paren_close:
    cmp bl, ')'
    jne .Lsql_word
    cmp dword ptr [rsp + 8], 0
    jle 1f
    dec dword ptr [rsp + 8]
1:  mov rdi, r14
    mov esi, ')'
    call sb_push_byte
    inc r15
    jmp .Lsql_loop

.Lsql_word:
    mov rbx, r15
.Lsql_word_scan:
    cmp r15, r13
    jae .Lsql_word_done
    movzx edi, byte ptr [r12 + r15]
    call fmt_is_space
    test eax, eax
    jnz .Lsql_word_done
    cmp dil, ','
    je .Lsql_word_done
    cmp dil, ';'
    je .Lsql_word_done
    cmp dil, '('
    je .Lsql_word_done
    cmp dil, ')'
    je .Lsql_word_done
    cmp dil, '\''
    je .Lsql_word_done
    cmp dil, '"'
    je .Lsql_word_done
    inc r15
    jmp .Lsql_word_scan

.Lsql_word_done:
    mov rax, r15
    sub rax, rbx                # word length
    test rax, rax
    jz .Lsql_single_char

    lea rdi, [r12 + rbx]
    mov [rsp + 16], rdi         # word_ptr
    mov [rsp + 24], rax         # word_len

    mov rsi, rax
    call sql_is_clause_keyword
    test eax, eax
    jz .Lsql_check_subclause

    # Clause keyword
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call sql_is_join_kw
    test eax, eax
    jz .Lsql_clause_nl
    call sql_sb_ends_join_mod
    test eax, eax
    jnz .Lsql_clause_same_line
.Lsql_clause_nl:
    call .Lsql_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    jmp .Lsql_clause_emit
.Lsql_clause_same_line:
    call .Lsql_add_space_if_needed
.Lsql_clause_emit:
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, r14
    call sql_push_upper
    jmp .Lsql_loop

.Lsql_check_subclause:
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call sql_is_subclause_keyword
    test eax, eax
    jz .Lsql_check_regular_keyword

    # Subclause keyword (AND, OR)
    call .Lsql_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    inc esi
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, r14
    call sql_push_upper
    jmp .Lsql_loop

.Lsql_check_regular_keyword:
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    call sql_is_other_keyword
    test eax, eax
    jz .Lsql_identifier

    call .Lsql_add_space_if_needed
    mov rdi, [rsp + 16]
    mov rsi, [rsp + 24]
    mov rdx, r14
    call sql_push_upper
    jmp .Lsql_loop

.Lsql_identifier:
    call .Lsql_add_space_if_needed
    mov rdi, r14
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 24]
    call sb_push
    jmp .Lsql_loop

.Lsql_single_char:
    mov rdi, r14
    movzx esi, byte ptr [r12 + r15]
    call sb_push_byte
    inc r15
    jmp .Lsql_loop

.Lsql_add_space_if_needed:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    movzx edx, byte ptr [rcx + rax - 1]
    cmp dl, ' '
    je 1f
    cmp dl, 10
    je 1f
    cmp dl, '('
    je 1f
    push rdi
    push rsi
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    pop rsi
    pop rdi
1:  ret

.Lsql_ensure_nl:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je 1f
    push rdi
    push rsi
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    pop rsi
    pop rdi
1:  ret

.Lsql_finish:
    call .Lsql_ensure_nl
    mov eax, 1
    EPILOGUE

# -------------------------------------------------------------
# sql_is_join_kw(ptr, len) -> eax 1/0
# -------------------------------------------------------------
sql_is_join_kw:
    cmp rsi, 4
    jne 9f
    lea rdx, [rip + .Lsql_join]
    mov rcx, 4
    jmp str_ieq
9:  xor eax, eax
    ret

# -------------------------------------------------------------
# sql_sb_ends_join_mod(sb in r14) -> eax 1/0
# -------------------------------------------------------------
sql_sb_ends_join_mod:
    mov rax, [r14 + SB_len]
    cmp rax, 4
    jb 9f
    mov rcx, [r14 + SB_ptr]
    # Check if ends with ' '
    cmp byte ptr [rcx + rax - 1], ' '
    jne 1f
    dec rax
1:  # Check if ends with LEFT (4)
    cmp rax, 4
    jb 9f
    lea rdi, [rcx + rax - 4]
    mov rsi, 4
    lea rdx, [rip + .Lsql_left]
    mov rcx, 4
    call str_ieq
    test eax, eax; jnz 8f
    # Check if ends with RIGHT (5)
    mov rax, [r14 + SB_len]
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], ' '
    jne 2f
    dec rax
2:  cmp rax, 5
    jb 9f
    lea rdi, [rcx + rax - 5]
    mov rsi, 5
    lea rdx, [rip + .Lsql_right]
    mov rcx, 5
    call str_ieq
    test eax, eax; jnz 8f
    # Check if ends with INNER (5)
    mov rax, [r14 + SB_len]
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], ' '
    jne 3f
    dec rax
3:  cmp rax, 5
    jb 9f
    lea rdi, [rcx + rax - 5]
    mov rsi, 5
    lea rdx, [rip + .Lsql_inner]
    mov rcx, 5
    call str_ieq
    test eax, eax; jnz 8f
    # Check if ends with CROSS (5)
    mov rax, [r14 + SB_len]
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], ' '
    jne 4f
    dec rax
4:  cmp rax, 5
    jb 9f
    lea rdi, [rcx + rax - 5]
    mov rsi, 5
    lea rdx, [rip + .Lsql_cross]
    mov rcx, 5
    call str_ieq
    test eax, eax; jnz 8f
    # Check if ends with OUTER (5)
    mov rax, [r14 + SB_len]
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], ' '
    jne 5f
    dec rax
5:  cmp rax, 5
    jb 9f
    lea rdi, [rcx + rax - 5]
    mov rsi, 5
    lea rdx, [rip + .Lsql_outer]
    mov rcx, 5
    call str_ieq
    test eax, eax; jnz 8f
9:  xor eax, eax
    ret
8:  mov eax, 1
    ret

# -------------------------------------------------------------
# sql_push_upper(src, len, sb)
# -------------------------------------------------------------
sql_push_upper:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor r15, r15
1:  cmp r15, r13
    jae 2f
    movzx esi, byte ptr [r12 + r15]
    cmp sil, 'a'
    jb 3f
    cmp sil, 'z'
    ja 3f
    sub sil, 32
3:  mov rdi, r14
    call sb_push_byte
    inc r15
    jmp 1b
2:  EPILOGUE

# -------------------------------------------------------------
# sql_is_clause_keyword(ptr, len) -> eax 1/0
# -------------------------------------------------------------
sql_is_clause_keyword:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + .Lsql_select]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_from]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_where]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_group]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_order]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_having]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_limit]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_offset]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_join]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_left]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_right]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_inner]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_union]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_insert]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_values]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_update]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_set]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_delete]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_create]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_alter]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_drop]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    xor eax, eax
9:  EPILOGUE

.Lsql_chk_kw:
    push rdi
    call strlen
    mov rsi, rax
    pop rdi
    mov rdx, r12
    mov rcx, r13
    jmp str_ieq

sql_is_subclause_keyword:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + .Lsql_and]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_or]
    call .Lsql_chk_kw
9:  EPILOGUE

sql_is_other_keyword:
    PROLOGUE 16
    mov r12, rdi
    mov r13, rsi
    lea rdi, [rip + .Lsql_by]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_on]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_as]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_in]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_is]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_not]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_null]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_distinct]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_case]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_when]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_then]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_else]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_end_kw]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_asc]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_desc]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_into]
    call .Lsql_chk_kw; test eax, eax; jnz 9f
    lea rdi, [rip + .Lsql_table]
    call .Lsql_chk_kw
9:  EPILOGUE

# =============================================================
# PHP FORMATTER
# format_php(src, len, sb, tab_width, insert_spaces) -> eax 1 on ok, 0 on err
# =============================================================
FN format_php
    PROLOGUE 48
    mov r12, rdi                # src
    mov r13, rsi                # len
    mov r14, rdx                # sb
    mov [rsp], ecx              # tab_width
    mov [rsp + 4], r8d          # insert_spaces
    mov dword ptr [rsp + 8], 0  # depth
    mov dword ptr [rsp + 12], 0 # had_space
    xor r15, r15                # src index

.Lphp_loop:
    cmp r15, r13
    jae .Lphp_end

    # Check for <?php or <?
    cmp byte ptr [r12 + r15], '<'
    jne .Lphp_skip_ws
    lea rax, [r15 + 2]
    cmp rax, r13
    ja .Lphp_skip_ws
    cmp byte ptr [r12 + r15 + 1], '?'
    jne .Lphp_skip_ws
    # Push <?... tag up to space or newline
    mov rbx, r15
.Lphp_tag_scan:
    cmp r15, r13
    jae .Lphp_tag_done
    mov al, [r12 + r15]
    inc r15
    cmp al, 10
    je .Lphp_tag_done
    cmp al, ' '
    je .Lphp_tag_done
    jmp .Lphp_tag_scan
.Lphp_tag_done:
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    call .Lphp_ensure_nl
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_skip_ws:
    movzx edi, byte ptr [r12 + r15]
    call fmt_is_space
    test eax, eax
    jz .Lphp_has_token
    mov dword ptr [rsp + 12], 1 # had whitespace
    inc r15
    jmp .Lphp_loop

.Lphp_has_token:
    movzx ebx, byte ptr [r12 + r15]

    # Comments: // or /*
    cmp bl, '/'
    jne .Lphp_check_hash
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .Lphp_check_ident
    cmp byte ptr [r12 + r15 + 1], '/'
    je .Lphp_lc
    cmp byte ptr [r12 + r15 + 1], '*'
    je .Lphp_bc
    jmp .Lphp_check_string

.Lphp_check_hash:
    cmp bl, '#'
    jne .Lphp_check_string
.Lphp_lc:
    call .Lphp_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rbx, r15
.Lphp_lc_scan:
    cmp r15, r13
    jae .Lphp_lc_done
    cmp byte ptr [r12 + r15], 10
    je .Lphp_lc_done
    inc r15
    jmp .Lphp_lc_scan
.Lphp_lc_done:
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    call .Lphp_ensure_nl
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_bc:
    call .Lphp_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rbx, r15
    add r15, 2
.Lphp_bc_scan:
    cmp r15, r13
    jae .Lphp_bc_done
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .Lphp_bc_done
    cmp byte ptr [r12 + r15], '*'
    jne 1f
    cmp byte ptr [r12 + r15 + 1], '/'
    je .Lphp_bc_found
1:  inc r15
    jmp .Lphp_bc_scan
.Lphp_bc_found:
    add r15, 2
.Lphp_bc_done:
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    call .Lphp_ensure_nl
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_string:
    cmp bl, '\''
    je .Lphp_string
    cmp bl, '"'
    je .Lphp_string
    jmp .Lphp_check_braces

.Lphp_string:
    call .Lphp_indent_if_nl
    mov rdi, r14
    mov esi, ebx
    call sb_push_byte
    inc r15
.Lphp_str_scan:
    cmp r15, r13
    jae .Lphp_str_done
    movzx eax, byte ptr [r12 + r15]
    inc r15
    mov rdi, r14
    mov esi, eax
    call sb_push_byte
    cmp al, '\\'
    jne 1f
    cmp r15, r13
    jae .Lphp_str_done
    movzx eax, byte ptr [r12 + r15]
    inc r15
    mov rdi, r14
    mov esi, eax
    call sb_push_byte
    jmp .Lphp_str_scan
1:  cmp al, bl
    jne .Lphp_str_scan
.Lphp_str_done:
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_braces:
    # Open brace '{'
    cmp bl, '{'
    jne .Lphp_check_close_brace
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    mov dl, [rcx + rax - 1]
    cmp dl, ' '
    je 1f
    cmp dl, 10
    je 1f
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
1:  mov rdi, r14
    mov esi, '{'
    call sb_push_byte
    call .Lphp_ensure_nl
    inc dword ptr [rsp + 8]     # depth++
    inc r15
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_close_brace:
    cmp bl, '}'
    jne .Lphp_check_semi
    cmp dword ptr [rsp + 8], 0
    jle 1f
    dec dword ptr [rsp + 8]
1:  call .Lphp_ensure_nl
    mov rdi, r14
    mov esi, [rsp + 8]
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    call fmt_push_indent
    mov rdi, r14
    mov esi, '}'
    call sb_push_byte
    inc r15
    # Peek next token for "else"
    mov rcx, r15
.Lphp_peek_else:
    cmp rcx, r13
    jae 2f
    movzx edi, byte ptr [r12 + rcx]
    call fmt_is_space
    test eax, eax
    jz .Lphp_chk_else_w
    inc rcx
    jmp .Lphp_peek_else
.Lphp_chk_else_w:
    lea rax, [rcx + 4]
    cmp rax, r13
    ja 2f
    cmp byte ptr [r12 + rcx], 'e'
    jne 2f
    cmp byte ptr [r12 + rcx + 1], 'l'
    jne 2f
    cmp byte ptr [r12 + rcx + 2], 's'
    jne 2f
    cmp byte ptr [r12 + rcx + 3], 'e'
    jne 2f
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    mov r15, rcx
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop
2:  call .Lphp_ensure_nl
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_semi:
    cmp bl, ';'
    jne .Lphp_check_comma
    mov rdi, r14
    mov esi, ';'
    call sb_push_byte
    call .Lphp_ensure_nl
    inc r15
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_comma:
    cmp bl, ','
    jne .Lphp_check_ops
    mov rdi, r14
    mov esi, ','
    call sb_push_byte
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    inc r15
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_ops:
    # Check ->
    cmp bl, '-'
    jne 1f
    lea rax, [r15 + 1]
    cmp rax, r13
    jae 1f
    cmp byte ptr [r12 + r15 + 1], '>'
    jne 1f
    mov rdi, r14
    mov esi, '-'
    call sb_push_byte
    mov rdi, r14
    mov esi, '>'
    call sb_push_byte
    add r15, 2
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop
1:  # Check =>
    cmp bl, '='
    jne 2f
    lea rax, [r15 + 1]
    cmp rax, r13
    jae 2f
    cmp byte ptr [r12 + r15 + 1], '>'
    jne 2f
    call .Lphp_space_before
    mov rdi, r14
    mov esi, '='
    call sb_push_byte
    mov rdi, r14
    mov esi, '>'
    call sb_push_byte
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    add r15, 2
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop
2:  # Check binary operators: '=', '==', '===', '!=', '!==', '<', '>', '<=', '>=', '+', '*', '/'
    cmp bl, '='
    je .Lphp_binop
    cmp bl, '+'
    je .Lphp_binop
    cmp bl, '*'
    je .Lphp_binop
    cmp bl, '<'
    je .Lphp_binop
    cmp bl, '>'
    je .Lphp_binop
    cmp bl, '!'
    je .Lphp_check_binop_excl
    jmp .Lphp_check_ident

.Lphp_check_binop_excl:
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .Lphp_check_ident
    cmp byte ptr [r12 + r15 + 1], '='
    jne .Lphp_check_ident
.Lphp_binop:
    call .Lphp_space_before
    # push operator characters
.Lphp_binop_loop:
    cmp r15, r13
    jae 3f
    movzx esi, byte ptr [r12 + r15]
    cmp sil, '='
    je 4f
    cmp sil, '+'
    je 4f
    cmp sil, '*'
    je 4f
    cmp sil, '<'
    je 4f
    cmp sil, '>'
    je 4f
    cmp sil, '!'
    je 4f
    jmp 3f
4:  mov rdi, r14
    call sb_push_byte
    inc r15
    jmp .Lphp_binop_loop
3:  mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_check_ident:
    movzx edi, bl
    call fmt_is_ident
    test eax, eax
    jz .Lphp_single_char

    # Read full identifier/keyword
    mov rbx, r15
.Lphp_ident_scan:
    cmp r15, r13
    jae .Lphp_ident_done
    movzx edi, byte ptr [r12 + r15]
    call fmt_is_ident
    test eax, eax
    jz .Lphp_ident_done
    inc r15
    jmp .Lphp_ident_scan
.Lphp_ident_done:
    call .Lphp_indent_if_nl
    # If had_space or previous char is ident, emit space
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 5f
    mov rcx, [r14 + SB_ptr]
    movzx edi, byte ptr [rcx + rax - 1]
    call fmt_is_ident
    test eax, eax
    jnz 6f
    cmp dword ptr [rsp + 12], 1
    jne 5f
    # Check if last was not space or newline
    mov rax, [r14 + SB_len]
    mov rcx, [r14 + SB_ptr]
    mov dl, [rcx + rax - 1]
    cmp dl, ' '
    je 5f
    cmp dl, 10
    je 5f
    cmp dl, '('
    je 5f
6:  mov rdi, r14
    mov esi, ' '
    call sb_push_byte
5:  mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r15
    sub rdx, rbx
    call sb_push
    mov dword ptr [rsp + 12], 0

    # If this word was "if", "for", "while", "foreach", "switch", add space before '('
    mov rdx, r15
    sub rdx, rbx
    lea rdi, [r12 + rbx]
    call .Lphp_is_ctrl_kw
    test eax, eax
    jz .Lphp_loop
    # Peek if next non-ws is '('
    mov rcx, r15
.Lphp_peek_paren:
    cmp rcx, r13
    jae .Lphp_loop
    movzx edi, byte ptr [r12 + rcx]
    call fmt_is_space
    test eax, eax
    jz .Lphp_peek_paren_chk
    inc rcx
    jmp .Lphp_peek_paren
.Lphp_peek_paren_chk:
    cmp byte ptr [r12 + rcx], '('
    jne .Lphp_loop
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    jmp .Lphp_loop

.Lphp_single_char:
    call .Lphp_indent_if_nl
    mov rdi, r14
    movzx esi, byte ptr [r12 + r15]
    call sb_push_byte
    inc r15
    mov dword ptr [rsp + 12], 0
    jmp .Lphp_loop

.Lphp_space_before:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], ' '
    je 1f
    cmp byte ptr [rcx + rax - 1], 10
    je 1f
    push rdi
    push rsi
    mov rdi, r14
    mov esi, ' '
    call sb_push_byte
    pop rsi
    pop rdi
1:  ret

.Lphp_indent_if_nl:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    jne 2f
1:  push rdi
    push rsi
    mov rdi, r14
    mov esi, [rsp + 8 + 16]
    mov edx, [rsp + 16]
    mov ecx, [rsp + 4 + 16]
    call fmt_push_indent
    pop rsi
    pop rdi
2:  ret

.Lphp_ensure_nl:
    mov rax, [r14 + SB_len]
    test rax, rax
    jz 1f
    mov rcx, [r14 + SB_ptr]
    cmp byte ptr [rcx + rax - 1], 10
    je 1f
    push rdi
    push rsi
    mov rdi, r14
    mov esi, 10
    call sb_push_byte
    pop rsi
    pop rdi
1:  ret

.Lphp_is_ctrl_kw:
    # rdi=ptr, rdx=len: returns 1 if "if", "for", "while", "foreach", "switch"
    cmp rdx, 2
    jne 1f
    cmp byte ptr [rdi], 'i'
    jne 9f
    cmp byte ptr [rdi + 1], 'f'
    jne 9f
    mov eax, 1
    ret
1:  cmp rdx, 3
    jne 2f
    cmp byte ptr [rdi], 'f'
    jne 9f
    cmp byte ptr [rdi + 1], 'o'
    jne 9f
    cmp byte ptr [rdi + 2], 'r'
    jne 9f
    mov eax, 1
    ret
2:  cmp rdx, 5
    jne 3f
    cmp byte ptr [rdi], 'w'
    jne 9f
    cmp byte ptr [rdi + 1], 'h'
    jne 9f
    cmp byte ptr [rdi + 2], 'i'
    jne 9f
    cmp byte ptr [rdi + 3], 'l'
    jne 9f
    cmp byte ptr [rdi + 4], 'e'
    jne 9f
    mov eax, 1
    ret
3:  cmp rdx, 7
    jne 9f
    cmp byte ptr [rdi], 'f'
    jne 9f
    cmp byte ptr [rdi + 1], 'o'
    jne 9f
    cmp byte ptr [rdi + 2], 'r'
    jne 9f
    cmp byte ptr [rdi + 3], 'e'
    jne 9f
    cmp byte ptr [rdi + 4], 'a'
    jne 9f
    cmp byte ptr [rdi + 5], 'c'
    jne 9f
    cmp byte ptr [rdi + 6], 'h'
    jne 9f
    mov eax, 1
    ret
9:  xor eax, eax
    ret

.Lphp_end:
    call .Lphp_ensure_nl
    mov eax, 1
    EPILOGUE

# =============================================================
# DOCUMENT DETECTION & APPLICATION
# =============================================================

FN fmt_detect_type
    PROLOGUE 16
    mov r12, rdi
    test r12, r12
    jz .Ldt_none

    mov rdi, r12
    call doc_language
    test rax, rax
    jz .Ldt_check_path
    mov r13, [rax + GR_name]
    test r13, r13
    jz .Ldt_check_path

    mov rdi, r13
    call strlen
    mov r14, rax

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_json]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_json

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_xml]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_html]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_svg]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_sql]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_sql

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_php]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_php

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_ini]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_ini

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lfmt_s_properties]
    mov ecx, 10
    call str_ieq
    test eax, eax; jnz .Ldt_ini

.Ldt_check_path:
    mov rdi, [r12 + DOC_path]
    test rdi, rdi
    jz .Ldt_none
    call strlen
    mov rsi, rax
    mov rdi, [r12 + DOC_path]
    call path_ext
    test rdx, rdx
    jz .Ldt_none
    mov r13, rax
    mov r14, rdx

    # JSON
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_json]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_json

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_jsonc]
    mov ecx, 5
    call str_ieq
    test eax, eax; jnz .Ldt_json

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_json5]
    mov ecx, 5
    call str_ieq
    test eax, eax; jnz .Ldt_json

    # XML
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_xml]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_svg]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_html]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_htm]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_xaml]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_plist]
    mov ecx, 5
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_xsd]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_xsl]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_xml

    # SQL
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_sql]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_sql

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_psql]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_sql

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_ddl]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_sql

    # PHP
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_php]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_php

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_phtml]
    mov ecx, 5
    call str_ieq
    test eax, eax; jnz .Ldt_php

    # INI
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_ini]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_ini

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_cfg]
    mov ecx, 3
    call str_ieq
    test eax, eax; jnz .Ldt_ini

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_conf]
    mov ecx, 4
    call str_ieq
    test eax, eax; jnz .Ldt_ini

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + .Lext_theme]
    mov ecx, 5
    call str_ieq
    test eax, eax; jnz .Ldt_ini

.Ldt_none:
    xor eax, eax
    EPILOGUE
.Ldt_json:
    mov eax, FMT_JSON
    EPILOGUE
.Ldt_xml:
    mov eax, FMT_XML
    EPILOGUE
.Ldt_sql:
    mov eax, FMT_SQL
    EPILOGUE
.Ldt_php:
    mov eax, FMT_PHP
    EPILOGUE
.Ldt_ini:
    mov eax, FMT_INI
    EPILOGUE

# -------------------------------------------------------------
# fmt_format_buffer(kind, src, len, sb, tab_width, insert_spaces) -> eax 1/0
# -------------------------------------------------------------
FN fmt_format_buffer
    PROLOGUE 16
    cmp edi, FMT_JSON
    je .Lfb_json
    cmp edi, FMT_XML
    je .Lfb_xml
    cmp edi, FMT_SQL
    je .Lfb_sql
    cmp edi, FMT_PHP
    je .Lfb_php
    cmp edi, FMT_INI
    je .Lfb_ini
    xor eax, eax
    EPILOGUE
.Lfb_json:
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov ecx, r8d
    mov r8d, r9d
    call format_json
    EPILOGUE
.Lfb_xml:
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov ecx, r8d
    mov r8d, r9d
    call format_xml
    EPILOGUE
.Lfb_sql:
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov ecx, r8d
    mov r8d, r9d
    call format_sql
    EPILOGUE
.Lfb_php:
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov ecx, r8d
    mov r8d, r9d
    call format_php
    EPILOGUE
.Lfb_ini:
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    mov ecx, r8d
    mov r8d, r9d
    call format_ini
    EPILOGUE

# -------------------------------------------------------------
# builtin_format_apply(doc, kind, toast_success, toast_fail) -> eax 1/0
# -------------------------------------------------------------
FN builtin_format_apply
    PROLOGUE 48
    mov rbx, rdi                # doc
    mov r12d, esi               # kind
    mov [rsp], rdx              # toast_success
    mov [rsp + 8], rcx          # toast_fail

    test rbx, rbx
    jz .Lfa_nodoc
    test dword ptr [rbx + DOC_flags], DF_READONLY
    jnz .Lfa_nodoc

    mov rdi, rbx
    call doc_len
    mov r13, rax                # src_len
    test r13, r13
    jz .Lfa_already

    lea rdi, [r13 + 1]
    call mem_alloc
    mov r14, rax                # src_buf
    mov rdi, rbx
    xor esi, esi
    mov rdx, r13
    mov rcx, r14
    call doc_copy
    mov byte ptr [r14 + r13], 0

    call fmt_doc_options
    mov [rsp + 16], eax         # tab_width
    mov [rsp + 20], edx         # insert_spaces

    lea r15, [rsp + 24]         # SB
    xor eax, eax
    mov [r15 + SB_ptr], rax
    mov [r15 + SB_len], rax
    mov [r15 + SB_cap], rax

    mov edi, r12d
    mov rsi, r14
    mov rdx, r13
    mov rcx, r15
    mov r8d, [rsp + 16]
    mov r9d, [rsp + 20]
    call fmt_format_buffer
    test eax, eax
    jz .Lfa_failed

    mov rax, [r15 + SB_len]
    cmp rax, r13
    jne .Lfa_apply_diff
    mov rdi, r14
    mov rsi, [r15 + SB_ptr]
    mov rdx, r13
    call memeq
    test eax, eax
    jnz .Lfa_already_clean

.Lfa_apply_diff:
    mov rdi, rbx
    call doc_begin_group

    mov rdi, rbx
    xor esi, esi
    mov rdx, [r15 + SB_ptr]
    mov rcx, [r15 + SB_len]
    mov r8d, EK_OTHER
    call doc_insert

    mov rdi, rbx
    mov rsi, [r15 + SB_len]
    mov rdx, r13
    mov ecx, EK_OTHER
    call doc_delete

    mov rdi, rbx
    call doc_end_group

    mov rdi, rbx
    call doc_len
    cmp [rbx + DOC_cur], rax
    jbe 1f
    mov [rbx + DOC_cur], rax
1:  cmp [rbx + DOC_anchor], rax
    jbe 2f
    mov [rbx + DOC_anchor], rax
2:  mov dword ptr [rip + g_dirty], 1
    call ed_touch

    mov rdi, r14
    call mem_free
    mov rdi, r15
    call sb_free

    mov rdi, [rsp]
    test rdi, rdi
    jz 3f
    call app_toast
3:  mov eax, 1
    EPILOGUE

.Lfa_already_clean:
    mov rdi, r14
    call mem_free
    mov rdi, r15
    call sb_free
.Lfa_already:
    lea rdi, [rip + .Lt_already]
    call app_toast
    mov eax, 1
    EPILOGUE

.Lfa_failed:
    mov rdi, r14
    call mem_free
    mov rdi, r15
    call sb_free
    mov rdi, [rsp + 8]
    test rdi, rdi
    jz 4f
    call app_toast
4:  xor eax, eax
    EPILOGUE

.Lfa_nodoc:
    lea rdi, [rip + .Lt_err_nodoc]
    call app_toast
    xor eax, eax
    EPILOGUE

# -------------------------------------------------------------
# builtin_format_doc(doc) -> eax 1/0
# -------------------------------------------------------------
FN builtin_format_doc
    PROLOGUE 16
    mov rbx, rdi
    test rbx, rbx
    jz .Lbfd_none
    mov rdi, rbx
    call fmt_detect_type
    test eax, eax
    jz .Lbfd_none

    cmp eax, FMT_JSON
    je .Lbfd_json
    cmp eax, FMT_XML
    je .Lbfd_xml
    cmp eax, FMT_SQL
    je .Lbfd_sql
    cmp eax, FMT_PHP
    je .Lbfd_php
    cmp eax, FMT_INI
    je .Lbfd_ini
.Lbfd_none:
    xor eax, eax
    EPILOGUE

.Lbfd_json:
    mov rdi, rbx
    mov esi, FMT_JSON
    lea rdx, [rip + .Lt_ok_json]
    lea rcx, [rip + .Lt_err_json]
    call builtin_format_apply
    EPILOGUE

.Lbfd_xml:
    mov rdi, rbx
    mov esi, FMT_XML
    lea rdx, [rip + .Lt_ok_xml]
    lea rcx, [rip + .Lt_err_xml]
    call builtin_format_apply
    EPILOGUE

.Lbfd_sql:
    mov rdi, rbx
    mov esi, FMT_SQL
    lea rdx, [rip + .Lt_ok_sql]
    xor ecx, ecx
    call builtin_format_apply
    EPILOGUE

.Lbfd_php:
    mov rdi, rbx
    mov esi, FMT_PHP
    lea rdx, [rip + .Lt_ok_php]
    xor ecx, ecx
    call builtin_format_apply
    EPILOGUE

.Lbfd_ini:
    mov rdi, rbx
    mov esi, FMT_INI
    lea rdx, [rip + .Lt_ok_ini]
    xor ecx, ecx
    call builtin_format_apply
    EPILOGUE

# -------------------------------------------------------------
# builtin_format_try() -> eax 1 if formatted, 0 if unsupported
# -------------------------------------------------------------
FN builtin_format_try
    mov rdi, [rip + g_doc]
    jmp builtin_format_doc

# =============================================================
# EXPLICIT EDITOR COMMANDS
# =============================================================

FN cmd_format_json
    mov rdi, [rip + g_doc]
    mov esi, FMT_JSON
    lea rdx, [rip + .Lt_ok_json]
    lea rcx, [rip + .Lt_err_json]
    jmp builtin_format_apply

FN cmd_format_xml
    mov rdi, [rip + g_doc]
    mov esi, FMT_XML
    lea rdx, [rip + .Lt_ok_xml]
    lea rcx, [rip + .Lt_err_xml]
    jmp builtin_format_apply

FN cmd_format_sql
    mov rdi, [rip + g_doc]
    mov esi, FMT_SQL
    lea rdx, [rip + .Lt_ok_sql]
    xor ecx, ecx
    jmp builtin_format_apply

FN cmd_format_php
    mov rdi, [rip + g_doc]
    mov esi, FMT_PHP
    lea rdx, [rip + .Lt_ok_php]
    xor ecx, ecx
    jmp builtin_format_apply

FN cmd_format_ini
    mov rdi, [rip + g_doc]
    mov esi, FMT_INI
    lea rdx, [rip + .Lt_ok_ini]
    xor ecx, ecx
    jmp builtin_format_apply
