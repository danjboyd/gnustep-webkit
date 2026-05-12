/* WKContentWorld.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 *
 * v1 note: WKContentWorld is exposed for API parity with Apple's
 * WebKit, but the WPE engine surface used by the backend does not
 * presently distinguish isolated worlds.  Named worlds are tracked
 * but JavaScript evaluation runs in the page world either way.
 */

#import <WebKit/WKContentWorld.h>
#import "GSWebKitInternal.h"

static WKContentWorld *gPageWorld;
static WKContentWorld *gDefaultClientWorld;
static NSMutableDictionary *gNamedWorlds;
static NSLock *gWorldLock;

@interface WKContentWorld ()
- (instancetype)_initWithName:(NSString *)name;
@end

@implementation WKContentWorld
{
  NSString *_name;
}

@synthesize name = _name;

+ (void)initialize
{
  if (self != [WKContentWorld class]) {
    return;
  }
  gPageWorld = [[WKContentWorld alloc] _initWithName:nil];
  gDefaultClientWorld = [[WKContentWorld alloc] _initWithName:@"__defaultClientWorld"];
  gNamedWorlds = [[NSMutableDictionary alloc] init];
  gWorldLock = [[NSLock alloc] init];
}

+ (WKContentWorld *)pageWorld
{
  return gPageWorld;
}

+ (WKContentWorld *)defaultClientWorld
{
  return gDefaultClientWorld;
}

+ (WKContentWorld *)worldWithName:(NSString *)name
{
  if (name == nil) {
    return gPageWorld;
  }
  [gWorldLock lock];
  WKContentWorld *world = [[gNamedWorlds objectForKey:name] retain];
  if (world == nil) {
    world = [[WKContentWorld alloc] _initWithName:name];
    [gNamedWorlds setObject:world forKey:name];
  }
  [gWorldLock unlock];
  return [world autorelease];
}

- (instancetype)_initWithName:(NSString *)name
{
  self = [super init];
  if (self != nil) {
    _name = [name copy];
  }
  return self;
}

- (void)dealloc
{
  [_name release];
  [super dealloc];
}

@end
