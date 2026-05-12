/* WKSnapshotConfiguration.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKSnapshotConfiguration
#define GNUstep_H_WKSnapshotConfiguration

#import <WebKit/WKFoundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKSnapshotConfiguration : NSObject <NSCopying>
@property (nonatomic) NSRect rect;
@property (nonatomic) CGFloat snapshotWidth;
@property (nonatomic) BOOL afterScreenUpdates;
@end


@interface WKPDFConfiguration : NSObject <NSCopying>
@property (nonatomic) NSRect rect;
@property (nonatomic) BOOL allowTransparentBackground;
@end

NS_ASSUME_NONNULL_END

#endif
