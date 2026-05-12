/* WKProcessPool.h
 *
 * Identity object representing a shared pool of web content processes.
 * Two WKWebViews configured with the same WKProcessPool may share a
 * back-end process; with different pools they are isolated.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKProcessPool
#define GNUstep_H_WKProcessPool

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKProcessPool : NSObject <NSCoding>
@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKProcessPool */
