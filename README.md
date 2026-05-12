# GNUstep WebKit

`gnustep-webkit` is an Objective-C implementation of Apple's WebKit
framework (`WKWebView` and friends) for GNUstep, backed by the
[WPE WebKit](https://wpewebkit.org/) engine.

The goal is to let any GNUstep AppKit application embed full web
content with the same API surface used on macOS / iOS, so that source
written against `<WebKit/WebKit.h>` for Apple platforms compiles and
runs unchanged on GNUstep.

The project is structured for eventual upstream into the GNUstep
project (alongside `libs-gui` / `libs-OpenSave`); the headers are
LGPL-2.1+ licensed and the code is plain Objective-C with manual
retain/release — no ARC, no Cocoa-runtime-only features.

## Status

Working v1: a real WPE-backed `WKWebView` paints into an `NSView` and
the bundled demo loads `https://www.gnustep.org/` end-to-end (HTTPS,
network process, web process, painting, page title, JS bridge).

### What works

- `WKWebView` as an `NSView` subclass — load URL / HTML / data
- WPE WebKit FDO/SHM rendering pipeline, copied into `NSBitmapImageRep`
  and drawn by `-drawRect:`
- `WKNavigationDelegate` lifecycle: didStart / didCommit / didFinish /
  didFail (provisional & post-commit)
- `WKUIDelegate`: alert / confirm / prompt panels (falls back to
  `NSAlert` if the delegate doesn't handle them)
- `evaluateJavaScript:completionHandler:` with `JSCValue` -> Objective-C
  conversion (strings, numbers, booleans, null, arrays, objects)
- `WKUserContentController` user-scripts and named
  `WKScriptMessageHandler` bridges (JS calls
  `window.webkit.messageHandlers.NAME.postMessage(...)`)
- `WKPreferences` (JavaScript on/off, minimum font size, etc.)
- `WKBackForwardList` driven from committed-navigation events
- Mouse, scroll, and keyboard input forwarded to the engine
- KVO on `title`, `URL`, `estimatedProgress`, `loading`

### Known v1 limitations

- Pixel format is SHM/CPU; no EGL / dma-buf yet. Fine on a laptop, will
  want the EGL path for HD video / 60fps animation.
- GLib main context is polled from `NSRunLoop` via an `NSTimer` at
  ~60Hz rather than wired into the run loop's `pollfd` set. Burns a
  tiny amount of idle CPU; correct but not vsync-perfect.
- Process termination through SIGTERM / `-[NSApplication terminate:]`
  currently segfaults inside GNUstep AppKit's autorelease pool drain on
  exit (the engine and its GMainContext threads outlive the AppKit
  teardown). Normal interactive use is unaffected; the bug shows up
  only as the process leaves. Tracked as a v1 follow-up.
- `WKContentWorld`, `WKHTTPCookieStore`, `WKContentRuleListStore`,
  PDF/snapshot APIs, find/zoom, custom URL scheme handlers, and the
  modern `callAsyncJavaScript:` API are not yet implemented.

## Layout

```
Headers/WebKit/        Public umbrella + per-class headers (Apple-style)
Source/                Framework implementation
  WK*.m                Value-type classes (WKWebViewConfiguration, …)
  WKWebView.m          The NSView subclass that consumers embed
  GSWebKitBackend.[hm] Engine abstraction (so another engine can slot in)
  GSWebKitWPE.[hm]     WPE WebKit + libwpe + WPEBackend-FDO bridge
  GSWebKitInternal.h   Internal-only declarations shared across .m files
Demo/                  WebKitDemo.app — minimal AppKit browser
```

## Build prerequisites

On Debian 13 / Trixie:

```
sudo apt install gnustep-make gnustep-base-runtime libgnustep-gui-dev \
                 libwpewebkit-2.0-dev libwpe-1.0-dev \
                 libwpebackend-fdo-1.0-dev
```

Equivalent packages exist on Fedora (`wpewebkit-devel`,
`libwpe-devel`, `wpebackend-fdo-devel`) and Arch
(`wpewebkit`, `libwpe`, `wpebackend-fdo`).

`pkg-config` must find `wpe-webkit-2.0`, `wpe-1.0`, and
`wpebackend-fdo-1.0`. If only the older 1.1 series is available, the
build system falls back automatically.

## Building

```
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
make            # builds Source/libWebKit.so + Demo/WebKitDemo.app
```

Run the demo (without installing):

```
make -C Demo run
```

Install the framework system-wide:

```
make -C Source install
```

After install, consumers include `<WebKit/WebKit.h>` and link
`-lWebKit`, exactly as on Apple platforms.

## Minimal consumer example

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

## Why WPE instead of WebKitGTK?

Both ports share the same upstream WebKit, but WPE was designed
explicitly for embedding into something that isn't GTK. We provide a
SHM rendering callback; WPE delivers `wl_shm_buffer`s of CPU-side
pixels; we copy those into `NSBitmapImageRep` and draw them through
`NSView`. No GTK widget hierarchy, no X11 window reparenting, no
hidden GtkWindow — just a flat seam between WPE and AppKit. The
tradeoff is more upfront work for the backend; the payoff is a clean
architectural boundary appropriate for upstreaming.

## License

LGPL-2.1+, matching GNUstep's `libs-gui` and `libs-OpenSave`. See
`COPYING.LIB`.
