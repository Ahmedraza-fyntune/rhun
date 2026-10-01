# rhun

![rhun](assets/social/github@2x.png)

## Get rhun

On Linux (x86-64) or macOS (Apple silicon), run:

```sh
curl -fsSL https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
```

Or using `wget` 

```sh
wget -qO- https://github.com/vshvedov/rhun/releases/latest/download/install.sh | sh
```

rhun shows up with your other apps, and `rhun` starts it from a terminal. When a new version is out, the status bar offers it.

On Windows 10 (1809 or later) or Windows 11, download the **windows-x86_64.zip** from [Releases](https://github.com/vshvedov/rhun/releases/latest), extract it, and open `rhun.exe`. For a Start menu shortcut and the `rhun` command, run the [Windows installer](https://github.com/vshvedov/rhun/releases/latest/download/install.ps1) in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Close rhun and rerun the installer to update on Windows. See the [Windows guide](docs/guide.md#windows) for paths, build instructions, and first-release limitations.

## Why rhun

When coding agents do more of the heavy lifting, you may not need everything that comes with vim, VS Code or Zed. You need to read and edit code, run commands, find files, and check what changed.

`rhun` is perfect for such tasks: it is blazing fast, has a minimal memory and disk space footprint, and ships with everything you need:

- **Code editing:** Tabs, syntax highlighting, find and replace, and optional Vim mode.
- **Built-in terminal:** Run your shell, tools, and coding agents right beside the code.
- **Git:** Stage, commit, pull and push, see changed files, read diffs, and browse commit history. Optionally draft commit messages with your Claude or Codex subscription, or a local Ollama model.
- **Fuzzy search:** Jump to a file or search across the whole project.
- **Agents panel:** See Claude Code and Codex sessions as they work.

<p>
  <img src="assets/social/screenshot-dark.png" width="49%" alt="rhun, dark theme">
  <img src="assets/social/screenshot-light.png" width="49%" alt="rhun, light theme">
</p>

Pick from 39 light and dark themes. On Omarchy, choose **Follow Omarchy** and rhun switches themes with your desktop.

Keep your terminal beside your code, and browse Git history without leaving the editor.

<p>
  <img src="assets/social/screenshot-terminal.png" width="49%" alt="Code and the built-in terminal in rhun">
  <img src="assets/social/screenshot-git.png" width="49%" alt="Git history and changed files in rhun">
</p>

[Usage, shortcuts, and configuration](docs/guide.md)

[MIT license](LICENSE). Built-in fonts: [SIL Open Font License](assets/fonts/LICENSE-Iosevka.md).
