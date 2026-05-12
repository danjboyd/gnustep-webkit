/* WKError.h
 *
 * Error domain and codes for the GNUstep WebKit framework.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKError
#define GNUstep_H_WKError

#import <WebKit/WKFoundation.h>

NS_ASSUME_NONNULL_BEGIN

WK_EXTERN NSString * const WKErrorDomain;

typedef NS_ENUM(NSInteger, WKErrorCode) {
  WKErrorUnknown = 1,
  WKErrorWebContentProcessTerminated = 2,
  WKErrorWebViewInvalidated = 3,
  WKErrorJavaScriptExceptionOccurred = 4,
  WKErrorJavaScriptResultTypeIsUnsupported = 5,
  WKErrorContentRuleListStoreCompileFailed = 6,
  WKErrorContentRuleListStoreLookUpFailed = 7,
  WKErrorContentRuleListStoreRemoveFailed = 8,
  WKErrorContentRuleListStoreVersionMismatch = 9,
  WKErrorAttributedStringContentFailedToLoad = 10,
  WKErrorAttributedStringContentLoadTimedOut = 11,
  WKErrorJavaScriptInvalidFrameTarget = 12,
  WKErrorNavigationAppBoundDomain = 13,
  WKErrorJavaScriptAppBoundDomain = 14
};

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKError */
