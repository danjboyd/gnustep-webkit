/* WKDownload.h
 *
 * Object representing an in-progress download from a WKWebView.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKDownload
#define GNUstep_H_WKDownload

#import <WebKit/WKFoundation.h>

@class WKWebView;
@protocol WKDownloadDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface WKDownload : NSObject

@property (nullable, nonatomic, weak) id <WKDownloadDelegate> delegate;
@property (nullable, nonatomic, readonly, copy) NSURLRequest *originalRequest;
@property (nullable, nonatomic, readonly, weak) WKWebView *webView;
@property (nonatomic, readonly, strong) NSProgress *progress;

- (void)cancel:(void (^ _Nullable)(NSData * _Nullable resumeData))completionHandler;

@end

NS_ASSUME_NONNULL_END

#endif
