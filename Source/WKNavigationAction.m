/* WKNavigationAction.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKNavigationAction.h>
#import "GSWebKitInternal.h"

@implementation WKNavigationAction
{
  WKFrameInfo *_sourceFrame;
  WKFrameInfo *_targetFrame;
  WKNavigationType _navigationType;
  NSURLRequest *_request;
  BOOL _shouldPerformDownload;
}

@synthesize sourceFrame = _sourceFrame;
@synthesize targetFrame = _targetFrame;
@synthesize navigationType = _navigationType;
@synthesize request = _request;
@synthesize shouldPerformDownload = _shouldPerformDownload;

- (instancetype)_initWithRequest:(NSURLRequest *)request
                  navigationType:(WKNavigationType)navigationType
                     sourceFrame:(WKFrameInfo *)source
                     targetFrame:(WKFrameInfo *)target
{
  self = [super init];
  if (self != nil) {
    _request        = [request copy];
    _navigationType = navigationType;
    _sourceFrame    = [source copy];
    _targetFrame    = [target copy];
    _shouldPerformDownload = NO;
  }
  return self;
}

- (void)dealloc
{
  [_request release];
  [_sourceFrame release];
  [_targetFrame release];
  [super dealloc];
}

@end
