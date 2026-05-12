/* WKSecurityOrigin.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKSecurityOrigin
#define GNUstep_H_WKSecurityOrigin

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKSecurityOrigin : NSObject

@property (readonly, copy) NSString *protocol;
@property (readonly, copy) NSString *host;
@property (readonly) NSInteger port;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKSecurityOrigin */
