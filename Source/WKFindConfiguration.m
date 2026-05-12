/* WKFindConfiguration.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <WebKit/WKFindConfiguration.h>

@implementation WKFindConfiguration {
  BOOL _backwards, _caseSensitive, _wraps;
}
@synthesize backwards = _backwards;
@synthesize caseSensitive = _caseSensitive;
@synthesize wraps = _wraps;

- (instancetype)init
{
  self = [super init];
  if (self) {
    _wraps = YES;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  WKFindConfiguration *c = [[[self class] allocWithZone:zone] init];
  c->_backwards = _backwards;
  c->_caseSensitive = _caseSensitive;
  c->_wraps = _wraps;
  return c;
}
@end

@implementation WKFindResult {
  BOOL _matchFound;
}
@synthesize matchFound = _matchFound;

- (instancetype)_initWithMatchFound:(BOOL)found
{
  self = [super init];
  if (self) {
    _matchFound = found;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  return [[[self class] allocWithZone:zone] _initWithMatchFound:_matchFound];
}
@end
