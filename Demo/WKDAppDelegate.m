/* WKDAppDelegate.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import "WKDAppDelegate.h"
#import "WKDBrowserWindowController.h"

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
  /* Drop the browser controller before the C runtime starts tearing
   * down GLib/WPE atexit state.  This pops -[WKWebView dealloc],
   * which calls -[GSWebKitBackend shutdown] and unwinds the engine
   * objects on our schedule rather than racing exit handlers. */
  [_browser release];
  _browser = nil;
}

- (void)dealloc
{
  [_browser release];
  [super dealloc];
}

@end
