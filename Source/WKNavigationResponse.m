/* WKNavigationResponse.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKNavigationResponse.h>
#import "GSWebKitInternal.h"

@implementation WKNavigationResponse
{
  BOOL _forMainFrame;
  NSURLResponse *_response;
  BOOL _canShowMIMEType;
}

@synthesize forMainFrame = _forMainFrame;
@synthesize response = _response;
@synthesize canShowMIMEType = _canShowMIMEType;

- (instancetype)_initWithResponse:(NSURLResponse *)response
                     forMainFrame:(BOOL)forMainFrame
                  canShowMIMEType:(BOOL)canShow
{
  self = [super init];
  if (self != nil) {
    _response        = [response copy];
    _forMainFrame    = forMainFrame;
    _canShowMIMEType = canShow;
  }
  return self;
}

- (void)dealloc
{
  [_response release];
  [super dealloc];
}

@end
