# Distribution and updates

Date: 2026-09-26. Status: approved design, not yet implemented.

## Goal

People install rhun with one command and keep it current from inside the editor, with nothing hosted but GitHub: no package managers, no Homebrew, no servers of our own.

- One `curl … | sh` line installs rhun on Linux x86-64 and macOS on Apple silicon, desktop entry and icons included.
- rhun looks for a new version at startup without slowing startup down, or when asked. It offers the update in the status bar, installs it in the background, and restarts into it.
- Pushing a version tag builds, tests, signs, notarizes and publishes both platforms.

Not in scope: Linux on ARM, Intel Macs, Windows, distribution packages, delta updates, rollback, a beta channel inside the editor, update signatures beyond SHA-256 and Apple's code signature.

## Overview

```
tools/release.sh 0.14.0 ──> commit "Version 0.14.0", tag v0.14.0, push
                                   │
             .github/workflows/release.yml (on tag v*)
          ┌────────────────────────┼─────────────────────────┐
     linux (ubuntu-24.04)     macos (macos-15)                │
     test, build, tar.gz      test, build, sign, notarize,    │
                              zip + dmg                       │
          └──────────────> publish: draft release, upload, publish last
                                   │
        github.com/vshvedov/rhun/releases/latest/download/VERSION
                 ▲                                   ▲
   install.sh (first install)          rhun (curl in the background)
                                                     │ newer
                                        [ Update to 0.14.0 ] in the status bar
                                                     │ click
                         sh -c 'curl …/v0.14.0/install.sh | sh -s -- --update …'
                                                     │ exit 0
                                        [ Restart to update ] ──> quit path, relaunch
```

## 1. Version

- `VERSION` at the repository root holds the version, `MAJOR.MINOR.PATCH`, optionally with a `-suffix` for prereleases (`0.13.56-rc1`). It starts at `0.13.55`, the version in `src/main.s` today.
- `tools/gen-assets.sh` emits `rhun_version` (the string from `VERSION`) and `rhun_dist` (1 when the environment has `RHUN_DIST=1`, else 0) into `build/assets.s`. The generated text changes with either, so the existing `cmp` step rebuilds when they change.
- `src/main.s` prints `rhun <rhun_version>` for `--version` instead of its own string. `tools/build-mac.sh` (Info.plist) and `tools/package-mac.sh` (file names) read `VERSION` instead of scraping `src/main.s`.
- `RHUN_DIST=1` is set only by the release workflow. It marks a build that may update itself (section 4).

## 2. Release pipeline

### Cutting a release

`tools/release.sh VERSION` stops unless the tree is clean, the branch is `main` and it is up to date with `origin/main`. It writes `VERSION`, commits `Version VERSION`, tags `vVERSION`, and pushes the commit and the tag.

### Workflow `.github/workflows/release.yml`

Runs on tags `v*`. Permissions: `contents: write`.

**linux** on `ubuntu-24.04`:
1. Stop unless the tag equals `v` + `VERSION`.
2. `tests/run.sh`.
3. `RHUN_DIST=1 ./build.sh release`.
4. Pack `rhun-VERSION-linux-x86_64.tar.gz` with one top folder `rhun-VERSION/`:
   `bin/rhun`, `share/applications/rhun.desktop`, `share/icons/hicolor/scalable/apps/rhun.svg`, `share/icons/hicolor/256x256/apps/rhun.png`, `share/icons/hicolor/512x512/apps/rhun.png`, `LICENSE`.
5. Upload it as a workflow artifact.

**macos** on `macos-15` (Apple silicon):
1. The same tag check.
2. Import the Developer ID certificate into a temporary keychain: decode `MACOS_CERT_P12`, `security create-keychain`, `import … -T /usr/bin/codesign`, `set-key-partition-list`, and add it to the search list. The keychain is deleted at the end of the job, including when it fails.
3. `tests/run.sh`.
4. `RHUN_DIST=1 tools/package-mac.sh`, notarizing with the App Store Connect API key (below).
5. `ditto -c -k --keepParent build/rhun.app rhun-VERSION-macos-arm64.zip`. ditto keeps the bundle's signature and stapled ticket intact, which tar does not guarantee. Keep the `.dmg` as well.
6. Upload both as workflow artifacts.

