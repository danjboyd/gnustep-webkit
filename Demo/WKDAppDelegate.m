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
  NSMenuItem *newWin = [appMenu addItemWithTitle:@"New Window"
                                          action:@selector(newBrowserWindow:)
                                   keyEquivalent:@"n"];
  [newWin setTarget:self];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:@"Quit"
                     action:@selector(terminate:)
              keyEquivalent:@"q"];
  [appItem setSubmenu:appMenu];
  [mainMenu addItem:appItem];

  /* Edit menu: Find. */
  NSMenuItem *editItem = [[[NSMenuItem alloc] initWithTitle:@"Edit"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
  NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
  [editMenu addItemWithTitle:@"Find…" action:@selector(showFindBar:) keyEquivalent:@"f"];
  [editMenu addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut"   action:NSSelectorFromString(@"cut:")  keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy"  action:NSSelectorFromString(@"copy:") keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:NSSelectorFromString(@"paste:") keyEquivalent:@"v"];
  [editItem setSubmenu:editMenu];
  [mainMenu addItem:editItem];

  /* View menu: Zoom. */
  NSMenuItem *viewItem = [[[NSMenuItem alloc] initWithTitle:@"View"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
  NSMenu *viewMenu = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
  [viewMenu addItemWithTitle:@"Zoom In"       action:@selector(zoomIn:)    keyEquivalent:@"="];
  [viewMenu addItemWithTitle:@"Zoom Out"      action:@selector(zoomOut:)   keyEquivalent:@"-"];
  [viewMenu addItemWithTitle:@"Actual Size"   action:@selector(zoomReset:) keyEquivalent:@"0"];
  [viewItem setSubmenu:viewMenu];
  [mainMenu addItem:viewItem];

  /* Demo menu: exercises framework features that already work but
   * aren't otherwise visible in the bundled chrome. */
  NSMenuItem *demoItem = [[[NSMenuItem alloc] initWithTitle:@"Demo"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
  NSMenu *demoMenu = [[[NSMenu alloc] initWithTitle:@"Demo"] autorelease];
  [demoMenu addItemWithTitle:@"File Picker (NSOpenPanel)"
                      action:@selector(demoFileChooser:) keyEquivalent:@""];
  [demoMenu addItemWithTitle:@"Custom Scheme (myapp://)"
                      action:@selector(demoCustomScheme:) keyEquivalent:@""];
  [demoMenu addItemWithTitle:@"Cookie Inspector"
                      action:@selector(demoCookieInspector:) keyEquivalent:@""];
  [demoMenu addItemWithTitle:@"Back/Forward History"
                      action:@selector(demoHistory:)  keyEquivalent:@""];
  [demoItem setSubmenu:demoMenu];
  [mainMenu addItem:demoItem];

  [NSApp setMainMenu:mainMenu];

  _browsers = [[NSMutableArray alloc] init];
  [self newBrowserWindow:nil];
}

- (void)newBrowserWindow:(id)sender
{
  (void)sender;
  WKDBrowserWindowController *b =
      [[[WKDBrowserWindowController alloc] init] autorelease];
  [_browsers addObject:b];
  [b showWindow:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
  (void)note;
  /* Drop the browser controllers so each WKWebView's dealloc runs
   * while the run loop is still alive — that's where
   * GSWebKitBackend shutdown happens (invalidates the GLib pump
   * timer, disconnects WebKit signals, unrefs the WebKitWebView). */
  [_browsers release];
  _browsers = nil;

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
  [_browsers release];
  [super dealloc];
}

@end
