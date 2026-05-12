/* GSWebKitWPE.h
 *
 * WPE WebKit concrete backend.  Not installed.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GS_WEBKIT_WPE_H
#define GS_WEBKIT_WPE_H

#import "GSWebKitBackend.h"

@class WKWebViewConfiguration;

@interface GSWebKitWPE : GSWebKitBackend

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)config;

@end

#endif /* GS_WEBKIT_WPE_H */
