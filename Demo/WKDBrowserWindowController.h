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
}

- (void)goToAddress:(id)sender;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)reload:(id)sender;
- (void)stopLoading:(id)sender;
- (void)evaluateJS:(id)sender;

@end

#endif
