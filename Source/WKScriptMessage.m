/* WKScriptMessage.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKScriptMessage.h>
#import <WebKit/WKWebView.h>
#import "GSWebKitInternal.h"

@implementation WKScriptMessage
{
  id _body;
  NSString *_name;
  WKWebView *_webView;       /* weak */
  WKFrameInfo *_frameInfo;
  WKContentWorld *_world;
}

@synthesize body = _body;
@synthesize name = _name;
@synthesize webView = _webView;
@synthesize frameInfo = _frameInfo;
@synthesize world = _world;

- (instancetype)_initWithName:(NSString *)name
                          body:(id)body
                       webView:(WKWebView *)webView
                     frameInfo:(WKFrameInfo *)frame
                         world:(WKContentWorld *)world
{
  self = [super init];
  if (self != nil) {
    _name      = [name copy];
    _body      = [body copy];
    _webView   = webView;
    _frameInfo = [frame retain];
    _world     = [world retain];
  }
  return self;
}

- (void)dealloc
{
  [_name release];
  [_body release];
  [_frameInfo release];
  [_world release];
  [super dealloc];
}

@end
