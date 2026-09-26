# rhun

A small and fast code editor written in Assembly.

rhun draws everything itself: it rasterizes TrueType fonts, icons and widgets into a pixel buffer and hands that buffer to the display server. It speaks the Wayland and X11 wire protocols directly, without libc, toolkits or libwayland. The result is one static binary (fonts, themes and grammars included) that looks the same on every desktop.

## Features

- Tabs, file explorer, command palette, fuzzy file finder, find and replace, find in files, go to line
- Syntax highlighting for about 50 languages, defined in plain text grammar files
- 39 color themes, dark and light, with a match for every Omarchy theme; add your own
- Settings page and a readable config file, both applied while running
- Agents panel: Claude Code and Codex sessions of the project, updated live as the agent works
- Undo and redo, auto-indent, bracket pairs, comment toggling, moving and duplicating lines, soft word wrap
- Characters missing from the built-in fonts are drawn with the system's fonts
- Every XKB layout, dead keys and the Compose key (the system's Compose rules, `~/.XCompose` or `$XCOMPOSEFILE`)
- Files changed on disk are reloaded, open files are restored per project
- Wayland with fractional scaling; X11 as a fallback

## Build

Linux on x86-64 for now. GNU as and ld (binutils) are all it needs.

```sh
./build.sh           # build/rhun with debug symbols
./build.sh release   # stripped
tests/run.sh         # unit tests and scripted UI tests
tools/install.sh     # release build into ~/.local, with the desktop entry and icon
```

## Run

```sh
rhun [folder] [files...]
```

Without a folder the current directory is the project. Without files the previous session of that project is reopened.

rhun uses Wayland when it can and falls back to X11 when there is no Wayland compositor. `RHUN_BACKEND=x11` or `RHUN_BACKEND=wayland` picks one.

The mouse pointer is the desktop's: the compositor draws it when it supports the cursor-shape protocol; otherwise rhun loads your Xcursor theme (`XCURSOR_THEME`, `XCURSOR_SIZE`, `~/.icons/default`, `/usr/share/icons/default`).

On Wayland rhun draws its own title bar with window buttons, except on tiling compositors (Hyprland, Sway, niri, river, dwl, Qtile), where windows stay bare. `decorations = auto | client | server` under `[ui]` overrides this; `client` is rhun's title bar, `server` is the compositor's.

| Key | Action |
| --- | --- |
| Ctrl+P | Go to file |
| Ctrl+Shift+P, F1 | Command palette |
| Ctrl+, | Settings |
| Ctrl+K | Color theme |
| Ctrl+B | Toggle explorer |
| Ctrl+Shift+A | Toggle agents panel |
| Ctrl+F, Ctrl+H | Find, replace |
| Ctrl+Shift+F | Find in files |
| Ctrl+G | Go to line |
| Ctrl+D | Select word, then next match |
| Ctrl+/ | Toggle comment |
| Alt+Z | Toggle word wrap |
| Alt+Up, Alt+Down | Move lines |
| Ctrl+Shift+D, Ctrl+Shift+K | Duplicate, delete line |
| Ctrl+Tab, Ctrl+W | Next tab, close tab |

All commands are listed in the command palette.

## Configuration

`~/.config/rhun/config` is written when you change something in Settings; Open Settings File creates it. Edits to the file apply as soon as it is saved.

```ini
[ui]
theme = tokyo-night
scale = 1.25
[editor]
font_size = 15
tab_width = 4
[keys]
ctrl+shift+d = duplicate_line
alt+z = none
```

Key names are those of the command palette entries in snake case (see `src/app/keys.s`). `none` removes a binding.

### Themes

A theme is a `name.theme` file in `~/.config/rhun/themes/`. Colors not given are derived from `bg`, `fg` and `accent`, so a theme can be three lines. See `runtime/themes/` for all keys.

```ini
name = My Theme
kind = dark
bg = #1e1e2e
fg = #cdd6f4
accent = #f5c2e7
keyword = #cba6f7
string = #a6e3a1
```

### Languages

A grammar is a `name.syn` file in `~/.config/rhun/syntax/`; user grammars take precedence over built-in ones.

```ini
name = Example
files = *.ex Examplefile
first_line = example
comment = //
block = /* */
string = " \
mstring = """ \
region = <% %> preproc multiline
line = # heading
keywords = if else while return
types = int str
constants = true false
builtins = print
prefix = $v @a #p
ident = -
captypes = yes
case = insensitive
```

`comment`, `block`, `string` and `mstring` are shorthands for `region = start end class [multiline] [bol] [escape=X]`. Classes: text keyword type function string number comment constant operator punctuation preproc variable builtin attribute tag heading inserted deleted escape link. Words not in a list are colored as functions when followed by `(`, and with `captypes` as types when capitalized.

## Scripting

`rhun --control /path/to/socket` accepts one command per line, and `rhun --headless 1280x800 --script file` runs a file of them without a display. The tests use this.

```
open src/main.s
key ctrl+g
type 40
key Return
cmd toggle_comment
shot /tmp/rhun.ppm
print-state
```

Commands: `key`, `type`, `click x y [right]`, `move`, `down`, `up`, `scroll`, `open`, `cmd`, `shot`, `wait`, `resize`, `print-doc`, `print-state`, `echo`, `quit`. `cmd` runs anything from the command palette by its snake case name.

## Extensions (planned)

Extensions will be separate programs, in any language, that talk to rhun over the control socket. rhun starts each one found in `~/.config/rhun/extensions/` and passes the socket path in `RHUN_SOCKET`. Two additions to the protocol cover most needs:

- `register name title [keys]` adds a command to the palette; invoking it sends `run name` back to the extension.
- `subscribe open save change cursor` streams events as lines (`saved /path/file.c`), so formatters, linters and language servers can run outside the editor.

An extension that crashes or hangs cannot take the editor with it.

## Source

| Path | |
| --- | --- |
| `src/sys.s mem.s lib.s` | syscalls, allocator, strings, UTF-8 |
| `src/gfx/` | canvas, TrueType parser, rasterizer, icons |
| `src/ui/ui.s` | immediate-mode widgets |
| `src/plat/` | Wayland, XKB keymaps, X11, headless |
| `src/app/` | documents, editor, explorer, palette, settings, agents, syntax, themes |
| `runtime/` | themes and grammars embedded into the binary |
| `assets/fonts/` | Iosevka Fixed, cut down (SIL Open Font License) |

Porting to another platform means another file in `src/plat/` that fills the platform table in `src/rhun.inc`.
