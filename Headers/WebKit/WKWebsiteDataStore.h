/* WKWebsiteDataStore.h
 *
 * Storage for cookies, caches, local storage etc. attached to a
 * WKWebView.  v1 exposes only the persistent/non-persistent factories
 * and identity comparisons; data-removal APIs are stubbed.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKWebsiteDataStore
#define GNUstep_H_WKWebsiteDataStore

#import <WebKit/WKFoundation.h>
#import <WebKit/WKHTTPCookieStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKWebsiteDataStore : NSObject <NSCoding>

@property (class, nonatomic, readonly, strong) WKWebsiteDataStore *defaultDataStore;
+ (WKWebsiteDataStore *)nonPersistentDataStore;

@property (nonatomic, readonly, getter=isPersistent) BOOL persistent;
@property (nonatomic, readonly, strong) WKHTTPCookieStore *httpCookieStore;

+ (NSSet<NSString *> *)allWebsiteDataTypes;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKWebsiteDataStore */
