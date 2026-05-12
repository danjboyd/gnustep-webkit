/* WKNavigationDelegate.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKNavigationDelegate
#define GNUstep_H_WKNavigationDelegate

#import <WebKit/WKFoundation.h>
#import <WebKit/WKNavigation.h>
#import <WebKit/WKNavigationAction.h>
#import <WebKit/WKNavigationResponse.h>

@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WKNavigationActionPolicy) {
  WKNavigationActionPolicyCancel,
  WKNavigationActionPolicyAllow,
  WKNavigationActionPolicyDownload = 2
};

typedef NS_ENUM(NSInteger, WKNavigationResponsePolicy) {
  WKNavigationResponsePolicyCancel,
  WKNavigationResponsePolicyAllow,
  WKNavigationResponsePolicyDownload = 2
};

@protocol WKNavigationDelegate <NSObject>
@optional

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
                      decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler;

- (void)webView:(WKWebView *)webView
    didStartProvisionalNavigation:(WKNavigation *)navigation;

- (void)webView:(WKWebView *)webView
    didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation;

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error;

- (void)webView:(WKWebView *)webView
    didCommitNavigation:(WKNavigation *)navigation;

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation;

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error;

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKNavigationDelegate */
