/* WKNavigationResponse.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKNavigationResponse
#define GNUstep_H_WKNavigationResponse

#import <WebKit/WKFoundation.h>
#import <WebKit/WKFrameInfo.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKNavigationResponse : NSObject

@property (nonatomic, readonly, getter=isForMainFrame) BOOL forMainFrame;
@property (nonatomic, readonly, copy) NSURLResponse *response;
@property (nonatomic, readonly) BOOL canShowMIMEType;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKNavigationResponse */
