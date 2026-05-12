/* WKDAppDelegate.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import "WKDAppDelegate.h"
#import "WKDBrowserWindowController.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

@implementation WKDAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  (void)note;
  /* Build a minimal menu bar programmatically so the demo runs without
   * a .gorm/.nib. */
  NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"WebKitDemo"] autorelease];

  NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"WebKitDemo"
                                                    action:NULL
                                             keyEquivalent:@""] autorelease];
  NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"WebKitDemo"] autorelease];
  [appMenu addItemWithTitle:@"Quit"
                     action:@selector(terminate:)
              keyEquivalent:@"q"];
  [appItem setSubmenu:appMenu];
  [mainMenu addItem:appItem];
  [NSApp setMainMenu:mainMenu];

  _browser = [[WKDBrowserWindowController alloc] init];
  [_browser showWindow:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  (void)note;
  /* Drop the browser controller so WKWebView's dealloc runs while
   * the run loop is still alive — that's where GSWebKitBackend
   * shutdown happens (invalidates the GLib pump timer, disconnects
   * WebKit signals, unrefs the WebKitWebView). */
  [_browser release];
  _browser = nil;

  /* Skip the rest of AppKit's teardown.  GNUstep's
   * -[NSAutoreleasePool emptyPool] sometimes drains objects whose
   * backing buffers were owned by WPE/GLib subsystems that we just
   * tore down (or, conversely, are still being touched by the WPE
   * web process's IPC layer during its own atexit handlers).  The
   * resulting use-after-free shows up as a SIGSEGV in
   * -[GSArray dealloc] inside the pool drain — a real defect, but
   * one we can't fix from outside libgnustep-gui.  All state we
   * cared about has been flushed; the OS will reclaim the rest. */
  fflush(NULL);
  _exit(0);
}

- (void)dealloc
{
  [_browser release];
  [super dealloc];
}

@end
