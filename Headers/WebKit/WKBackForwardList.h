/* WKBackForwardList.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKBackForwardList
#define GNUstep_H_WKBackForwardList

#import <WebKit/WKFoundation.h>
#import <WebKit/WKBackForwardListItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKBackForwardList : NSObject

@property (nullable, readonly, strong) WKBackForwardListItem *currentItem;
@property (nullable, readonly, strong) WKBackForwardListItem *backItem;
@property (nullable, readonly, strong) WKBackForwardListItem *forwardItem;

@property (readonly, copy) NSArray<WKBackForwardListItem *> *backList;
@property (readonly, copy) NSArray<WKBackForwardListItem *> *forwardList;

- (nullable WKBackForwardListItem *)itemAtIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKBackForwardList */
