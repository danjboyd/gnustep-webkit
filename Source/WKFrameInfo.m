/* WKFrameInfo.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKFrameInfo.h>
#import <WebKit/WKWebView.h>
#import "GSWebKitInternal.h"

@implementation WKFrameInfo
{
  BOOL _isMainFrame;
  NSURLRequest *_request;
  WKSecurityOrigin *_securityOrigin;
  WKWebView *_webView;   /* weak */
}

@synthesize mainFrame = _isMainFrame;
@synthesize request = _request;
@synthesize securityOrigin = _securityOrigin;
@synthesize webView = _webView;

- (instancetype)_initWithMainFrame:(BOOL)mainFrame
                           request:(NSURLRequest *)request
                    securityOrigin:(WKSecurityOrigin *)origin
                           webView:(WKWebView *)webView
{
  self = [super init];
  if (self != nil) {
    _isMainFrame    = mainFrame;
    _request        = [request copy];
    _securityOrigin = [origin retain];
    _webView        = webView;  /* weak, no retain */
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  WKFrameInfo *c = [[[self class] allocWithZone:zone] _initWithMainFrame:_isMainFrame
                                                                  request:_request
                                                           securityOrigin:_securityOrigin
                                                                  webView:_webView];
  return c;
}

- (void)dealloc
{
  [_request release];
  [_securityOrigin release];
  [super dealloc];
}

@end
