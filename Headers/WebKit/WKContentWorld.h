/* WKContentWorld.h
 *
 * Isolated JavaScript execution context.  v1 implements the named-world
 * surface but treats all worlds as the page world internally.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKContentWorld
#define GNUstep_H_WKContentWorld

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKContentWorld : NSObject

@property (class, nonatomic, readonly) WKContentWorld *pageWorld;
@property (class, nonatomic, readonly) WKContentWorld *defaultClientWorld;

+ (WKContentWorld *)worldWithName:(NSString *)name;

@property (nullable, nonatomic, readonly, copy) NSString *name;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKContentWorld */
