/* WKUserScript.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKUserScript.h>

@implementation WKUserScript
{
  NSString *_source;
  WKUserScriptInjectionTime _injectionTime;
  BOOL _forMainFrameOnly;
  WKContentWorld *_contentWorld;
}

@synthesize source = _source;
@synthesize injectionTime = _injectionTime;
@synthesize forMainFrameOnly = _forMainFrameOnly;
@synthesize contentWorld = _contentWorld;

- (instancetype)initWithSource:(NSString *)source
                 injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly
{
  return [self initWithSource:source
                injectionTime:injectionTime
             forMainFrameOnly:forMainFrameOnly
                 contentWorld:[WKContentWorld pageWorld]];
}

- (instancetype)initWithSource:(NSString *)source
                 injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly
                  contentWorld:(WKContentWorld *)contentWorld
{
  self = [super init];
  if (self != nil) {
    _source           = [source copy];
    _injectionTime    = injectionTime;
    _forMainFrameOnly = forMainFrameOnly;
    _contentWorld     = [contentWorld retain];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  return [[[self class] allocWithZone:zone] initWithSource:_source
                                             injectionTime:_injectionTime
                                          forMainFrameOnly:_forMainFrameOnly
                                              contentWorld:_contentWorld];
}

- (void)dealloc
{
  [_source release];
  [_contentWorld release];
  [super dealloc];
}

@end
