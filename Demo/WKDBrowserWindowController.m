/* WKDBrowserWindowController.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import "WKDBrowserWindowController.h"

@implementation WKDBrowserWindowController

- (instancetype)init
{
  NSRect frame = NSMakeRect(120, 120, 1100, 750);
  NSUInteger style = NSTitledWindowMask
                   | NSClosableWindowMask
                   | NSMiniaturizableWindowMask
                   | NSResizableWindowMask;
  NSWindow *window = [[[NSWindow alloc]
      initWithContentRect:frame
                styleMask:style
                  backing:NSBackingStoreBuffered
                    defer:NO] autorelease];
  [window setTitle:@"GNUstep WebKit Demo"];
  [window setMinSize:NSMakeSize(640, 480)];

  self = [super initWithWindow:window];
  if (self == nil) {
    return nil;
  }

  [self _buildContentInWindow:window];
  [window setDelegate:(id)self];
  [window setReleasedWhenClosed:NO];

  /* Test mode: when WKDEMO_TEST_MODE=1 in the environment, accept a
   * simple line-oriented command protocol on stdin so an external
   * harness can drive the browser deterministically.  Commands:
   *   GOTO <url>
   *   EVAL <javascript-expr>     -> "WKDEMO_EVAL_RESULT: <repr>" on stderr
   *   STATE                      -> "WKDEMO_STATE: ..." on stderr (size,
   *                                 frame size, URL, title, loading flag,
   *                                 selection length)
   *   RESIZE <width> <height>    -> resize the window
   *   QUIT
   */
  if (getenv("WKDEMO_TEST_MODE") != NULL) {
    _testMode = YES;
    _stdinHandle = [[NSFileHandle fileHandleWithStandardInput] retain];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_stdinDataAvailable:)
               name:NSFileHandleReadCompletionNotification
             object:_stdinHandle];
    [_stdinHandle readInBackgroundAndNotify];
    fprintf(stderr, "WKDEMO_READY\n");
    fflush(stderr);
  }

  return self;
}

- (void)_stdinDataAvailable:(NSNotification *)note
{
  NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
  if ([data length] == 0) {
    /* EOF on stdin → terminate. */
    [NSApp terminate:nil];
    return;
  }
  NSString *blob = [[[NSString alloc] initWithData:data
                                          encoding:NSUTF8StringEncoding]
                       autorelease];
  NSArray *lines = [blob componentsSeparatedByString:@"\n"];
  NSEnumerator *e = [lines objectEnumerator];
  NSString *line;
  while ((line = [e nextObject]) != nil) {
    NSString *cmd = [line stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cmd length] == 0) continue;
    [self _handleTestCommand:cmd];
  }
  [_stdinHandle readInBackgroundAndNotify];
}

- (void)_handleTestCommand:(NSString *)cmd
{
  if ([cmd hasPrefix:@"GOTO "]) {
    NSString *url = [cmd substringFromIndex:5];
    [_addressField setStringValue:url];
    [self goToAddress:nil];
    fprintf(stderr, "WKDEMO_ACK: GOTO\n");
    fflush(stderr);
  } else if ([cmd hasPrefix:@"EVAL "]) {
    NSString *js = [cmd substringFromIndex:5];
    [_webView evaluateJavaScript:js
               completionHandler:^(id r, NSError *err) {
      NSString *out;
      if (err != nil) {
        out = [NSString stringWithFormat:@"ERROR %@", [err localizedDescription]];
      } else if (r == nil) {
        out = @"undefined";
      } else if ([r isKindOfClass:[NSString class]]) {
        out = [NSString stringWithFormat:@"string %@", r];
      } else if ([r isKindOfClass:[NSNumber class]]) {
        out = [NSString stringWithFormat:@"number %@", r];
      } else {
        out = [NSString stringWithFormat:@"object %@", r];
      }
      fprintf(stderr, "WKDEMO_EVAL_RESULT: %s\n", [out UTF8String]);
      fflush(stderr);
    }];
  } else if ([cmd isEqualToString:@"STATE"]) {
    NSRect vf = [_webView frame];
    NSURL *u  = [_webView URL];
    NSString *t = [_webView title] ?: @"";
    fprintf(stderr, "WKDEMO_STATE: view=%.0fx%.0f url=%s title=%s loading=%d\n",
            vf.size.width, vf.size.height,
            [[u absoluteString] UTF8String] ?: "",
            [t UTF8String],
            (int)[_webView isLoading]);
    fflush(stderr);
  } else if ([cmd hasPrefix:@"RESIZE "]) {
    int w = 0, h = 0;
    sscanf([[cmd substringFromIndex:7] UTF8String], "%d %d", &w, &h);
    if (w > 0 && h > 0) {
      NSWindow *win = [self window];
      NSRect f = [win frame];
      f.size.width  = w;
      f.size.height = h;
      [win setFrame:f display:YES animate:NO];
      NSRect winFrame = [win frame];
      NSRect viewFrame = [_webView frame];
      fprintf(stderr, "WKDEMO_ACK: RESIZE want=%dx%d got_win=%.0fx%.0f web=%.0fx%.0f\n",
              w, h,
              winFrame.size.width, winFrame.size.height,
              viewFrame.size.width, viewFrame.size.height);
      fflush(stderr);
    }
  } else if ([cmd hasPrefix:@"WEBVIEW_RESIZE "]) {
    int w = 0, h = 0;
    sscanf([[cmd substringFromIndex:15] UTF8String], "%d %d", &w, &h);
    if (w > 0 && h > 0) {
      [_webView setFrameSize:NSMakeSize(w, h)];
      fprintf(stderr, "WKDEMO_ACK: WEBVIEW_RESIZE %d %d\n", w, h);
      fflush(stderr);
    }
  } else if ([cmd isEqualToString:@"QUIT"]) {
    [NSApp terminate:nil];
  } else {
    fprintf(stderr, "WKDEMO_UNKNOWN: %s\n", [cmd UTF8String]);
    fflush(stderr);
  }
}

- (void)dealloc
{
  if (_stdinHandle != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleReadCompletionNotification
                                                  object:_stdinHandle];
    [_stdinHandle release];
  }
  [_webView release];
  [_addressField release];
  [_jsField release];
  [_backButton release];
  [_forwardButton release];
  [_reloadButton release];
  [_stopButton release];
  [_evalButton release];
  [_progress release];
  [_statusField release];
  [super dealloc];
}

