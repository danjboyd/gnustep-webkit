/* WKNavigation.h
 *
 * Token object identifying a navigation in flight.  Delegate callbacks
 * receive the same WKNavigation instance returned by the load... call
 * that began the navigation.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKNavigation
#define GNUstep_H_WKNavigation

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKNavigation : NSObject

@property (nullable, nonatomic, readonly, copy) NSURLRequest *request;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKNavigation */
