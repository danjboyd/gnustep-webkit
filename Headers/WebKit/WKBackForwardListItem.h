/* WKBackForwardListItem.h
 *
 * Represents a single entry in a WKWebView's back-forward list.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKBackForwardListItem
#define GNUstep_H_WKBackForwardListItem

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKBackForwardListItem : NSObject

@property (readonly, copy) NSURL *URL;
@property (nullable, readonly, copy) NSString *title;
@property (readonly, copy) NSURL *initialURL;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKBackForwardListItem */
