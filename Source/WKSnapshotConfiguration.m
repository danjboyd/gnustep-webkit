/* WKSnapshotConfiguration.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <WebKit/WKSnapshotConfiguration.h>

@implementation WKSnapshotConfiguration {
  NSRect _rect;
  CGFloat _snapshotWidth;
  BOOL _afterScreenUpdates;
}
@synthesize rect = _rect;
@synthesize snapshotWidth = _snapshotWidth;
@synthesize afterScreenUpdates = _afterScreenUpdates;
- (instancetype)init
{
  self = [super init];
  if (self) {
    _rect = NSZeroRect;
    _afterScreenUpdates = YES;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)z
{
  WKSnapshotConfiguration *c = [[[self class] allocWithZone:z] init];
  c->_rect = _rect;
  c->_snapshotWidth = _snapshotWidth;
  c->_afterScreenUpdates = _afterScreenUpdates;
  return c;
}
@end

@implementation WKPDFConfiguration {
  NSRect _rect;
  BOOL _allowTransparentBackground;
}
@synthesize rect = _rect;
@synthesize allowTransparentBackground = _allowTransparentBackground;
- (id)copyWithZone:(NSZone *)z
{
  WKPDFConfiguration *c = [[[self class] allocWithZone:z] init];
  c->_rect = _rect;
  c->_allowTransparentBackground = _allowTransparentBackground;
  return c;
}
@end
