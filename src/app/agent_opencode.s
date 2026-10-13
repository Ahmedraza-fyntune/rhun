# OpenCode's database is read only in the background metadata worker, by OpenCode's own binary: its
# `db` command (OpenCode 1), or, in OpenCode 2, which has none, the Bun runtime it is built on, whose
# SQLite reads the database. No shell, provider requests, server or extra SQLite runtime are needed.
.include "rhun.inc"
.equ OPENCODE_TIMEOUT, 15000    # ms one CLI run may take
.equ OPENCODE_BUDGET, 30000     # ms for all of a discovery run's CLI runs
.bss
.p2align 3
cli: .quad 0
deadline: .quad 0
bun_env: .quad 0                # the environment with BUN_BE_BUN, made once
.globl agent_opencode_v2
agent_opencode_v2: .long 0      # OpenCode 2 or later: sessions are in session_v2 and session_message
.p2align 3
output: .zero SB_SIZE
out_path: .zero SB_SIZE
cwd: .zero SB_SIZE              # where the CLI runs: Rhun's state folder, never the project
key: .zero SB_SIZE
.text

FN agent_opencode_init
    PROLOGUE
    lea rdi, [rip + .Lcli]
    call proc_which
    test rax, rax
    jnz 3f
.ifndef WINDOWS
    lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    mov r12, rax
    lea r13, [rip + locations]
1:  mov rsi, [r13]
    test rsi, rsi
    jz 9f
    mov rdi, r12
    cmp byte ptr [rsi], '/'
    jne 11f
    mov rdi, rsi
    call strlen
    mov rsi, rax
    mov rdi, [r13]
    call mem_dup
    jmp 12f
11: call path_join
12:
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    SYS SYS_access
    test rax, rax
    jz 2f
    mov rdi, rbx
    call mem_free
    add r13, 8
    jmp 1b
2:  mov rax, rbx
.else
    jmp 9f                      # Windows looks on PATH alone
.endif
3:  mov rbx, rax
    # a relative PATH entry names it from here, and it runs in Rhun's state folder (run_cli)
    PATH_ABSOLUTE rbx, 4f
    sub rsp, 4096
    mov rdi, rsp
    mov esi, 4000
    SYS SYS_getcwd
    test rax, rax
    js 41f
    mov rdi, rsp
    mov rsi, rbx
    call path_join
    mov rbx, rax
41: add rsp, 4096
4:  mov [rip + cli], rbx
    mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# agent_opencode_scope(data dir) -> identity of the database this profile's CLI uses: its data folder
#   and the variables OpenCode chooses the database with. Cached rows of another one are never listed.
FN agent_opencode_scope
    PROLOGUE
    mov r12, rdi
    lea rdi, [rip + key]
    call sb_clear
    mov rdi, r12
    call key_hash
    EPILOGUE

# agent_opencode_cli_key(data dir) -> identity of what decides the database path and OpenCode's version:
# the CLI file (an update replaces it) and the scope's folder and variables.
FN agent_opencode_cli_key
    PROLOGUE 16
    mov r12, rdi
    lea rdi, [rip + key]
    call sb_clear
    lea rdi, [rip + key]
    mov rsi, [rip + cli]
    call sb_push_cstr
    lea rdi, [rip + key]
    xor esi, esi
    call sb_push_byte
    mov rdi, [rip + cli]
    call file_stamp
    mov [rsp], rax
    lea rdi, [rip + key]
    mov rsi, rsp
    mov edx, 8
    call sb_push
    mov rdi, r12
    call key_hash
    EPILOGUE

# key_hash(data dir) -> hash of the key so far, the variables and the folder
key_hash:
    PROLOGUE
    mov r12, rdi
    lea rbx, [rip + key_env]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 2f
    call getenv
    test rax, rax
    jz 11f
    lea rdi, [rip + key]
    mov rsi, rax
    call sb_push_cstr
11: lea rdi, [rip + key]
    xor esi, esi
    call sb_push_byte
    add rbx, 8
    jmp 1b
2:  lea rdi, [rip + key]
    mov rsi, r12
    call sb_push_cstr
    mov rdi, [rip + key + SB_ptr]
    mov rsi, [rip + key + SB_len]
    call hash_line
    EPILOGUE

# Data is created by OpenCode's global bootstrap, including installations with a custom database.
# Do not invoke the CLI (or initialize its database) until OpenCode has been used in this profile.
FN agent_opencode_data_dir
    PROLOGUE
    lea rdi, [rip + .Ldata]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    je 1f
    mov rdi, rax
    lea rsi, [rip + .Lcli]
    call path_join
    EPILOGUE
1:  lea rdi, [rip + .Lhome]
    call getenv
    test rax, rax
    jz 9f
    mov rdi, rax
    lea rsi, [rip + .Ldefault_data]
    call path_join
9:  EPILOGUE

# agent_opencode_locate() -> borrowed path of the database the CLI uses, rdx bytes; 0 on failure, with rdx
#   -1 when the run's time for the CLI is used up. Sets agent_opencode_v2 from `opencode --version`
#   ("1.19.0", "opencode v2.0.28"): OpenCode 2 has no `db` command, and `opencode db` alone would start its
#   interface in a folder named db; its `debug paths` names the database on a line "db  PATH".
FN agent_opencode_locate
    PROLOGUE 32
    mov rax, [rip + cli]
    mov [rsp], rax
    lea rax, [rip + .Lversion]
    mov [rsp + 8], rax
    mov qword ptr [rsp + 16], 0
    mov rdi, rsp
    mov rsi, [rip + g_envp]
    call run_cli
    test rax, rax
    jz 9f
    xor ecx, ecx                # the first number is the major version
1:  cmp rcx, rdx
    jae 8f
    movzx r8d, byte ptr [rax + rcx]
    sub r8d, '0'
    cmp r8d, 9
    jbe 2f
    inc rcx
    jmp 1b
2:  lea rdi, [rax + rcx]
    mov rsi, rdx
    sub rsi, rcx
    call parse_u64
    xor ecx, ecx
    cmp rax, 2
    setae cl
    mov [rip + agent_opencode_v2], ecx
    lea rax, [rip + .Ldb]
    lea rdx, [rip + .Lpath]
    test ecx, ecx
    jz 3f
    lea rax, [rip + .Ldebug]
    lea rdx, [rip + .Lpaths]
3:  mov [rsp + 8], rax
    mov [rsp + 16], rdx
    mov qword ptr [rsp + 24], 0
    mov rdi, rsp
    mov rsi, [rip + g_envp]
    call run_cli
    test rax, rax
    jz 9f
    mov rbx, rax
    mov r12, rdx
    cmp dword ptr [rip + agent_opencode_v2], 0
    jne 4f
    mov rdi, rax                # OpenCode 1 prints the path alone
    mov rsi, rdx
    call path_text
    EPILOGUE
4:  xor r13d, r13d              # the start of a line
5:  cmp r13, r12
    jae 8f
    mov r14, r13
6:  cmp r14, r12
    jae 7f
    cmp byte ptr [rbx + r14], 10
    je 7f
    inc r14
    jmp 6b
7:  lea rcx, [r13 + 3]
    cmp rcx, r14
    jae 71f
    cmp word ptr [rbx + r13], 0x6264 # "db", then spaces
    jne 71f
    movzx ecx, byte ptr [rbx + r13 + 2]
    cmp ecx, ' '
    je 72f
    cmp ecx, 9
    jne 71f
72: lea rdi, [rbx + r13 + 2]
    mov rsi, r14
    sub rsi, r13
    sub rsi, 2
    call path_text
    EPILOGUE
71: lea r13, [r14 + 1]
    jmp 5b
8:  xor eax, eax
    xor edx, edx
9:  EPILOGUE

# path_text(ptr, bytes) -> the path without the blanks and line end around it
path_text:
    call trim
1:  test rdx, rdx               # and the line's end, which trim keeps
    jz 9f
    movzx ecx, byte ptr [rax + rdx - 1]
    cmp cl, 10
    je 2f
    cmp cl, 13
    je 2f
    cmp cl, ' '
    jne 9f
2:  dec rdx
    jmp 1b
9:  ret

# agent_opencode_query(SQL, database path) -> borrowed output ptr, rdx bytes; 0 on failure, with rdx
#   -1 when the run's time for the CLI is used up and -2 for output past 64 MiB. Either way the output is
#   the TSV of `opencode db --format tsv`: a header "line", then one row a line.
FN agent_opencode_query
    PROLOGUE 64
    mov rax, [rip + cli]
    mov [rsp], rax
    cmp dword ptr [rip + agent_opencode_v2], 0
    jne 1f
    lea rax, [rip + .Ldb]
    mov [rsp + 8], rax
    mov [rsp + 16], rdi
    lea rax, [rip + .Lformat]
    mov [rsp + 24], rax
    lea rax, [rip + .Ltsv]
    mov [rsp + 32], rax
    mov qword ptr [rsp + 40], 0
    mov rsi, [rip + g_envp]
    jmp 2f
1:  lea rax, [rip + .Lno_env]
    mov [rsp + 8], rax
    lea rax, [rip + .Leval]
    mov [rsp + 16], rax
    lea rax, [rip + .Lreader]
    mov [rsp + 24], rax
    mov [rsp + 32], rsi
    mov [rsp + 40], rdi
    mov qword ptr [rsp + 48], 0
    mov rsi, [rip + bun_env]
    test rsi, rsi
    jnz 2f
    lea rdi, [rip + bun_extras]
    call env_make
    mov [rip + bun_env], rax
    mov rsi, rax
2:  mov rdi, rsp
    call run_cli
    EPILOGUE

# run_cli(argv, envp) -> as agent_opencode_query, for the output of the CLI run with argv.
# The CLI writes to a file: OpenCode 1.19 exits before a pipe has taken all of its output and drops
# the rest, with status 0. Output and time stay bounded if a CLI installation is broken or hangs, and
# the runs of one discovery share a deadline, well inside the app's limit for the whole run. It runs in
# Rhun's state folder: as Bun, OpenCode 2's binary reads a bunfig.toml (whose preload runs code) and a
# .env from the folder it starts in, which in the project's could be anyone's.
run_cli:
    PROLOGUE 32
    mov [rsp], rdi
    mov [rsp + 8], rsi
    call time_ms
    mov r14, rax
    mov rcx, [rip + deadline]
    test rcx, rcx
    jnz 2f
    lea rcx, [rax + OPENCODE_BUDGET]
    mov [rip + deadline], rcx
2:  cmp r14, rcx
    jae 10f                     # this run's time for OpenCode is used up
    add r14, OPENCODE_TIMEOUT
    cmp r14, rcx
    cmova r14, rcx
    call out_open
    test eax, eax
    js 9f
    mov r15d, eax
    lea rdi, [rip + .Ldevnull]
    mov esi, O_RDWR | O_CLOEXEC
    xor edx, edx
    SYS SYS_open
    test rax, rax
    js 8f
    mov ebx, eax
    lea rdi, [rip + cwd]
    call session_state_dir      # out_open has found it
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rip + cwd + SB_ptr]
    mov ecx, ebx
    mov r8d, r15d
    mov r9d, ebx
    xor eax, eax
    push rax
    push rax
    call proc_spawn
    add rsp, 16
    mov r12, rax
    mov edi, ebx
    SYS SYS_close
    test r12, r12
    jle 8f
3:  mov edi, r12d
    mov esi, 1
    call proc_wait
    cmp eax, -1
    jne 5f
    mov edi, r15d
    call file_size
    cmp rax, 1 << 26
    ja 41f
    call time_ms
    cmp rax, r14
    jae 4f
    lea rdi, [rsp + 16]
    xor esi, esi
    mov edx, 20
    SYS SYS_poll
    jmp 3b
4:  mov edi, r12d
    mov esi, 9
    SYS SYS_kill
    mov edi, r12d
    xor esi, esi
    call proc_wait
    mov edi, r15d
    call out_close
    cmp r14, [rip + deadline]
    je 10f                      # stopped for the run's time, not its own
    jmp 9f
41: mov edi, r12d
    mov esi, 9
    SYS SYS_kill
    mov edi, r12d
    xor esi, esi
    call proc_wait
    jmp 11f
5:  test eax, eax
    jnz 8f
    lea rdi, [rip + output]
    call sb_clear
    mov edi, r15d
    xor esi, esi
    xor edx, edx
    SYS SYS_lseek
    test rax, rax
    js 8f
6:  lea rdi, [rip + output]
    mov esi, 65536
    call sb_reserve
    mov rsi, rax
    mov edi, r15d
    mov edx, 65536
    SYS SYS_read
    cmp rax, -EINTR
    je 6b
    test rax, rax
    js 8f
    jz 7f
    add [rip + output + SB_len], rax
    cmp qword ptr [rip + output + SB_len], 1 << 26
    ja 11f
    jmp 6b
7:  mov edi, r15d
    call out_close
    mov rax, [rip + output + SB_ptr]
    mov rdx, [rip + output + SB_len]
    EPILOGUE
8:  mov edi, r15d
    call out_close
9:  xor eax, eax
    xor edx, edx
    EPILOGUE
10: xor eax, eax
    mov rdx, -1
    EPILOGUE
11: mov edi, r15d
    call out_close
    xor eax, eax
    mov rdx, -2
    EPILOGUE

# out_open() -> fd of a new file, readable by this user alone, for the CLI's output (or -errno). On
#   Linux and macOS it loses its name at once; a Windows file keeps it until out_close.
out_open:
    PROLOGUE 32
    lea rdi, [rip + out_path]
    call session_state_dir
    test eax, eax
    jz 8f
    lea rdi, [rip + out_path]
    lea rsi, [rip + .Lout_prefix]
    call sb_push_cstr
    SYS SYS_getpid
    mov rsi, rax
    mov rdi, rsp
    call fmt_u64
    lea rdi, [rip + out_path]
    mov rsi, rsp
    mov rdx, rax
    call sb_push
    lea rdi, [rip + out_path]
    lea rsi, [rip + .Lout_suffix]
    call sb_push_cstr
    mov ebx, 2
1:  mov rdi, [rip + out_path + SB_ptr]
    mov esi, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC
    mov edx, 0600
    SYS SYS_open
    cmp rax, -17                # EEXIST: what a stopped run of this process ID left
    jne 2f
    dec ebx
    jz 2f
    mov rdi, [rip + out_path + SB_ptr]
    SYS SYS_unlink
    jmp 1b
2:  test rax, rax
    js 9f
.ifndef WINDOWS
    mov r12, rax
    mov rdi, [rip + out_path + SB_ptr]
    SYS SYS_unlink
    mov rax, r12
.endif
9:  EPILOGUE
8:  mov rax, -2
    EPILOGUE

# out_close(fd)
out_close:
    PROLOGUE
    SYS SYS_close
.ifdef WINDOWS
    mov rdi, [rip + out_path + SB_ptr]
    SYS SYS_unlink
.endif
    EPILOGUE

# SQL string literal, with quotes doubled. Arguments go directly to the CLI, never a shell.
FN agent_opencode_quote
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov esi, 39
    call sb_push_byte
1:  movzx esi, byte ptr [r13]
    test esi, esi
    jz 3f
    mov ebx, esi
    mov rdi, r12
    call sb_push_byte
    cmp ebx, 39
    jne 2f
    mov rdi, r12
    mov esi, 39
    call sb_push_byte
