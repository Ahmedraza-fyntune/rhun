# Distribution and Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install rhun with one command from GitHub releases, and let rhun check for, install and restart into new versions without slowing startup.

**Architecture:** A tag push runs a GitHub workflow that builds, tests, signs and publishes Linux and macOS archives plus `VERSION`, `SHA256SUMS` and `install.sh` to a GitHub release. `install.sh` does first installs and in-place updates. Inside rhun, `src/app/update.s` runs `curl` (or `wget`) in the background the way `git.s` runs git, shows the result in the status bar and settings, runs the release's `install.sh --update`, and restarts through the normal quit path.

**Tech Stack:** x86-64 GNU assembly (Intel syntax; translated to AArch64 on macOS by `tools/arm64.py`), POSIX sh, GitHub Actions, `gh`, `codesign`/`notarytool`.

**Spec:** `docs/superpowers/specs/2026-09-26-distribution-and-updates-design.md`

**Note on code in this plan:** small and medium pieces carry their code here. The three large files (`src/app/update.s`, `install.sh`, `.github/workflows/release.yml`) are specified by exact interfaces, strings, commands and tests. They are written during their tasks, following `src/app/git.s` (background jobs) and `tools/install.sh` / `tools/package-mac.sh` (shell style).

## Global Constraints

- Platforms: Linux x86-64 and macOS on Apple silicon only.
- Release URL base: `https://github.com/vshvedov/rhun/releases`, overridable with `RHUN_RELEASES_URL` (installer and editor).
- Latest version: `<base>/latest/download/VERSION`; a release's file: `<base>/download/vVERSION/NAME`.
- Version format: `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$`, at most 31 characters.
- Archives: `rhun-VERSION-linux-x86_64.tar.gz` (top folder `rhun-VERSION/`), `rhun-VERSION-macos-arm64.zip` (made with `ditto`), `rhun-VERSION-macos-arm64.dmg`.
- macOS team ID: `G29V3JRMJJ`. Bundle id: `com.r13.rhun`.
- `RHUN_DIST=1` only in the release workflow; it sets `rhun_dist`.
- Update check: first automatic check 5000 ms after startup, then every 86400000 ms; throttle 3600 s; curl `--max-time 20`, wget `-T 20`; reply capped at 64 bytes.
- Commit messages: short plain subject in the repo's style; never mention Claude, no `Co-Authored-By` trailers.
- Every rhun run in tests gets its own `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`.
- Assembly must build with GNU as on Linux (no local labels with a leading zero, `.equ` defined before use) and through `tools/arm64.py` on macOS. Build both after every assembly change.
- If a build or test times out, kill the whole process tree and confirm with `ps` before going on; keep `tools/arm64.py`'s 512 MB / 120 s guard.
- Linux builds and tests run in Docker `--platform linux/amd64` (image `rhun-linux-ref`, or a derived image with the test tools).

---

### Task 1: `VERSION` as the single source of the version

**Files:**
- Create: `VERSION`
- Modify: `tools/gen-assets.sh`, `src/main.s:145-175,281`, `tools/build-mac.sh:75`, `tools/package-mac.sh:21`, `tests/run.sh`

**Interfaces:**
- Produces: `rhun_version` (global, NUL-terminated string, e.g. `"0.13.55"`), `rhun_dist` (global `.long`, 1 or 0).

- [ ] **Step 1: Write the failing check.** In `tests/run.sh`, after the `check strfind …` line, add:

```sh
if [ "$(build/rhun --version)" = "rhun $(cat VERSION)" ]; then echo "ok   version"; else echo "FAIL version"; fail=1; fi
```

- [ ] **Step 2: Run it and see it fail.** `printf '0.0.1\n' > VERSION && tests/run.sh 2>&1 | grep version` gives `FAIL version`, because `--version` still prints `rhun 0.13.55`.

- [ ] **Step 3: Implement.**
  - `VERSION` holds `0.13.55` and a newline.
  - At the end of `tools/gen-assets.sh`:

```sh
# the version (VERSION) and whether this is a release build (RHUN_DIST=1, set by the release workflow)
dist=0
[ "${RHUN_DIST:-}" = 1 ] && dist=1
printf '.globl rhun_version, rhun_dist\nrhun_version: .asciz "%s"\n.p2align 2\nrhun_dist: .long %d\n' "$(cat VERSION)" "$dist"
```

  - `src/main.s`: `.Lversion` becomes `.asciz "rhun "`. `help_flag` writes `.Lversion`, then `rhun_version`, then `.Lnl` (`.asciz "\n"`) before `sys_exit`, through a local `out_cstr` helper (`strlen` then `write_all(1, …)`).
  - `tools/build-mac.sh` and `tools/package-mac.sh`: `version=$(cat VERSION)` instead of the `sed` over `src/main.s`.

- [ ] **Step 4: Run.** `tests/run.sh` on macOS: `ok   version`. `./build.sh release` in Docker, then `build/rhun --version` prints `rhun 0.13.55`. `RHUN_DIST=1 ./build.sh && grep -A1 rhun_dist build/assets.s` shows `.long 1`.

- [ ] **Step 5: Commit** `VERSION holds the version; the build embeds it`.

### Task 2: Version comparison

**Files:**
- Create: `src/app/update.s` (first part), `tests/update_test.s`, `tests/data/versions.txt`, `tests/data/versions.expected`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces: `ver_valid(ptr, len) -> eax 1/0`, following the version format in Global Constraints. `ver_cmp(a cstr, b cstr) -> eax -1/0/1`: numeric, field by field over up to 4 dot-separated fields; missing fields count as 0; parsing stops at the first byte that is neither a digit nor `.`, so `-rc1` is ignored.

- [ ] **Step 1: Write the test data.** `tests/data/versions.txt`, one case per line, `A B`:

```
0.13.55 0.13.55
0.13.56 0.13.55
0.13.55 0.13.56
0.14.0 0.13.99
1.0.0 0.99.99
0.13.100 0.13.99
10.0.0 9.9.9
0.13.55-rc1 0.13.55
0.13 0.13.0
garbage 0.13.55
1.2.3.4 1.2.3
<html> 0.13.55
```

`tests/data/versions.expected`: for each line, `ver_cmp(A, B)` then `ver_valid(A)`:

```
0 1
1 1
-1 1
1 1
1 1
1 1
1 1
0 1
0 0
-1 0
1 0
-1 0
```

- [ ] **Step 2: The test program.** `tests/update_test.s`, in the shape of `tests/str_test.s`: read the file named in `argv[1]`, and for each line split at the space, NUL-terminate both halves, and print `ver_cmp` (as `-1`, `0`, `1`) and `ver_valid(A, len A)`, space-separated, one line per case. Add `check versions build/update_test tests/data/versions.txt` to `tests/run.sh`.

- [ ] **Step 3: Run it and see it fail.** `tests/run.sh` fails to link `update_test`: `ver_cmp` is undefined.

- [ ] **Step 4: Implement.** Create `src/app/update.s` with `.include "rhun.inc"`, then `FN ver_valid` and `FN ver_cmp`. `ver_cmp` keeps two 4-quad arrays on the stack, fills each with a helper `ver_fields(cstr, out)` (for each field: `parse_u64` over the digits, then skip one `.`, stop at anything else), and compares element by element.

- [ ] **Step 5: Run.** `tests/run.sh` shows `ok   versions` on macOS, and the same in Docker (`./build.sh test && build/update_test tests/data/versions.txt | cmp - tests/data/versions.expected`).

- [ ] **Step 6: Commit** `Version comparison for the updater`.

### Task 3: Checking for updates

