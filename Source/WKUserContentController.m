/* WKUserContentController.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKUserContentController.h>
#import "GSWebKitInternal.h"

@implementation _GSWKScriptHandlerRegistration
- (instancetype)initWithHandler:(id <WKScriptMessageHandler>)h
                           name:(NSString *)n
                          world:(WKContentWorld *)w
{
  self = [super init];
  if (self != nil) {
    _name    = [n copy];
    _handler = h;
    _world   = [w retain];
  }
  return self;
}
- (void)dealloc
{
  [_name release];
  [_world release];
  [super dealloc];
}
@end

@implementation WKUserContentController
{
  NSMutableArray *_userScripts;
  NSMutableArray *_handlers;
}

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    _userScripts = [[NSMutableArray alloc] init];
    _handlers    = [[NSMutableArray alloc] init];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  return [self init];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  /* Handlers and scripts are not encodable in a useful way; leave empty. */
}

- (void)dealloc
{
  [_userScripts release];
  [_handlers release];
  [super dealloc];
}

- (NSArray *)userScripts
{
  return [[_userScripts copy] autorelease];
}

- (void)addUserScript:(WKUserScript *)userScript
{
  if (userScript != nil) {
    [_userScripts addObject:userScript];
  }
}

- (void)removeAllUserScripts
{
  [_userScripts removeAllObjects];
}

- (void)addScriptMessageHandler:(id <WKScriptMessageHandler>)handler
                           name:(NSString *)name
{
  [self addScriptMessageHandler:handler
                   contentWorld:[WKContentWorld pageWorld]
                           name:name];
}

- (void)addScriptMessageHandler:(id <WKScriptMessageHandler>)handler
                   contentWorld:(WKContentWorld *)world
                           name:(NSString *)name
{
  _GSWKScriptHandlerRegistration *reg =
      [[_GSWKScriptHandlerRegistration alloc] initWithHandler:handler
                                                          name:name
                                                         world:world];
  [_handlers addObject:reg];
  [reg release];
}

- (void)removeScriptMessageHandlerForName:(NSString *)name
{
  [self removeScriptMessageHandlerForName:name
                             contentWorld:[WKContentWorld pageWorld]];
}

- (void)removeScriptMessageHandlerForName:(NSString *)name
                             contentWorld:(WKContentWorld *)world
{
  NSUInteger i, count = [_handlers count];
  for (i = 0; i < count; i++) {
    _GSWKScriptHandlerRegistration *reg = [_handlers objectAtIndex:i];
    if ([reg->_name isEqualToString:name] && reg->_world == world) {
      [_handlers removeObjectAtIndex:i];
      return;
    }
  }
}

- (void)removeAllScriptMessageHandlers
{
  [_handlers removeAllObjects];
}

- (NSArray *)_handlers
{
  return _handlers;
}

@end
