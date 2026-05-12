/* WKBackForwardListItem.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKBackForwardListItem.h>
#import "GSWebKitInternal.h"

@implementation WKBackForwardListItem
{
  NSURL *_URL;
  NSURL *_initialURL;
  NSString *_title;
}

@synthesize URL = _URL;
@synthesize initialURL = _initialURL;
@synthesize title = _title;

- (instancetype)_initWithURL:(NSURL *)url
                  initialURL:(NSURL *)initialURL
                       title:(NSString *)title
{
  self = [super init];
  if (self != nil) {
    _URL = [url copy];
    _initialURL = [initialURL copy];
    _title = [title copy];
  }
  return self;
}

- (void)dealloc
{
  [_URL release];
  [_initialURL release];
  [_title release];
  [super dealloc];
}

@end
