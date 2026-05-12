/* WKSecurityOrigin.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKSecurityOrigin.h>
#import "GSWebKitInternal.h"

@implementation WKSecurityOrigin
{
  NSString *_protocol;
  NSString *_host;
  NSInteger _port;
}

@synthesize protocol = _protocol;
@synthesize host = _host;
@synthesize port = _port;

- (instancetype)_initWithProtocol:(NSString *)protocol
                              host:(NSString *)host
                              port:(NSInteger)port
{
  self = [super init];
  if (self != nil) {
    _protocol = [protocol copy];
    _host     = [host copy];
    _port     = port;
  }
  return self;
}

- (void)dealloc
{
  [_protocol release];
  [_host release];
  [super dealloc];
}

@end
