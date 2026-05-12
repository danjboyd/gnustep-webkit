/* WKNavigation.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKNavigation.h>
#import "GSWebKitInternal.h"

@implementation WKNavigation
{
  NSURLRequest *_request;
  uint64_t      _identifier;   /* internal correlation key with WPE */
}

@synthesize request = _request;

- (instancetype)_initWithRequest:(NSURLRequest *)request
                       identifier:(uint64_t)identifier
{
  self = [super init];
  if (self != nil) {
    _request    = [request copy];
    _identifier = identifier;
  }
  return self;
}

- (uint64_t)_identifier
{
  return _identifier;
}

- (void)_setRequest:(NSURLRequest *)request
{
  if (request == _request) {
    return;
  }
  [_request release];
  _request = [request copy];
}

- (void)dealloc
{
  [_request release];
  [super dealloc];
}

@end