**Files:**
- Modify: `src/app/update.s`, `src/app/app.s` (`app_init`, `app_timeout`, `app_tick`), `src/app/control.s` (commands), `src/app/keys.s` (palette), `src/app/config.s` (setting variable only), `src/rhun.inc` (state constants)
- Create: `tests/update.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `ver_valid`, `ver_cmp`, `rhun_version`, `rhun_dist`, `run_piped`, `watch_add`, `watch_remove`, `proc_wait`, `proc_which`, `getenv`, `time_ms`, `time_now`, `file_read_all`, `file_write_all`, `mkdir_parent`, `ini_init`, `ini_next`, `app_toast`, `g_headless`, `g_envp`.
- Produces:
  - `rhun.inc`: `.equ UP_IDLE, 0`, `UP_CHECKING, 1`, `UP_AVAILABLE, 2`, `UP_INSTALLING, 3`, `UP_READY, 4`.
  - Globals `g_update_state` (.long), `g_restart` (.long), `cfg_update_check` (.long 1, in `config.s`), `g_update_desc` (256-byte buffer holding the settings row's text).
  - `update_init()`: reads the state file and schedules the first automatic check.
  - `update_timeout() -> eax` ms or -1.
  - `update_tick()`.
  - `update_apply()`: the setting changed; schedule or cancel.
  - `update_busy() -> eax 1` while a job runs.
  - `update_dump(sb)`: appends `state=<idle|checking|available|installing|ready> current=<v> latest=<v or empty> error=<text or empty>\n`.
  - `update_desc_refresh()`: rewrites `g_update_desc`.
  - `cmd_check_for_updates()`.
  - `update_installable() -> eax 1` when `rhun_dist` = 1 or `RHUN_UPDATE_TARGET` is set.
  - Control commands `wait-update` (like `wait-git`, at most 30 s) and `print-update`.
  - Palette entry `COMMAND check_for_updates, "Check for Updates", cmd_check_for_updates, ""`.

**Behavior (from the spec, section 4):**
- **Automatic checks are allowed when:** `cfg_update_check` && ((`rhun_dist` && !`g_headless`) || `RHUN_UPDATE_TARGET` set).
- **`update_init`:**
  - Reads `$XDG_STATE_HOME/rhun/update` (or `$HOME/.local/state/rhun/update`) with the ini iterator: `checked=` into `up_checked`, `latest=` into `up_latest` (only if `ver_valid`).
  - If allowed, sets `up_next_at = time_ms() + 5000`.
- **When the timer fires:** set `up_next_at = time_ms() + 86400000`.
  - If `time_now() - up_checked < 3600` and `up_latest` is set: decide from `up_latest` without fetching.
  - Otherwise start a fetch.
- **Fetch:**
  - `url = base + "/latest/download/VERSION"`.
  - With curl: `[curl, -fsSL, --max-time, 20, --proto, =https, --proto-redir, =https, url]`, dropping the four `--proto` items when `RHUN_RELEASES_URL` is set.
  - Otherwise wget: `[wget, -qO-, -T, 20, url]`.
  - Neither: error `Checking for updates needs curl or wget`.
  - One job at a time (`up_pid`, `up_fd`, `up_kind` 1 check / 2 install, `up_out` SB). `on_up_job` reads until EOF, then `watch_remove`, `close`, `proc_wait(pid, 0)`, and dispatches.
- **Check done:**
  - Exit status non-zero: error `download failed`.
  - Otherwise trim trailing whitespace; the reply must pass `ver_valid` and be at most 31 bytes, else error `unexpected reply`.
  - On success: copy into `up_latest`, set `up_checked = time_now()`, write the state file (`checked=N\nlatest=V\n`, via `mkdir_parent` and `file_write_all`), and clear the error.
  - `ver_cmp(up_latest, rhun_version) > 0` && `update_installable()`: `UP_AVAILABLE`. Otherwise `UP_IDLE`.
- **Toasts, for manual checks only:**
  - Error: `Couldn't check for updates: <error>`.
  - Not newer: `rhun <current> is the latest`.
  - Newer but source build: `rhun <v> is available; pull and rebuild to update`.
  - Newer and installable: no toast; the status bar item appears.
- **`update_desc_refresh`:**
  - CHECKING: `Checking…`
  - Error set: `Couldn't check: <error>`
  - AVAILABLE: `rhun <v> is available`
  - INSTALLING: `Installing <v>…`
  - READY: `<v> is installed; restart to use it`
  - Newer but source build: `<v> is available (built from source)`
  - Checked before: `<current> is the latest (checked <age>)`, where age is `just now` under 60 s, `N min ago` under 3600 s, `N h ago` under 86400 s, else `N days ago`.
  - Never checked: `Not checked yet`.

- [ ] **Step 1: Write the failing test.** `tests/update.sh` (POSIX sh, `set -u`, in the shape of `tests/files.sh`):

```sh
#!/bin/sh
# the updater against a fake release folder (file://) and stub programs; prints ok/FAIL per case
set -u
cd "$(dirname "$0")/.."
w=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$w"' EXIT HUP INT TERM
cur=$(cat VERSION)
fail=0
mkdir -p "$w/proj" "$w/rel/latest/download" "$w/rel/download/v99.0.0"
cat > "$w/rel/download/v99.0.0/install.sh" <<'EOF'
printf '%s\n' "$@" > "$STUB_LOG"
if [ -n "${STUB_FAIL:-}" ]; then echo "rhun install: stub failure"; exit 3; fi
EOF
cat > "$w/target" <<EOF
#!/bin/sh
printf 'restarted %s\n' "\$*" > "$w/restart.log"
EOF
chmod +x "$w/target"
# run CASE VERSION-REPLY SCRIPT-LINES... : runs rhun headless; out in $w/CASE.out
run() {
    c=$1; reply=$2; shift 2
    rm -rf "$w/home" "$w/state" "$w/config"; mkdir -p "$w/home" "$w/state/rhun" "$w/config"
    if [ -n "$reply" ]; then printf '%s\n' "$reply" > "$w/rel/latest/download/VERSION"; else rm -f "$w/rel/latest/download/VERSION"; fi
    [ -n "${SEED:-}" ] && printf '%s' "$SEED" > "$w/state/rhun/update"
    printf '%s\n' "$@" > "$w/$c.rsc"
    HOME=$w/home XDG_CONFIG_HOME=$w/config XDG_STATE_HOME=$w/state RHUN_RELEASES_URL=file://$w/rel \
        STUB_LOG=$w/stub.log ${TARGET:+RHUN_UPDATE_TARGET=$TARGET} \
        build/rhun "$w/proj" --headless 800x600 --script "$w/$c.rsc" > "$w/$c.out" 2>&1
}
expect() { # CASE LINE
    if grep -qxF "$2" "$w/$1.out"; then echo "ok   update/$1"; else echo "FAIL update/$1"; cat "$w/$1.out"; fail=1; fi
}
TARGET=$w/target
run newer 99.0.0 'cmd check_for_updates' wait-update print-update
expect newer "state=available current=$cur latest=99.0.0 error="
run same "$cur" 'cmd check_for_updates' wait-update print-update
expect same "state=idle current=$cur latest=$cur error="
run garbage '<html>' 'cmd check_for_updates' wait-update print-update
expect garbage "state=idle current=$cur latest= error=unexpected reply"
run missing '' 'cmd check_for_updates' wait-update print-update
expect missing "state=idle current=$cur latest= error=download failed"
SEED="checked=$(date +%s)
latest=98.0.0
" run throttled 99.0.0 'wait 5500' wait-update print-update
expect throttled "state=available current=$cur latest=98.0.0 error="
SEED="checked=1
latest=98.0.0
" run stale 99.0.0 'wait 5500' wait-update print-update
expect stale "state=available current=$cur latest=99.0.0 error="
TARGET=
run source 99.0.0 'cmd check_for_updates' wait-update print-update
expect source "state=idle current=$cur latest=99.0.0 error="
run source-auto 99.0.0 'wait 5500' wait-update print-update
expect source-auto "state=idle current=$cur latest= error="
exit $fail
```

Add `sh tests/update.sh || fail=1` to `tests/run.sh` after `tests/files.sh`.

- [ ] **Step 2: Run it and see it fail.** `sh tests/update.sh`: every case fails (`print-update` is an unknown command).
- [ ] **Step 3: Implement** the behavior above in `src/app/update.s`. Then:
  - `app_init`: call `update_init` after the config is read.
  - `app_timeout`: fold in `update_timeout`, like `git_timeout`.
  - `app_tick`: call `update_tick`.
  - `control.s`: add `wait-update` and `print-update` to `ctl_table` and the header comment.
  - `keys.s`: add the palette entry.
  - `config.s`: add `cfg_update_check: .long 1` and its `.globl`.
  - `c_wait` must run the loop and `app_tick` so the 5 s timer fires in script mode; check it, and add `app_tick` if it is missing.
- [ ] **Step 4: Run.** `sh tests/update.sh`: all eight cases `ok` on macOS. Then in Docker: `./build.sh test && sh tests/update.sh` (the image needs curl; add it to the test image).
- [ ] **Step 5: Commit** `Check for updates in the background`.

### Task 4: Installing and restarting

**Files:**
- Modify: `src/app/update.s`, `src/app/app.s` (dialog cancel clears `g_restart`), `src/main.s` (after the loop), `src/app/keys.s`, `src/mac/rt.s` (`mac_exe_path`), `tests/update.sh`

**Interfaces:**
- Consumes: Task 3's globals and job machinery, `cmd_quit`, `g_project`, `g_envp`, `proc_spawn`, `proc_wait`.
- Produces:
  - `cmd_install_update()`, `cmd_restart_to_update()`, `update_click()` (AVAILABLE: install; READY: restart).
  - `update_item() -> rax` cstr for the status bar (`Update to <v>`, `Updating…`, `Restart to update`) or 0.
  - `update_restart()`: called by `main` after the loop; returns only if the new rhun could not be started.
  - `update_target() -> rax` cstr or 0.
  - macOS native `mac_exe_path(buf, size) -> x8` length or -1, using `_NSGetExecutablePath` and `realpath`.
  - Palette entries `install_update` ("Install Update") and `restart_to_update` ("Restart to Update").

**Behavior:**
- **`update_target`:**
  - `RHUN_UPDATE_TARGET` if set.
  - Otherwise, on Linux, `readlink("/proc/self/exe")` with a trailing ` (deleted)` removed.
  - On macOS, `mac_exe_path`, cut before `/Contents/MacOS/`. A path without that part is an error: `rhun is not running from an app bundle`.
