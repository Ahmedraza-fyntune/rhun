# Startup stats

Each script is standalone. Download the one for your desktop, or run it from the
repository. All four use Python's standard library, with no `pip install` step.
Rhun must be installed. They use your existing configuration and current directory,
open Rhun repeatedly, and terminate only the process they launched after detecting
its window.

| Desktop | Script | Additional native dependency | Measurement endpoint |
| --- | --- | --- | --- |
| Hyprland | [startup-stats-hyprland.py](startup-stats-hyprland.py) | `hyprctl` | Hyprland window-open event, with PID verification |
| macOS | [startup-stats-mac.py](startup-stats-mac.py) | Built-in CoreGraphics and CoreFoundation | Onscreen layer-zero window belonging to the launched PID |
| Windows | [startup-stats-win.py](startup-stats-win.py) | Built-in user32 | Visible, non-minimized `rhunWindow` belonging to the launched PID |
| Linux X11 | [startup-stats-x11.py](startup-stats-x11.py) | `libX11`, `libXRes`, local X server with X-Resource 1.2 | Map event for a viewable window belonging to the launched PID |

## Run

From the repository, on macOS:

```sh
python3 tools/startup-stats-mac.py
```

On Windows:

```powershell
py -3 tools/startup-stats-win.py
```

If your Python installation provides `python` rather than `py`, use
`python tools/startup-stats-win.py`.

On Linux X11:

```sh
python3 tools/startup-stats-x11.py
```

The X11 script forces Rhun's X11 backend. It also works with a local XWayland
display. It handles window managers that reparent the editor inside a frame.
It uses X-Resource to check the window owner's PID because Rhun does not currently
publish `_NET_WM_PID` on X11. If the native libraries are missing, their packages
are `libx11-6 libxres1` on Debian/Ubuntu and `libx11 libxres` on Arch Linux.

All scripts default to 10 measured runs and no discarded warmups. Use
`--runs 20 --warmups 3` to discard three launches before measuring 20. Use
`--timeout 15` to allow up to 15 seconds per launch.

Pass `--binary PATH` for a custom installation or build. The macOS and Windows
scripts also look in the usual installation locations if Rhun is not on `PATH`.
The macOS script accepts an `.app` path, for example:

```sh
python3 tools/startup-stats-mac.py --binary /Applications/rhun.app
```

Each report includes runs, median, average, fastest, slowest, standard deviation,
first measured launch, and the median of runs 2 onward when available. Include
the OS, CPU, Rhun version, script, working directory, and configuration/session
details alongside results you share.

## Interpret results

These are warm-cache window-appearance timings. The first launch is not a cold-boot
test, and the scripts do not clear filesystem caches. Process creation and window
detection overhead are included; process termination is excluded.

macOS and Windows query native APIs with a 1 ms pause between unsuccessful checks.
API query time and OS scheduling add latency, so 1 ms is not a precision guarantee.
Hyprland and X11 timestamp received window events before verifying their owner.

The endpoints are specific to each desktop. They do not guarantee compositor
presentation, a fully painted frame, completed background work, or input readiness.
On Windows and X11, window visibility can precede the first editor frame. Use the
same desktop, script, configuration, and directory for comparisons.

Native API references: [Apple window information](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)),
[Win32 window enumeration](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-enumwindows),
and [X-Resource API](https://www.x.org/releases/current/doc/man/man3/XRes.3.xhtml).
