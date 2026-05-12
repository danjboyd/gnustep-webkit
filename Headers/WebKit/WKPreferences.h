/* WKPreferences.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKPreferences
#define GNUstep_H_WKPreferences

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKPreferences : NSObject <NSCoding>

@property (nonatomic) CGFloat minimumFontSize;
@property (nonatomic) BOOL javaScriptCanOpenWindowsAutomatically;
@property (nonatomic) BOOL javaScriptEnabled;  /* deprecated on Apple; honoured here */
@property (nonatomic) BOOL fraudulentWebsiteWarningEnabled;
@property (nonatomic, getter=isElementFullscreenEnabled) BOOL elementFullscreenEnabled;
@property (nonatomic, getter=isTextInteractionEnabled) BOOL textInteractionEnabled;
@property (nonatomic) BOOL shouldPrintBackgrounds;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKPreferences */
