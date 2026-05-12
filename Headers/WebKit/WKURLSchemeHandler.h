/* WKURLSchemeHandler.h
 *
 * Register handlers for custom URL schemes (myapp://...).
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKURLSchemeHandler
#define GNUstep_H_WKURLSchemeHandler

#import <WebKit/WKFoundation.h>

@class WKWebView;
@protocol WKURLSchemeTask;

NS_ASSUME_NONNULL_BEGIN

@protocol WKURLSchemeHandler <NSObject>
@required

- (void)webView:(WKWebView *)webView
    startURLSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask;

- (void)webView:(WKWebView *)webView
    stopURLSchemeTask:(id <WKURLSchemeTask>)urlSchemeTask;

@end

@protocol WKURLSchemeTask <NSObject>
@required

@property (nonatomic, readonly, copy) NSURLRequest *request;

- (void)didReceiveResponse:(NSURLResponse *)response;
- (void)didReceiveData:(NSData *)data;
- (void)didFinish;
- (void)didFailWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END

#endif
