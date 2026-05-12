# GNUstep WebKit — Overview

`gnustep-webkit` is an Objective‑C implementation of Apple's
`WebKit.framework` API surface (`WKWebView` and friends) for GNUstep.
Web content is rendered by [WPE WebKit](https://wpewebkit.org/), the
same upstream WebKit Igalia ships for embedded use, glued to AppKit by
a thin engine‑abstraction layer.

The goal is source compatibility with code written against Apple's
`<WebKit/WebKit.h>` so existing Cocoa apps can compile and run on
GNUstep without rewriting their web view layer.

## Architecture

```
                ┌────────────────────────────────────────────────┐
                │                Consumer app                    │
                │    #import <WebKit/WebKit.h>                   │
                └─────────────────┬──────────────────────────────┘
                                  │  WKWebView, WKNavigationDelegate,
                                  │  WKUserContentController, …
                ┌─────────────────▼──────────────────────────────┐
                │   WK* facade classes (Source/WK*.m)            │
                │   - Apple‑compatible public API                │
                │   - Translates AppKit (NSEvent, NSView)        │
                │     into engine‑neutral calls                  │
                │   - JS‑based shims for features WPE omits:     │
                │       * drag‑select (ENABLE_DRAG_SUPPORT=OFF)  │
                │       * Ctrl+V paste through NSPasteboard      │
                └─────────────────┬──────────────────────────────┘
                                  │  GSWebKitBackend protocol
                ┌─────────────────▼──────────────────────────────┐
                │   GSWebKitWPE  (Source/GSWebKitWPE.m)          │
                │   - libwpe + WPEBackend‑FDO + libWPEWebKit‑2.0 │
                │   - SHM exportable view backend → NSBitmapImage│
                │   - GLib main context driven from NSRunLoop    │
                └─────────────────┬──────────────────────────────┘
                                  │  C library calls
                ┌─────────────────▼──────────────────────────────┐
                │   libwpewebkit‑2.0  (Igalia, system library)   │
                │   WebKit2 UI process + Web process + Network   │
                │   process.  Same upstream as Apple's WebKit.   │
                └────────────────────────────────────────────────┘
```

`GSWebKitBackend` is a deliberate seam.  Today the only concrete
implementation is `GSWebKitWPE`, but the abstraction lets a future
backend (an updated WPE 2.x build with full feature support, or
something else entirely) slot in without touching the public API.

## What's implemented

| Apple API | Status | Notes |
| --- | --- | --- |
| `WKWebView` (`NSView` subclass) | ✅ | load URL/HTML/data, navigate, JS eval, scroll, click, drag, paste |
| `WKWebViewConfiguration` | ✅ | preferences, UCC, processPool, websiteDataStore, scheme handlers |
| `WKNavigationDelegate` | ✅ | start / commit / finish / fail (provisional & post-commit) |
| `WKUIDelegate` | ✅ | alert / confirm / prompt; `NSAlert` fallback if not implemented |
| `WKUserContentController` | ✅ | user scripts + named JS message handlers + content rule lists |
| `WKUserScript` | ✅ | document-start and document-end injection times |
| `WKScriptMessage(Handler)` | ✅ | `window.webkit.messageHandlers.NAME.postMessage(...)` |
| `WKPreferences` | ✅ | JavaScript on/off, minimum font size, etc. |
| `WKBackForwardList(Item)` | ✅ | populated from committed navigations |
| `WKContentWorld` | ✅ (API) | named worlds tracked; JS eval currently all in page world |
| `WKWebsiteDataStore` | ✅ | default + non-persistent factories |
| `WKHTTPCookieStore` | ✅ | get/set/delete via `SoupCookie` bridge |
| `WKURLSchemeHandler` | ✅ | custom `myapp://` schemes via `webkit_web_context_register_uri_scheme` |
| `WKContentRuleListStore` | ✅ | compile + persist Safari-style content blockers |
| `WKDownload` + delegate | ✅ | default UI shows `NSSavePanel` |
| `WKFindConfiguration` | ✅ | find / find-next / find-previous |
| `takeSnapshot…` | ✅ | returns the current SHM frame as `NSImage` |
| `createPDF…` | ✋ stubbed | WPE 2.48 doesn't expose PDF export; reports not-supported |
| `printOperationWithPrintInfo:` | ✋ stubbed | same reason as PDF |

## Engine‑level features compiled out in distro WPE

Debian's `libwpewebkit-2.0` (and most other distro builds) ships with
`ENABLE_DRAG_SUPPORT=OFF`.  That feature flag is documented as
"toggle support of drag actions (including selection of text with
mouse)" — so the engine itself **doesn't** extend selection on
mouse drag.  We work around it in the framework:

- **Drag‑to‑select**: `WKWebView` synthesises selection extension
  by reading the existing anchor offset (which WebKit *does* set on
  mousedown) and calling `Selection.setBaseAndExtent(...)` via
  `evaluateJavaScript:` on each motion event with the left button
  held.

- **Native clipboard**: `_wpe_pasteboard_interface` isn't exported by
  WPEBackend‑FDO, so WebKit's built‑in Ctrl+V / Ctrl+C / Ctrl+X
  paths read an empty clipboard.  We intercept the keystrokes
  *before* forwarding to the engine and route them through
  `NSPasteboard` (with an `xclip` fallback for `gpbs` ↔ X11 selection
  desyncs).

- **PDF / print**: not in the WPE port at all.

These shims behave correctly in practice but a custom WPE build with
the relevant features enabled would let us drop them and pick up
native autoscroll, drag‑and‑drop between page and host, etc.

## Build prerequisites

See [BUILD.md](./BUILD.md) for distro-specific package names.

## Layout

```
Headers/WebKit/   Public API.  Mirror Apple's <WebKit/WebKit.h>.
Source/           Framework implementation:
   WK*.m              Apple-shaped facade classes
   GSWebKitBackend.{h,m}   Engine abstraction protocol
   GSWebKitWPE.{h,m}       libwpe / WPEBackend-FDO / libWPEWebKit bridge
   GSWebKitInternal.h      Cross-file private declarations
Demo/             WebKitDemo.app — minimal browser exercising the API
Tests/            Xvfb-driven integration tests
configure         Probes pkg-config, writes config.make
GNUmakefile       Aggregate; includes Source/ and Demo/
```

## Threading

Everything runs on the AppKit main thread.  GLib's default main context
is pumped by a 60 Hz `NSTimer`, so WPE callbacks and signal handlers
all land on the same thread as `-drawRect:` and `-mouseDown:`.  No
locks are required between rendering and event dispatch.

A v2 polish item: replace the polling timer with a proper integration
using `g_main_context_prepare/query/check/dispatch` driven by
`NSRunLoop`'s pollfd set.  Idle CPU would drop from ~0.1% to 0%.

## Known v1 follow‑ups

1. **Process‑exit clean‑up.** `applicationWillTerminate:` releases the
   browser controller and calls `_exit(0)` to skip the rest of
   AppKit's teardown.  The root cause is a use‑after‑free inside
   `-[NSAutoreleasePool emptyPool]` while WPE/GLib state is being torn
   down.  The `_exit` works around it cleanly for users; properly
   fixing it requires coordinating with libgnustep‑gui's signal /
   terminate path.
2. **IME (input method editor).** Non‑ASCII *characters* work via
   direct Unicode keysyms (X11R6 convention), but CJK preedit
   composition isn't wired.  Needs `NSTextInputClient` integration
   with `WebKitInputMethodContext`.
3. **Real EGL/dma‑buf rendering.** Currently CPU‑side SHM; fine for
   static pages, want EGL textures for smooth video / animation.
4. **PDF / print.** Stubbed; requires a custom WPE build that exposes
   `webkit_print_operation` (the GTK port has it, WPE port doesn't).
5. **NSAccessibility / AT‑SPI bridge.** Stubbed at the `NSView`
   surface; full bridge into WebKit's accessibility tree is a
   separate project.

## License

LGPL‑2.1+, matching `libs-gui` / `libs-OpenSave`.
