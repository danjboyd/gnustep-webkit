/* main.m
 *
 * Entry point for the WebKitDemo GNUstep application.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <AppKit/AppKit.h>
#import "WKDAppDelegate.h"

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSApplication *app = [NSApplication sharedApplication];

  WKDAppDelegate *delegate = [[[WKDAppDelegate alloc] init] autorelease];
  [app setDelegate:delegate];

  int status = NSApplicationMain(argc, argv);

  [pool release];
  return status;
}
