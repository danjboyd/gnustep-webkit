/* WKFindConfiguration.h
 *
 * Options for WKWebView find:configuration:completionHandler:.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKFindConfiguration
#define GNUstep_H_WKFindConfiguration

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKFindConfiguration : NSObject <NSCopying>
@property (nonatomic) BOOL backwards;
@property (nonatomic) BOOL caseSensitive;
@property (nonatomic) BOOL wraps;
@end

@interface WKFindResult : NSObject <NSCopying>
@property (nonatomic, readonly) BOOL matchFound;
@end

NS_ASSUME_NONNULL_END

#endif
