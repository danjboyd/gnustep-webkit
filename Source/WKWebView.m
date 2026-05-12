/* WKWebView.m
 *
 * NSView subclass that hosts a GSWebKitBackend and exposes the
 * Apple-style WKWebView API.
 *
 * Coordinate system: the view is -isFlipped, so NSView local
 * coordinates have origin at the top-left, matching the web engine's
 * own coordinate space.  This avoids per-event flipping.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKWebView.h>
#import <WebKit/WKError.h>

#import "GSWebKitBackend.h"
#import "GSWebKitInternal.h"

#include <stdint.h>
#include <stdlib.h>

/* X11 keysym values for a handful of named keys.  Copied here rather
 * than dragging in <X11/keysymdef.h> as a hard build dependency. */
#define GS_WKKEY_BackSpace 0xff08
#define GS_WKKEY_Tab       0xff09
#define GS_WKKEY_Return    0xff0d
#define GS_WKKEY_Escape    0xff1b
#define GS_WKKEY_Left      0xff51
#define GS_WKKEY_Up        0xff52
#define GS_WKKEY_Right     0xff53
#define GS_WKKEY_Down      0xff54
#define GS_WKKEY_PageUp    0xff55
#define GS_WKKEY_PageDown  0xff56
#define GS_WKKEY_Home      0xff50
#define GS_WKKEY_End       0xff57
#define GS_WKKEY_Delete    0xffff

/* WPE modifier bits we want to convey. */
#define GS_WK_MOD_CTRL  (1u << 0)
#define GS_WK_MOD_SHIFT (1u << 1)
#define GS_WK_MOD_ALT   (1u << 2)
#define GS_WK_MOD_META  (1u << 3)


@interface WKWebView () <GSWebKitBackendHost>
@end


@implementation WKWebView
{
  WKWebViewConfiguration   *_configuration;
  GSWebKitBackend          *_backend;
  WKBackForwardList        *_backForwardList;

  /* Delegates: weak, per Apple convention. */
  id <WKNavigationDelegate> _navigationDelegate;
  id <WKUIDelegate>         _UIDelegate;

  /* Mirrored state (so KVO-style getters are cheap). */
  NSURL    *_currentURL;
  NSString *_currentTitle;
  double    _estimatedProgress;
  BOOL      _isLoading;
  NSString *_customUserAgent;
  BOOL      _allowsBackForwardNavigationGestures;

  /* In-flight navigation token; returned from load... and threaded
   * through delegate callbacks. */
  WKNavigation *_currentNavigation;
  uint64_t      _navigationCounter;
}

@synthesize configuration         = _configuration;
@synthesize navigationDelegate    = _navigationDelegate;
@synthesize UIDelegate            = _UIDelegate;
@synthesize backForwardList       = _backForwardList;
@synthesize URL                   = _currentURL;
@synthesize title                 = _currentTitle;
@synthesize estimatedProgress     = _estimatedProgress;
@synthesize loading               = _isLoading;
@synthesize customUserAgent       = _customUserAgent;
@synthesize allowsBackForwardNavigationGestures = _allowsBackForwardNavigationGestures;


/* -------------------------------------------------------------- Init */

- (instancetype)initWithFrame:(NSRect)frame
                configuration:(WKWebViewConfiguration *)configuration
{
  self = [super initWithFrame:frame];
  if (self == nil) {
    return nil;
  }
  if (configuration != nil) {
    _configuration = [configuration copy];
  } else {
    _configuration = [[WKWebViewConfiguration alloc] init];
  }

  _backForwardList = [[WKBackForwardList alloc] init];

  _backend = [[GSWebKitBackend backendWithConfiguration:_configuration] retain];
  if (_backend == nil) {
    NSLog(@"WKWebView: no web engine backend available");
    [self release];
    return nil;
  }
  [_backend setHost:self];
  [_backend setSize:frame.size scale:1.0];

  [self _wireScriptMessageHandlersFromController:[_configuration userContentController]];

  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  return [self initWithFrame:frame
              configuration:[[[WKWebViewConfiguration alloc] init] autorelease]];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  /* No nib serialisation support in v1; behave as default. */
  return [self initWithFrame:NSMakeRect(0, 0, 800, 600)];
}

- (void)dealloc
{
  if (_backend != nil) {
    [_backend setHost:nil];
    [_backend shutdown];
  }
  [_backend release];
  [_configuration release];
  [_backForwardList release];
  [_currentURL release];
  [_currentTitle release];
  [_customUserAgent release];
  [_currentNavigation release];
  [super dealloc];
}


- (void)_wireScriptMessageHandlersFromController:(WKUserContentController *)ucc
{
  if (ucc == nil) return;
  NSEnumerator *e = [[ucc _handlers] objectEnumerator];
  _GSWKScriptHandlerRegistration *reg;
  while ((reg = [e nextObject]) != nil) {
    if ([reg->_name length] > 0) {
      [_backend registerScriptMessageHandlerName:reg->_name];
    }
  }

  NSEnumerator *se = [[ucc userScripts] objectEnumerator];
  WKUserScript *s;
  while ((s = [se nextObject]) != nil) {
    [_backend addUserScript:[s source]
              injectionTime:(NSInteger)[s injectionTime]
           forMainFrameOnly:[s isForMainFrameOnly]];
  }
}


/* ----------------------------------------------------------- NSView */

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)isOpaque
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (BOOL)becomeFirstResponder
{
  return YES;
}

- (void)setFrameSize:(NSSize)newSize
{
  [super setFrameSize:newSize];
  [_backend setSize:newSize scale:1.0];
}

- (void)drawRect:(NSRect)dirtyRect
{
  NSBitmapImageRep *rep = [_backend takeCurrentFrame];
  NSRect bounds = [self bounds];

  if (rep == nil) {
    [[NSColor whiteColor] set];
    NSRectFill(bounds);
    return;
  }

  /* Engine renders at the view's pixel size, but if the view has been
   * resized since the last frame the rep dimensions may briefly differ.
   * drawInRect: scales for us. */
  [rep drawInRect:bounds
         fromRect:NSZeroRect
        operation:NSCompositeCopy
         fraction:1.0
   respectFlipped:YES
            hints:nil];
}


/* ------------------------------------------------- Event translation */

static uint32_t GSWK_ModsFromEvent(NSEvent *event)
{
  NSEventModifierFlags m = [event modifierFlags];
  uint32_t out = 0;
  if (m & NSEventModifierFlagControl)  out |= GS_WK_MOD_CTRL;
  if (m & NSEventModifierFlagShift)    out |= GS_WK_MOD_SHIFT;
  if (m & NSEventModifierFlagOption)   out |= GS_WK_MOD_ALT;
  if (m & NSEventModifierFlagCommand)  out |= GS_WK_MOD_META;
  return out;
}

static uint32_t GSWK_TimestampFromEvent(NSEvent *event)
{
  /* NSEvent timestamp is seconds since boot.  WPE wants milliseconds. */
  return (uint32_t)([event timestamp] * 1000.0);
}

- (NSPoint)_pointFromEvent:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  return p;
}

- (void)mouseMoved:(NSEvent *)event
{
  [_backend dispatchPointerMoveAt:[self _pointFromEvent:event]
                        modifiers:GSWK_ModsFromEvent(event)
                        timestamp:GSWK_TimestampFromEvent(event)];
}

- (void)mouseDragged:(NSEvent *)event
{
  [self mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
  [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
  [self mouseMoved:event];
}

- (void)_dispatchButton:(int)button pressed:(BOOL)pressed event:(NSEvent *)event
{
  [_backend dispatchPointerButton:button
                          pressed:pressed
                               at:[self _pointFromEvent:event]
                        modifiers:GSWK_ModsFromEvent(event)
                        timestamp:GSWK_TimestampFromEvent(event)];
}

- (void)mouseDown:(NSEvent *)event
{
  [[self window] makeFirstResponder:self];
  [self _dispatchButton:1 pressed:YES event:event];
}

- (void)mouseUp:(NSEvent *)event
{
  [self _dispatchButton:1 pressed:NO event:event];
}

- (void)rightMouseDown:(NSEvent *)event
{
  [self _dispatchButton:3 pressed:YES event:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
  [self _dispatchButton:3 pressed:NO event:event];
}

- (void)otherMouseDown:(NSEvent *)event
{
  [self _dispatchButton:2 pressed:YES event:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
  [self _dispatchButton:2 pressed:NO event:event];
}

- (void)scrollWheel:(NSEvent *)event
{
  /* AppKit deltas are in lines/points with arbitrary scaling.  We feed
   * them through roughly 1:1 — refine if needed. */
  CGFloat dx = [event deltaX];
  CGFloat dy = [event deltaY];
  [_backend dispatchScrollAt:[self _pointFromEvent:event]
                      deltaX:(double)(dx * 20.0)
                      deltaY:(double)(dy * 20.0)
                   modifiers:GSWK_ModsFromEvent(event)
                   timestamp:GSWK_TimestampFromEvent(event)];
}

static uint32_t GSWK_KeysymFromEvent(NSEvent *event)
{
  NSString *chars = [event charactersIgnoringModifiers];
  if ([chars length] == 0) {
    return 0;
  }
  unichar c = [chars characterAtIndex:0];
  switch (c) {
    case NSUpArrowFunctionKey:    return GS_WKKEY_Up;
    case NSDownArrowFunctionKey:  return GS_WKKEY_Down;
    case NSLeftArrowFunctionKey:  return GS_WKKEY_Left;
    case NSRightArrowFunctionKey: return GS_WKKEY_Right;
    case NSPageUpFunctionKey:     return GS_WKKEY_PageUp;
    case NSPageDownFunctionKey:   return GS_WKKEY_PageDown;
    case NSHomeFunctionKey:       return GS_WKKEY_Home;
    case NSEndFunctionKey:        return GS_WKKEY_End;
    case NSDeleteCharacter:       /* 0x7f, Apple's "delete" key */
    case 0x08:                    return GS_WKKEY_BackSpace;
    case 0x09:                    return GS_WKKEY_Tab;
    case 0x0d:
    case 0x03:                    return GS_WKKEY_Return;
    case 0x1b:                    return GS_WKKEY_Escape;
    case NSDeleteFunctionKey:     return GS_WKKEY_Delete;
    default:
      /* Printable ASCII: keysym == ASCII. */
      if (c >= 0x20 && c < 0x7f) {
        return (uint32_t)c;
      }
      return 0;
  }
}

- (void)keyDown:(NSEvent *)event
{
  uint32_t keysym = GSWK_KeysymFromEvent(event);
  if (keysym != 0) {
    [_backend dispatchKeyCode:keysym
                       pressed:YES
                     modifiers:GSWK_ModsFromEvent(event)
                     timestamp:GSWK_TimestampFromEvent(event)];
  }
}

- (void)keyUp:(NSEvent *)event
{
  uint32_t keysym = GSWK_KeysymFromEvent(event);
  if (keysym != 0) {
    [_backend dispatchKeyCode:keysym
                       pressed:NO
                     modifiers:GSWK_ModsFromEvent(event)
                     timestamp:GSWK_TimestampFromEvent(event)];
  }
}


/* ----------------------------------------------------------- Loading */

- (WKNavigation *)_makeNavigationForRequest:(NSURLRequest *)request
{
  uint64_t ident = ++_navigationCounter;
  [_currentNavigation release];
  _currentNavigation = [[WKNavigation alloc] _initWithRequest:request
                                                    identifier:ident];
  return _currentNavigation;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request
{
  if (request == nil) return nil;
  WKNavigation *nav = [self _makeNavigationForRequest:request];
  [_backend loadURL:[request URL]];
  return nav;
}

- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
  if (string == nil) return nil;
  NSURLRequest *fakeReq = (baseURL != nil)
      ? [NSURLRequest requestWithURL:baseURL]
      : nil;
  WKNavigation *nav = [self _makeNavigationForRequest:fakeReq];
  [_backend loadHTMLString:string baseURL:baseURL];
  return nav;
}

- (WKNavigation *)loadData:(NSData *)data
                  MIMEType:(NSString *)MIMEType
     characterEncodingName:(NSString *)characterEncodingName
                   baseURL:(NSURL *)baseURL
{
  /* Falls back to load-html if MIME type is HTML-ish; otherwise data:
   * URL.  Good enough for v1. */
  if ([MIMEType hasPrefix:@"text/html"] || [MIMEType hasPrefix:@"application/xhtml"]) {
    NSStringEncoding enc = NSUTF8StringEncoding;
    if ([characterEncodingName length] > 0) {
      NSString *lc = [characterEncodingName lowercaseString];
      if ([lc isEqualToString:@"utf-8"] || [lc isEqualToString:@"utf8"]) {
        enc = NSUTF8StringEncoding;
      } else if ([lc isEqualToString:@"utf-16"] || [lc isEqualToString:@"utf16"]) {
        enc = NSUTF16StringEncoding;
      } else if ([lc isEqualToString:@"iso-8859-1"]
                 || [lc isEqualToString:@"latin1"]) {
        enc = NSISOLatin1StringEncoding;
      } else if ([lc isEqualToString:@"us-ascii"] || [lc isEqualToString:@"ascii"]) {
        enc = NSASCIIStringEncoding;
      }
      /* Unrecognised encoding names fall through to UTF-8 which is the
       * web's overwhelmingly dominant case. */
    }
    NSString *html = [[[NSString alloc] initWithData:data encoding:enc] autorelease];
    return [self loadHTMLString:html baseURL:baseURL];
  }
  NSString *b64 = [data base64EncodedStringWithOptions:0];
  NSString *uri = [NSString stringWithFormat:@"data:%@;base64,%@", MIMEType, b64];
  NSURL    *url = [NSURL URLWithString:uri];
  return [self loadRequest:[NSURLRequest requestWithURL:url]];
}

- (WKNavigation *)loadFileURL:(NSURL *)URL
        allowingReadAccessToURL:(NSURL *)readAccessURL
{
  (void)readAccessURL;
  return [self loadRequest:[NSURLRequest requestWithURL:URL]];
}

- (WKNavigation *)reload
{
  [_backend reload];
  return [self _makeNavigationForRequest:nil];
}

- (WKNavigation *)reloadFromOrigin
{
  [_backend reloadFromOrigin];
  return [self _makeNavigationForRequest:nil];
}

- (void)stopLoading
{
  [_backend stopLoading];
}

- (BOOL)canGoBack
{
  return [_backend canGoBack];
}

- (BOOL)canGoForward
{
  return [_backend canGoForward];
}

- (WKNavigation *)goBack
{
  if (![self canGoBack]) return nil;
  [_backend goBack];
  return [self _makeNavigationForRequest:nil];
}

- (WKNavigation *)goForward
{
  if (![self canGoForward]) return nil;
  [_backend goForward];
  return [self _makeNavigationForRequest:nil];
}

- (WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item
{
  /* v1 does not support arbitrary list-item navigation through the
   * WPE bridge; honour the call by treating it as no-op. */
  (void)item;
  return nil;
}


/* ----------------------------------------------------------- Eval JS */

- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^)(id, NSError *))completionHandler
{
  [_backend evaluateJavaScript:javaScriptString completion:completionHandler];
}

- (void)evaluateJavaScript:(NSString *)javaScriptString
                   inFrame:(WKFrameInfo *)frame
            inContentWorld:(WKContentWorld *)contentWorld
         completionHandler:(void (^)(id, NSError *))completionHandler
{
  /* Frame/world targeting is not yet propagated to the WPE backend; we
   * always evaluate in the page world's main frame. */
  (void)frame; (void)contentWorld;
  [_backend evaluateJavaScript:javaScriptString completion:completionHandler];
}


/* ----------------------------------------------------------- UA */

- (void)setCustomUserAgent:(NSString *)ua
{
  if (ua == _customUserAgent) return;
  [_customUserAgent release];
  _customUserAgent = [ua copy];
  [_backend setCustomUserAgent:ua];
}


/* ----------------------------------------- Backend host callbacks */

- (void)backendFrameDidChange:(GSWebKitBackend *)backend
{
  (void)backend;
  [self setNeedsDisplay:YES];
}

- (void)backendDidStartProvisionalNavigation:(GSWebKitBackend *)backend
{
  (void)backend;
  if ([_navigationDelegate respondsToSelector:
          @selector(webView:didStartProvisionalNavigation:)]) {
    [_navigationDelegate webView:self
        didStartProvisionalNavigation:_currentNavigation];
  }
}

- (void)backendDidCommitNavigation:(GSWebKitBackend *)backend
{
  (void)backend;
  /* Append committed URL to back-forward list. */
  NSURL *url = [_backend currentURL];
  if (url != nil) {
    WKBackForwardListItem *item =
        [[[WKBackForwardListItem alloc] _initWithURL:url
                                          initialURL:url
                                               title:_currentTitle] autorelease];
    [_backForwardList _appendItem:item];
  }
  if ([_navigationDelegate respondsToSelector:
          @selector(webView:didCommitNavigation:)]) {
    [_navigationDelegate webView:self didCommitNavigation:_currentNavigation];
  }
}

- (void)backendDidFinishNavigation:(GSWebKitBackend *)backend
{
  (void)backend;
  if ([_navigationDelegate respondsToSelector:
          @selector(webView:didFinishNavigation:)]) {
    [_navigationDelegate webView:self didFinishNavigation:_currentNavigation];
  }
}

- (void)backend:(GSWebKitBackend *)backend
    didFailNavigationWithError:(NSError *)error
                   provisional:(BOOL)provisional
{
  (void)backend;
  if (provisional) {
    if ([_navigationDelegate respondsToSelector:
            @selector(webView:didFailProvisionalNavigation:withError:)]) {
      [_navigationDelegate webView:self
            didFailProvisionalNavigation:_currentNavigation
                                withError:error];
    }
  } else {
    if ([_navigationDelegate respondsToSelector:
            @selector(webView:didFailNavigation:withError:)]) {
      [_navigationDelegate webView:self
                  didFailNavigation:_currentNavigation
                          withError:error];
    }
  }
}

- (void)backend:(GSWebKitBackend *)backend didChangeTitle:(NSString *)title
{
  (void)backend;
  if (title == _currentTitle) return;
  [self willChangeValueForKey:@"title"];
  [_currentTitle release];
  _currentTitle = [title copy];
  [self didChangeValueForKey:@"title"];
}

- (void)backend:(GSWebKitBackend *)backend didChangeURL:(NSURL *)url
{
  (void)backend;
  if ([url isEqual:_currentURL]) return;
  [self willChangeValueForKey:@"URL"];
  [_currentURL release];
  _currentURL = [url copy];
  [self didChangeValueForKey:@"URL"];
}

- (void)backend:(GSWebKitBackend *)backend
    didChangeEstimatedProgress:(double)progress
{
  (void)backend;
  if (progress == _estimatedProgress) return;
  [self willChangeValueForKey:@"estimatedProgress"];
  _estimatedProgress = progress;
  [self didChangeValueForKey:@"estimatedProgress"];
}

- (void)backend:(GSWebKitBackend *)backend didChangeIsLoading:(BOOL)isLoading
{
  (void)backend;
  if (isLoading == _isLoading) return;
  [self willChangeValueForKey:@"loading"];
  _isLoading = isLoading;
  [self didChangeValueForKey:@"loading"];
}

- (void)backendDidChangeBackForwardList:(GSWebKitBackend *)backend
{
  (void)backend;
}

- (void)backend:(GSWebKitBackend *)backend
        didReceiveScriptMessageWithName:(NSString *)name
                                   body:(id)body
{
  (void)backend;
  WKUserContentController *ucc = [_configuration userContentController];
  if (ucc == nil) return;
  NSEnumerator *e = [[ucc _handlers] objectEnumerator];
  _GSWKScriptHandlerRegistration *reg;
  while ((reg = [e nextObject]) != nil) {
    if (![reg->_name isEqualToString:name]) {
      continue;
    }
    id <WKScriptMessageHandler> handler = reg->_handler;
    if (![handler respondsToSelector:
            @selector(userContentController:didReceiveScriptMessage:)]) {
      break;
    }
    WKContentWorld *world = reg->_world ?: [WKContentWorld pageWorld];
    NSString *scheme = [_currentURL scheme] ?: @"";
    NSString *host   = [_currentURL host]   ?: @"";
    WKSecurityOrigin *origin =
        [[[WKSecurityOrigin alloc] _initWithProtocol:scheme
                                                host:host
                                                port:0] autorelease];
    WKFrameInfo *frame =
        [[[WKFrameInfo alloc] _initWithMainFrame:YES
                                           request:nil
                                    securityOrigin:origin
                                           webView:self] autorelease];
    WKScriptMessage *msg =
        [[[WKScriptMessage alloc] _initWithName:name
                                            body:body
                                         webView:self
                                       frameInfo:frame
                                           world:world] autorelease];
    [handler userContentController:ucc didReceiveScriptMessage:msg];
    break;
  }
}


/* UI delegate alert/confirm/prompt fallback windows.  If the embedder
 * provides a UIDelegate that implements the runJavaScript* methods we
 * forward to it; otherwise we drive synchronous NSAlert/NSAlert prompt
 * panels. */

- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptAlertWithMessage:(NSString *)message
                       completion:(void (^)(void))completion
{
  (void)backend;
  if ([_UIDelegate respondsToSelector:
          @selector(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)]) {
    [_UIDelegate webView:self
        runJavaScriptAlertPanelWithMessage:message
                          initiatedByFrame:[self _mainFrameInfo]
                         completionHandler:completion];
    return;
  }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"JavaScript"];
  [alert setInformativeText:message ?: @""];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  if (completion) completion();
}

- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptConfirmWithMessage:(NSString *)message
                         completion:(void (^)(BOOL))completion
{
  (void)backend;
  if ([_UIDelegate respondsToSelector:
          @selector(webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:)]) {
    [_UIDelegate webView:self
        runJavaScriptConfirmPanelWithMessage:message
                            initiatedByFrame:[self _mainFrameInfo]
                           completionHandler:completion];
    return;
  }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"JavaScript"];
  [alert setInformativeText:message ?: @""];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  NSModalResponse r = [alert runModal];
  if (completion) completion(r == NSAlertFirstButtonReturn);
}

- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptPromptWithMessage:(NSString *)message
                        defaultText:(NSString *)defaultText
                         completion:(void (^)(NSString *))completion
{
  (void)backend;
  if ([_UIDelegate respondsToSelector:
          @selector(webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:)]) {
    [_UIDelegate webView:self
        runJavaScriptTextInputPanelWithPrompt:message
                                  defaultText:defaultText
                             initiatedByFrame:[self _mainFrameInfo]
                            completionHandler:completion];
    return;
  }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"JavaScript"];
  [alert setInformativeText:message ?: @""];
  NSTextField *field = [[[NSTextField alloc]
      initWithFrame:NSMakeRect(0, 0, 280, 24)] autorelease];
  [field setStringValue:defaultText ?: @""];
  [alert setAccessoryView:field];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  NSModalResponse r = [alert runModal];
  if (completion) {
    completion((r == NSAlertFirstButtonReturn) ? [field stringValue] : nil);
  }
}

- (WKFrameInfo *)_mainFrameInfo
{
  NSString *scheme = [_currentURL scheme] ?: @"";
  NSString *host   = [_currentURL host]   ?: @"";
  WKSecurityOrigin *origin =
      [[[WKSecurityOrigin alloc] _initWithProtocol:scheme
                                              host:host
                                              port:0] autorelease];
  return [[[WKFrameInfo alloc] _initWithMainFrame:YES
                                           request:nil
                                    securityOrigin:origin
                                           webView:self] autorelease];
}

@end
