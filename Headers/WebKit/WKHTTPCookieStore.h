/* WKHTTPCookieStore.h
 *
 * Manage HTTP cookies for a WKWebView's WKWebsiteDataStore.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKHTTPCookieStore
#define GNUstep_H_WKHTTPCookieStore

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WKHTTPCookieStoreObserver <NSObject>
@optional
- (void)cookiesDidChangeInCookieStore:(id)cookieStore;
@end

@interface WKHTTPCookieStore : NSObject

- (void)getAllCookies:(void (^)(NSArray<NSHTTPCookie *> *))completionHandler;
- (void)setCookie:(NSHTTPCookie *)cookie
   completionHandler:(void (^ _Nullable)(void))completionHandler;
- (void)deleteCookie:(NSHTTPCookie *)cookie
    completionHandler:(void (^ _Nullable)(void))completionHandler;

- (void)addObserver:(id <WKHTTPCookieStoreObserver>)observer;
- (void)removeObserver:(id <WKHTTPCookieStoreObserver>)observer;

@end

NS_ASSUME_NONNULL_END

#endif
