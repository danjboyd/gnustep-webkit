/* WKWebsiteDataStore.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKWebsiteDataStore.h>

static WKWebsiteDataStore *gDefaultStore;
static NSLock *gDefaultStoreLock;

@implementation WKWebsiteDataStore
{
  BOOL _persistent;
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
