/* WKUserContentController.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKUserContentController
#define GNUstep_H_WKUserContentController

#import <WebKit/WKFoundation.h>
#import <WebKit/WKContentRuleListStore.h>
#import <WebKit/WKUserScript.h>
#import <WebKit/WKScriptMessageHandler.h>
#import <WebKit/WKContentWorld.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKUserContentController : NSObject <NSCoding>

@property (nonatomic, readonly, copy) NSArray<WKUserScript *> *userScripts;

- (void)addUserScript:(WKUserScript *)userScript;
- (void)removeAllUserScripts;

- (void)addScriptMessageHandler:(id <WKScriptMessageHandler>)scriptMessageHandler
                           name:(NSString *)name;
- (void)addScriptMessageHandler:(id <WKScriptMessageHandler>)scriptMessageHandler
                   contentWorld:(WKContentWorld *)world
                           name:(NSString *)name;
- (void)removeScriptMessageHandlerForName:(NSString *)name;
- (void)removeScriptMessageHandlerForName:(NSString *)name
                             contentWorld:(WKContentWorld *)contentWorld;
- (void)removeAllScriptMessageHandlers;

- (void)addContentRuleList:(WKContentRuleList *)contentRuleList;
- (void)removeContentRuleList:(WKContentRuleList *)contentRuleList;
- (void)removeAllContentRuleLists;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKUserContentController */
