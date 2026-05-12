# Contributing to gnustep-webkit

Thanks for your interest!  This project is still pre‑1.0 — broad
contributions, big or small, are very welcome.

## What this project is

An Objective‑C implementation of Apple's `WKWebView` API for GNUstep,
backed by [WPE WebKit](https://wpewebkit.org/).  The goal is
**source compatibility with code written against Apple's
`<WebKit/WebKit.h>`**, so apps that already use `WKWebView` on
macOS/iOS can compile and run on GNUstep without rewriting their
web‑view layer.

The long‑term aim is to be accepted into GNUstep proper as an
officially maintained framework (alongside `libs-gui` /
`libs-OpenSave`).  Patches that move us in that direction are
especially welcome.

## What this project is *not*

- Not a browser.  It's a framework for embedding web content; the
  bundled `WebKitDemo.app` is a minimal browser only to exercise the
  API.
- Not a new web engine.  Rendering and JavaScript are all WPE WebKit
  (the same upstream as Apple's Safari, just a different port).

## Where to file bugs / discuss

- **Bugs / feature requests** — open an issue on the project's git
  forge (link in the README).
- **General discussion / design** — the `gnu.gnustep.developer`
  mailing list is the right venue for anything that touches the
  GNUstep platform side.  Pasteboard, AppKit integration, NSView /
  responder chain questions should go there in addition to (or
  instead of) the issue tracker.

When filing an issue please include:

- Distribution and version (`lsb_release -a`)
- pkg‑config output for `wpe-webkit-2.0`, `wpe-1.0`,
  `wpebackend-fdo-1.0` (run `pkg-config --modversion <pkg>` for each)
- `gnustep-config --variable=GNUSTEP_MAKEFILES`
- The full output of `./configure` and the failing `make` invocation
- For runtime issues, a minimal repro page

## What patches I'd love

In rough order of leverage:

1. **Custom `libwpewebkit` build with `ENABLE_DRAG_SUPPORT=ON`** — would
   let us drop the JavaScript shims for drag‑to‑select and clipboard
   and pick up engine‑native drag‑and‑drop.  Big quality‑of‑life win.
2. **Real exit‑time clean‑up.**  Today the demo's
   `applicationWillTerminate:` calls `_exit(0)` to avoid a
   use‑after‑free inside libgnustep‑gui's terminate path.  Fixing
   this properly probably means coordination with the libs‑gui
   maintainers about signal/terminate handling.
3. **EGL / dma‑buf rendering path.**  Rendering is currently CPU‑side
   SHM (memcpy + byte swizzle, ~3× faster than the original byte
   loop but still CPU‑bound).  WPE supports EGL exports
   (`wpe_view_backend_exportable_fdo_egl_create`) that hand WebKit
   pixels directly into a GPU texture; combined with GNUstep's
   `NSOpenGLView` this would give us smooth video / animation.
4. **NSAccessibility ↔ AT‑SPI bridge.**  WebKit exposes the page's
   accessibility tree via AT‑SPI; surfacing that as `NSAccessibility`
   so VoiceOver‑on‑GNUstep can navigate web content would be a
   substantial accessibility win.
5. **IME / preedit composition.**  Non‑ASCII *characters* work via
   direct Unicode keysyms (X11R6 convention).  CJK preedit
   composition needs `NSTextInputClient` ↔
   `WebKitInputMethodContext` plumbing.
6. **`g_main_context_prepare/query` integration into NSRunLoop.**
   Today GLib is pumped by a 60 Hz `NSTimer` (cheap but not idle‑free).
   A proper pollfd‑driven integration would drop idle CPU to ~0.  An
   earlier attempt is preserved in the git history; the failure mode
   was IPC reply latency, so the next attempt should look at WebKit's
   default vs idle priority distinction.
7. **Per‑distro packaging.** `.deb` / `.rpm` / `PKGBUILD` files.
   Right now `./configure` does the right thing on Debian; verified
   builds on Fedora / Arch / openSUSE would catch packaging‑name
   drift.
8. **More API surface.** Several Apple WebKit classes are not yet
   implemented at all: `WKHTTPCookieStoreObserver` notifications,
   `WKContentWorld` isolated execution, `WKNavigationActionPolicy`'s
   policy decision handlers, custom `WKURLSchemeTask`'s redirect
   handling, `WKWebView`'s `interactionState`,
   `WKWebView.allowsLinkPreview`.

## Coding style

This project follows the GNUstep house style so it can plausibly
move into `libs-gui` someday:

- **No ARC.**  Manual `retain` / `release` / `autorelease`,
  explicit `-dealloc`.  ARC requires the modern Apple runtime and
  isn't universally available on GNUstep targets.
- **`@property` in headers, explicit `@synthesize` in
  implementations.**  The properties match Apple's public API
  exactly, so consumer code is source‑compatible.  Explicit
  `@synthesize` (vs auto‑synthesis) keeps the ivar layout obvious to
  the reader.
- **Blocks are fine** — Apple's WKWebView API uses them heavily
  (completion handlers) and we'd lose source compatibility without
  them.  GCC + libBlocksRuntime is part of GNUstep's modern stack.
- **`#import <Foundation/Foundation.h>` and
  `#import <AppKit/AppKit.h>`** for new files; one umbrella import
  per framework, not per class.
- **No emoji in source, headers, or commit messages** — they don't
  always survive `git format-patch` round trips and aren't in
  GNUstep's convention.
- **License header** at the top of every new file:
  ```
  /* Copyright (C) <year> Free Software Foundation, Inc.
   *
   * This library is free software; you can redistribute it and/or modify
   * it under the terms of the GNU Lesser General Public License as
   * published by the Free Software Foundation; either version 2.1 of the
   * License, or (at your option) any later version.
   */
  ```
- **Tabs for indent, 2 spaces inside braces** matches the
  surrounding GNUstep code.
- **Don't introduce new third‑party dependencies** without a
  pkg-config probe in `./configure` and a fallback to compile
  without when the dep is missing.  Hard runtime dependency on
  `libwpewebkit-2.0` is the one acceptable hard requirement.

## Building from a fresh clone

```sh
sudo apt install gnustep-make gnustep-base-runtime libgnustep-gui-dev \
                 libwpewebkit-2.0-dev libwpe-1.0-dev libwpebackend-fdo-1.0-dev \
                 xclip
./configure
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make
make -C Tests/Unit run                 # 34 unit tests
./Tests/run_tests.sh                   # 7 Xvfb integration tests
make -C Demo run                       # launch the demo browser
```

If any of those steps fail, that's a bug — please file it.

## Patch conventions

- One logical change per commit.  "Add X and also rename Y while
  I'm here" → two commits.
- Commit message subject ≤ 70 chars, imperative ("Add
  WKHTTPCookieStore observer notifications" — not "Added" or
  "Adds").
- Body wraps at 72 chars, explains *why* not *what* (the diff
  shows what).
- Reference the issue number if there is one.

## License of contributions

By submitting a patch you agree it's licensed under LGPL‑2.1 or
later (same as the project), and that you have the right to license
it that way.  See `COPYING.LIB`.
