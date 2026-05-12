/* WKDBrowserWindowController.h
 *
 * A miniature browser window built with the WebKit framework.  Shows
 * an address bar, back/forward/reload/stop buttons, a JavaScript-eval
 * box, a progress indicator, and a WKWebView filling the rest of the
 * window.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#ifndef WKD_BROWSER_WINDOW_CONTROLLER_H
#define WKD_BROWSER_WINDOW_CONTROLLER_H

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

@interface WKDBrowserWindowController : NSWindowController
    <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
{
  WKWebView          *_webView;
  NSTextField        *_addressField;
  NSTextField        *_jsField;
  NSButton           *_backButton;
  NSButton           *_forwardButton;
  NSButton           *_reloadButton;
  NSButton           *_stopButton;
  NSButton           *_evalButton;
  NSProgressIndicator *_progress;
  NSTextField        *_statusField;
  NSFileHandle       *_stdinHandle;     /* only used in test mode */
  BOOL                _testMode;

  /* Find bar (hidden by default; Cmd/Ctrl+F shows it). */
  NSView             *_findBar;
  NSTextField        *_findField;
  NSTextField        *_findStatus;
  BOOL                _findBarVisible;
}

- (void)goToAddress:(id)sender;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)reload:(id)sender;
- (void)stopLoading:(id)sender;
- (void)evaluateJS:(id)sender;
- (void)showFindBar:(id)sender;
- (void)hideFindBar:(id)sender;
- (void)findNext:(id)sender;
- (void)findPrevious:(id)sender;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)zoomReset:(id)sender;
- (void)demoFileChooser:(id)sender;
- (void)demoCustomScheme:(id)sender;
- (void)demoCookieInspector:(id)sender;
- (void)demoHistory:(id)sender;

@end

/* Tiny custom URL scheme handler so the demo's Demo menu can show the
 * registration round-trip working.  Responds to myapp://* with a
 * canned HTML page that includes the URL it was loaded from. */
@interface _WKDAppSchemeHandler : NSObject <WKURLSchemeHandler>
@end

#endif