- (void)_buildContentInWindow:(NSWindow *)window
{
  NSView *content = [window contentView];
  NSRect cb = [content bounds];

  /* Toolbar row: back / forward / reload / stop / address. */
  CGFloat tx = 8.0;
  CGFloat ty = cb.size.height - 36.0;

  _backButton = [self _makeButtonAt:NSMakePoint(tx, ty)
                              width:60
                              title:@"<"
                             action:@selector(goBack:)];
  [content addSubview:_backButton];
  tx += 64;

  _forwardButton = [self _makeButtonAt:NSMakePoint(tx, ty)
                                 width:60
                                 title:@">"
                                action:@selector(goForward:)];
  [content addSubview:_forwardButton];
  tx += 64;

  _reloadButton = [self _makeButtonAt:NSMakePoint(tx, ty)
                                width:80
                                title:@"Reload"
                               action:@selector(reload:)];
  [content addSubview:_reloadButton];
  tx += 84;

  _stopButton = [self _makeButtonAt:NSMakePoint(tx, ty)
                              width:60
                              title:@"Stop"
                             action:@selector(stopLoading:)];
  [content addSubview:_stopButton];
  tx += 64;

  CGFloat goButtonWidth = 50;
  CGFloat addressWidth  = cb.size.width - tx - 8 - goButtonWidth - 4;
  _addressField = [[NSTextField alloc] initWithFrame:
      NSMakeRect(tx, ty, addressWidth, 26)];
  [_addressField setStringValue:@"https://www.gnustep.org/"];
  [_addressField setTarget:self];
  [_addressField setAction:@selector(goToAddress:)];
  [_addressField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [content addSubview:_addressField];
  tx += addressWidth + 4;

  NSButton *goButton = [self _makeButtonAt:NSMakePoint(tx, ty)
                                     width:goButtonWidth
                                     title:@"Go"
                                    action:@selector(goToAddress:)];
  [goButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [content addSubview:goButton];

  /* JS row. */
  ty -= 32;
  tx  = 8.0;
  _jsField = [[NSTextField alloc] initWithFrame:
      NSMakeRect(tx, ty, cb.size.width - 16 - 88, 24)];
  [_jsField setStringValue:@"document.title"];
  [[_jsField cell] setPlaceholderString:@"JavaScript expression"];
  [_jsField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [content addSubview:_jsField];

  _evalButton = [self _makeButtonAt:NSMakePoint(cb.size.width - 80 - 8, ty)
                              width:80
                              title:@"Evaluate"
                             action:@selector(evaluateJS:)];
  [_evalButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [content addSubview:_evalButton];

  /* Progress + status row at bottom. */
  _progress = [[NSProgressIndicator alloc] initWithFrame:
      NSMakeRect(8, 8, 120, 16)];
  [_progress setIndeterminate:NO];
  [_progress setMinValue:0.0];
  [_progress setMaxValue:1.0];
  [_progress setDoubleValue:0.0];
  [_progress setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
  [content addSubview:_progress];

  _statusField = [[NSTextField alloc] initWithFrame:
      NSMakeRect(136, 6, cb.size.width - 144, 18)];
  [_statusField setEditable:NO];
  [_statusField setSelectable:YES];
  [_statusField setBezeled:NO];
  [_statusField setDrawsBackground:NO];
  [_statusField setStringValue:@""];
  [_statusField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [content addSubview:_statusField];

  /* Web view fills the rest. */
  NSRect webFrame = NSMakeRect(8, 36, cb.size.width - 16,
                               cb.size.height - 36 - 8 - 32 - 32);
  WKWebViewConfiguration *config = [[[WKWebViewConfiguration alloc] init] autorelease];

  /* Wire a JS->host message bridge for demonstration purposes. */
  WKUserContentController *ucc = [config userContentController];
  [ucc addScriptMessageHandler:(id <WKScriptMessageHandler>)self name:@"demoBridge"];
  WKUserScript *boot = [[[WKUserScript alloc]
      initWithSource:@"window.WebKitDemoSay = function(msg){"
                      "  window.webkit.messageHandlers.demoBridge.postMessage(msg);"
                      "};"
       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
    forMainFrameOnly:YES] autorelease];
  [ucc addUserScript:boot];

  _webView = [[WKWebView alloc] initWithFrame:webFrame configuration:config];
  [_webView setNavigationDelegate:(id <WKNavigationDelegate>)self];
  [_webView setUIDelegate:(id <WKUIDelegate>)self];
  [_webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [content addSubview:_webView];

  /* In test mode we don't want the initial auto-load racing the
   * harness's GOTO command.  The harness will pick the URL. */
  if (getenv("WKDEMO_TEST_MODE") == NULL) {
    [self goToAddress:nil];
  }
}

- (NSButton *)_makeButtonAt:(NSPoint)origin
                      width:(CGFloat)width
                      title:(NSString *)title
                     action:(SEL)action
{
  NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(origin.x, origin.y, width, 26)];
  [b setBezelStyle:NSRoundedBezelStyle];
  [b setTitle:title];
  [b setTarget:self];
  [b setAction:action];
  return [b autorelease];
}


/* ----------------------------------------------------- Actions */

- (void)goToAddress:(id)sender
{
  (void)sender;
  NSString *raw = [_addressField stringValue];
  if ([raw length] == 0) {
    return;
  }
  /* Treat the input as already having a scheme if NSURL parses one
   * out — covers http://, https://, file://, data:, about:, etc. */
  NSURL *url = [NSURL URLWithString:raw];
  if (url == nil || [url scheme] == nil) {
    NSString *withScheme = [@"https://" stringByAppendingString:raw];
    [_addressField setStringValue:withScheme];
    url = [NSURL URLWithString:withScheme];
  }
  if (url == nil) {
    [_statusField setStringValue:[NSString stringWithFormat:@"Bad URL: %@", raw]];
    return;
  }
  [_webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)goBack:(id)sender
{
  (void)sender;
  [_webView goBack];
}

- (void)goForward:(id)sender
{
  (void)sender;
  [_webView goForward];
}

- (void)reload:(id)sender
{
  (void)sender;
  [_webView reload];
}

- (void)stopLoading:(id)sender
{
  (void)sender;
  [_webView stopLoading];
}

- (void)evaluateJS:(id)sender
{
  (void)sender;
  NSString *expr = [_jsField stringValue];
  if ([expr length] == 0) {
    return;
  }
  [_webView evaluateJavaScript:expr completionHandler:^(id result, NSError *error) {
    if (error != nil) {
      [_statusField setStringValue:
          [NSString stringWithFormat:@"JS error: %@", [error localizedDescription]]];
      return;
    }
    NSString *desc;
    if (result == nil) {
      desc = @"(undefined)";
    } else {
      desc = [NSString stringWithFormat:@"%@", result];
    }
    [_statusField setStringValue:[NSString stringWithFormat:@"JS => %@", desc]];
  }];
}


/* -------------------------------------------- WKNavigationDelegate */

- (void)webView:(WKWebView *)webView
    didStartProvisionalNavigation:(WKNavigation *)navigation
{
  (void)webView; (void)navigation;
  [_statusField setStringValue:@"Loading…"];
}

- (void)webView:(WKWebView *)webView
    didCommitNavigation:(WKNavigation *)navigation
{
  (void)webView; (void)navigation;
  NSURL *u = [webView URL];
  if (u != nil) {
    [_addressField setStringValue:[u absoluteString]];
  }
}

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation
{
  (void)navigation;
  [_statusField setStringValue:
      [NSString stringWithFormat:@"Loaded: %@",
                                 [webView title] ?: [[webView URL] absoluteString]]];
  [_progress setDoubleValue:1.0];
  if (_testMode) {
    fprintf(stderr, "WKDEMO_LOADED: %s\n",
            [[[webView URL] absoluteString] UTF8String] ?: "");
    fflush(stderr);
  }
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error
{
  (void)webView; (void)navigation;
  [_statusField setStringValue:
      [NSString stringWithFormat:@"Failed: %@", [error localizedDescription]]];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error
{
  [self webView:webView didFailNavigation:navigation withError:error];
}


/* ----------------------------------- WKScriptMessageHandler */

- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message
{
  (void)ucc;
  [_statusField setStringValue:
      [NSString stringWithFormat:@"Bridge[%@] => %@",
                                 [message name], [message body]]];
}


/* KVO-based progress tracking */

- (void)windowDidLoad
{
  [_webView addObserver:self
              forKeyPath:@"estimatedProgress"
                 options:NSKeyValueObservingOptionNew
                 context:NULL];
  [_webView addObserver:self
              forKeyPath:@"title"
                 options:NSKeyValueObservingOptionNew
                 context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
  (void)object; (void)context;
  if ([keyPath isEqualToString:@"estimatedProgress"]) {
    [_progress setDoubleValue:[_webView estimatedProgress]];
  } else if ([keyPath isEqualToString:@"title"]) {
    NSString *t = [_webView title];
    if ([t length] > 0) {
      [[self window] setTitle:[NSString stringWithFormat:@"%@ — GNUstep WebKit Demo", t]];
    }
  }
}

@end
