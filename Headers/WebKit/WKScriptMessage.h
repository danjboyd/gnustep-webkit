/* WKScriptMessage.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKScriptMessage
#define GNUstep_H_WKScriptMessage

#import <WebKit/WKFoundation.h>
#import <WebKit/WKContentWorld.h>
#import <WebKit/WKFrameInfo.h>

@class WKWebView;

NS_ASSUME_NONNULL_BEGIN

@interface WKScriptMessage : NSObject

@property (nonatomic, readonly, copy) id body;
@property (nullable, nonatomic, readonly, weak) WKWebView *webView;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) WKFrameInfo *frameInfo;
@property (nonatomic, readonly, copy) WKContentWorld *world;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKScriptMessage */
