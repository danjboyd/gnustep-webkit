# Building gnustep-webkit

## Required packages

| Distribution | Required | Optional (nicer messages) |
| --- | --- | --- |
| Debian 13+ / Ubuntu 25+ | `gnustep-make`, `gnustep-base-runtime`, `libgnustep-gui-dev`, `libwpewebkit-2.0-dev`, `libwpe-1.0-dev`, `libwpebackend-fdo-1.0-dev` | `xclip` (clipboard fallback) |
| Fedora 40+ | `gnustep-make`, `gnustep-base-devel`, `gnustep-gui-devel`, `wpewebkit-devel`, `libwpe-devel`, `wpebackend-fdo-devel` | `xclip` |
| Arch Linux | `gnustep-make`, `gnustep-base`, `gnustep-gui`, `wpewebkit`, `libwpe`, `wpebackend-fdo` | `xclip` |
| openSUSE Tumbleweed | `gnustep-make`, `gnustep-base-devel`, `gnustep-gui-devel`, `libwpewebkit-2_0-dev`, `libwpe-1_0-devel`, `libwpebackend-fdo-1_0-devel` | `xclip` |

The build also pulls in `libsoup-3.0`, `libwayland-server`, and
`glib-2.0` transitively through the WPE pkg-config files; no separate
install needed.

## Build steps

```sh
./configure                  # probes pkg-config, writes config.make
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make                         # builds Source/libWebKit.so + Demo/WebKitDemo.app
```

`./configure` accepts:

- `--prefix=DIR`   install prefix (default `/usr/GNUstep`)
- `--enable-debug` adds `-g -O0 -DGS_WEBKIT_DEBUG=1`

A plain `make` works without running `./configure` first; the
makefile falls back to inline `pkg-config` probes that work on most
Debian/Ubuntu installs.

## Running the demo

```sh
make -C Demo run
```

This builds `Demo/WebKitDemo.app` and launches it with the
appropriate `LD_LIBRARY_PATH` so it finds the in-tree
`Source/obj/libWebKit.so` without first having to install.

## Installing system-wide

```sh
sudo -E env GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES make -C Source install
```

The framework headers land at `$GNUSTEP_HEADERS/WebKit/` and the
library at `$GNUSTEP_SYSTEM_LIBRARIES/libWebKit.so` (paths from
`gnustep-config`).

After install, consumer apps build with:

```makefile
ADDITIONAL_GUI_LIBS  += -lWebKit
ADDITIONAL_OBJC_LIBS += -ldispatch
ADDITIONAL_OBJCFLAGS += -fblocks
```

and `#import <WebKit/WebKit.h>` exactly like on macOS.

## Runtime dependencies

`gpbs` (GNUstep pasteboard server) must be running for `Ctrl+V` /
context-menu Paste to work.  It's installed alongside
`gnustep-base-runtime`; under a normal GNUstep session manager it
starts on demand.  If you're launching the app directly:

```sh
gpbs &      # then start your WebKit-using app
```

## Tests

```sh
./Tests/run_tests.sh                  # all
./Tests/run_tests.sh drag_select      # one test
WKDEMO_KEEP_LOGS=1 ./Tests/run_tests.sh paste   # keep diagnostics
```

The harness boots its own `Xvfb`, starts `gpbs`, and drives the demo
through a stdin command channel (`GOTO` / `EVAL` / `RESIZE` / `QUIT`).
Mouse and keyboard events are synthesised with `xdotool`; clipboard
round-trips use the framework's own `Ctrl+C` → `NSPasteboard` →
`Ctrl+V` path.
