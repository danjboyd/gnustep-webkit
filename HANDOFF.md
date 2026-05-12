# Handoff — where we left off 2026-05-12

Quick orientation for tomorrow.  All commits are pushed to
`danjboyd/gnustep-webkit` on GitHub.

## What's solid

- **Framework + demo work end-to-end.**  Demo loads gnustep.org,
  paste / drag-select / hover / context menus / find bar / zoom /
  cookies / custom URL schemes all functional on Debian 13.
- **Unit suite: 119 assertions across 28 tests, all passing locally.**
  `make -C Tests/Unit run`
- **Integration suite: 43 assertions across 22 tests, all passing
  locally** under Xvfb + xdotool.  `./Tests/run_tests.sh`
- **Tests caught two real bugs** in v0.1.0 code which are fixed in
  the same commit (`19d617f`):
  1. `WKWebViewConfiguration -copyWithZone:` was dropping the
     `_schemeHandlers` dictionary, so `WKURLSchemeHandler`s
     registered on a config never reached the `WKWebView`'s
     internal copy.  myapp:// URLs always loaded as `about:blank`.
  2. `WKHTTPCookieStore -getAllCookies:` was using the per-URI
     filter (empty URI = zero cookies returned) instead of WPE
     2.40+'s `webkit_cookie_manager_get_all_cookies` which returns
     the full jar.  Now switched.
- **Release `v0.1.0` published** with release notes:
  https://github.com/danjboyd/gnustep-webkit/releases/tag/v0.1.0
- **`Documentation/Licensing.md`** spells out the dependency
  license graph for downstream packagers.
- **`Documentation/screenshot.png`** is the canonical demo
  screenshot embedded in the README.

## What's actively broken

**GitHub Actions CI is red** at HEAD (`03dfc55`).  The Debian
Trixie container job fails at the "Install build dependencies"
step:

```
E: Unable to locate package gnustep-clang-libobjc2
```

I confirmed the package exists locally (`dpkg -S
/usr/GNUstep/System/Library/Headers/objc/blocks_runtime.h` returns
`gnustep-clang-libobjc2`).  The container probably needs a
different apt source / suite enabled, or the package name is
distribution-codename-specific.

The unit tests run fine locally with the exact same Debian Trixie
version — the difference must be apt sources / suite enabled in
the container vs. our local install.  Things to try in the
morning:

1. **Check which sources install `gnustep-clang-libobjc2` locally.**
   `apt-cache policy gnustep-clang-libobjc2` should show which
   archive provides it.  The `debian:trixie` container image
   probably enables only `main`; this package might be in
   `contrib` or only in `sid`.
2. **Alternative package name** — see also `libdispatch0-dev`,
   `libblocksruntime-dev`, or installing it indirectly via
   `gnustep-base-runtime`'s recommends.
3. **Drop the CI container entirely** and use the
   `gnustep/gnustep` Docker image (Igalia ships one) if it
   already has the runtime configured.  Tradeoff: opaque
   upstream image.
4. **Worst-case fallback:** in `Source/GNUmakefile` make `-fblocks`
   conditional on whether `<objc/blocks_runtime.h>` is present.
   Block APIs are only used in three places (completion handlers
   for `evaluateJavaScript:`, `WKDownload.cancel:`, and our
   internal scheme task ranges), and they'd still work via
   `Block_copy` shipped with libdispatch.

## Status of the v1 follow-ups (from README "Limitations" section)

Unchanged since v0.1.0.  Big-ticket items still:

- Custom WPE build with `ENABLE_DRAG_SUPPORT=ON` to replace the
  drag-select / clipboard JS shims with engine-native paths.
- Real exit-time clean teardown vs the `_exit(0)` workaround in
  `applicationWillTerminate:`.
- EGL / dma-buf rendering path.
- CJK IME composition via `NSTextInputClient` ↔
  `WebKitInputMethodContext`.
- AT-SPI ↔ `NSAccessibility` bridge.

## Things that are tested but I'd still want to add coverage for
(open follow-up work)

- `WKContentRuleListStore` actually compiling JSON rules and
  blocking a request.  The class is covered structurally; the
  compile path isn't exercised.
- `WKDownload` lifecycle end-to-end with a real `download-started`
  signal firing.  We test the API surface, not a real download
  completing.
- Cursor shape changes via the mouse-target-changed signal.
- File chooser (NSOpenPanel) panel callback (modal panels trip up
  xdotool sequencing in CI).
- Memory leak / valgrind sweep.
- Multi-distro CI matrix beyond Debian.

## Next-session quick-start

```sh
# get oriented
cd ~/git/gnustep/gnustep-webkit
git log --oneline | head -5
git status

# verify everything still works locally
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make -C Tests/Unit run        # expect: 119 passed
./Tests/run_tests.sh          # expect: 43 passed

# fix CI: figure out the apt source/suite for gnustep-clang-libobjc2
apt-cache policy gnustep-clang-libobjc2

# CI history
gh run list --limit 5
```

Two outstanding GitHub items still pending public announcement
(see https://github.com/danjboyd/gnustep-webkit#contributing):

1. Post a brief intro on `gnustep-dev@gnu.org`.
2. Maybe webkit-wpe@lists.webkit.org to let Igalia know.

## Recent commit chain (most recent first)

```
03dfc55 CI: switch libobjc2-dev -> gnustep-clang-libobjc2 (Debian package name)
5010a70 CI: install libobjc2-dev for blocks_runtime.h
fd72323 CI: force clang; gcc rejects -fblocks
e5c1993 CI: install libwayland-dev on Debian; drop Ubuntu (no WPE in noble main repos)
19d617f Mature the test suite: 162 assertions, CI, fixed two real bugs
466aecc Add Documentation/Licensing.md with dependency-license breakdown
e8daf78 Match GNUstep house license-header wording
7920fd8 README/CONTRIBUTING polish; screenshot; download-signal fix
9882663 Restore BGRA->RGBA swizzle; libs-back ignores bitmap-format flags
184941c Find bar, zoom, demo features, page-zoom, function keys, new-window
129cf71 .gitignore: exclude configure output and apt-get source artifacts
43b5c85 Expand API surface, add hit-test menu, hover, paste, downloads, more
18db56f Initial WebKit framework with WPE backend and demo app
```
