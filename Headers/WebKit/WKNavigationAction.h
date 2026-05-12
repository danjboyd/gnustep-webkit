/* WKNavigationAction.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKNavigationAction
#define GNUstep_H_WKNavigationAction

#import <WebKit/WKFoundation.h>
#import <WebKit/WKFrameInfo.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WKNavigationType) {
  WKNavigationTypeLinkActivated,
  WKNavigationTypeFormSubmitted,
  WKNavigationTypeBackForward,
  WKNavigationTypeReload,
  WKNavigationTypeFormResubmitted,
  WKNavigationTypeOther = -1
};

@interface WKNavigationAction : NSObject

@property (nonatomic, readonly, copy) WKFrameInfo *sourceFrame;
@property (nullable, nonatomic, readonly, copy) WKFrameInfo *targetFrame;
@property (nonatomic, readonly) WKNavigationType navigationType;
@property (nonatomic, readonly, copy) NSURLRequest *request;
@property (nonatomic, readonly) BOOL shouldPerformDownload;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKNavigationAction */
