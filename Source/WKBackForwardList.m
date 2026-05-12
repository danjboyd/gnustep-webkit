/* WKBackForwardList.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKBackForwardList.h>
#import "GSWebKitInternal.h"

@implementation WKBackForwardList
{
  NSMutableArray *_items;       /* ordered oldest -> newest */
  NSInteger _currentIndex;      /* index of currentItem in _items, or -1 */
}

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    _items = [[NSMutableArray alloc] init];
    _currentIndex = -1;
  }
  return self;
}

- (void)dealloc
{
  [_items release];
  [super dealloc];
}

- (WKBackForwardListItem *)currentItem
{
  if (_currentIndex < 0 || _currentIndex >= (NSInteger)[_items count]) {
    return nil;
  }
  return [_items objectAtIndex:_currentIndex];
}

- (WKBackForwardListItem *)backItem
{
  if (_currentIndex <= 0) {
    return nil;
  }
  return [_items objectAtIndex:_currentIndex - 1];
}

- (WKBackForwardListItem *)forwardItem
{
  if (_currentIndex < 0 || _currentIndex + 1 >= (NSInteger)[_items count]) {
    return nil;
  }
  return [_items objectAtIndex:_currentIndex + 1];
}

- (NSArray *)backList
{
  if (_currentIndex <= 0) {
    return [NSArray array];
  }
  return [_items subarrayWithRange:NSMakeRange(0, _currentIndex)];
}

- (NSArray *)forwardList
{
  NSInteger total = (NSInteger)[_items count];
  if (_currentIndex < 0 || _currentIndex + 1 >= total) {
    return [NSArray array];
  }
  return [_items subarrayWithRange:NSMakeRange(_currentIndex + 1,
                                               total - _currentIndex - 1)];
}

- (WKBackForwardListItem *)itemAtIndex:(NSInteger)index
{
  /* Apple uses 0 == current, negative == back, positive == forward. */
  NSInteger target = _currentIndex + index;
  if (target < 0 || target >= (NSInteger)[_items count]) {
    return nil;
  }
  return [_items objectAtIndex:target];
}

/* Internal mutation: called by WKWebView/backend as navigation progresses. */
- (void)_appendItem:(WKBackForwardListItem *)item
{
  if (item == nil) {
    return;
  }
  if (_currentIndex >= 0 && _currentIndex + 1 < (NSInteger)[_items count]) {
    NSRange tail = NSMakeRange(_currentIndex + 1,
                               [_items count] - _currentIndex - 1);
    [_items removeObjectsInRange:tail];
  }
  [_items addObject:item];
  _currentIndex = (NSInteger)[_items count] - 1;
}

- (void)_setCurrentIndex:(NSInteger)index
{
  if (index < -1 || index >= (NSInteger)[_items count]) {
    return;
  }
  _currentIndex = index;
}

- (NSInteger)_currentIndex
{
  return _currentIndex;
}

@end
