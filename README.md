# gnustep-webkit

> **Status:** v0.1 — preview / call‑for‑feedback.
> All features in the demo screenshot below work today; the rough
> edges are listed honestly under [Limitations](#limitations).
> See [CONTRIBUTING.md](CONTRIBUTING.md) for how to help.

A reimplementation of Apple's WebKit framework — `WKWebView` and
friends — for GNUstep, rendered by [WPE WebKit](https://wpewebkit.org/).

The goal is **source compatibility with `<WebKit/WebKit.h>` on Apple
platforms**, so AppKit code that already uses `WKWebView` on macOS /
iOS can compile and run on GNUstep without rewriting the web‑view
layer.  The long‑term destination is acceptance into mainline GNUstep
as an officially maintained framework next to `libs-gui` /
`libs-OpenSave`.

![Screenshot of the bundled WebKitDemo.app rendering gnustep.org —
toolbar with back/forward/reload, an address bar, an inline JS
evaluator, and the live web page below.](Documentation/screenshot.png)

The bundled `WebKitDemo.app` is a minimal browser exercising the
public API: paste from a password manager, drag‑select text, right‑
click context menus that vary by what's under the cursor, Cmd+F find
bar, Cmd+= / Cmd+- zoom, hover dropdowns, Cmd+N for additional
windows, and a Demo menu showing the custom URL scheme handler,
cookie inspector, file picker, and back/forward history.

## Quick start

Tested on Debian 13 (Trixie).  Equivalent packages exist on Fedora,
Arch, and openSUSE — see [`Documentation/BUILD.md`](Documentation/BUILD.md)
for per‑distro names.

```sh
sudo apt install gnustep-make gnustep-base-runtime libgnustep-gui-dev \
                 libwpewebkit-2.0-dev libwpe-1.0-dev libwpebackend-fdo-1.0-dev \
                 xclip
./configure
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make
make -C Demo run
```

## Consumer example

```objc
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@interface MyController : NSObject <WKNavigationDelegate>
@end
@implementation MyController
- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  NSWindow *win = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 1024, 768)
                styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask
                  backing:NSBackingStoreBuffered defer:NO];
  WKWebView *web = [[WKWebView alloc]
      initWithFrame:[[win contentView] bounds]];
  [web setNavigationDelegate:self];
  [web setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [[win contentView] addSubview:web];
  [web loadRequest:[NSURLRequest requestWithURL:
      [NSURL URLWithString:@"https://example.com/"]]];
  [win makeKeyAndOrderFront:nil];
}

- (void)webView:(WKWebView *)v didFinishNavigation:(WKNavigation *)n
{
  [v evaluateJavaScript:@"document.title"
      completionHandler:^(id r, NSError *e) { NSLog(@"%@", r); }];
}
@end
```

Build with `-lWebKit -lgnustep-gui -lgnustep-base -ldispatch -fblocks`.

## Features

Behaviour:

- Real WebKit rendering via WPE + WPEBackend-FDO
- Mouse / scroll / keyboard input (Unicode keysyms; F1‑F12;
  modifier‑only keypress events via `flagsChanged:`)
- Hover (`:hover`, `onmouseover`, `mouseenter`) and cursor shape
  changes (I‑beam over text, hand over links)
- Drag‑to‑select text (via JS shim, see [Limitations](#limitations))
- Resize repaint without artifacts
- Clipboard `Ctrl+C` / `Ctrl+V` / `Ctrl+X` through `NSPasteboard`
  (with `xclip` fallback for X11/Wayland selection desync)
- Hit‑test aware right‑click menu (Cut/Copy/Paste over editables;
  Copy Link / Open Image / etc. over other targets)
- Find in page (`Cmd+F`)
- Page zoom (`Cmd+=` / `Cmd+-` / `Cmd+0`)
- File chooser (`<input type=file>`) via `NSOpenPanel`
- Downloads via `NSSavePanel` (full `WKDownload` + `WKDownloadDelegate`)
- Custom URL schemes (`myapp://...`)
- JS↔native bridge in both directions
- KVO on `title`, `URL`, `estimatedProgress`, `loading`

API surface (Apple‑compatible):

`WKWebView`, `WKWebViewConfiguration`, `WKPreferences`,
`WKProcessPool`, `WKUserContentController`, `WKUserScript`,
`WKScriptMessage(Handler)`, `WKNavigation(Action|Response|Delegate)`,
`WKUIDelegate`, `WKBackForwardList(Item)`, `WKFrameInfo`,
`WKSecurityOrigin`, `WKContentWorld`, `WKWebsiteDataStore`,
`WKHTTPCookieStore`, `WKURLSchemeHandler` / `WKURLSchemeTask`,
`WKContentRuleList(Store)`, `WKDownload(Delegate)`,
`WKFindConfiguration` / `WKFindResult`, `WKSnapshotConfiguration` /
`WKPDFConfiguration`, `WKError`.

## Tests

```sh
make -C Tests/Unit run        # 34 unit tests (value-type classes)
./Tests/run_tests.sh          # 7 integration tests (Xvfb + xdotool)
```

The integration harness boots its own Xvfb, starts `gpbs`, drives
the demo via a stdin command channel (`GOTO` / `EVAL` / `RESIZE` /
`QUIT`), synthesises mouse and keyboard events with `xdotool`, and
asserts via JavaScript evaluation against the loaded page.

## Limitations

Things that don't work yet and the reason:

| Item | Why | Tracking |
|---|---|---|
| Engine‑native drag‑select | Debian's `libwpewebkit-2.0` is built with `ENABLE_DRAG_SUPPORT=OFF` (which the CMake comment literally says "includes selection of text with mouse"). We work around with a JS shim. | Custom WPE build needed |
| Engine‑native drag‑and‑drop | Same flag | Custom WPE build needed |
| Engine clipboard | `_wpe_pasteboard_interface` isn't exported by WPEBackend‑FDO, so the engine's `Ctrl+V` reads an empty clipboard. We bypass via `NSPasteboard`. | Custom WPE build needed |
| PDF / print | The WPE port doesn't ship `webkit_print_operation` at all | Custom WPE build (and WPE upstream patch) |
| CJK IME preedit | Needs `NSTextInputClient` ↔ `WebKitInputMethodContext` plumbing | Open contribution |
| EGL / dma‑buf rendering | Currently CPU‑side SHM. EGL textures would give us hardware compositing for video/animation. | Open contribution |
| `g_main_context` integration into `NSRunLoop` | 60 Hz `NSTimer` works fine; a pollfd‑driven version was tried but introduced WebKit IPC reply latency. | Open contribution |
| Process‑exit clean teardown | `_exit(0)` workaround avoids a use‑after‑free in libgnustep‑gui's autorelease drain during `terminate:`. | Open contribution (libs‑gui side) |
| Accessibility | `-accessibilityRoleDescription` stub. Real AT‑SPI ↔ `NSAccessibility` bridge is a separate project. | Open contribution |
| In‑window tab bar | Demo has `Cmd+N` for new window; full tabs UI is demo polish, not framework work. | Open contribution |

Architectural details and per‑distro install notes:
[`Documentation/Overview.md`](Documentation/Overview.md) and
[`Documentation/BUILD.md`](Documentation/BUILD.md).

## Layout

```
Headers/WebKit/        Public umbrella + per-class headers
Source/                Framework implementation
  WK*.m                  Apple-shaped facade classes
  GSWebKitBackend.{h,m}  Engine abstraction protocol
  GSWebKitWPE.{h,m}      libwpe / WPEBackend-FDO / libWPEWebKit bridge
Demo/                  WebKitDemo.app — minimal browser
Tests/run_tests.sh     Xvfb integration tests
Tests/Unit/            ObjC unit tests for value-type classes
Documentation/         Architecture + build instructions + screenshot
configure              pkg-config probing → config.make
```

## Why WPE rather than WebKitGTK?

Both ports share the same upstream WebKit, but WPE was designed
explicitly for embedding into something that isn't GTK.  We register
a SHM rendering client; WPE delivers `wl_shm_buffer`s of pixels; we
hand those to `NSBitmapImageRep` and draw through `NSView`.  No GTK
widget hierarchy, no X11 window reparenting, no hidden `GtkWindow` —
just a flat seam between WPE and AppKit, appropriate for
upstreaming.

## Contributing

Patches very welcome.  See [CONTRIBUTING.md](CONTRIBUTING.md) for
project scope, what's open for help, coding style, and how to
file issues.

## License

LGPL‑2.0‑or‑later, matching GNUstep's `libs-gui` and `libs-OpenSave`.
See [`COPYING.LIB`](COPYING.LIB).

Every runtime dependency is LGPL‑compatible or permissively
licensed; the engine itself (`libwpewebkit-2.0`) is dual
LGPL‑2.0+ / BSD‑2‑Clause.  Full breakdown for packagers in
[`Documentation/Licensing.md`](Documentation/Licensing.md), including
what downstream MIT / proprietary / GPL apps can do with the
framework.
