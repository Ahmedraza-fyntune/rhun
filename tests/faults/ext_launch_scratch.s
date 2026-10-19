.include "rhun.inc"
.include "app/taskauth.inc"
.include "app/extprepare.inc"
.include "app/extprepareretire.inc"
.bss
.p2align 3
lsf_ext: .zero EXT_SIZE
lsf_plan: .zero KE_SIZE
lsf_case: .quad 0
lsf_arguments: .quad 0
lsf_calls: .quad 0
lsf_baseline: .quad 0
.globl lsf_builds
lsf_builds: .quad 0
lsf_charge: .quad 0
lsf_expected: .zero 8192
.globl lsf_info
lsf_info: .zero 32
lsf_cleanup: .zero 32
.text
lsf_fail:
    mov edi, 74
    call sys_exit
    ud2
# A synchronous launch consumer inspects both vectors and borrows nothing after return.
FN lsf_consumer
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    lea rax, [rip + lsf_program]
    cmp [rbx], rax
    jne lsf_fail
    lea rax, [rip + lsf_script]
    cmp [rbx + 8], rax
    jne lsf_fail
    cmp qword ptr [rip + lsf_arguments], 0
    je 1f
    mov rdi, [rbx + 16]
    lea rsi, [rip + lsf_one]
    call strcmp_eq
    test eax, eax
    jz lsf_fail
    mov rdi, [rbx + 24]
    lea rsi, [rip + lsf_two]
    call strcmp_eq
    test eax, eax
    jz lsf_fail
    cmp qword ptr [rbx + 32], 0
    jne lsf_fail
    jmp 2f
1:  cmp qword ptr [rbx + 16], 0
    jne lsf_fail
2:  lea rax, [rip + lsf_inherited]
    cmp [r12], rax
    jne lsf_fail
    xor r13d, r13d
    lea r14, [rip + lsf_env_specs]
3:  mov rdi, [r14]
    test rdi, rdi
    jz 4f
    mov rsi, [r14 + 8]
    mov rdx, [r14 + 16]
    call lsf_expected_entry
    mov rdi, [r12 + r13 * 8]
    test rdi, rdi
    jz lsf_fail
    lea rsi, [rip + lsf_expected]
    call strcmp_eq
    test eax, eax
    jz lsf_fail
    inc r13
    add r14, 24
    jmp 3b
4:  cmp qword ptr [r12 + r13 * 8], 0
    jne lsf_fail
    dec r13
    mov [rip + lsf_info + 16], r13
    inc qword ptr [rip + lsf_calls]
    mov rax, -22
    EPILOGUE
# Independent exact environment oracle. Each row is prefix, literal/suffix, state flag.
lsf_expected_entry:
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea r14, [rip + lsf_expected]
    mov rsi, rbx
    call lsf_append
    test r13, r13
    jz 1f
    mov rsi, [rip + lsf_ext + EXT_state]
    call lsf_append
1:  mov rsi, r12
    call lsf_append
    mov byte ptr [r14], 0
    EPILOGUE
lsf_append:
    test rsi, rsi
    jz 3f
1:  mov al, [rsi]
    test al, al
    jz 3f
    lea rcx, [rip + lsf_expected + 8191]
    cmp r14, rcx
    jae lsf_fail
    mov [r14], al
    inc r14
    inc rsi
    jmp 1b
3:  ret
lsf_validate_counts:
    cmp [rip + lsf_builds], rdi
    jne lsf_fail
    cmp qword ptr [rip + lsf_case], 2
    jne 1f
    xor edi, edi
1:  cmp [rip + lsf_calls], rdi
    jne lsf_fail
    ret
FN lsf_setup_fcntl
    mov rax, -5
    ret
lsf_attempt:
    PROLOGUE
    lea rbx, [rip + lsf_ext]
    mov dword ptr [rbx + EXT_status], ES_IDLE
    cmp qword ptr [rip + lsf_case], 0
    jne 1f
    mov rdi, rbx
    call ext_legacy_start_impl
    jmp 2f
1:  mov rdi, rbx
    call ext_supervised_start_impl
2:  cmp dword ptr [rbx + EXT_status], ES_FAILED
    jne lsf_fail
    mov rdi, [rbx + EXT_reason]
    test rdi, rdi
    jz lsf_fail
    lea rsi, [rip + lsf_spawn_reason]
    cmp qword ptr [rip + lsf_case], 2
    jne 21f
    lea rsi, [rip + lsf_pipe_reason]
21: call strcmp_eq
    test eax, eax
    jz lsf_fail
    # Exercise the real periodic integration, including the empty extension-table case.
    mov r12d, 256
3:  call ext_tick
    lea rdi, [rip + lsf_cleanup]
    call ext_prepare_retire_status
    mov rax, [rip + lsf_cleanup + 8]
    or rax, [rip + lsf_cleanup + 16]
    jz 4f
    dec r12
    jnz 3b
    jmp lsf_fail
4:  EPILOGUE
FN main
    PROLOGUE
    cmp qword ptr [rip + g_argc], 4
    jne lsf_fail
    mov rbx, [rip + g_argv]
    mov rdi, [rbx + 16]
    mov esi, 1
    call parse_u64
    mov [rip + lsf_case], rax
    mov rdi, [rbx + 24]
    mov esi, 1
    call parse_u64
    mov [rip + lsf_arguments], rax
    mov [rip + lsf_info + 24], rax
    lea rax, [rip + lsf_environment]
    mov [rip + g_envp], rax
    lea rax, [rip + lsf_directory]
    mov [rip + g_ext_dir], rax
    lea r12, [rip + lsf_ext]
    mov dword ptr [r12 + EXT_in], -1
    mov dword ptr [r12 + EXT_out], -1
    mov dword ptr [r12 + EXT_log], -1
    mov rax, [rbx + 8]
    mov [r12 + EXT_state], rax
    mov [r12 + EXT_dir], rax
    lea rax, [rip + lsf_program]
    mov [r12 + EXT_prog], rax
    lea rax, [rip + lsf_script]
    mov [r12 + EXT_script], rax
    lea rax, [rip + lsf_empty]
    cmp qword ptr [rip + lsf_arguments], 0
    je 1f
    lea rax, [rip + lsf_words]
1:  mov [r12 + EXT_args], rax
    lea rax, [rip + lsf_owner]
    mov [r12 + EXT_owner], rax
    lea rax, [rip + lsf_name]
    mov [r12 + EXT_name], rax
    lea rax, [rip + lsf_plan]
    mov [r12 + EXT_activation_plan], rax
    mov dword ptr [r12 + EXT_manifest_ok], 1
    mov dword ptr [r12 + EXT_noconfine], 1
    call ext_prepare_retire_charge
    mov [rip + lsf_charge], rax
    mov r14d, 3
2:  call lsf_attempt
    dec r14
    jnz 2b
    mov edi, 3
    call lsf_validate_counts
    call ext_prepare_retire_charge
    cmp rax, [rip + lsf_charge]
    jne lsf_fail
    mov qword ptr [rip + lsf_builds], 0
    mov qword ptr [rip + lsf_calls], 0
    mov rax, [rip + g_mem_live]
    mov [rip + lsf_baseline], rax
    mov r14d, 4
3:  call lsf_attempt
    dec r14
    jnz 3b
    mov edi, 4
    call lsf_validate_counts
    call ext_prepare_retire_charge
    cmp rax, [rip + lsf_charge]
    jne lsf_fail
    mov rax, [rip + lsf_calls]
    mov [rip + lsf_info + 8], rax
    mov rax, [rip + g_mem_live]
    sub rax, [rip + lsf_baseline]
    test rax, rax
    jz 4f
    mov [rip + lsf_info], rax
    mov edi, 1
    lea rsi, [rip + lsf_info]
    mov edx, 32
    call write_all
    mov edi, 73
    call sys_exit
4:  xor eax, eax
    EPILOGUE
.section .rodata
lsf_program: .asciz "/fixture/program"
lsf_script: .asciz "script"
lsf_words: .asciz "one two"
lsf_one: .asciz "one"
lsf_two: .asciz "two"
lsf_empty: .asciz ""
lsf_owner: .asciz "owner"
lsf_name: .asciz "name"
lsf_directory: .asciz "/fixture"
lsf_inherited: .asciz "INHERITED_SENTINEL=keep"
lsf_old_protocol: .asciz "RHUN_PROTOCOL=old"
lsf_path: .asciz "PATH=/bin"
.p2align 3
lsf_environment: .quad lsf_inherited,lsf_old_protocol,lsf_path
.ifdef LSF_OPTIONAL
    .quad lsf_optional_lang,lsf_optional_all,lsf_optional_tz
.ifdef MACOS
    .quad lsf_optional_dev
.endif
.ifdef WINDOWS
    .quad lsf_optional_root,lsf_optional_comspec
.endif
.endif
    .quad 0

