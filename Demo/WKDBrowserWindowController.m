/* WKDBrowserWindowController.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import "WKDBrowserWindowController.h"

@implementation _WKDAppSchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id <WKURLSchemeTask>)task
{
  (void)webView;
  NSString *uri = [[[task request] URL] absoluteString];
  NSString *body = [NSString stringWithFormat:
      @"<!doctype html><html><body style='font-family:sans-serif'>"
      @"<h1>Custom scheme handler</h1>"
      @"<p>WebKit asked the host for this URL:</p>"
      @"<pre style='background:#eef;padding:8px'>%@</pre>"
      @"<p>The framework's <code>WKURLSchemeHandler</code> implementation "
      @"is what produced this page.</p>"
      @"</body></html>", uri];
  NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
  NSURLResponse *resp = [[[NSURLResponse alloc]
      initWithURL:[[task request] URL]
         MIMEType:@"text/html"
   expectedContentLength:(NSInteger)[data length]
   textEncodingName:@"utf-8"] autorelease];
  [task didReceiveResponse:resp];
  [task didReceiveData:data];
  [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id <WKURLSchemeTask>)task
{
  (void)webView; (void)task;
}
@end


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
  } else if ([cmd hasPrefix:@"COOKIE_SET "]) {
    /* Format: COOKIE_SET name=value;domain=host */
    NSString *body = [cmd substringFromIndex:11];
    NSArray *parts = [body componentsSeparatedByString:@";"];
    NSString *kv = [parts count] > 0 ? [parts objectAtIndex:0] : @"";
    NSString *dom = [parts count] > 1 ? [parts objectAtIndex:1] : @".test";
    NSArray *kvParts = [kv componentsSeparatedByString:@"="];
    if ([kvParts count] >= 2) {
      [self _testCookieRoundTripTo:[kvParts objectAtIndex:0]
                              value:[kvParts objectAtIndex:1]
                             domain:dom];
    }
    fprintf(stderr, "WKDEMO_ACK: COOKIE_SET\n");
    fflush(stderr);
  } else if ([cmd isEqualToString:@"COOKIE_LIST"]) {
    [self _testReadCookies:^(NSString *out) {
      fprintf(stderr, "WKDEMO_COOKIE_RESULT: %s\n", [out UTF8String]);
      fflush(stderr);
    }];
  } else if ([cmd isEqualToString:@"SNAPSHOT"]) {
    [self _testSnapshotInto:^(NSString *out) {
      fprintf(stderr, "WKDEMO_SNAPSHOT_RESULT: %s\n", [out UTF8String]);
      fflush(stderr);
    }];
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
  [_findBar release];
  [_findField release];
  [_findStatus release];
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

  /* Find bar — built but hidden by default.  Cmd/Ctrl+F shows it. */
  _findBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, cb.size.width, 32)];
  [_findBar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [_findBar setHidden:YES];
  {
    NSButton *close = [self _makeButtonAt:NSMakePoint(8, 4)
                                     width:24
                                     title:@"×"
                                    action:@selector(hideFindBar:)];
    [_findBar addSubview:close];
    _findField = [[NSTextField alloc] initWithFrame:NSMakeRect(36, 4, 400, 24)];
    [[_findField cell] setPlaceholderString:@"Find in page (Enter = next, Shift+Enter = previous, Esc = close)"];
    [_findField setTarget:self];
    [_findField setAction:@selector(findNext:)];
    [_findBar addSubview:_findField];
    NSButton *prev = [self _makeButtonAt:NSMakePoint(444, 4)
                                    width:36 title:@"◀"
                                   action:@selector(findPrevious:)];
    [_findBar addSubview:prev];
    NSButton *next = [self _makeButtonAt:NSMakePoint(484, 4)
                                    width:36 title:@"▶"
                                   action:@selector(findNext:)];
    [_findBar addSubview:next];
    _findStatus = [[NSTextField alloc] initWithFrame:NSMakeRect(528, 6, 300, 18)];
    [_findStatus setEditable:NO];
    [_findStatus setBezeled:NO];
    [_findStatus setDrawsBackground:NO];
    [_findStatus setStringValue:@""];
    [_findBar addSubview:_findStatus];
  }
  [content addSubview:_findBar];

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

  /* Register a custom myapp:// scheme handler so the Demo menu can
   * exercise the WKURLSchemeHandler / WKURLSchemeTask plumbing. */
  _WKDAppSchemeHandler *scheme = [[[_WKDAppSchemeHandler alloc] init] autorelease];
  [config setURLSchemeHandler:scheme forURLScheme:@"myapp"];

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

/* Esc in the find field (or anywhere the find bar is the first
 * responder) closes the find bar.  NSTextField forwards Esc as
 * cancelOperation: up the responder chain. */
- (void)cancelOperation:(id)sender
{
  (void)sender;
  if (_findBarVisible) {
    [self hideFindBar:nil];
  }
}

- (void)showFindBar:(id)sender
{
  (void)sender;
  if (_findBarVisible) {
    [[self window] makeFirstResponder:_findField];
    return;
  }
  _findBarVisible = YES;
  NSView *content = [[self window] contentView];
  NSRect cb = [content bounds];
  /* Place the find bar just below the JS row.  Web view shrinks. */
  CGFloat findBarY = cb.size.height - 36 - 32 - 32;
  [_findBar setFrame:NSMakeRect(0, findBarY, cb.size.width, 32)];
  [_findBar setHidden:NO];
  /* Shrink web view by 32px. */
  NSRect wf = [_webView frame];
  wf.size.height -= 32;
  [_webView setFrame:wf];
  [[self window] makeFirstResponder:_findField];
}

- (void)hideFindBar:(id)sender
{
  (void)sender;
  if (!_findBarVisible) return;
  _findBarVisible = NO;
  [_findBar setHidden:YES];
  NSRect wf = [_webView frame];
  wf.size.height += 32;
  [_webView setFrame:wf];
  [_findStatus setStringValue:@""];
}

- (void)findNext:(id)sender
{
  (void)sender;
  NSString *q = [_findField stringValue];
  if ([q length] == 0) return;
  WKFindConfiguration *cfg = [[[WKFindConfiguration alloc] init] autorelease];
  [cfg setBackwards:NO];
  [cfg setWraps:YES];
  [_webView findString:q
         configuration:cfg
     completionHandler:^(WKFindResult *r) {
    [_findStatus setStringValue:[r matchFound] ? @"Found" : @"Not found"];
  }];
}

- (void)findPrevious:(id)sender
{
  (void)sender;
  NSString *q = [_findField stringValue];
  if ([q length] == 0) return;
  WKFindConfiguration *cfg = [[[WKFindConfiguration alloc] init] autorelease];
  [cfg setBackwards:YES];
  [cfg setWraps:YES];
  [_webView findString:q
         configuration:cfg
     completionHandler:^(WKFindResult *r) {
    [_findStatus setStringValue:[r matchFound] ? @"Found" : @"Not found"];
  }];
}

- (void)zoomIn:(id)sender    { (void)sender; [_webView setPageZoom:[_webView pageZoom] * 1.1]; }
- (void)zoomOut:(id)sender   { (void)sender; [_webView setPageZoom:[_webView pageZoom] / 1.1]; }
- (void)zoomReset:(id)sender { (void)sender; [_webView setPageZoom:1.0]; }

- (void)_testCookieRoundTripTo:(NSString *)key
                          value:(NSString *)value
                         domain:(NSString *)domain
{
  WKHTTPCookieStore *cs = [[WKWebsiteDataStore defaultDataStore] httpCookieStore];
  NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:[NSDictionary
      dictionaryWithObjectsAndKeys:
        key,                 NSHTTPCookieName,
        value,               NSHTTPCookieValue,
        domain,              NSHTTPCookieDomain,
        @"/",                NSHTTPCookiePath,
        nil]];
  [cs setCookie:c completionHandler:NULL];
}