**publish** on `ubuntu-24.04`, after both:
1. Collect the artifacts. Write `SHA256SUMS` (`sha256sum` over the archives and the dmg) and a `VERSION` file.
2. Write release notes: `- subject` for each commit since the previous `v*` tag (checkout with full history).
3. `gh release create vVERSION --draft --title "rhun VERSION" --notes-file …` with the archives, the dmg, `SHA256SUMS`, `VERSION` and `install.sh`. Mark it `--prerelease` when the version has a `-`.
4. Last step: `gh release edit vVERSION --draft=false`. GitHub's `releases/latest` only counts published, non-prerelease releases, so neither the installer nor the editor can see a version before all of its files are uploaded.

### Notarization in CI

`tools/package-mac.sh` keeps the keychain profile path for local use and gains a second path: when `RHUN_NOTARY_KEY` (path to a `.p8` file), `RHUN_NOTARY_KEY_ID` and `RHUN_NOTARY_ISSUER` are set, it calls `xcrun notarytool submit … --key --key-id --issuer --wait`. It also writes the zip (step 5 above) so a local run produces the same files as CI.

### Repository secrets (set once by the maintainer)

| Secret | Contents |
| --- | --- |
| `MACOS_CERT_P12` | base64 of the "Developer ID Application: Itsy Bitsy Pixels Media Inc (G29V3JRMJJ)" certificate and key, exported from Keychain Access as .p12 |
| `MACOS_CERT_PASSWORD` | the .p12 password |
| `APPLE_API_KEY_P8` | base64 of an App Store Connect API key (.p8), Developer role |
| `APPLE_API_KEY_ID` | its key ID |
| `APPLE_API_ISSUER_ID` | the issuer ID shown on the same page |

### URLs

- Latest version: `https://github.com/vshvedov/rhun/releases/latest/download/VERSION`
- A release's files: `https://github.com/vshvedov/rhun/releases/download/vVERSION/NAME`

Both go through GitHub's download CDN, not the REST API, so the API's 60-requests-per-hour limit does not apply. The base `https://github.com/vshvedov/rhun/releases` can be overridden with `RHUN_RELEASES_URL` in both the installer and the editor, for tests.

### Dry run

A tag with a `-` (`v0.13.56-rc1`, with `VERSION` set to match) goes through the whole pipeline and publishes a prerelease, which never becomes `latest`. The first real release follows once the dry run works.

## 3. Installer: `install.sh`

A POSIX `sh` script at the repository root, attached to every release. It must run under dash, bash, zsh's `sh` and busybox `sh`. It installs into places the user owns, so neither installing nor updating needs sudo. The whole script is one function called on its last line, so a download cut off halfway through runs nothing.

### Interface

```
curl -fsSL https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
wget -qO- https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
… | sh -s -- [options]
```

| Option | |
| --- | --- |
| `--version X` | install X instead of the latest |
| `--prefix DIR` | Linux: install under DIR (default `~/.local`) |
| `--app-dir DIR` | macOS: where rhun.app goes (default `/Applications`, or `~/Applications` when that is not writable) |
| `--no-modify-path` | leave shell startup files alone |
| `--uninstall` | remove what the installer put in place |
| `--update --target PATH` | the editor's mode (below) |

Messages are short lines on stdout (`rhun 0.14.0 installed in ~/.local`). Errors go to stderr as one line starting with `rhun install:` and exit non-zero.

### Steps

1. **Platform.** `uname -s` and `uname -m`: Linux with x86_64 means `linux-x86_64`; Darwin with `sysctl -n hw.optional.arm64` = 1 means `macos-arm64`. The sysctl catches a Rosetta shell, which reports x86_64. Anything else: `rhun install: rhun runs on Linux x86-64 and macOS on Apple silicon`.
2. **Downloader.** curl (`-fsSL --proto =https --proto-redir =https`), else wget (`-q -O`), else an error naming both.
3. **Version.** `--version`, else the latest `VERSION`. It must match `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$`.
4. **Download and verify** into `mktemp -d`, removed by a trap on exit:
   - Fetch the archive and `SHA256SUMS` from the release. Check the hash with `sha256sum -c` or `shasum -a 256 -c`.
   - macOS, after unpacking with `ditto -x -k`: `codesign --verify --strict --deep` on the bundle, and the team identifier from `codesign -dv` must be `G29V3JRMJJ`. The hash shows the download is intact; the signature shows it is ours.
5. **Linux install** under the prefix:
   - `bin/rhun`: copied to `bin/.rhun.new`, then renamed over `bin/rhun`, so a running rhun keeps its inode.
   - `share/applications/rhun.desktop`, with `Exec=` rewritten to the absolute path of `bin/rhun`. Graphical sessions often lack `~/.local/bin` on PATH, and launchers would otherwise fail to start it.
   - Icons: `share/icons/hicolor/scalable/apps/rhun.svg`, plus the 256 and 512 px PNGs for launchers and docks that do not draw SVG.
   - Refresh the desktop's caches, each only when present, errors ignored: `update-desktop-database`, `gtk-update-icon-cache -qtf`, `xdg-desktop-menu forceupdate`, and on KDE (`XDG_CURRENT_DESKTOP` contains KDE) `kbuildsycoca6`, else `kbuildsycoca5`. Tiling setups (Hyprland, Sway, niri; walker, wofi, rofi, fuzzel) read the desktop file directly. `StartupWMClass=rhun` and the window's app id `rhun` give docks the right icon.
6. **macOS install** in the app folder:
   - Unpack to `.rhun.app.new` beside the target. Rename the old bundle to `.rhun.app.old`, the new one to `rhun.app`, then delete the old one. A running rhun keeps its mapped code, as with `tools/build-mac.sh`.
   - Register the bundle with `lsregister -f` so the Dock and Open With pick it up.
   - Write the `~/.local/bin/rhun` wrapper (`exec "…/rhun.app/Contents/MacOS/rhun" "$@"`), as `tools/install.sh` does today.
7. **PATH.** When `~/.local/bin` (the prefix's `bin` on Linux) is not on PATH, append one line between `# rhun` marker comments and print which file changed: zsh `~/.zshrc`; bash `~/.bashrc`, plus `~/.bash_profile` on macOS; fish `~/.config/fish/conf.d/rhun.fish`; any other shell gets a printed hint only. `--no-modify-path` skips this step.
8. **Done.** Print the version, the location, and how to start it.

### Uninstall

`--uninstall` (with the same `--prefix` or `--app-dir` if one was given at install) removes the binary, desktop entry and icons, or the bundle and the wrapper, plus the marked PATH lines, and refreshes the caches. It leaves `~/.config/rhun` and `~/.local/state/rhun` in place and says where they are.

### Update mode

`--update --target PATH --version X`, run by the editor:
- PATH is the running binary on Linux (`<prefix>/bin/rhun`; the prefix is two levels up) or the `.app` bundle on macOS.
- If `PATH --version` (or the bundle's binary) already prints `rhun X`, exit 0 at once. A second rhun window then just offers the restart.
- If the target's folder is not writable, fail with `rhun install: <folder> is not writable; run the installer again`.
- Otherwise steps 1 to 6 for that one installation only. No PATH changes and no messages on success.

### Requirements

`uname`, `tar`, `gzip`, `mktemp`, curl or wget, and `sha256sum` or `shasum`. All of these ship with macOS and with mainstream desktop Linux distributions.

## 4. Updater in the editor: `src/app/update.s`

### Settings and commands

- `[updates]` `check = true` (default on): the **Check for updates** switch, "Look for a new version at startup and once a day."
- A **Check now** row beneath it, with the state in place of a description: "0.13.55 is the latest (checked 5 min ago)", "0.14.0 is available", "Checking…", "Couldn't check: …". This needs a new setting type, `ST_ACTION`: a label and a button, no config key, skipped when reading or writing the config.
- Palette commands: `check_for_updates`, `install_update`, `restart_to_update`. The last two do nothing outside their state (below).

### State

```
IDLE ──check──> CHECKING ──newer──> AVAILABLE ──install──> INSTALLING ──exit 0──> READY ──restart──> (relaunch)
                   │                    ▲                      │
                   └─not newer/error─> IDLE                    └─failed: toast──> AVAILABLE
```

The status bar shows a right-aligned, clickable item in AVAILABLE (`Update to 0.14.0`), INSTALLING (`Updating…`) and READY (`Restart to update`), and nothing otherwise. Clicking it does install_update in AVAILABLE and restart_to_update in READY.

### The check never touches startup

- **When.** The app timer (`app_timeout`/`app_tick`, beside `git_timeout`) fires the first automatic check 5 s after launch, long after the first frame. After that, 24 h after the last attempt, for sessions left open for days. No automatic check when the setting is off, in `--headless`/`--script` runs, or in a source build (`rhun_dist` = 0).
- **Throttle.** `$XDG_STATE_HOME/rhun/update` (default `~/.local/state/rhun/update`) holds `checked=<unix seconds>` and `latest=<version>`. An automatic check within an hour of `checked` uses `latest` instead of the network, so five windows opened together make one request. A manual check always fetches. The file is written after every fetch that succeeds.
- **Fetch.** `curl -fsSL --max-time 20 --proto =https --proto-redir =https <releases>/latest/download/VERSION`, or `wget -qO- -T 20 …` when `proc_which` finds no curl. With `RHUN_RELEASES_URL` set, the `--proto` options are left out so tests can use `file://`. It runs through `run_piped` and `watch_add`, as `git_run` does (`src/app/git.s`): the UI thread pays one fork/exec, then only reacts to poll. The output is capped at 64 bytes.
- **Parse and compare.** The reply must be one version line as in section 3 step 3; anything else, such as a captive portal page, counts as an error. Versions compare numerically, field by field, over up to four fields; a `-suffix` is ignored for the comparison.
- **Results.** Newer: AVAILABLE. Otherwise IDLE. An automatic check shows nothing unless it finds something newer. A manual check always answers with a toast: "rhun 0.13.55 is the latest", "Couldn't check for updates: <reason>", or "Checking for updates needs curl or wget".

### Install

- **Target.** Linux: `readlink /proc/self/exe`, dropping the ` (deleted)` the kernel appends once an earlier update has replaced the file. macOS: the executable path from `_NSGetExecutablePath` in `src/mac`, cut after the enclosing `.app`. A target that cannot be found is an error toast.
- **Run**, in the background, through `run_piped` (argv given directly, no outer shell):
  `sh -c 'exec 2>&1; f=$(mktemp) || exit 1; curl -fsSL -o "$f" "$1" && sh "$f" --update --target "$2" --version "$3"; s=$?; rm -f "$f"; exit $s' sh <releases>/download/vX/install.sh <target> X`
  (the wget form when there is no curl). The script is downloaded to a file first: with `curl | sh`, a failed download would hand `sh` nothing and exit 0, which would look like success. `exec 2>&1` is needed because `run_piped` sends stderr to `/dev/null`. The installer is pinned to the release being installed, never `main`.
- **Result.** Exit 0: READY. Anything else: a toast with the last line of the output (at most 200 characters), then back to AVAILABLE.
- **Source builds** (`rhun_dist` = 0) never install. Check now still works and reports, but the status bar item is not shown and install_update answers with a toast: "This rhun was built from source; pull and rebuild to update". A release build never overwrites a working tree.

### Restart

- restart_to_update sets `g_restart` and runs `cmd_quit` (`src/app/app.s`): the Save / Don't Save / Cancel dialog for each unsaved file, then `session_save`. Cancel clears `g_restart`.
- After `loop_run` returns, `src/main.s` checks `g_restart`. The new rhun gets one argument, the absolute path of the project folder, and session restore reopens the files. Original arguments are not reused: they may be relative, and `open` starts apps in `/`.
  - **Both systems:** mark every descriptor above 2 close-on-exec (the display connection included; `close_range` with `CLOSE_RANGE_CLOEXEC` on Linux, `fcntl` on both), then `execve` the target (on macOS the bundle's `Contents/MacOS/rhun`) with the environment. Same pid, same terminal, same environment.
  - Not `open -n -a` on macOS, as first planned: Launch Services starts the app with launchd's environment, so a rhun started from a terminal with `XDG_CONFIG_HOME` or the like would come back reading another config. macOS replaces the task on exec, so the old window server connection goes with it; checked end to end with signed builds.
- Terminal-panel shells end, as with any restart.

### Control commands for tests

- `wait-update`: runs the loop until no check or install is running (at most 30 s), like `wait-git`.
- `print-update`: prints `state=… current=… latest=… error=…`.
- A test can start a check in headless mode with `cmd check_for_updates`.

## 5. Failure handling and security

- Offline, DNS failure, timeout (20 s), HTTP errors: the check ends in IDLE; only a manual check says so.
- Garbage, an oversized reply, or a version not newer: IDLE, no offer.
- curl and wget both missing: a manual check says so; automatic checks stay silent.
- An install that fails leaves the old installation untouched. Every file is placed by rename, and the bundle swap keeps the old copy until the new one is in place.
- Trust root: the `vshvedov/rhun` GitHub releases, the same as for the one-line install. Updates run the release's installer, which is no more trust than running the release's binary. HTTPS only, SHA-256 for integrity, the Apple team ID for authenticity on macOS. Signing Linux archives (minisign or `ssh-keygen -Y`) can come later without changing the rest.

## 6. Testing

- **Version comparison:** a unit test, `tests/update_test.s` with `tests/data/update.expected`: equal, newer by each field, different field counts, suffixes, garbage.
- **Updater:** `tests/update.sh`, run from `tests/run.sh`. Headless rhun with its own `HOME`, `XDG_CONFIG_HOME` and `XDG_STATE_HOME`, built with `RHUN_DIST=1`, `RHUN_RELEASES_URL=file://<fake release folder>`, and a stub `install.sh` that records its arguments and exits with a chosen status. Cases:
  - newer found: AVAILABLE
  - same version: IDLE
  - garbage reply: IDLE
  - install succeeds: READY, with the stub given the right `--target` and `--version`
  - install fails: AVAILABLE, with the error line reported
  - throttle: a second check within the hour makes no fetch
  - a source build never installs
- **Installer:** `tests/install.sh`, run by hand and in the linux CI job, against a fake release folder served over `file://`, plus a small `python3 -m http.server` for the wget path:
  - Linux, in Docker under dash, bash and busybox (Alpine):
    - install: files in place, `Exec=` absolute, PATH line added once
    - update: the binary swapped while a copy of the old one runs
    - update to the same version: no-op
    - update of an unwritable target: fails cleanly
    - uninstall: everything removed
  - macOS, on this machine: into a scratch `--app-dir` with a locally signed bundle.
- **Restart:** checked by hand on Linux (Wayland and X11) and macOS, with unsaved files, a canceled dialog, and a project with open files.
- **Pipeline:** the prerelease dry run of section 2 before the first real release.

All test runs of rhun use their own `HOME` and XDG folders, as `tests/ui.sh` does.

## 7. Documentation

- `README.md` stays short: its "Get rhun" section gets the one-line install command (curl, with wget as an alternative), a line saying rhun updates itself, and the link to the guide.
- `docs/guide.md` gets an "Install and update" section: the installer's options, where files go, uninstalling, the `[updates]` setting, what the check sends (one HTTPS request to github.com), building from source, and making a release.

## 8. Files

New:
- `VERSION`, `install.sh`, `tools/release.sh`, `.github/workflows/release.yml`
- `src/app/update.s`
- `tests/update_test.s`, `tests/data/update.expected`, `tests/update.sh`, `tests/install.sh`, fake release fixtures under `tests/data/release/`
- `assets/icons/rhun-256.png`, `assets/icons/rhun-512.png`, drawn from `rhun.svg` by `tools/png-icons.py` (the distance-field drawing of `tools/mac-icon.py`, without the macOS grid) and committed

Changed:
- `tools/gen-assets.sh`, `tools/build-mac.sh`, `tools/package-mac.sh`
- `src/main.s` (version, restart), `src/app/app.s` (status bar item, timers, commands), `src/app/config.s` (settings rows), `src/app/settings.s` (the button row), `src/app/control.s` (`wait-update`, `print-update`), `src/app/keys.s` (palette entries), `src/rhun.inc` (`ST_ACTION`, state), `src/mac/` (executable path)
- `tests/run.sh`, `README.md`, `docs/guide.md`

## 9. Maintainer actions

1. Export the Developer ID Application certificate with its key from Keychain Access as .p12, with a password.
2. Create an App Store Connect API key (Users and Access, Integrations, App Store Connect API; Developer role) and download the .p8.
3. Add the five secrets of section 2 (`base64 -i file | pbcopy` for the two files).
4. Run the prerelease dry run, then `tools/release.sh` for the first release.
