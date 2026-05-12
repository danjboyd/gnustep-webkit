/* WKContentRuleListStore.h
 *
 * Compile and persist content-blocking rules for WKWebView.
 * Rules are written in the same JSON format Apple's Safari uses
 * (https://developer.apple.com/documentation/safariservices/creating_a_content_blocker).
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKContentRuleListStore
#define GNUstep_H_WKContentRuleListStore

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKContentRuleList : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@end

@interface WKContentRuleListStore : NSObject

+ (WKContentRuleListStore *)defaultStore;
+ (nullable WKContentRuleListStore *)storeForURL:(NSURL *)url;

- (void)compileContentRuleListForIdentifier:(NSString *)identifier
              encodedContentRuleList:(NSString *)json
                  completionHandler:(void (^)(WKContentRuleList * _Nullable list,
                                              NSError * _Nullable error))completionHandler;

- (void)lookUpContentRuleListForIdentifier:(NSString *)identifier
                          completionHandler:(void (^)(WKContentRuleList * _Nullable list,
                                                      NSError * _Nullable error))completionHandler;

- (void)removeContentRuleListForIdentifier:(NSString *)identifier
                          completionHandler:(void (^)(NSError * _Nullable error))completionHandler;

@end

NS_ASSUME_NONNULL_END

#endif