- (void)_testReadCookies:(void (^)(NSString *))block
{
  WKHTTPCookieStore *cs = [[WKWebsiteDataStore defaultDataStore] httpCookieStore];
  [cs getAllCookies:^(NSArray *cookies) {
    NSMutableArray *bits = [NSMutableArray array];
    NSEnumerator *e = [cookies objectEnumerator];
    NSHTTPCookie *c;
    while ((c = [e nextObject]) != nil) {
      [bits addObject:[NSString stringWithFormat:@"%@@%@=%@",
                                                  [c name], [c domain], [c value]]];
    }
    block([bits componentsJoinedByString:@","]);
  }];
}

- (void)_testSnapshotInto:(void (^)(NSString *))block
{
  [_webView takeSnapshotWithConfiguration:nil
                         completionHandler:^(NSImage *img, NSError *err) {
    if (err != nil) {
      block([NSString stringWithFormat:@"error:%@", [err localizedDescription]]);
      return;
    }
    if (img == nil) {
      block(@"nil");
      return;
    }
    NSSize sz = [img size];
    block([NSString stringWithFormat:@"image:%.0fx%.0f", sz.width, sz.height]);
  }];
}

- (void)demoFileChooser:(id)sender
{
  (void)sender;
  NSString *html = @"<!doctype html><html><body style='font-family:sans-serif'>"
                   @"<h1>File chooser demo</h1>"
                   @"<p>Clicking the button below pops up <code>NSOpenPanel</code> "
                   @"via the framework's <code>run-file-chooser</code> bridge.</p>"
                   @"<input id=f type=file multiple>"
                   @"<pre id=out style='background:#eef;padding:8px'></pre>"
                   @"<script>"
                   @"document.getElementById('f').addEventListener('change',function(e){"
                   @"  var names=[]; for(var i=0;i<this.files.length;i++)names.push(this.files[i].name);"
                   @"  document.getElementById('out').textContent='Selected: '+names.join(', ');"
                   @"});"
                   @"</script></body></html>";
  [_webView loadHTMLString:html baseURL:nil];
}

- (void)demoCustomScheme:(id)sender
{
  (void)sender;
  [_webView loadRequest:[NSURLRequest requestWithURL:
      [NSURL URLWithString:@"myapp://hello/world?from=demo"]]];
}

- (void)demoHistory:(id)sender
{
  (void)sender;
  WKBackForwardList *list = [_webView backForwardList];
  NSMutableString *html = [NSMutableString stringWithString:
      @"<!doctype html><html><body style='font-family:sans-serif'>"
      @"<h1>Back-Forward History</h1>"];
  WKBackForwardListItem *cur = [list currentItem];
  [html appendString:@"<h2>Back</h2><ol reversed>"];
  NSArray *back = [list backList];
  for (WKBackForwardListItem *it in back) {
    [html appendFormat:@"<li><a href='%@'>%@</a></li>",
                        [[it URL] absoluteString],
                        [it title] ?: [[it URL] absoluteString]];
  }
  [html appendString:@"</ol>"];
  if (cur != nil) {
    [html appendFormat:@"<h2>Current</h2><p><a href='%@'>%@</a></p>",
                        [[cur URL] absoluteString],
                        [cur title] ?: [[cur URL] absoluteString]];
  }
  [html appendString:@"<h2>Forward</h2><ol>"];
  for (WKBackForwardListItem *it in [list forwardList]) {
    [html appendFormat:@"<li><a href='%@'>%@</a></li>",
                        [[it URL] absoluteString],
                        [it title] ?: [[it URL] absoluteString]];
  }
  [html appendString:@"</ol></body></html>"];
  [_webView loadHTMLString:html baseURL:nil];
}

- (void)demoCookieInspector:(id)sender
{
  (void)sender;
  WKHTTPCookieStore *cs = [[WKWebsiteDataStore defaultDataStore] httpCookieStore];
  [cs getAllCookies:^(NSArray *cookies) {
    NSMutableString *html = [NSMutableString stringWithString:
        @"<!doctype html><html><body style='font-family:sans-serif'>"
        @"<h1>Cookie inspector</h1>"];
    [html appendFormat:@"<p>%lu cookies via WKHTTPCookieStore:</p>",
                       (unsigned long)[cookies count]];
    [html appendString:@"<table border=1 cellpadding=4 style='border-collapse:collapse'>"
                       @"<tr><th>Domain</th><th>Name</th><th>Path</th><th>Secure</th></tr>"];
    NSEnumerator *e = [cookies objectEnumerator];
    NSHTTPCookie *c;
    while ((c = [e nextObject]) != nil) {
      [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>%@</td><td>%@</td></tr>",
                          [c domain], [c name], [c path],
                          [c isSecure] ? @"yes" : @"no"];
    }
    [html appendString:@"</table></body></html>"];
    [_webView loadHTMLString:html baseURL:nil];
  }];
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