2:  inc r13
    jmp 1b
3:  mov rdi, r12
    mov esi, 39
    call sb_push_byte
    EPILOGUE

# The query returns one JSON object per TSV row, under the single column "line".
# each_line(ptr, bytes, callback(ptr,len)) -> 1 valid transport, 0 invalid/truncated.
FN agent_opencode_each_line
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test r13, r13
    jz 9f                      # db prints nothing when the SELECT returns no rows
    cmp r13, 5
    jb 8f
    cmp dword ptr [r12], 0x656e696c # line
    jne 8f
    mov ebx, 4
    cmp byte ptr [r12 + rbx], 13
    jne 1f
    inc rbx
1:  cmp byte ptr [r12 + rbx], 10
    jne 8f
    inc rbx
2:  cmp rbx, r13
    jae 9f
    mov r15, rbx
3:  cmp r15, r13
    jae 8f
    cmp byte ptr [r12 + r15], 10
    je 4f
    inc r15
    jmp 3b
4:  lea rdi, [r12 + rbx]
    mov rsi, r15
    sub rsi, rbx
    call r14
    test eax, eax
    jz 8f
    lea rbx, [r15 + 1]
    jmp 2b
8:  xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE

.section .rodata
.Lcli: .asciz "opencode"
.Ldb: .asciz "db"
.Lpath: .asciz "path"
.Lversion: .asciz "--version"
.Ldebug: .asciz "debug"
.Lpaths: .asciz "paths"
.Leval: .asciz "-e"
.Lno_env: .asciz "--no-env-file"
.Lbun_be_bun: .asciz "BUN_BE_BUN=1"
# OpenCode 2's binary as Bun runs this with the database and the query. It reads without a write when
# OpenCode has the database open; with no -shm (OpenCode closed) SQLite cannot read the log read-only,
# so it opens the database as OpenCode does, never creating one, and on closing removes the log files
# that made, which Apple's SQLite, Bun's on macOS, otherwise keeps. Statements are prepared rather than
# cached, which would keep the database open past close. It prints what `db --format tsv` did, a row at
# a time: the output limit applies while it runs.
.Lreader: .asciz "const{Database}=require('bun:sqlite'),f=require('fs'),a=process.argv;let d,s;try{d=new Database(a[1],{readonly:true});s=d.prepare('SELECT 1 FROM sqlite_master');s.get();s.finalize()}catch(e){if(s)s.finalize();if(d)d.close();d=new Database(a[1],{readwrite:true,create:false});try{d.fileControl(10,0)}catch(e){}}d.exec('PRAGMA busy_timeout=5000');s=d.prepare(a[2]);f.writeSync(1,'line\\n');for(const r of s.iterate())f.writeSync(1,r.line+'\\n');s.finalize();d.close()"
.Lformat: .asciz "--format"
.Ltsv: .asciz "tsv"
.Ldevnull: .asciz "/dev/null"
.Lout_prefix: .asciz "/.rhun-opencode-"
.Lout_suffix: .asciz ".tmp"
.Lhome: .asciz "HOME"
.Ldata: .asciz "XDG_DATA_HOME"
.Ldefault_data: .asciz ".local/share/opencode"
.Linstaller: .asciz ".opencode/bin/opencode"
.Llocal: .asciz ".local/bin/opencode"
.Lbrew: .asciz "/opt/homebrew/bin/opencode"
.Lusr: .asciz "/usr/local/bin/opencode"
.Lenv_db: .asciz "OPENCODE_DB"
.Lenv_channel: .asciz "OPENCODE_DISABLE_CHANNEL_DB"
.p2align 3
locations: .quad .Linstaller, .Llocal, .Lbrew, .Lusr, 0
bun_extras: .quad .Lbun_be_bun, 0
key_env: .quad .Lenv_db, .Lenv_channel, 0
