/* WKWebsiteDataStore.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKWebsiteDataStore.h>
#import "GSWebKitInternal.h"

#include <wpe/webkit.h>

static WKWebsiteDataStore *gDefaultStore;
static NSLock *gDefaultStoreLock;

@implementation WKWebsiteDataStore
{
  BOOL _persistent;
  WKHTTPCookieStore *_httpCookieStore;
}

@synthesize persistent = _persistent;

+ (void)initialize
{
  if (self != [WKWebsiteDataStore class]) {
    return;
  }
  gDefaultStoreLock = [[NSLock alloc] init];
}

+ (WKWebsiteDataStore *)defaultDataStore
{
  [gDefaultStoreLock lock];
  if (gDefaultStore == nil) {
    gDefaultStore = [[WKWebsiteDataStore alloc] _initPersistent:YES];
  }
  WKWebsiteDataStore *result = gDefaultStore;
  [gDefaultStoreLock unlock];
  return result;
}

+ (WKWebsiteDataStore *)nonPersistentDataStore
{
  return [[[WKWebsiteDataStore alloc] _initPersistent:NO] autorelease];
}

+ (NSSet *)allWebsiteDataTypes
{
  static NSSet *types = nil;
  if (types == nil) {
    types = [[NSSet alloc] initWithObjects:
             @"WKWebsiteDataTypeDiskCache",
             @"WKWebsiteDataTypeMemoryCache",
             @"WKWebsiteDataTypeOfflineWebApplicationCache",
             @"WKWebsiteDataTypeCookies",
             @"WKWebsiteDataTypeSessionStorage",
             @"WKWebsiteDataTypeLocalStorage",
             @"WKWebsiteDataTypeWebSQLDatabases",
             @"WKWebsiteDataTypeIndexedDBDatabases",
             nil];
  }
  return types;
}

- (instancetype)init
{
  return [self _initPersistent:YES];
}

- (WKHTTPCookieStore *)httpCookieStore
{
  if (_httpCookieStore == nil) {
    /* Lazy-initialise against the default WebKitNetworkSession's
     * cookie manager.  Using the default session means cookies set or
     * read here are shared with any WKWebView using the default
     * configuration — same behaviour as Apple's defaultDataStore. */
    WebKitNetworkSession *session = webkit_network_session_get_default();
    WebKitCookieManager *cm = NULL;
    if (session != NULL) {
      cm = webkit_network_session_get_cookie_manager(session);
    }
    _httpCookieStore = [[WKHTTPCookieStore alloc] _initWithCookieManager:cm];
  }
  return _httpCookieStore;
}

- (void)dealloc
{
  [_httpCookieStore release];
  [super dealloc];
}

- (instancetype)_initPersistent:(BOOL)persistent
{
  self = [super init];
  if (self != nil) {
    _persistent = persistent;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  return [self _initPersistent:YES];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
}

@end