- **`cmd_install_update`:**
  - Only in `UP_AVAILABLE`.
  - Not installable: toast `This rhun was built from source; pull and rebuild to update`.
  - Otherwise `run_piped` with argv `[sh, -c, SCRIPT, sh, <base>/download/v<latest>/install.sh, <target>, <latest>]`:
    - curl SCRIPT: `exec 2>&1; f=$(mktemp) || exit 1; curl -fsSL PROTO -o "$f" "$1" && sh "$f" --update --target "$2" --version "$3"; s=$?; rm -f "$f"; exit $s`. `PROTO` is `--proto =https --proto-redir =https`, or nothing when `RHUN_RELEASES_URL` is set, so there are two string constants.
    - wget SCRIPT: the same with `wget -q -O "$f" "$1"`.
  - State becomes `UP_INSTALLING`.
- **Install done:**
  - Exit 0: `UP_READY`.
  - Otherwise: error is the last non-empty line of the output, cut to 200 bytes. Toast `Update failed: <error>`, state back to `UP_AVAILABLE`.
- **`cmd_restart_to_update`:**
  - Only in `UP_READY`: set `g_restart = 1`, then `cmd_quit`.
  - In `app.s`, `dialog_choose` with choice 0 (Cancel) clears `g_restart`.
- **`main`,** after `.Lm_exit`'s `session_save` / `config_save`: if `g_restart`, call `update_restart`.
- **`update_restart`:**
  - argv is `[target, g_project, 0]`.
  - Linux: `close_range(3, ~0, 0)`, or on `-ENOSYS` close 3..1023; then `execve(target, argv, g_envp)`.
  - macOS: `proc_spawn([/usr/bin/open, -n, -a, target, --args, g_project, 0], g_envp, 0, 0, 1, 2, 0)`, then `proc_wait(pid, 0)`. With `RHUN_UPDATE_TARGET` set on macOS, exec the target directly, as on Linux, so the test works on both.

- [ ] **Step 1: Extend the failing test.** Append to `tests/update.sh`, before `exit $fail`:

```sh
TARGET=$w/target
run install 99.0.0 'cmd check_for_updates' wait-update 'cmd install_update' wait-update print-update
expect install "state=ready current=$cur latest=99.0.0 error="
if [ "$(tr '\n' ' ' < "$w/stub.log")" = "--update --target $w/target --version 99.0.0 " ]; then echo "ok   update/install-args"; else echo "FAIL update/install-args"; cat "$w/stub.log"; fail=1; fi
STUB_FAIL=1 run install-fail 99.0.0 'cmd check_for_updates' wait-update 'cmd install_update' wait-update print-update
expect install-fail "state=available current=$cur latest=99.0.0 error=rhun install: stub failure"
rm -f "$w/restart.log"
run restart 99.0.0 'cmd check_for_updates' wait-update 'cmd install_update' wait-update 'cmd restart_to_update'
if [ "$(cat "$w/restart.log" 2>/dev/null)" = "restarted $w/proj" ]; then echo "ok   update/restart"; else echo "FAIL update/restart"; cat "$w/restart.out"; fail=1; fi
```

`STUB_FAIL` reaches the stub because `run` passes the environment through; export it for that one command with `env STUB_FAIL=1` inside `run` if the shell's prefix-assignment-on-function does not export it.

- [ ] **Step 2: Run it and see it fail.** The three new cases fail.
- [ ] **Step 3: Implement** the behavior above.
- [ ] **Step 4: Run.** `sh tests/update.sh`: all cases `ok` on macOS and in Docker. Build `tools/build-mac.sh` and the Linux build.
- [ ] **Step 5: Commit** `Install updates and restart into them`.

### Task 5: Status bar item, settings rows, palette

**Files:**
- Modify: `src/app/app.s` (`statusbar_draw`), `src/app/config.s` (rows, `.Ls_updates`), `src/app/settings.s` (`ST_ACTION` drawing, `section_title`, `desc_room`, `setting_applied`), `src/rhun.inc` (`ST_ACTION`)

**Interfaces:**
- Consumes: `update_item`, `update_click`, `update_desc_refresh`, `g_update_desc`, `cmd_check_for_updates`, `update_apply`, `cfg_update_check`.
- Produces: `.equ ST_ACTION, 5` (a row with a button: `SET_ptr` is the function the button calls, `SET_desc` points at a writable buffer, `SET_label` the button's row label; `SET_key` is non-zero but never read or written in the config).

**Behavior:**
- **`statusbar_draw`:**
  - The right edge `x + w - MI_12` is computed once, and the update item is drawn there first when `update_item` returns text: accent color, a thin rounded frame, `ui_btn` with id `ID_STATUS + 1`, pointer cursor on hover, `update_click` on click.
  - The remaining right-side items start left of it (text documents).
  - `iv_status` gets the width up to it (images).
  - The item is shown with no document open too.
- **`config.s`:**
  - `.Ls_updates: .asciz "updates"`.
  - `SETTING .Ls_updates, check, ST_BOOL, cfg_update_check, 0, 1, 1, 0, "Check for updates", "Look for a new version at startup and once a day."`
  - An `ST_ACTION` row written with a small `SETTING_ACTION sec, key, fn, label, descptr` macro: `SETTING_ACTION .Ls_updates, check_now, cmd_check_for_updates, "Updates", g_update_desc`.
  - `setting_find` and `config_save` skip `ST_ACTION` rows.
- **`settings.s`:**
  - `section_title` tells `ui` from `updates` by the second byte (`Updates` title).
  - `settings_draw` calls `update_desc_refresh` before the rows.
  - `.Lsd_action` draws a framed button `Check now` (like the theme button, without the chevron) and calls `[rbx + SET_ptr]` on click.
  - `desc_room` gives `ST_ACTION` the button's width plus `MI_32`.
  - `setting_applied` calls `update_apply` when `SET_ptr` is `cfg_update_check`.

- [ ] **Step 1: Check the current look.** Headless screenshots, each in its own HOME: `cmd settings` then `shot`; and a status bar with a document open. Convert with `tools/ppm2png.py` and look at them.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Verify.**
  - Screenshots with `RHUN_UPDATE_TARGET`, `RHUN_RELEASES_URL` and a newer fake release: after `cmd check_for_updates` / `wait-update` the status bar shows `Update to 99.0.0`.
  - The Settings page shows the Updates section with the switch and the Check now row reading `rhun 99.0.0 is available`.
  - `click` on the item's coordinates runs the install (then `print-update` shows `ready`).
  - Toggling the switch writes `[updates]` `check = false` to the isolated config on exit, and the config has no `check_now` line.
  - `tests/run.sh` still passes, and the existing `tests/data/*.ui.expected` are unchanged (or updated only where the Settings page or palette listing legitimately grew; check each diff by eye).
- [ ] **Step 4: Commit** `Updates in the status bar, Settings and the palette`.

### Task 6: PNG icons for Linux launchers

**Files:**
- Create: `tools/png-icons.py`, `assets/icons/rhun-256.png`, `assets/icons/rhun-512.png`

- [ ] **Step 1: Write `tools/png-icons.py`.**
  - It draws `rhun.svg` (rounded square `#1c1e24`, x/y 4, size 56, radius 12.5, in a 64 box; the rune strokes of `tools/mac-icon.py`'s `RUNE`, width 4.8, color `#8aa4ff`, round caps) with distance fields and 4x4 supersampling.
  - It writes RGBA PNGs with `zlib`/`struct`, as `mac-icon.py` does, at 256 and 512 px.
  - It reuses the `rrect` and segment-distance helpers by importing them from `mac-icon.py` via `importlib` (the file name has a dash).
- [ ] **Step 2: Run** `python3 tools/png-icons.py`, then open both PNGs and compare them with `assets/icons/rhun.svg` rendered by Quick Look (`qlmanage -t -s 512`).
- [ ] **Step 3: Commit** `PNG icons for launchers that do not draw SVG`.

### Task 7: The installer

**Files:**
- Create: `install.sh`, `tests/install.sh`

**Interfaces:**
- Consumes: the release layout (Global Constraints), `RHUN_RELEASES_URL`.
- Produces: the command-line interface of spec section 3: `--version`, `--prefix`, `--app-dir`, `--no-modify-path`, `--uninstall`, `--update --target`. Also `RHUN_TEAM_ID` (test-only override of `G29V3JRMJJ`, for bundles signed with another identity in tests).

**Structure of `install.sh`:**
- `#!/bin/sh`, `set -eu`, all code inside functions, and the last line `main "$@"`.
- `say()` for stdout; `fail()` for `rhun install: …` on stderr, then `exit 1`.
- `fetch URL FILE` (curl or wget, `--proto =https --proto-redir =https` unless `RHUN_RELEASES_URL` is set).
- `sha256_check DIR FILE`.
- `platform` (sets `os`, `asset`).
- `install_linux PREFIX DIR`, `install_mac APPDIR DIR`.
- `refresh_desktop PREFIX`.
- `add_path BIN`, `remove_path`.
- `uninstall`.
- `installed_version TARGET`.
- `main` (parses options, dispatches).
- PATH lines are written as `# rhun` / line / `# rhun end`, so they can be removed.

**Tests, `tests/install.sh ENV`:**
- It builds a fake release folder from the current build:
  - Linux: a tarball from `build/rhun` and the assets, laid out as in the workflow.
  - macOS: `ditto` of `build/rhun.app`, signed ad hoc or with the local Developer ID, with `RHUN_TEAM_ID` matching.
  - Plus `SHA256SUMS`, `VERSION`, and `install.sh` itself.
- It checks each case and prints `ok`/`FAIL`:
  - `fresh`: files exist, `rhun --version` runs, `Exec=` is absolute, the PATH block appears once in the startup file, and running it again does not add a second.
  - `update`: a second fake version `99.0.0` built by rewriting `VERSION` in a copy is installed with `--update --target`. The binary changes while a copy of the old one is running (Linux: `sleep`-like run of the old binary via `--headless … --script` with `wait 3000`).
  - `same`: `--update` to the installed version exits 0 without touching files (the mtime is unchanged).
  - `unwritable`: a target whose folder is `chmod 555` exits 1 with `rhun install: … is not writable`.
  - `badsum`: a corrupted archive exits 1 and leaves the installation untouched.
  - `uninstall`: everything is gone, including the PATH block; `~/.config/rhun` is kept.
  - `platform`: `uname -m` faked through a PATH shim to `aarch64` exits 1 with the platform message.
- Runs, from macOS:
  - `docker run --platform linux/amd64` with Debian (dash as `/bin/sh`, curl), again with `wget` only (a python http server as the release host), and Alpine (busybox `sh`, busybox `wget`).
  - On macOS itself, with `--app-dir` in a scratch folder and `HOME` in a scratch folder.

- [ ] **Step 1: Write `tests/install.sh`** with the cases above.
- [ ] **Step 2: Run it and see it fail** (no `install.sh`).
- [ ] **Step 3: Write `install.sh`** to spec section 3.
- [ ] **Step 4: Run** the three Docker variants and the macOS run until every case is `ok`. `sh -n install.sh`, plus `shellcheck -s sh install.sh` if shellcheck is available.
- [ ] **Step 5: Commit** `install.sh: install, update and remove rhun from GitHub releases`.

### Task 8: Release tooling and the workflow

**Files:**
- Create: `tools/release.sh`, `.github/workflows/release.yml`
- Modify: `tools/package-mac.sh`

**`tools/package-mac.sh` changes:**
- Notary credentials: when `RHUN_NOTARY_KEY`, `RHUN_NOTARY_KEY_ID` and `RHUN_NOTARY_ISSUER` are set, `submit` uses `xcrun notarytool submit "$1" --key "$RHUN_NOTARY_KEY" --key-id "$RHUN_NOTARY_KEY_ID" --issuer "$RHUN_NOTARY_ISSUER" --wait`, and the profile check is skipped.
- After stapling the app: `ditto -c -k --keepParent build/rhun.app build/rhun-$version-macos-arm64.zip`.
- Prints both paths at the end.

**`tools/release.sh VERSION`:**

```sh
#!/bin/sh
# cuts a release: VERSION, a commit, the tag vVERSION, pushed; the workflow builds and publishes it
# usage: tools/release.sh 0.14.0   (a version with a dash, 0.14.0-rc1, is published as a prerelease)
set -eu
cd "$(dirname "$0")/.."
v=${1:?usage: tools/release.sh VERSION}
echo "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' || { echo "release: bad version $v" >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "release: not on main" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "release: uncommitted changes" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "release: main differs from origin/main" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/v$v" >/dev/null && { echo "release: v$v exists" >&2; exit 1; }
printf '%s\n' "$v" > VERSION
git commit -q -m "Version $v" VERSION
git tag -a "v$v" -m "rhun $v"
git push -q origin main "v$v"
echo "pushed v$v; follow it with: gh run watch"
```

**`.github/workflows/release.yml`:**
- `on: push: tags: ['v*']`, `permissions: contents: write`, `concurrency: release`.
- Job `linux` on `ubuntu-24.04`:
  - `actions/checkout@v4`.
  - A tag check step: `[ "${GITHUB_REF_NAME#v}" = "$(cat VERSION)" ]`.
  - `sudo apt-get install -y binutils curl git python3`.
  - `tests/run.sh`.
  - `RHUN_DIST=1 ./build.sh release`.
  - The pack step: stage `rhun-$V/{bin,share/applications,share/icons/hicolor/{scalable,256x256,512x512}/apps}`, copy `LICENSE`, `tar -czf`.
  - `actions/upload-artifact@v4` named `linux`.
- Job `macos` on `macos-15`:
  - checkout, then the tag check.
  - Import the certificate:
    - `echo "$MACOS_CERT_P12" | base64 -d > cert.p12`
    - `security create-keychain -p "$KP" build.keychain`, `security set-keychain-settings -lut 21600 build.keychain`, `security unlock-keychain -p "$KP" build.keychain`
    - `security import cert.p12 -k build.keychain -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign`
    - `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KP" build.keychain`
    - `security list-keychains -d user -s build.keychain $(security list-keychains -d user | tr -d '"')`
    - `KP` is a random per-run password.
  - `tests/run.sh`.
  - Write the API key: `echo "$APPLE_API_KEY_P8" | base64 -d > "$RUNNER_TEMP/key.p8"`.
  - `RHUN_DIST=1 RHUN_NOTARY_KEY=… RHUN_NOTARY_KEY_ID=… RHUN_NOTARY_ISSUER=… tools/package-mac.sh`.
  - Upload artifact `macos` (zip and dmg).
  - An `if: always()` step deletes the keychain.
- Job `publish` on `ubuntu-24.04`, `needs: [linux, macos]`:
  - checkout with `fetch-depth: 0`.
  - `actions/download-artifact@v4` into `dist/`, `merge-multiple: true`.
  - `cp install.sh dist/`, `cat VERSION > dist/VERSION`, `(cd dist && sha256sum rhun-* > SHA256SUMS)`.
  - Notes: `prev=$(git describe --tags --abbrev=0 --match 'v*' "$GITHUB_REF_NAME^" 2>/dev/null || true)`, then `git log --format='- %s' ${prev:+$prev..}$GITHUB_REF_NAME > notes.md`.
  - `gh release create "$GITHUB_REF_NAME" --draft --title "rhun $V" --notes-file notes.md $pre dist/*`, where `pre=--prerelease` if `V` contains `-`.
  - `gh release edit "$GITHUB_REF_NAME" --draft=false`, with `GH_TOKEN: ${{ github.token }}`.

- [ ] **Step 1: Change `tools/package-mac.sh`** and run it locally with `RHUN_NOTARIZE=0`. Check that `build/rhun-0.13.55-macos-arm64.zip` unpacks with `ditto -x -k` to a bundle that passes `codesign --verify --strict --deep` and shows `TeamIdentifier=G29V3JRMJJ` in `codesign -dv`.
- [ ] **Step 2: Write `tools/release.sh`** and test its refusals in a scratch clone: bad version, dirty tree, a branch other than main, an existing tag. Never push from the test: point the clone's `origin` at a scratch bare repo.
- [ ] **Step 3: Write the workflow.** Lint it with `actionlint` if available (`brew` is not assumed; otherwise `python3 -c 'import yaml…'` for syntax). Check every shell step by running it locally where it makes sense (the pack step on the Linux build in Docker; the notes step in the repo).
- [ ] **Step 4: Commit** `Release workflow: build, test, sign, notarize and publish on a version tag`.

### Task 9: Documentation

**Files:**
- Modify: `README.md` ("Get rhun"), `docs/guide.md` (new "Install and update" section; "Build" mentions `VERSION` and `tools/release.sh`)

- [ ] **Step 1: README.** Replace the "first release will include…" sentence with the curl one-liner, the wget alternative, and one sentence saying rhun keeps itself up to date (from Settings, or Check for Updates in the palette). Keep the README's tone and length (see the README-is-marketing note).
- [ ] **Step 2: Guide.** Add an "Install and update" section:
  - what the installer puts where on each system, and its options
  - uninstalling
  - the `[updates]` `check` setting
  - what the check sends: one HTTPS request to github.com for a small text file, via curl or wget
  - that source builds only check when asked
  - making a release (`tools/release.sh`, the secrets)
- [ ] **Step 3: Commit** `README and guide: installing and updating`.

### Task 10: End-to-end verification

- [ ] **Step 1:** `tests/run.sh` on macOS and in Docker (Linux): all `ok`.
- [ ] **Step 2: macOS by hand.**
  - Make a fake release folder with a newer version (a `RHUN_DIST=1` build with `VERSION` 99.0.0, zipped with ditto, `SHA256SUMS`, `install.sh`).
  - Install the current version from it into a scratch `--app-dir`.
  - Start that copy with `RHUN_RELEASES_URL=file://…` and `RHUN_TEAM_ID` set if signed ad hoc.
  - Wait for `Update to 99.0.0`, click it, see `Restart to update`, open a file with unsaved changes, click restart, and answer the dialog both ways (Cancel keeps running; Save restarts).
  - Confirm the new window reports 99.0.0 (`--version` of the installed binary and the Settings row) and reopens the project.
- [ ] **Step 3: Linux by hand**, the same in the Docker desktop image (`rhun-desktop`, sway headless + wayvnc) as far as it allows. At least: status bar item, install, restart via `execve` keeps the pid.
- [ ] **Step 4:** List what could not be verified without the real secrets (CI signing and notarization, the published release) in the final report, together with the maintainer steps.
