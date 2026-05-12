/* GSWebKitInternal.h
 *
 * Private declarations shared between the WK* facade classes and the
 * engine backend.  Not installed.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GS_WEBKIT_INTERNAL_H
#define GS_WEBKIT_INTERNAL_H

#import <Foundation/Foundation.h>

#import <WebKit/WKBackForwardList.h>
#import <WebKit/WKBackForwardListItem.h>
#import <WebKit/WKContentWorld.h>
#import <WebKit/WKFrameInfo.h>
#import <WebKit/WKNavigation.h>
#import <WebKit/WKNavigationAction.h>
#import <WebKit/WKNavigationResponse.h>
#import <WebKit/WKScriptMessage.h>
#import <WebKit/WKScriptMessageHandler.h>
#import <WebKit/WKSecurityOrigin.h>
#import <WebKit/WKUserContentController.h>
#import <WebKit/WKWebsiteDataStore.h>

@interface WKBackForwardListItem ()
- (instancetype)_initWithURL:(NSURL *)url
                  initialURL:(NSURL *)initialURL
                       title:(NSString *)title;
@end

@interface WKBackForwardList ()
- (void)_appendItem:(WKBackForwardListItem *)item;
- (void)_setCurrentIndex:(NSInteger)index;
- (NSInteger)_currentIndex;
@end

@interface WKSecurityOrigin ()
- (instancetype)_initWithProtocol:(NSString *)protocol
                             host:(NSString *)host
                             port:(NSInteger)port;
@end

@class WKWebView;

@interface WKFrameInfo ()
- (instancetype)_initWithMainFrame:(BOOL)mainFrame
                           request:(NSURLRequest *)request
                    securityOrigin:(WKSecurityOrigin *)origin
                           webView:(WKWebView *)webView;
@end

@interface WKNavigation ()
- (instancetype)_initWithRequest:(NSURLRequest *)request
                      identifier:(uint64_t)identifier;
- (uint64_t)_identifier;
- (void)_setRequest:(NSURLRequest *)request;
@end

@interface WKNavigationAction ()
- (instancetype)_initWithRequest:(NSURLRequest *)request
                  navigationType:(WKNavigationType)navigationType
                     sourceFrame:(WKFrameInfo *)source
                     targetFrame:(WKFrameInfo *)target;
@end

@interface WKNavigationResponse ()
- (instancetype)_initWithResponse:(NSURLResponse *)response
                     forMainFrame:(BOOL)forMainFrame
                  canShowMIMEType:(BOOL)canShow;
@end

@interface WKScriptMessage ()
- (instancetype)_initWithName:(NSString *)name
                         body:(id)body
                      webView:(WKWebView *)webView
                    frameInfo:(WKFrameInfo *)frame
                        world:(WKContentWorld *)world;
@end

@interface WKWebsiteDataStore ()
- (instancetype)_initPersistent:(BOOL)persistent;
@end

@interface WKUserContentController ()
- (NSArray *)_handlers;
@end

/* Internal record describing one registered message handler.  Stored
 * in WKUserContentController's _handlers array and walked by
 * WKWebView to dispatch incoming bridge messages.  Visible to other
 * files in the framework so WKWebView can access the fields directly
 * without relying on KVC string lookups. */
@class WKContentWorld;
@protocol WKScriptMessageHandler;

@interface _GSWKScriptHandlerRegistration : NSObject
{
@public
  NSString *_name;
  id <WKScriptMessageHandler> _handler;   /* weak by Apple convention */
  WKContentWorld *_world;
}
- (instancetype)initWithHandler:(id <WKScriptMessageHandler>)h
                           name:(NSString *)n
                          world:(WKContentWorld *)w;
@end

#endif /* GS_WEBKIT_INTERNAL_H */
