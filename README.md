# GNUstep WebKit

`gnustep-webkit` is an Objective-C implementation of Apple's WebKit
framework (`WKWebView` and friends) for GNUstep, backed by the
[WPE WebKit](https://wpewebkit.org/) engine.

The goal is letting any GNUstep AppKit application embed full web
content with the **same API surface used on macOS / iOS**, so source
written against `<WebKit/WebKit.h>` for Apple platforms compiles and
runs unchanged on GNUstep.

The project is structured for eventual upstream into the GNUstep
project (alongside `libs-gui` / `libs-OpenSave`); the code is plain
Objective-C with manual retain/release — no ARC, no Cocoa-runtime-only
features — and the public headers are LGPL-2.1+.

## Status

Working v1: a real WPE-backed `WKWebView` paints into an `NSView`, the
bundled demo loads HTTPS pages end-to-end, and the API surface covers
what most embedders reach for.

### What works

Behaviour:

- Real WebKit rendering via WPE + WPEBackend-FDO (SHM exportable
  buffers → `NSBitmapImageRep` via direct memcpy, no per-pixel
  swizzle)
- Mouse, scroll, keyboard input (Unicode keysyms for non-ASCII)
- Hover (`:hover`, `onmouseover`, `mouseenter`) via `NSTrackingRect`
- Cursor shape changes (`I-beam` over text, hand over links)
- Drag-to-select (via JS `Selection.setBaseAndExtent` shim, because
  Debian's WPE is built with `ENABLE_DRAG_SUPPORT=OFF`)
- Resize repaint with no visual artifacts during a live drag
- Clipboard Ctrl+V / Ctrl+C / Ctrl+X through `NSPasteboard` (with
  `xclip` fallback for X11 selection desyncs)
- Right-click context menu, hit-test aware: Cut/Copy/Paste over
  editables, Copy Link / Open Image / etc. over the right element
- File chooser (`<input type=file>`) via `NSOpenPanel`
- Downloads via `NSSavePanel` (with full `WKDownload` /
  `WKDownloadDelegate` API)
- Find in page
- JS bridge in both directions (`window.webkit.messageHandlers.NAME`)
- KVO on `title`, `URL`, `estimatedProgress`, `loading`

API surface implemented:

`WKWebView`, `WKWebViewConfiguration`, `WKPreferences`,
`WKProcessPool`, `WKUserContentController`, `WKUserScript`,
`WKScriptMessage(Handler)`, `WKNavigation(Action|Response|Delegate)`,
`WKUIDelegate`, `WKBackForwardList(Item)`, `WKFrameInfo`,
`WKSecurityOrigin`, `WKContentWorld`, `WKWebsiteDataStore`,
`WKHTTPCookieStore`, `WKURLSchemeHandler`,
`WKContentRuleList(Store)`, `WKDownload(Delegate)`,
`WKFindConfiguration` / `WKFindResult`, `WKSnapshotConfiguration` /
`WKPDFConfiguration`, `WKError`.

### Known v1 follow-ups

| | |
| --- | --- |
| Exit-time `_exit(0)` workaround | `applicationWillTerminate:` skips AppKit's pool drain to avoid a use-after-free inside libgnustep-gui's terminate path. Users don't see it. |
| PDF / print stubbed | `webkit_print_operation` is GTK-port only in WPE 2.48; `createPDFWithConfiguration:` reports not-supported. |
| Engine-native drag-select | Debian's libwpewebkit has `ENABLE_DRAG_SUPPORT=OFF`; we work around with JS. Custom WPE build would remove the need. |
| CJK IME | Latin-1 / Cyrillic / Greek work via Unicode keysyms; CJK preedit needs `WebKitInputMethodContext` ↔ `NSTextInputClient`. |
| EGL/dma-buf rendering | Currently CPU/SHM (memcpy fast path, no swizzle). EGL textures are v2. |
| Polling GLib pump | 60 Hz `NSTimer`. v2: prepare/query/check/dispatch driven by `NSRunLoop`. |
| Accessibility | Stub (`-accessibilityRoleDescription` returns "web content"). Real AT-SPI ↔ NSAccessibility bridge is a project of its own. |

See `Documentation/Overview.md` and `Documentation/BUILD.md` for the
architectural details and per-distro install instructions.

## Layout

```
Headers/WebKit/        Public umbrella + per-class headers
Source/                Framework implementation
  WK*.m                  Apple-shaped facade classes
  GSWebKitBackend.[hm]   Engine abstraction protocol
  GSWebKitWPE.[hm]       libwpe + WPEBackend-FDO + libWPEWebKit-2.0 bridge
  GSWebKitInternal.h     Cross-file private declarations
Demo/                  WebKitDemo.app — minimal browser
Tests/run_tests.sh     Xvfb integration tests (7 passing)
Tests/Unit/            ObjC unit tests for value-type classes (34 passing)
Documentation/         Overview + build instructions
configure              pkg-config probing → config.make
```

## Build

```sh
sudo apt install gnustep-make gnustep-base-runtime libgnustep-gui-dev \
                 libwpewebkit-2.0-dev libwpe-1.0-dev libwpebackend-fdo-1.0-dev
./configure
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make
make -C Demo run
```

Equivalent packages exist on Fedora (`wpewebkit-devel libwpe-devel
wpebackend-fdo-devel`) and Arch (`wpewebkit libwpe wpebackend-fdo`).
See `Documentation/BUILD.md` for the full matrix.

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
                  backing:NSBackingStoreBuffered
                    defer:NO];
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

## Why WPE instead of WebKitGTK?

Both ports share the same upstream WebKit, but WPE was designed
explicitly for embedding into something that isn't GTK. We register a
SHM rendering client; WPE delivers `wl_shm_buffer`s of CPU-side
pixels; we hand those to `NSBitmapImageRep` and draw through
`NSView`. No GTK widget hierarchy, no X11 window reparenting, no
hidden `GtkWindow` — just a flat seam between WPE and AppKit. The
tradeoff was more upfront work for the backend; the payoff is a clean
architectural boundary appropriate for upstreaming.

## License

LGPL-2.1+, matching GNUstep's `libs-gui` and `libs-OpenSave`. See
`COPYING.LIB`.
