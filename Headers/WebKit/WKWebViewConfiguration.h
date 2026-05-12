/* WKWebViewConfiguration.h
 *
 * A collection of properties used to initialise a WKWebView.  Setting
 * the configuration after the web view has been created has no effect.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKWebViewConfiguration
#define GNUstep_H_WKWebViewConfiguration

#import <WebKit/WKFoundation.h>
#import <WebKit/WKPreferences.h>
#import <WebKit/WKProcessPool.h>
#import <WebKit/WKURLSchemeHandler.h>
#import <WebKit/WKUserContentController.h>
#import <WebKit/WKWebsiteDataStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKWebViewConfiguration : NSObject <NSCopying, NSCoding>

@property (nonatomic, strong) WKProcessPool *processPool;
@property (nonatomic, strong) WKPreferences *preferences;
@property (nonatomic, strong) WKUserContentController *userContentController;
@property (nonatomic, strong) WKWebsiteDataStore *websiteDataStore;

@property (nullable, nonatomic, copy) NSString *applicationNameForUserAgent;
@property (nonatomic) BOOL suppressesIncrementalRendering;
@property (nonatomic) BOOL allowsAirPlayForMediaPlayback;
@property (nonatomic) BOOL limitsNavigationsToAppBoundDomains;
@property (nonatomic) BOOL upgradeKnownHostsToHTTPS;

/* Custom URL scheme handlers. */
- (void)setURLSchemeHandler:(nullable id <WKURLSchemeHandler>)urlSchemeHandler
               forURLScheme:(NSString *)urlScheme;
- (nullable id <WKURLSchemeHandler>)urlSchemeHandlerForURLScheme:(NSString *)urlScheme;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKWebViewConfiguration */
