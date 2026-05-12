/* WKUIDelegate.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKUIDelegate
#define GNUstep_H_WKUIDelegate

#import <WebKit/WKFoundation.h>
#import <WebKit/WKFrameInfo.h>
#import <WebKit/WKNavigationAction.h>

@class WKWebView;
@class WKWebViewConfiguration;

NS_ASSUME_NONNULL_BEGIN

@protocol WKUIDelegate <NSObject>
@optional

- (nullable WKWebView *)webView:(WKWebView *)webView
                createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
                           forNavigationAction:(WKNavigationAction *)navigationAction
                                windowFeatures:(id)windowFeatures;

- (void)webViewDidClose:(WKWebView *)webView;

- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler;

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL result))completionHandler;

- (void)webView:(WKWebView *)webView
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                              defaultText:(nullable NSString *)defaultText
                         initiatedByFrame:(WKFrameInfo *)frame
                        completionHandler:(void (^)(NSString * _Nullable result))completionHandler;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKUIDelegate */
