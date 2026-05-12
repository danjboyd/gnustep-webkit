/* WKScriptMessageHandler.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKScriptMessageHandler
#define GNUstep_H_WKScriptMessageHandler

#import <WebKit/WKFoundation.h>
#import <WebKit/WKScriptMessage.h>

@class WKUserContentController;

NS_ASSUME_NONNULL_BEGIN

@protocol WKScriptMessageHandler <NSObject>
@required
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message;
@end

@protocol WKScriptMessageHandlerWithReply <NSObject>
@required
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                  replyHandler:(void (^)(id _Nullable reply, NSString * _Nullable errorMessage))replyHandler;
@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKScriptMessageHandler */
