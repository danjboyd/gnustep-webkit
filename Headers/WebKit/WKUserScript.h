/* WKUserScript.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKUserScript
#define GNUstep_H_WKUserScript

#import <WebKit/WKFoundation.h>
#import <WebKit/WKContentWorld.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WKUserScriptInjectionTime) {
  WKUserScriptInjectionTimeAtDocumentStart,
  WKUserScriptInjectionTimeAtDocumentEnd
};

@interface WKUserScript : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSString *source;
@property (nonatomic, readonly) WKUserScriptInjectionTime injectionTime;
@property (nonatomic, readonly, getter=isForMainFrameOnly) BOOL forMainFrameOnly;
@property (nonatomic, readonly, copy) WKContentWorld *contentWorld;

- (instancetype)initWithSource:(NSString *)source
                 injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly;

- (instancetype)initWithSource:(NSString *)source
                 injectionTime:(WKUserScriptInjectionTime)injectionTime
              forMainFrameOnly:(BOOL)forMainFrameOnly
                  contentWorld:(WKContentWorld *)contentWorld;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKUserScript */
