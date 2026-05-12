/* WKFoundation.h
 *
 * Compatibility shims for the GNUstep WebKit framework.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; see the file COPYING.LIB for details.
 */

#ifndef GNUstep_H_WKFoundation
#define GNUstep_H_WKFoundation

#import <Foundation/Foundation.h>

/* On Apple, public WebKit symbols are tagged WK_EXTERN / WK_CLASS_AVAILABLE
 * etc.  GNUstep does not need the availability infrastructure, so these
 * collapse to plain declarations.
 */
#ifndef WK_EXTERN
#  ifdef __cplusplus
#    define WK_EXTERN extern "C"
#  else
#    define WK_EXTERN extern
#  endif
#endif

#ifndef WK_CLASS_AVAILABLE
#  define WK_CLASS_AVAILABLE(...)
#endif

#ifndef WK_API_AVAILABLE
#  define WK_API_AVAILABLE(...)
#endif

#ifndef WK_API_DEPRECATED
#  define WK_API_DEPRECATED(...)
#endif

#ifndef WK_API_DEPRECATED_WITH_REPLACEMENT
#  define WK_API_DEPRECATED_WITH_REPLACEMENT(...)
#endif

#endif /* GNUstep_H_WKFoundation */
