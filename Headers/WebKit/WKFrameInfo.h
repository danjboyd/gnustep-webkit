/* WKFrameInfo.h
 *
 * Information about a frame in a web page.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKFrameInfo
#define GNUstep_H_WKFrameInfo

#import <WebKit/WKFoundation.h>
#import <WebKit/WKSecurityOrigin.h>

@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

@interface WKFrameInfo : NSObject <NSCopying>

@property (nonatomic, readonly, getter=isMainFrame) BOOL mainFrame;
@property (nullable, nonatomic, readonly, copy) NSURLRequest *request;
@property (nonatomic, readonly, copy) WKSecurityOrigin *securityOrigin;
@property (nullable, nonatomic, readonly, weak) WKWebView *webView;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKFrameInfo */
