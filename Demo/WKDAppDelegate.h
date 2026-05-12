/* WKDAppDelegate.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#ifndef WKD_APP_DELEGATE_H
#define WKD_APP_DELEGATE_H

#import <AppKit/AppKit.h>

@class WKDBrowserWindowController;

@interface WKDAppDelegate : NSObject <NSApplicationDelegate>
{
  WKDBrowserWindowController *_browser;
}
@end

#endif
