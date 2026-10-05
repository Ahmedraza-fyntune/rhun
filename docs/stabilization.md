# Stabilization validation

Validation started on 2026-10-04 against `1f92f87`, version `0.17.4`.
The work is on `feat/stabilization-tests` for a stabilization PR. It does not
add features or change the release version. Installer operations use isolated
fixtures.

**Release signoff is still incomplete.** The shared editor has broad automated
coverage, but an inventory check does not prove every command's behavior.
Windows long-path saving and constrained-window controls have regression
fixes. The oldest supported clients and physical input checks below remain
required.
Do not treat a skipped or compatibility-only test
as a platform pass.

## Changes being validated

- Find and Replace controls no longer send their clicks through to the editor
  underneath. Replace, All, case sensitivity, previous, next, close, and undo
  have document and selection assertions.
- Reassigning string settings releases the previous owned allocation. Aliased
  input and theme-picker pointers remain safe. The allocation test warms every
  string, repeats 64 assignment rounds, and checks stable live allocation counts.
- Local model download progress is visible while the stream remains open on
  Linux with mawk. The regression requires a progress event before releasing
  the fixture's download-completion gate.
- Long project names cannot paint into toolbar controls or retain overlapping
  click targets. Optional status details are omitted when they would overlap
  the cursor label. A clipped branch button cannot take an updater click.
  Pixel comparisons and long linked-worktree cases check these boundaries.
- The macOS Replace shortcut displays Control-H, matching the working shortcut.
  Command-H retains the native application Hide action. Shortcut hint tests and
  a native Replace invocation verify the correction.
- Windows copy and paste retry a temporarily busy clipboard for at most about
  475 milliseconds. Native tests reproduce a 150-millisecond lock and verify
  Unicode copy/paste, plus a persistent lock that returns without changing the
  document or clipboard. The contention cases failed before the fix.
- Closing the active Settings tab restores document focus, so the next typing
  or paste reaches the visible editor. The close command, keyboard shortcut,
  middle click and last-tab case have regression checks. Closing an inactive
  tab preserves Find or Settings focus. Native macOS typing and Undo also
  verify that the original document is restored without unsaved changes.
- Windows filesystem operations resolve ordinary long paths before applying
  the extended path prefix. Saving an existing Unicode file, creating a file
  through relative dot components, and saving inside a long parent directory
  preserve the original or replacement bytes and clean up atomic-save siblings.
  Short paths, UNC conversion, explicit namespaces and device behavior have
  adapter tests. The VM's `LongPathsEnabled=0` policy remains unchanged.
- Constrained titlebars reduce button widths and gaps together. Find retains
  a usable query field and omits its optional count when space is insufficient.
  Pickers fit their visible rows to the viewport and reveal keyboard selection.
  Narrow Settings cards place controls below labels, with every string and
  choice still reachable. Standard-width controls keep their existing geometry.
- Find also blocks its covered scrollbar, including an existing drag. Blocked
  redraws preserve the document's fractional scroll offset instead of repeatedly
  truncating it through a pixel conversion. Large
  match counts are clipped before the Find controls. Mouse hit tests respect
  the current drawing clip, so invisible parts of
  controls cannot capture clicks. Centered labels and icons stay inside their
  buttons. Nested clips and blocked input have a direct regression test.
- CI runs the full editor gate on Linux and macOS, retains visual/performance
  artifacts, and propagates failures through its log pipeline. Native Windows
  also runs the new settings, editor matrix, stress, allocation, and key tests.
- The Linux reference comparison excludes the Windows platform sources, which
  are not inputs to the Linux reference build.

## Platform evidence

| Platform | Execution | Status and limits |
| --- | --- | --- |
| macOS, Apple silicon | macOS 27.0, build 26A428; native ARM64 build | Final full gate passed. Installer, download-failure and file-association checks passed. Native mouse, keyboard and clipboard checks passed for editor, Find/Replace, settings, theme picker and terminal. |
| Linux x86-64 | Debian 13.7 container, x86-64 through Rosetta | Final full gate passed. X11 and Wayland launches, installer and curl/wget failure fixtures passed. Syscall fault injection explicitly skips because tracing is unavailable under Rosetta. |
| Windows x64 | LLVM cross-build on macOS | Build passed. Wine execution produced Rosetta faults and is not a passing Windows gate. |
| Windows 11 ARM VM | Windows build 26300.9457; x64 application under Windows emulation | Final desktop gate passed, including 95 named checks and its Python test groups. All five native window cases, Unicode clipboard contention, ConPTY, watchers, providers and the five long-path cases passed with `LongPathsEnabled=0`. Installer (10 named checks) and updater (13 named checks) gates also passed on the same binary. Portable Python 3.13.7 ARM64 and MinGit 2.51.0 ARM64 are isolated test dependencies. |
| Native CI | Ubuntu 24.04, macOS 15, Windows Server 2022 | Gates defined. The PR checks record remote outcomes separately from this local evidence. |

The supported Windows application is x64. An ARM Windows VM can exercise the
Windows APIs through x64 emulation, but does not replace a physical x64 check.
macOS 12 and Windows 10 1809 compatibility have not been established by these
local runs.

The first Windows run used a hidden Task Scheduler launch and failed foreground
assertions. The desktop-launched repeat passed all five native window cases and
all updater restart cases without changing production activation handling. One
desktop run was interrupted by a user-initiated VM shutdown and was repeated.
The final Windows cross-build passed the editor matrix (18 cases), settings
(11 cases), and the direct clipping regression. These checks include every
compact string and choice, actual wheel scrolling, hidden-scrollbar clicks,
and 100 blocked redraws during a drag. The final desktop, installer and updater
rerun passed with zero exit codes. Native clipboard contention also passed.
Guest binary hashes match the final host cross-build. The four temporary scheduled
test tasks were removed after their runs finished; the VM was left running.

The original file-save failure was deterministic: ordinary paths of total
lengths 145, 235 and 255 saved, while lengths 275 through 346 failed and retained
their original bytes. A clean `1f92f87` build reproduced the same failure.
The regression repeats the existing Unicode file, new relative path, and long
parent-directory cases against clean and changed file drivers. The baseline
fails all three; the changed driver passes. Path normalization precedes the
extended prefix so slash and dot-component interpretation remains consistent.
See [Microsoft's path-limit requirements](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation).

## Feature and control coverage

These checks run in temporary projects and configuration directories. Git,
update, and provider operations use local fixtures. Real providers, remote
repositories, user documents, and the installed editor are not used for the
test mutations.

| Surface | Behaviors and controls exercised | Checks |
| --- | --- | --- |
| Command palette and shortcuts | All 82 registered entries appear under their title filter; every default shortcut resolves to its advertised handler; unknown and unbound inputs return no handler; scroll, filtering, reopen, keyboard reveal and partial wheel deltas | `keys_test.s`, `editor-matrix.py`, `palette-scroll.py` |
| Text editing | Insert, delete, cut/copy/paste, selection, word/line/document movement, indentation, comments, duplicate/delete/move lines, newline above/below, undo/redo, Unicode, gap-buffer boundaries, Windows clipboard contention | `doc_test.s`, `cols_test.s`, `textarea_test.s`, UI editing/clipboard/cursor/mouse/movelines/togglecomment scripts, `windows-clipboard.py` |
| Find and Replace | Query and replacement fields, keyboard acceptance, mouse Replace/All, case switch, previous/next/close, growing/shrinking/empty replacements, absent query, Unicode, transactional undo/redo | UI find/replace scripts, `editor-matrix.py`, `stress.py` |
| Vim | Normal/insert/visual modes, counts, operators, motions, search and supported ex commands | UI vim script and its golden output |
| Tabs and documents | New/open/save/save-as/save-all/reload, tab switching/closing, Settings close restoring document input, inactive close preserving focus, dirty state, untitled and image tabs, session restoration | UI tabs/openfile/recent scripts, `editor-matrix.py`, `files.sh`, `session.sh`, `live-reload.py` |
| Explorer | Create file/folder, keyboard and mouse prompts, cancel, delete confirmation, unreadable directories, active file deletion, recursive trees, symbolic links, empty-space menus and refresh | `explorer-create.py`, `explorer-delete.py`, UI contextmenu/openfolder scripts |
| File and folder pickers | Fuzzy search, excluded directories, nested paths, 3,000 files, open folder, recent projects and project switching | UI openfile/openfolder/recent scripts, `stress.py`, `desktop-ux.py` |
| Window and titlebar | Sidebar/settings/agents/terminal controls, client window controls, drag/foreground behavior, project menu, tooltips, long project names and toolbar hitboxes | UI titlebar/titlebar-tap scripts, `tooltips.py`, `desktop-ux.py`, native launch tests, `editor-matrix.py` |
| Settings | All 43 schema rows: 41 editable rows and 2 actions; every control type, string commit/cancel/blur, numeric limits, choices, theme preview/cancel/accept, open config, scroll, local model action and Check now | `settings-ui.py`, `config_test.s`, `config_strings_test.s`, provider/update fixtures |
| Zoom and scaling | Independent editor/terminal zoom, reset, persistence, remapping, font limits and image focus; 18 size/scale combinations for editor, Find, quick open, commands and settings | `focused-zoom.py`, `editor-matrix.py` |
| Themes and fonts | All 40 built-in themes render without changing the document; custom/Omarchy theme handling, theme parsing and fallback; UI/editor font setting bounds and strings | `theme_test.s`, UI omarchy script, settings/zoom/matrix tests |
| Syntax and grammars | 127 built-in grammar files, sample output, filename patterns, duplicate pattern guard, user overrides and prefix-tag behavior | `syntax_test.s`, `grammar_test.s`, UI highlight script |
| Image viewer | Decode formats and failures, zoom/fit/navigation UI, image tabs, edit commands remaining harmless, unchanged source bytes, session and update restoration | `image_test.s`, UI image script, `editor-matrix.py`, session/update checks |
| Terminal | Escape parser, colors, cursor/screen/scrollback operations, shell interaction, terminal tabs, active/inactive/last-tab close, middle click, overflow, zoom and clipboard | `term_test.s`, UI terminal script, `terminal-tabs.py`, `focused-zoom.py`, native Windows ConPTY cmd/PowerShell/create/resize/output/close/slow-start and cls checks |
| Git and source control | Status, diff, history, staged/unstaged changes, commit payload wrapping, repository/init/worktree operations, reset confirmation, failed reset, conflicts, untracked/ignored/nested repository safety | `diff_test.s`, UI git/gitinit/gitscm scripts, `git-reset.py`, `commit-wrap.py`, long-worktree updater regression |
| Commit message providers | Off/Claude/Codex/local selection, authentication mode rejection, generation/cancellation, stale drafts/diffs, temporary index, bounded output, model setup/download/delete, confirmation, checksum failure, concurrent installation and lock recovery | `commit-ai.py`, native Windows subscription CLI/cancel and local-model protocol fixtures |
| Agents panel | Discovery, project matching, Claude/Codex metadata, large/growing/partial records, CRLF/Unicode, malformed records, thread loading and refresh | `agents.py`, UI agents script |
| Disk changes and saves | Atomic and non-atomic external writes, debounce, active/background tabs, local edits, reload animation/fade, watch alias, save failures, backup preservation, permissions and CRLF | `live-reload.py`, `files.sh`, `file-faults.sh`, `windows-longpaths.py`, native Windows file/readonly/sharing/symlink/Unicode/CRLF/watcher checks |
| Idle and lifecycle | Blink behavior, caret timing, detachment, repeated palette/settings lifecycle, no redraw while settled with blinking/agents disabled | `blink.sh`, `detach.sh`, `stress.py`, live-reload checks |
| Updater | Same/new/missing/invalid versions, persisted checks, source builds, failure, installation arguments, restart/cancel, text/image/standalone tabs and long branch hitboxes | `update_test.s`, `update.sh`, local HTTP fixtures, native Windows staged-update/cancel/discard/detached-restart/standalone-text/image/mixed-tabs checks |
| Installer and associations | Fresh/update/same/uninstall, unwritable target, checksum and missing download failures, redirects/output modes, shell PATH blocks, optional file associations and preserved defaults | `install.sh`, `install-download.py`, association tests, `mac-defaults.py`, native Windows install gate |
| Translation | Random edits compared for state, document bytes and rendered pixels between the ARM64 translator and Linux reference | Final build: 20 sessions, 420 identical outputs |

### Settings inventory

The settings test checks equality against the schema inventory, so adding an
uncovered row fails the gate.

| Section | Covered rows and options |
| --- | --- |
| Appearance | theme; scale 0.5 to 3.0; font size 9 to 24; font; sidebar; sidebar width 140 to 600; agents panel; agents width 240 to 900; tooltips; decorations auto/client/server |
| Editor | font size 8 to 40; font; line height 1.0 to 2.5; tab width 1 to 16; insert spaces; line numbers; highlight line; animate disk changes; match brackets; indent guides; word wrap; whitespace; cursor blink; smooth caret; auto pairs; scroll past end; Vim mode |
| Files | exclusions; trim trailing whitespace; final newline; restore session; restore project |
| Agents | sources |
| Terminal | font size 8 to 40; shell; scrollback 0 to 100000; height 80 to 2000 |
| Git | enabled; commit AI off/claude/codex/ollama; local model; local model action |
| Updates | automatic check; Check now |

Booleans toggle both ways. Steppers move both ways and clamp at both limits.
Strings test Enter, Escape, and blur. Choice controls test every segment.
Compact cards repeat every string and every choice at 480 pixels wide.
Scrolling checks that lower rows appear and the original top view returns.
Provider lifecycle tests cover Download, Cancel, Delete, and confirmation with
fixture models.

## Performance and dead code

Three interleaved clean-build and final-build pairs ran separately for each
platform after the final production fix. All 18 stress runs passed, covering
72 test cases. The tables show medians in seconds. These are whole
scripted-process times, not typing latency percentiles. The lifecycle workload
includes 2.6 seconds of intentional settling/idle waits.

| Workload | macOS baseline | macOS changed |
| --- | ---: | ---: |
| Quick open, 3,000 files | 0.0961 | 0.0962 |
| Wrap, 100,000 characters | 0.0173 | 0.0173 |
| 100 palette/settings cycles | 5.9571 | 5.9720 |
| Replace, 20,000 Unicode lines | 0.2028 | 0.2016 |
| Replace and undo | 0.3444 | 0.3437 |
| Replace, undo and redo | 0.4987 | 0.5036 |

| Workload | Linux baseline | Linux changed | Windows baseline | Windows changed |
| --- | ---: | ---: | ---: | ---: |
| Quick open, 3,000 files | 0.1175 | 0.1190 | 0.1700 | 0.1672 |
| Wrap, 100,000 characters | 0.0301 | 0.0304 | 0.0961 | 0.0900 |
| 100 palette/settings cycles | 6.6910 | 6.6400 | 5.9560 | 5.9561 |
| Replace, 20,000 Unicode lines | 0.2496 | 0.2561 | 0.7116 | 0.7120 |
| Replace and undo | 0.4074 | 0.4079 | 1.3056 | 1.3222 |
| Replace, undo and redo | 0.5901 | 0.5878 | 1.8876 | 1.8821 |

The largest positive median changes are 14.9 milliseconds for macOS lifecycle
cycles (0.3%), 6.5 milliseconds for Linux replacement (2.6%), and 16.6
milliseconds for Windows replace-and-undo (1.3%). Three samples cannot establish
a general speedup or the absence of a regression. Linux and Windows use
emulation, so compare each platform with its own baseline. Native CI should
establish larger-sample baselines and interactive latency measurements before
release signoff.

Final raw samples, zero exit markers, binary hashes and medians are retained in
`performance/final-macos`, `performance/final-linux` and
`performance/final-windows`. Earlier samples, including overlapping preparation
and runs before the final fixes, remain retained separately. The final sample
sets ran one platform at a time, with no other validation suite running.
The configuration allocation regression directly checks stable live
allocations instead of relying on a noisy process-memory sample.

A source/reference audit removed five unreferenced helpers: `memset32`,
`is_space`, `log_hex`, `wrap_active`, and `win_download_page`, along with the
last helper's unused URL. None has a call, table reference, test reference or
public export. `term_focus` is retained because it implements focus reports
for the supported terminal mode 1004. `log_u64` and `syntax_by_name` are used by tests. Platform entry points
and generated ARM64 helpers are not dead code. No broad deletion or refactor is
included in the stabilization fixes.

## Required native and visual signoff

- Repeat `python tests/windows.py`, `python tests/windows-install.py`, and
  `python tests/windows-update.py` on physical x64 Windows 10 and Windows 11.
  Verify ConPTY, native window input, Unicode paths/clipboard, file sharing,
  directory notifications, shell launching and updater restart.
- On each desktop, sweep mouse and trackpad controls in the coverage table:
  titlebar, tabs, terminal tabs, explorer menus/prompts, Find/Replace, pickers,
  settings, agents, source control, image controls, confirmation dialogs and
  updater. Repeat with keyboard navigation and remapped shortcuts.
- Verify IME composition/candidate placement, dead keys, non-Latin layouts,
  selection dragging, double/triple click, wheel/trackpad scrolling, focus loss,
  minimize/restore/fullscreen and multiple-monitor DPI transitions.
- Check native menus, file manager opening, OS file associations and application
  launch/reuse with unsaved files. Use fixture documents for destructive controls.
- Confirm native minimum sizes and monitor DPI changes. The constrained-window
  regressions cover independent titlebar clicks, a mouse-focusable Find field,
  picker selection visibility and bounded Settings fields at 640 pixels with
  300% scaling. The 200-pixel matrix cases are robustness probes below native
  minimum sizes; they do not establish usable controls at those dimensions.
- Run Linux syscall fault injection on native x86-64 with working `strace`.
  Check macOS 12 and Windows 10 1809 if those remain release support promises.

Native macOS automation verified Settings close followed by typing and Undo,
the Control-H Replace shortcut, Replace/All and undo, Find next/previous/case/
close, settings steppers, theme filtering/preview/cancel/accept, and terminal
Unicode clipboard input/output in an isolated app. The document was restored
byte for byte with no unsaved changes. A further native 300% scaling check
verified the compact Settings layout, mouse selection of its font field,
keyboard entry and persistence after clean quit. Closing Settings restored
editor input. Two Undo operations restored the exact document because native
typing arrived in separate undo groups. These representative native checks do
not replace the full physical mouse/trackpad and IME sweep above.

Final software-rendered screenshots were inspected for all three platforms:
131 per platform, comprising 40 themes, 18 dimensions/scales for each of five
surfaces, and the compact Settings field regression. Contact sheets retain the
full matrix. These images verify the shared renderer; they do not establish
native Windows IME, monitor DPI or physical input behavior.

## Reproducing and retaining evidence

```sh
RHUN_TEST_ARTIFACTS=build/stabilization/macos tests/run.sh
sh tests/install.sh
python3 tests/install-download.py
python3 tests/mac-defaults.py
python3 tests/linux-launch.py
python3 tests/linux-launch.py --wayland
KEEP=1 tests/compare-linux.sh 20
```

Use `linux` instead of `macos` for the Linux artifact directory. Windows uses
`python tools/build-windows.py test` followed by its native gates above, with
`RHUN_TEST_ARTIFACTS=build/stabilization/windows`.

Local logs, screenshots, and performance JSON live under `build/stabilization/`
and remain ignored by Git. CI uploads its visual/performance directories even
when tests fail. The macOS and Linux final logs are `macos-pr-final.log` and
`linux-pr-final.log`; translation evidence is `translation-pr-final.log`.
Final Linux native launch logs are `linux-native-x11-pr.log` and
`linux-native-wayland-pr.log`. Earlier gate logs remain retained separately.
Final Windows logs are `windows-pr-final.stdout.log`,
`windows-pr-final.stderr.log`, `windows-install-pr-final.*.log` and
`windows-update-pr-final.*.log`, with matching zero `.exit.txt` markers.
Completion, session evidence and the binary hash are in
`windows-pr-final-snapshot.json`. The unchanged VM path policy and matching
hashes are in `windows-pr-evidence.json`. Earlier results remain retained
in `windows-final-exit-codes.json` and `windows-longpaths-policy.json`. The current and clean-build path probes
are `windows-longpath-probe.log` and `windows-longpath-baseline-probe.log`.
Final Windows headless checks are `windows-pr-matrix.log`,
`windows-pr-settings.log` and `windows-pr-clip.log`, with zero exit markers.
The five-case path regression is `windows-longpaths-current.log`; the matching
clean-build run is `windows-longpaths-clean-baseline.log`. The fractional
scrollbar regression is retained in `find-held-before.log` and
`find-held-after.log`. The Settings-close failure and corrected regression are retained in
`settings-close-baseline.log` and `settings-close-fixed.log`. Native evidence
is `native-mac/settings-close-native.log` and `native-mac/settings-close.ppm`.
The final Windows focus-fix checks are `windows-settings-close-matrix.log`,
`windows-settings-close-settings.log` and `windows-settings-close-stress.log`,
with matching `.exit.txt` files.
Earlier guest binary hashes and task cleanup are recorded in
`windows-focus-final-evidence.json` and `windows-cleaned-test-tasks.json`.
The final evidence manifest is `manifest.json`.

Integration copies combine these changes with main `2bf869d`, whose separate
Agents session-cache correction touches different files. All 15 Agents tests
passed on macOS, Linux and the Windows VM, including project-switch discovery
and refresh. The macOS read-interposition case skips on Linux and Windows.
The integration logs are `integration-macos-agents.log`,
`integration-linux-agents.log` and `integration-windows-agents.log`. Native CI
also tests the PR merge result.

Independent review completed in five rounds. Four findings were fixed: Unix
CI pipelines could mask failures, Windows source/theme reads needed explicit
UTF-8, a new statusbar frame slot overlapped the long-branch text buffer, and
the Windows long-path fixture needed removal through its extended path.
The last review reported no findings. The later Settings-close correction had
its own fresh diagnosis and one-round independent review, also with no
findings. Diagnosis agreed that document synchronization left Settings focus
behind, and the regression failed with focus 4 before the fix. No findings were
rebutted. The final long-path/layout/dead-code diff completed a separate
three-round review. Two findings were fixed: narrow Find clicks could capture
the covered scrollbar, and blocked drag redraws could truncate the document
scroll offset through pixel writeback. The third round returned no findings.
No findings were rebutted in this loop. Build and test
checks have the outcomes described above, including the original Windows
long-path failures and their corrected regression. Python compilation, shell syntax checks, and
`git diff --check` also passed. Wine/Rosetta faults and the Linux tracing skip
remain environment limitations, not passing native-platform results.