lsf_pipe_reason: .asciz "cannot create pipes"
.ifdef WINDOWS
lsf_spawn_reason: .asciz "failed to start: the program could not be executed"
lsf_expected_target: .asciz "windows-x64"
.else
lsf_spawn_reason: .asciz "cannot start the program"
.ifdef MACOS
lsf_expected_target: .asciz "macos-arm64"
.else
lsf_expected_target: .asciz "linux-x86_64"
.endif
.endif
lsf_expected_version: .asciz "0.18.0"
lsf_expected_protocol: .asciz "1.1"
lsf_expected_identity: .asciz "owner/name"
lsf_prefix_path: .asciz "PATH="
lsf_expected_path: .asciz "/bin"
lsf_prefix_home: .asciz "HOME="
lsf_prefix_tmpdir: .asciz "TMPDIR="
lsf_suffix_tmp: .asciz "/tmp"
lsf_prefix_cache: .asciz "XDG_CACHE_HOME="
lsf_suffix_cache: .asciz "/cache"
lsf_prefix_gocache: .asciz "GOCACHE="
lsf_suffix_gocache: .asciz "/gocache"
lsf_prefix_gomod: .asciz "GOMODCACHE="
lsf_suffix_gomod: .asciz "/gomod"
lsf_prefix_gopath: .asciz "GOPATH="
lsf_suffix_gopath: .asciz "/gopath"
lsf_prefix_npm: .asciz "npm_config_cache="
lsf_suffix_npm: .asciz "/npm"
lsf_prefix_xcrun: .asciz "xcrun_db="
lsf_suffix_xcrun: .asciz "/xcrun_db"
lsf_prefix_temp: .asciz "TEMP="
lsf_prefix_tmp: .asciz "TMP="
lsf_prefix_profile: .asciz "USERPROFILE="
lsf_prefix_appdata: .asciz "APPDATA="
lsf_suffix_appdata: .asciz "/appdata"
lsf_prefix_local: .asciz "LOCALAPPDATA="
lsf_suffix_local: .asciz "/localappdata"
lsf_prefix_version: .asciz "RHUN_VERSION="
lsf_prefix_protocol: .asciz "RHUN_PROTOCOL="
lsf_prefix_identity: .asciz "RHUN_EXTENSION="
lsf_prefix_target: .asciz "RHUN_TARGET="
lsf_prefix_state: .asciz "RHUN_STATE="
.p2align 3
lsf_env_specs:
    .quad lsf_inherited,0,0
.ifdef LSF_OPTIONAL
    .quad lsf_optional_lang,0,0
    .quad lsf_optional_all,0,0
    .quad lsf_optional_tz,0,0
.ifdef WINDOWS
    .quad lsf_optional_root,0,0
    .quad lsf_optional_comspec,0,0
.endif
.endif
    .quad lsf_prefix_path,lsf_expected_path,0
    .quad lsf_prefix_home,0,1
    .quad lsf_prefix_tmpdir,lsf_suffix_tmp,1
    .quad lsf_prefix_cache,lsf_suffix_cache,1
    .quad lsf_prefix_gocache,lsf_suffix_gocache,1
    .quad lsf_prefix_gomod,lsf_suffix_gomod,1
    .quad lsf_prefix_gopath,lsf_suffix_gopath,1
    .quad lsf_prefix_npm,lsf_suffix_npm,1
.ifdef LSF_OPTIONAL
    .quad lsf_optional_lang,0,0
    .quad lsf_optional_all,0,0
    .quad lsf_optional_tz,0,0
.endif
.ifdef MACOS
    .quad lsf_prefix_xcrun,lsf_suffix_xcrun,1
.ifdef LSF_OPTIONAL
    .quad lsf_optional_dev,0,0
.endif
.endif
.ifdef WINDOWS
 .ifdef LSF_OPTIONAL
    .quad lsf_optional_root,0,0
    .quad lsf_optional_comspec,0,0
.endif
    .quad lsf_prefix_temp,lsf_suffix_tmp,1
    .quad lsf_prefix_tmp,lsf_suffix_tmp,1
    .quad lsf_prefix_profile,0,1
    .quad lsf_prefix_appdata,lsf_suffix_appdata,1
    .quad lsf_prefix_local,lsf_suffix_local,1
.endif
    .quad lsf_prefix_version,lsf_expected_version,0
    .quad lsf_prefix_protocol,lsf_expected_protocol,0
    .quad lsf_prefix_identity,lsf_expected_identity,0
    .quad lsf_prefix_target,lsf_expected_target,0
    .quad lsf_prefix_state,0,1
    .quad 0,0,0

lsf_optional_lang: .asciz "LANG=fixture-locale"
lsf_optional_all: .asciz "LC_ALL=fixture-all"
lsf_optional_tz: .asciz "TZ=UTC"
lsf_optional_dev: .asciz "DEVELOPER_DIR=/fixture/xcode"
lsf_optional_root: .asciz "SYSTEMROOT=C:/fixture/Windows"
lsf_optional_comspec: .asciz "COMSPEC=C:/fixture/cmd.exe"
