/* GSWebKitBackend.m
 *
 * Factory and default no-op implementations for the engine
 * abstraction.  Concrete engines override the interesting methods.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import "GSWebKitBackend.h"
#import "GSWebKitWPE.h"

@implementation GSWebKitBackend

@synthesize host = _host;

+ (GSWebKitBackend *)backendWithConfiguration:(WKWebViewConfiguration *)config
{
  return [[[GSWebKitWPE alloc] initWithConfiguration:config] autorelease];
}

/* Default no-ops; overridden by concrete engine class. */
- (void)setSize:(NSSize)size scale:(CGFloat)scale { (void)size; (void)scale; }
- (void)shutdown                                   {}
- (void)loadURL:(NSURL *)url                       { (void)url; }
- (void)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL
                                                   { (void)html; (void)baseURL; }
- (void)reload                                     {}
- (void)reloadFromOrigin                           {}
- (void)stopLoading                                {}
- (BOOL)canGoBack                                  { return NO; }
- (BOOL)canGoForward                               { return NO; }
- (void)goBack                                     {}
- (void)goForward                                  {}

- (void)evaluateJavaScript:(NSString *)js
                completion:(void (^)(id, NSError *))completion
{
  (void)js;
  if (completion != NULL) {
    completion(nil, nil);
  }
}

- (void)addUserScript:(NSString *)src injectionTime:(NSInteger)t forMainFrameOnly:(BOOL)b
                                                   { (void)src; (void)t; (void)b; }
- (void)registerScriptMessageHandlerName:(NSString *)n { (void)n; }
- (void)unregisterScriptMessageHandlerName:(NSString *)n { (void)n; }

- (NSString *)currentTitle                         { return nil; }
- (NSURL *)currentURL                              { return nil; }
- (double)currentEstimatedProgress                 { return 0.0; }
- (BOOL)isLoading                                  { return NO; }
- (void)setCustomUserAgent:(NSString *)ua          { (void)ua; }
- (NSString *)customUserAgent                      { return nil; }

- (NSBitmapImageRep *)takeCurrentFrame             { return nil; }
- (NSSize)currentFrameSize                         { return NSZeroSize; }

- (void)dispatchPointerMoveAt:(NSPoint)p
                    modifiers:(uint32_t)m
                    timestamp:(uint32_t)t
{
  (void)p; (void)m; (void)t;
}
- (void)dispatchPointerButton:(int)b pressed:(BOOL)pr at:(NSPoint)p
                    modifiers:(uint32_t)m timestamp:(uint32_t)t
{
  (void)b; (void)pr; (void)p; (void)m; (void)t;
}
- (void)dispatchScrollAt:(NSPoint)p deltaX:(double)dx deltaY:(double)dy
                modifiers:(uint32_t)m timestamp:(uint32_t)t
{
  (void)p; (void)dx; (void)dy; (void)m; (void)t;
}
- (void)dispatchKeyCode:(uint32_t)k pressed:(BOOL)pr
                modifiers:(uint32_t)m timestamp:(uint32_t)t
{
  (void)k; (void)pr; (void)m; (void)t;
}

@end
