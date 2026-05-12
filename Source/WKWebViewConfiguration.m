/* WKWebViewConfiguration.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKWebViewConfiguration.h>

@implementation WKWebViewConfiguration
{
  WKProcessPool *_processPool;
  WKPreferences *_preferences;
  WKUserContentController *_userContentController;
  WKWebsiteDataStore *_websiteDataStore;
  NSString *_applicationNameForUserAgent;
  BOOL _suppressesIncrementalRendering;
  BOOL _allowsAirPlayForMediaPlayback;
  BOOL _limitsNavigationsToAppBoundDomains;
  BOOL _upgradeKnownHostsToHTTPS;
}

@synthesize processPool = _processPool;
@synthesize preferences = _preferences;
@synthesize userContentController = _userContentController;
@synthesize websiteDataStore = _websiteDataStore;
@synthesize applicationNameForUserAgent = _applicationNameForUserAgent;
@synthesize suppressesIncrementalRendering = _suppressesIncrementalRendering;
@synthesize allowsAirPlayForMediaPlayback = _allowsAirPlayForMediaPlayback;
@synthesize limitsNavigationsToAppBoundDomains = _limitsNavigationsToAppBoundDomains;
@synthesize upgradeKnownHostsToHTTPS = _upgradeKnownHostsToHTTPS;

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    _processPool           = [[WKProcessPool alloc] init];
    _preferences           = [[WKPreferences alloc] init];
    _userContentController = [[WKUserContentController alloc] init];
    _websiteDataStore      = [[WKWebsiteDataStore defaultDataStore] retain];
    _allowsAirPlayForMediaPlayback = YES;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  return [self init];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
}

- (id)copyWithZone:(NSZone *)zone
{
  WKWebViewConfiguration *c = [[[self class] allocWithZone:zone] init];
  /* Replace defaults with our values where they were customised. */
  [c->_processPool release];
  c->_processPool = [_processPool retain];
  [c->_preferences release];
  c->_preferences = [_preferences retain];
  [c->_userContentController release];
  c->_userContentController = [_userContentController retain];
  [c->_websiteDataStore release];
  c->_websiteDataStore = [_websiteDataStore retain];
  c->_applicationNameForUserAgent = [_applicationNameForUserAgent copy];
  c->_suppressesIncrementalRendering = _suppressesIncrementalRendering;
  c->_allowsAirPlayForMediaPlayback  = _allowsAirPlayForMediaPlayback;
  c->_limitsNavigationsToAppBoundDomains = _limitsNavigationsToAppBoundDomains;
  c->_upgradeKnownHostsToHTTPS = _upgradeKnownHostsToHTTPS;
  return c;
}

- (void)setProcessPool:(WKProcessPool *)pool
{
  if (pool == _processPool) return;
  [_processPool release];
  _processPool = [pool retain];
}

- (void)setPreferences:(WKPreferences *)prefs
{
  if (prefs == _preferences) return;
  [_preferences release];
  _preferences = [prefs retain];
}

- (void)setUserContentController:(WKUserContentController *)ucc
{
  if (ucc == _userContentController) return;
  [_userContentController release];
  _userContentController = [ucc retain];
}

- (void)setWebsiteDataStore:(WKWebsiteDataStore *)ds
{
  if (ds == _websiteDataStore) return;
  [_websiteDataStore release];
  _websiteDataStore = [ds retain];
}

- (void)setApplicationNameForUserAgent:(NSString *)name
{
  if (name == _applicationNameForUserAgent) return;
  [_applicationNameForUserAgent release];
  _applicationNameForUserAgent = [name copy];
}

- (void)dealloc
{
  [_processPool release];
  [_preferences release];
  [_userContentController release];
  [_websiteDataStore release];
  [_applicationNameForUserAgent release];
  [super dealloc];
}

@end
