/* WKWebView.m
 *
 * NSView subclass that hosts a GSWebKitBackend and exposes the
 * Apple-style WKWebView API.
 *
 * Coordinate system: the view is -isFlipped, so NSView local
 * coordinates have origin at the top-left, matching the web engine's
 * own coordinate space.  This avoids per-event flipping.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKWebView.h>
#import <WebKit/WKError.h>

#import "GSWebKitBackend.h"
#import "GSWebKitInternal.h"

#include <stdint.h>
#include <stdlib.h>

/* X11 keysym values for named keys.  Copied here rather than dragging
 * in <X11/keysymdef.h> as a hard build dependency. */
#define GS_WKKEY_BackSpace 0xff08
#define GS_WKKEY_Tab       0xff09
#define GS_WKKEY_Return    0xff0d
#define GS_WKKEY_Escape    0xff1b
#define GS_WKKEY_Left      0xff51
#define GS_WKKEY_Up        0xff52
#define GS_WKKEY_Right     0xff53
#define GS_WKKEY_Down      0xff54
#define GS_WKKEY_PageUp    0xff55
#define GS_WKKEY_PageDown  0xff56
#define GS_WKKEY_Home      0xff50
#define GS_WKKEY_End       0xff57
#define GS_WKKEY_Insert    0xff63
#define GS_WKKEY_Delete    0xffff
#define GS_WKKEY_F1        0xffbe   /* F2..F12 are F1+n */
#define GS_WKKEY_Shift_L   0xffe1
#define GS_WKKEY_Shift_R   0xffe2
#define GS_WKKEY_Control_L 0xffe3
#define GS_WKKEY_Control_R 0xffe4
#define GS_WKKEY_Alt_L     0xffe9
#define GS_WKKEY_Alt_R     0xffea
#define GS_WKKEY_Meta_L    0xffe7
#define GS_WKKEY_Meta_R    0xffe8

/* WPE modifier bits we want to convey. */
#define GS_WK_MOD_CTRL    (1u << 0)
#define GS_WK_MOD_SHIFT   (1u << 1)
#define GS_WK_MOD_ALT     (1u << 2)
#define GS_WK_MOD_META    (1u << 3)
#define GS_WK_MOD_BUTTON1 (1u << 20)
#define GS_WK_MOD_BUTTON2 (1u << 21)
#define GS_WK_MOD_BUTTON3 (1u << 22)

/* Optional verbose event tracing.  Enabled by WKDEMO_TRACE_EVENTS=1 in
 * the environment.  Cheap when disabled (one branch). */
static int GSWK_TraceEvents(void)
{
  static int v = -1;
  if (v < 0) {
    const char *env = getenv("WKDEMO_TRACE_EVENTS");
    v = (env != NULL && env[0] != '\0' && env[0] != '0') ? 1 : 0;
  }
  return v;
}

#define GSWK_TRACE(fmt, ...) do { \
    if (GSWK_TraceEvents()) { fprintf(stderr, "WKWV " fmt "\n", ##__VA_ARGS__); fflush(stderr); } \
  } while (0)


@interface WKWebView () <GSWebKitBackendHost>
@end


@implementation WKWebView
{
  WKWebViewConfiguration   *_configuration;
  GSWebKitBackend          *_backend;
  WKBackForwardList        *_backForwardList;

  /* Delegates: weak, per Apple convention. */
  id <WKNavigationDelegate> _navigationDelegate;
  id <WKUIDelegate>         _UIDelegate;

  /* Mirrored state (so KVO-style getters are cheap). */
  NSURL    *_currentURL;
  NSString *_currentTitle;
  double    _estimatedProgress;
  BOOL      _isLoading;
  NSString *_customUserAgent;
  BOOL      _allowsBackForwardNavigationGestures;

  /* In-flight navigation token; returned from load... and threaded
   * through delegate callbacks. */
  WKNavigation *_currentNavigation;
  uint64_t      _navigationCounter;

  /* Bitmask of buttons currently held.  WPE expects these bits ORed
   * into the modifiers field on every pointer event (motion or button)
   * so the engine can distinguish a hover from a drag. */
  uint32_t      _pressedButtons;

  /* Mouse-moved tracking.  Without this AppKit does not call
   * -mouseMoved: at all, so :hover / onmouseover / mouseenter
   * JS handlers in the engine never fire.  GNUstep only implements
   * the legacy -addTrackingRect:owner:userData:assumeInside: API
   * (NSTrackingArea is declared in headers but isn't wired into
   * NSView), so we use that. */
  NSTrackingRectTag _trackingTag;
  BOOL              _hasTrackingTag;

  /* Cursor the engine has asked us to display.  Updated when WebKit's
   * mouse-target-changed signal fires; consulted from -cursorUpdate:
   * and applied directly when the mouse moves so the visible cursor
   * matches what's hovered. */
  NSCursor *_engineCursor;

  /* Latest hit-test info from the engine.  Used by the context menu
   * to vary items (Copy Link / Open Image / etc.). */
  NSDictionary *_mouseTargetInfo;
}

@synthesize configuration         = _configuration;
@synthesize navigationDelegate    = _navigationDelegate;
@synthesize UIDelegate            = _UIDelegate;
@synthesize backForwardList       = _backForwardList;
@synthesize URL                   = _currentURL;
@synthesize title                 = _currentTitle;
@synthesize estimatedProgress     = _estimatedProgress;
@synthesize loading               = _isLoading;
@synthesize customUserAgent       = _customUserAgent;
@synthesize allowsBackForwardNavigationGestures = _allowsBackForwardNavigationGestures;


/* -------------------------------------------------------------- Init */

- (instancetype)initWithFrame:(NSRect)frame
                configuration:(WKWebViewConfiguration *)configuration
{
  self = [super initWithFrame:frame];
  if (self == nil) {
    return nil;
  }
  if (configuration != nil) {
    _configuration = [configuration copy];
  } else {
    _configuration = [[WKWebViewConfiguration alloc] init];
  }

  _backForwardList = [[WKBackForwardList alloc] init];

  _backend = [[GSWebKitBackend backendWithConfiguration:_configuration] retain];
  if (_backend == nil) {
    NSLog(@"WKWebView: no web engine backend available");
    [self release];
    return nil;
  }
  [_backend setHost:self];
  [_backend setSize:frame.size scale:1.0];

  [self _wireScriptMessageHandlersFromController:[_configuration userContentController]];

  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  return [self initWithFrame:frame
              configuration:[[[WKWebViewConfiguration alloc] init] autorelease]];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  /* No nib serialisation support in v1; behave as default. */
  return [self initWithFrame:NSMakeRect(0, 0, 800, 600)];
}

- (void)dealloc
{
  if (_backend != nil) {
    [_backend setHost:nil];
    [_backend shutdown];
  }
  [_backend release];
  [_configuration release];
  [_backForwardList release];
  [_currentURL release];
  [_currentTitle release];
  [_customUserAgent release];
  [_currentNavigation release];
  if (_hasTrackingTag) {
    [self removeTrackingRect:_trackingTag];
    _hasTrackingTag = NO;
  }
  [_engineCursor release];
  [_mouseTargetInfo release];
  [super dealloc];
}


- (void)_wireScriptMessageHandlersFromController:(WKUserContentController *)ucc
{
  if (ucc == nil) return;
  NSEnumerator *e = [[ucc _handlers] objectEnumerator];
  _GSWKScriptHandlerRegistration *reg;
  while ((reg = [e nextObject]) != nil) {
    if ([reg->_name length] > 0) {
      [_backend registerScriptMessageHandlerName:reg->_name];
    }
  }

  NSEnumerator *se = [[ucc userScripts] objectEnumerator];
  WKUserScript *s;
  while ((s = [se nextObject]) != nil) {
    [_backend addUserScript:[s source]
              injectionTime:(NSInteger)[s injectionTime]
           forMainFrameOnly:[s isForMainFrameOnly]];
  }
}


/* ----------------------------------------------------------- NSView */

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)isOpaque
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (BOOL)becomeFirstResponder
{
  return YES;
}

- (void)setFrameSize:(NSSize)newSize
{
  [super setFrameSize:newSize];
  GSWK_TRACE("setFrameSize %.0fx%.0f", newSize.width, newSize.height);
  [_backend setSize:newSize scale:1.0];
  [self _updateTrackingArea];
}

- (void)_updateTrackingArea
{
  if (_hasTrackingTag) {
    [self removeTrackingRect:_trackingTag];
    _hasTrackingTag = NO;
  }
  if ([self window] == nil) {
    return;
  }
  _trackingTag = [self addTrackingRect:[self bounds]
                                 owner:self
                              userData:NULL
                          assumeInside:NO];
  _hasTrackingTag = YES;
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self _updateTrackingArea];
  /* AppKit only delivers -mouseMoved: when the window is opted in.
   * Without this, the tracking rect still gives us mouseEntered:
   * and mouseExited:, but motion events in between are dropped and
   * the engine never sees :hover / onmouseover / pointermove with
   * no buttons. */
  [[self window] setAcceptsMouseMovedEvents:YES];
}

- (void)mouseEntered:(NSEvent *)event
{
  /* Treat enter as a position update so the engine can fire
   * mouseenter/mouseover for whatever element is under the cursor. */
  [self mouseMoved:event];
}

- (void)mouseExited:(NSEvent *)event
{
  /* Send one final motion event far off-view so :hover / mouseleave
   * clear on the engine side.  WPE has no dedicated "exited" event,
   * but a motion event with out-of-bounds coordinates does the trick. */
  uint32_t m = [self _modifiersForEvent:event];
  uint32_t t = GSWK_TimestampFromEvent(event);
  [_backend dispatchPointerMoveAt:NSMakePoint(-1, -1)
                        modifiers:m
                        timestamp:t];
}

- (void)setFrame:(NSRect)frameRect
{
  [super setFrame:frameRect];
  GSWK_TRACE("setFrame %.0fx%.0f", frameRect.size.width, frameRect.size.height);
  [_backend setSize:frameRect.size scale:1.0];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
  [super resizeWithOldSuperviewSize:oldSize];
  NSSize cur = [self frame].size;
  GSWK_TRACE("resizeWithOldSuperviewSize old=%.0fx%.0f new=%.0fx%.0f",
             oldSize.width, oldSize.height, cur.width, cur.height);
  [_backend setSize:cur scale:1.0];
}

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  NSRect bounds = [self bounds];
  NSBitmapImageRep *rep = [_backend takeCurrentFrame];

  if (rep == nil) {
    [[NSColor whiteColor] set];
    NSRectFill(bounds);
    return;
  }

  /* Draw the bitmap at its NATIVE pixel size, anchored at the
   * top-left (we are -isFlipped).  Do not let drawInRect: scale us:
   * during a live resize, the engine has not yet produced a frame at
   * the new size, and stretching the previous frame produces the
   * distortion the user noticed.  Anything outside the bitmap (i.e.
   * while the view is growing faster than the engine can repaint) is
   * filled white so the gap is invisible. */
  NSSize bs = NSMakeSize((CGFloat)[rep pixelsWide], (CGFloat)[rep pixelsHigh]);
  if (bs.width  < bounds.size.width  - 0.5 ||
      bs.height < bounds.size.height - 0.5) {
    [[NSColor whiteColor] set];
    NSRectFill(bounds);
  }
  NSRect dst = NSMakeRect(0.0, 0.0, bs.width, bs.height);
  [rep drawInRect:dst
         fromRect:NSZeroRect
        operation:NSCompositeCopy
         fraction:1.0
   respectFlipped:YES
            hints:nil];
}


/* ------------------------------------------------- Event translation */

static uint32_t GSWK_ModsFromEvent(NSEvent *event)
{
  NSEventModifierFlags m = [event modifierFlags];
  uint32_t out = 0;
  if (m & NSEventModifierFlagControl)  out |= GS_WK_MOD_CTRL;
  if (m & NSEventModifierFlagShift)    out |= GS_WK_MOD_SHIFT;
  if (m & NSEventModifierFlagOption)   out |= GS_WK_MOD_ALT;
  if (m & NSEventModifierFlagCommand)  out |= GS_WK_MOD_META;
  return out;
}

static uint32_t GSWK_TimestampFromEvent(NSEvent *event)
{
  /* NSEvent timestamp is seconds since boot.  WPE wants milliseconds. */
  return (uint32_t)([event timestamp] * 1000.0);
}

- (NSPoint)_pointFromEvent:(NSEvent *)event
{
  NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
  return p;
}

- (uint32_t)_modifiersForEvent:(NSEvent *)event
{
  return GSWK_ModsFromEvent(event) | _pressedButtons;
}

- (void)mouseMoved:(NSEvent *)event
{
  NSPoint p = [self _pointFromEvent:event];
  uint32_t m = [self _modifiersForEvent:event];
  GSWK_TRACE("mouseMoved %.0f,%.0f mods=0x%x pressed=0x%x", p.x, p.y, m, _pressedButtons);
  [_backend dispatchPointerMoveAt:p
                        modifiers:m
                        timestamp:GSWK_TimestampFromEvent(event)];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint p = [self _pointFromEvent:event];
  uint32_t m = [self _modifiersForEvent:event];
  uint32_t t = GSWK_TimestampFromEvent(event);
  GSWK_TRACE("mouseDragged %.0f,%.0f mods=0x%x ts=%u pressed=0x%x", p.x, p.y, m, t, _pressedButtons);
  [_backend dispatchPointerMoveAt:p
                        modifiers:m
                        timestamp:t];
  /* Drag-to-select emulation.  WPE WebKit binaries are typically
   * built with ENABLE_DRAG_SUPPORT=OFF (the CMake option literally
   * says "drag actions (including selection of text with mouse)"),
   * so motion events while LEFT is held never reach
   * EventHandler::handleMouseDraggedEvent in the engine.  We
   * reconstruct the behaviour here using JS: read the current
   * selection's anchor (set by WebKit during the mousedown that began
   * the drag) and extend the focus to whatever caret is under the new
   * cursor position. */
  if (_pressedButtons & GS_WK_MOD_BUTTON1) {
    [self _extendSelectionToViewPoint:p];
  }
}

- (void)_extendSelectionToViewPoint:(NSPoint)p
{
  NSString *js = [NSString stringWithFormat:
      @"(function(x,y){"
      @"var s=window.getSelection();"
      @"if(!s||!s.anchorNode)return;"
      @"var r=(document.caretRangeFromPoint?document.caretRangeFromPoint(x,y):null);"
      @"if(!r){if(document.caretPositionFromPoint){"
      @"var cp=document.caretPositionFromPoint(x,y);"
      @"if(!cp)return;"
      @"s.setBaseAndExtent(s.anchorNode,s.anchorOffset,cp.offsetNode,cp.offset);return;}"
      @"return;}"
      @"s.setBaseAndExtent(s.anchorNode,s.anchorOffset,r.startContainer,r.startOffset);"
      @"})(%d,%d);",
      (int)p.x, (int)p.y];
  [_backend evaluateJavaScript:js completion:NULL];
}

- (void)rightMouseDragged:(NSEvent *)event
{
  [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
  [self mouseMoved:event];
}

- (uint32_t)_buttonBitFor:(int)button
{
  switch (button) {
    case 1: return GS_WK_MOD_BUTTON1;
    case 2: return GS_WK_MOD_BUTTON2;
    case 3: return GS_WK_MOD_BUTTON3;
    default: return 0;
  }
}

- (void)_dispatchButton:(int)button pressed:(BOOL)pressed event:(NSEvent *)event
{
  uint32_t bit = [self _buttonBitFor:button];
  if (pressed) {
    _pressedButtons |= bit;
  } else {
    _pressedButtons &= ~bit;
  }
  NSPoint p = [self _pointFromEvent:event];
  uint32_t m = [self _modifiersForEvent:event];
  uint32_t t = GSWK_TimestampFromEvent(event);
  GSWK_TRACE("button=%d pressed=%d at %.0f,%.0f mods=0x%x ts=%u", button, pressed, p.x, p.y, m, t);
  [_backend dispatchPointerButton:button
                          pressed:pressed
                               at:p
                        modifiers:m
                        timestamp:t];
}

- (void)mouseDown:(NSEvent *)event
{
  [[self window] makeFirstResponder:self];
  [self _dispatchButton:1 pressed:YES event:event];
}

- (void)mouseUp:(NSEvent *)event
{
  [self _dispatchButton:1 pressed:NO event:event];
}

- (void)rightMouseDown:(NSEvent *)event
{
  /* Show our own context menu instead of forwarding to the engine.
   * WPE WebKit's context-menu support is GTK-widget-shaped and not
   * trivially adaptable to NSMenu, so we offer a minimal Apple-style
   * menu (Copy / Cut / Paste / Reload) sourced from our own
   * NSPasteboard bridge.  The mousedown is not forwarded to WPE. */
  [[self window] makeFirstResponder:self];
  NSMenu *menu = [self _makeContextMenu];
  if (menu != nil) {
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
  }
}

- (void)rightMouseUp:(NSEvent *)event
{
  (void)event;
}

- (NSMenu *)_makeContextMenu
{
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
  NSDictionary *info = _mouseTargetInfo;
  BOOL isLink     = [[info objectForKey:GSWebKitMouseTargetIsLink] boolValue];
  BOOL isImage    = [[info objectForKey:GSWebKitMouseTargetIsImage] boolValue];
  BOOL isEditable = [[info objectForKey:GSWebKitMouseTargetIsEditable] boolValue];
  BOOL isSelection= [[info objectForKey:GSWebKitMouseTargetIsSelection] boolValue];

  void (^addItem)(NSString *, SEL) = ^(NSString *title, SEL action) {
    NSMenuItem *it = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    [it setTarget:self];
  };

  if (isLink) {
    addItem(@"Open Link in New Window", @selector(_contextOpenLinkInNewWindow:));
    addItem(@"Copy Link", @selector(_contextCopyLink:));
    [menu addItem:[NSMenuItem separatorItem]];
  }
  if (isImage) {
    addItem(@"Open Image in New Window", @selector(_contextOpenImageInNewWindow:));
    addItem(@"Copy Image URL", @selector(_contextCopyImageURL:));
    [menu addItem:[NSMenuItem separatorItem]];
  }
  if (isEditable) {
    addItem(@"Cut", @selector(_contextCut:));
    addItem(@"Copy", @selector(_contextCopy:));
    addItem(@"Paste", @selector(_contextPaste:));
    [menu addItem:[NSMenuItem separatorItem]];
  } else if (isSelection) {
    addItem(@"Copy", @selector(_contextCopy:));
    [menu addItem:[NSMenuItem separatorItem]];
  }
  /* Always-available actions */
  addItem(@"Reload", @selector(_contextReload:));
  addItem(@"Back", @selector(_contextBack:));
  addItem(@"Forward", @selector(_contextForward:));
  return menu;
}

- (void)_contextCut:(id)sender   { (void)sender; [self _performCutToPasteboard]; }
- (void)_contextCopy:(id)sender  { (void)sender; [self _performCopyToPasteboard]; }
- (void)_contextPaste:(id)sender { (void)sender; [self _performPasteFromPasteboard]; }
- (void)_contextReload:(id)sender { (void)sender; [self reload]; }
- (void)_contextBack:(id)sender { (void)sender; [self goBack]; }
- (void)_contextForward:(id)sender { (void)sender; [self goForward]; }

- (void)_contextCopyLink:(id)sender
{
  (void)sender;
  NSString *url = [_mouseTargetInfo objectForKey:GSWebKitMouseTargetLinkURL];
  if ([url length] == 0) return;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
  [pb setString:url forType:NSStringPboardType];
}

- (void)_contextCopyImageURL:(id)sender
{
  (void)sender;
  NSString *url = [_mouseTargetInfo objectForKey:GSWebKitMouseTargetImageURL];
  if ([url length] == 0) return;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
  [pb setString:url forType:NSStringPboardType];
}

- (void)_contextOpenLinkInNewWindow:(id)sender
{
  (void)sender;
  NSString *url = [_mouseTargetInfo objectForKey:GSWebKitMouseTargetLinkURL];
  if ([url length] == 0) return;
  [self _openInNewWindow:url];
}

- (void)_contextOpenImageInNewWindow:(id)sender
{
  (void)sender;
  NSString *url = [_mouseTargetInfo objectForKey:GSWebKitMouseTargetImageURL];
  if ([url length] == 0) return;
  [self _openInNewWindow:url];
}

- (void)_openInNewWindow:(NSString *)urlString
{
  /* Delegate to UIDelegate's createWebViewWithConfiguration:... if
   * present; otherwise fall back to loading the URL in this view. */
  WKWebViewConfiguration *cfg = [[_configuration copy] autorelease];
  if ([_UIDelegate respondsToSelector:
          @selector(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)]) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) return;
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    WKNavigationAction *act =
        [[[WKNavigationAction alloc] _initWithRequest:req
                                       navigationType:WKNavigationTypeLinkActivated
                                          sourceFrame:nil
                                          targetFrame:nil] autorelease];
    WKWebView *newView = [_UIDelegate webView:self
                createWebViewWithConfiguration:cfg
                           forNavigationAction:act
                                windowFeatures:nil];
    if (newView != nil) {
      [newView loadRequest:req];
      return;
    }
  }
  /* Fallback */
  NSURL *url = [NSURL URLWithString:urlString];
  if (url == nil) return;
  [self loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)otherMouseDown:(NSEvent *)event
{
  [self _dispatchButton:2 pressed:YES event:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
  [self _dispatchButton:2 pressed:NO event:event];
}

- (void)scrollWheel:(NSEvent *)event
{
  /* AppKit deltas are in lines/points with arbitrary scaling.  We feed
   * them through roughly 1:1 — refine if needed. */
  CGFloat dx = [event deltaX];
  CGFloat dy = [event deltaY];
  [_backend dispatchScrollAt:[self _pointFromEvent:event]
                      deltaX:(double)(dx * 20.0)
                      deltaY:(double)(dy * 20.0)
                   modifiers:GSWK_ModsFromEvent(event)
                   timestamp:GSWK_TimestampFromEvent(event)];
}

static uint32_t GSWK_KeysymFromEvent(NSEvent *event)
{
  NSString *chars = [event charactersIgnoringModifiers];
  if ([chars length] == 0) {
    return 0;
  }
  unichar c = [chars characterAtIndex:0];
  switch (c) {
    case NSUpArrowFunctionKey:    return GS_WKKEY_Up;
    case NSDownArrowFunctionKey:  return GS_WKKEY_Down;
    case NSLeftArrowFunctionKey:  return GS_WKKEY_Left;
    case NSRightArrowFunctionKey: return GS_WKKEY_Right;
    case NSPageUpFunctionKey:     return GS_WKKEY_PageUp;
    case NSPageDownFunctionKey:   return GS_WKKEY_PageDown;
    case NSHomeFunctionKey:       return GS_WKKEY_Home;
    case NSEndFunctionKey:        return GS_WKKEY_End;
    case NSDeleteCharacter:       /* 0x7f, Apple's "delete" key */
    case 0x08:                    return GS_WKKEY_BackSpace;
    case 0x09:                    return GS_WKKEY_Tab;
    case 0x0d:
    case 0x03:                    return GS_WKKEY_Return;
    case 0x1b:                    return GS_WKKEY_Escape;
    case NSDeleteFunctionKey:     return GS_WKKEY_Delete;
    case NSInsertFunctionKey:     return GS_WKKEY_Insert;
    case NSF1FunctionKey:  case NSF2FunctionKey:  case NSF3FunctionKey:
    case NSF4FunctionKey:  case NSF5FunctionKey:  case NSF6FunctionKey:
    case NSF7FunctionKey:  case NSF8FunctionKey:  case NSF9FunctionKey:
    case NSF10FunctionKey: case NSF11FunctionKey: case NSF12FunctionKey:
      return GS_WKKEY_F1 + (uint32_t)(c - NSF1FunctionKey);
    default:
      /* Printable ASCII: keysym == ASCII. */
      if (c >= 0x20 && c < 0x7f) {
        return (uint32_t)c;
      }
      /* Non-ASCII Unicode: X11 keysyms in the range 0x01000100..
       * 0x0110FFFF are direct Unicode codepoints (X11R6+ convention).
       * Lets users type accented Latin, Cyrillic, Greek etc.
       * without an IME.  CJK preedit composition still needs
       * NSTextInputClient + WebKitInputMethodContext plumbing. */
      if (c >= 0x80 && c < NSF1FunctionKey) {
        return 0x01000000u | (uint32_t)c;
      }
      return 0;
  }
}

- (void)keyDown:(NSEvent *)event
{
  /* Ctrl+V / Ctrl+C / Ctrl+X are intercepted and bridged to
   * NSPasteboard, because Debian's libwpewebkit ships without a
   * working pasteboard backend (libwpe's _wpe_pasteboard_interface
   * isn't exported by WPEBackend-FDO).  The engine's built-in
   * paste/copy/cut paths would otherwise see an empty clipboard. */
  NSString *raw = [event characters];
  NSEventModifierFlags mods = [event modifierFlags];
  unichar c = [raw length] > 0 ? [raw characterAtIndex:0] : 0;
  GSWK_TRACE("keyDown chars=%@ char0=0x%x mods=0x%lx",
             raw, (unsigned)c, (unsigned long)mods);
  /* Match either Ctrl or Cmd, since Apple convention is Cmd-V while
   * Linux/GNUstep users press Ctrl-V. */
  BOOL clipModifier = (mods & NSEventModifierFlagControl)
                   || (mods & NSEventModifierFlagCommand);
  if (clipModifier && (c == 'v' || c == 'V' || c == 22)) {
    [self _performPasteFromPasteboard];
    return;
  }
  if (clipModifier && (c == 'c' || c == 'C' || c == 3)) {
    [self _performCopyToPasteboard];
    return;
  }
  if (clipModifier && (c == 'x' || c == 'X' || c == 24)) {
    [self _performCutToPasteboard];
    return;
  }

  uint32_t keysym = GSWK_KeysymFromEvent(event);
  if (keysym != 0) {
    [_backend dispatchKeyCode:keysym
                       pressed:YES
                     modifiers:GSWK_ModsFromEvent(event)
                     timestamp:GSWK_TimestampFromEvent(event)];
  }
}

/* Standard responder-chain selectors so Edit-menu items wired with
 * cut: / copy: / paste: routes also use our clipboard plumbing. */
- (void)cut:(id)sender   { (void)sender; [self _performCutToPasteboard]; }
- (void)copy:(id)sender  { (void)sender; [self _performCopyToPasteboard]; }
- (void)paste:(id)sender { (void)sender; [self _performPasteFromPasteboard]; }

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  /* Always enable Cut / Copy / Paste while this view is focused. */
  SEL action = [item action];
  if (action == @selector(cut:) || action == @selector(copy:)
      || action == @selector(paste:)) {
    return YES;
  }
  return YES;
}

- (void)_performPasteFromPasteboard
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  NSArray *types = [pb types];
  NSString *text = [pb stringForType:NSStringPboardType];
  fprintf(stderr, "WKWV paste: types=%s textLen=%lu\n",
          [[types description] UTF8String] ?: "(nil)",
          (unsigned long)[text length]);
  fflush(stderr);
  if ([text length] == 0) {
    /* Fallback: NSPasteboard via gpbs might be out of sync with the
     * X11 CLIPBOARD selection (different selection-owner timing in
     * X11/Wayland mixed setups).  Read CLIPBOARD directly via xclip
     * as a last resort. */
    text = [self _readX11ClipboardFallback];
    fprintf(stderr, "WKWV paste fallback len=%lu\n", (unsigned long)[text length]);
    fflush(stderr);
    if ([text length] == 0) return;
  }
  /* Encode the text as a JS string literal.  JSON.stringify on a
   * temporary array gives us reliable escaping. */
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[NSArray arrayWithObject:text]
                                                     options:0
                                                       error:NULL];
  NSString *jsonArr = [[[NSString alloc] initWithData:jsonData
                                              encoding:NSUTF8StringEncoding] autorelease];
  /* Strip the wrapping [ and ] to leave just the JS-escaped string. */
  if ([jsonArr length] < 2) return;
  NSString *jsString = [jsonArr substringWithRange:NSMakeRange(1, [jsonArr length] - 2)];

  NSString *js = [NSString stringWithFormat:
      @"(function(t){"
      @"var el=document.activeElement;"
      @"if(!el)return false;"
      @"var tag=(el.tagName||'').toUpperCase();"
      @"if(tag==='INPUT'||tag==='TEXTAREA'){"
        @"var s=el.selectionStart,e=el.selectionEnd;"
        @"if(s==null){s=el.value.length;e=el.value.length;}"
        @"el.value=el.value.slice(0,s)+t+el.value.slice(e);"
        @"el.selectionStart=el.selectionEnd=s+t.length;"
        @"el.dispatchEvent(new Event('input',{bubbles:true}));"
        @"el.dispatchEvent(new Event('change',{bubbles:true}));"
        @"return true;"
      @"}"
      @"return document.execCommand('insertText',false,t);"
      @"})(%@);", jsString];
  [_backend evaluateJavaScript:js completion:NULL];
}

- (void)_performCopyToPasteboard
{
  [_backend evaluateJavaScript:
      @"(function(){"
      @"var el=document.activeElement,tag=(el&&el.tagName||'').toUpperCase();"
      @"if(tag==='INPUT'||tag==='TEXTAREA'){"
        @"return el.value.substring(el.selectionStart,el.selectionEnd);"
      @"}"
      @"return window.getSelection().toString();"
      @"})();"
            completion:^(id result, NSError *err) {
    if (err != nil || ![result isKindOfClass:[NSString class]]) return;
    NSString *text = result;
    if ([text length] == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:text forType:NSStringPboardType];
  }];
}

- (NSString *)_readX11ClipboardFallback
{
  /* Shell out to xclip; cheap, single-shot, and avoids us implementing
   * the X11 selection protocol in-process.  If xclip is missing or
   * the selection is empty, returns nil/empty. */
  NSTask *task = [[[NSTask alloc] init] autorelease];
  [task setLaunchPath:@"/usr/bin/xclip"];
  [task setArguments:[NSArray arrayWithObjects:@"-selection", @"clipboard", @"-o", nil]];
  NSPipe *out = [NSPipe pipe];
  [task setStandardOutput:out];
  [task setStandardError:[NSPipe pipe]];
  NS_DURING
    [task launch];
    [task waitUntilExit];
  NS_HANDLER
    return nil;
  NS_ENDHANDLER
  NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
  if ([data length] == 0) return nil;
  return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (void)_performCutToPasteboard
{
  [_backend evaluateJavaScript:
      @"(function(){"
      @"var el=document.activeElement,tag=(el&&el.tagName||'').toUpperCase();"
      @"var t='';"
      @"if(tag==='INPUT'||tag==='TEXTAREA'){"
        @"var s=el.selectionStart,e=el.selectionEnd;"
        @"t=el.value.substring(s,e);"
        @"if(t){el.value=el.value.slice(0,s)+el.value.slice(e);"
        @"el.selectionStart=el.selectionEnd=s;"
        @"el.dispatchEvent(new Event('input',{bubbles:true}));"
        @"el.dispatchEvent(new Event('change',{bubbles:true}));}"
      @"}else{"
        @"t=window.getSelection().toString();"
        @"if(t)document.execCommand('delete');"
      @"}"
      @"return t;"
      @"})();"
            completion:^(id result, NSError *err) {
    if (err != nil || ![result isKindOfClass:[NSString class]]) return;
    NSString *text = result;
    if ([text length] == 0) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:text forType:NSStringPboardType];
  }];
}

- (void)keyUp:(NSEvent *)event
{
  uint32_t keysym = GSWK_KeysymFromEvent(event);
  if (keysym != 0) {
    [_backend dispatchKeyCode:keysym
                       pressed:NO
                     modifiers:GSWK_ModsFromEvent(event)
                     timestamp:GSWK_TimestampFromEvent(event)];
  }
}

/* Modifier-only keypresses (Shift, Control, Alt) don't produce
 * -keyDown:/-keyUp: events; they come through -flagsChanged: instead.
 * Some web content (game keyboard handlers, IME triggers, modifier-
 * aware shortcut detection) needs to see these as key events.
 *
 * Note: do not override -performKeyEquivalent: here.  When this view
 * is the first responder, AppKit also routes the keyDown: path to us
 * for menu key-equivalents like Cmd+V; intercepting flagsChanged is
 * safe but we must explicitly fall through to super for menu
 * key-equivalent matching. */
- (void)flagsChanged:(NSEvent *)event
{
  static NSEventModifierFlags prevMods = 0;
  NSEventModifierFlags now = [event modifierFlags];
  NSEventModifierFlags changed = now ^ prevMods;
  uint32_t timestamp = GSWK_TimestampFromEvent(event);
  uint32_t mods = GSWK_ModsFromEvent(event);

  struct { NSEventModifierFlags flag; uint32_t keysym; } table[] = {
    { NSEventModifierFlagShift,   GS_WKKEY_Shift_L },
    { NSEventModifierFlagControl, GS_WKKEY_Control_L },
    { NSEventModifierFlagOption,  GS_WKKEY_Alt_L },
    { NSEventModifierFlagCommand, GS_WKKEY_Meta_L },
  };
  for (unsigned i = 0; i < sizeof(table)/sizeof(table[0]); i++) {
    if (changed & table[i].flag) {
      BOOL pressed = (now & table[i].flag) != 0;
      [_backend dispatchKeyCode:table[i].keysym
                        pressed:pressed
                      modifiers:mods
                      timestamp:timestamp];
    }
  }
  prevMods = now;
  /* Ensure the event continues up the responder chain so AppKit's
   * menu-key-equivalent matching for Cmd+C / Cmd+V still runs. */
  [super flagsChanged:event];
}


/* ----------------------------------------------------------- Loading */

- (WKNavigation *)_makeNavigationForRequest:(NSURLRequest *)request
{
  uint64_t ident = ++_navigationCounter;
  [_currentNavigation release];
  _currentNavigation = [[WKNavigation alloc] _initWithRequest:request
                                                    identifier:ident];
  return _currentNavigation;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request
{
  if (request == nil) return nil;
  WKNavigation *nav = [self _makeNavigationForRequest:request];
  [_backend loadURL:[request URL]];
  return nav;
}

- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
  if (string == nil) return nil;
  NSURLRequest *fakeReq = (baseURL != nil)
      ? [NSURLRequest requestWithURL:baseURL]
      : nil;
  WKNavigation *nav = [self _makeNavigationForRequest:fakeReq];
  [_backend loadHTMLString:string baseURL:baseURL];
  return nav;
}

- (WKNavigation *)loadData:(NSData *)data
                  MIMEType:(NSString *)MIMEType
     characterEncodingName:(NSString *)characterEncodingName
                   baseURL:(NSURL *)baseURL
{
  /* Falls back to load-html if MIME type is HTML-ish; otherwise data:
   * URL.  Good enough for v1. */
  if ([MIMEType hasPrefix:@"text/html"] || [MIMEType hasPrefix:@"application/xhtml"]) {
    NSStringEncoding enc = NSUTF8StringEncoding;
    if ([characterEncodingName length] > 0) {
      NSString *lc = [characterEncodingName lowercaseString];
      if ([lc isEqualToString:@"utf-8"] || [lc isEqualToString:@"utf8"]) {
        enc = NSUTF8StringEncoding;
      } else if ([lc isEqualToString:@"utf-16"] || [lc isEqualToString:@"utf16"]) {
        enc = NSUTF16StringEncoding;
      } else if ([lc isEqualToString:@"iso-8859-1"]
                 || [lc isEqualToString:@"latin1"]) {
        enc = NSISOLatin1StringEncoding;
      } else if ([lc isEqualToString:@"us-ascii"] || [lc isEqualToString:@"ascii"]) {
        enc = NSASCIIStringEncoding;
      }
      /* Unrecognised encoding names fall through to UTF-8 which is the
       * web's overwhelmingly dominant case. */
    }
    NSString *html = [[[NSString alloc] initWithData:data encoding:enc] autorelease];
    return [self loadHTMLString:html baseURL:baseURL];
  }
  NSString *b64 = [data base64EncodedStringWithOptions:0];
  NSString *uri = [NSString stringWithFormat:@"data:%@;base64,%@", MIMEType, b64];
  NSURL    *url = [NSURL URLWithString:uri];
  return [self loadRequest:[NSURLRequest requestWithURL:url]];
}

- (WKNavigation *)loadFileURL:(NSURL *)URL
        allowingReadAccessToURL:(NSURL *)readAccessURL
{
  (void)readAccessURL;
  return [self loadRequest:[NSURLRequest requestWithURL:URL]];
}

- (WKNavigation *)reload
{
  [_backend reload];
  return [self _makeNavigationForRequest:nil];
}

- (WKNavigation *)reloadFromOrigin
{
  [_backend reloadFromOrigin];
  return [self _makeNavigationForRequest:nil];
}

- (void)stopLoading
{
  [_backend stopLoading];
}

- (BOOL)canGoBack
{
  return [_backend canGoBack];
}

- (BOOL)canGoForward
{
  return [_backend canGoForward];
}

- (WKNavigation *)goBack
{
  if (![self canGoBack]) return nil;
  [_backend goBack];
  return [self _makeNavigationForRequest:nil];
}

- (WKNavigation *)goForward
{
  if (![self canGoForward]) return nil;
  [_backend goForward];
  return [self _makeNavigationForRequest:nil];
}

- (WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item
{
  /* v1 does not support arbitrary list-item navigation through the
   * WPE bridge; honour the call by treating it as no-op. */
  (void)item;
  return nil;
}


/* ----------------------------------------------------------- Eval JS */

- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^)(id, NSError *))completionHandler
{
  [_backend evaluateJavaScript:javaScriptString completion:completionHandler];
}

- (void)evaluateJavaScript:(NSString *)javaScriptString
                   inFrame:(WKFrameInfo *)frame
            inContentWorld:(WKContentWorld *)contentWorld
         completionHandler:(void (^)(id, NSError *))completionHandler
{
  /* Frame/world targeting is not yet propagated to the WPE backend; we
   * always evaluate in the page world's main frame. */
  (void)frame; (void)contentWorld;
  [_backend evaluateJavaScript:javaScriptString completion:completionHandler];
}

- (void)takeSnapshotWithConfiguration:(WKSnapshotConfiguration *)config
                     completionHandler:(void (^)(NSImage *, NSError *))completionHandler
{
  (void)config;
  /* Use the latest frame the engine has delivered.  This is roughly
   * equivalent to Apple's takeSnapshot with snapshotConfiguration=nil,
   * which captures the visible viewport.  WPE has no API to capture a
   * specific page region, so the config's rect / snapshotWidth are
   * ignored; document this in the framework reference. */
  NSBitmapImageRep *rep = [_backend takeCurrentFrame];
  if (rep == nil) {
    if (completionHandler) completionHandler(nil,
        [NSError errorWithDomain:WKErrorDomain code:WKErrorUnknown
                        userInfo:[NSDictionary dictionaryWithObject:@"No frame available yet"
                                                             forKey:NSLocalizedDescriptionKey]]);
    return;
  }
  NSImage *img = [[[NSImage alloc] init] autorelease];
  [img addRepresentation:rep];
  if (completionHandler) completionHandler(img, nil);
}

- (void)createPDFWithConfiguration:(WKPDFConfiguration *)config
                  completionHandler:(void (^)(NSData *, NSError *))completionHandler
{
  (void)config;
  /* WPE WebKit doesn't expose PDF rendering in its public API (it's a
   * GTK-port-only feature in 2.48).  Report not-supported. */
  NSError *err = [NSError errorWithDomain:WKErrorDomain
                                     code:WKErrorUnknown
                                 userInfo:[NSDictionary dictionaryWithObject:
                                            @"PDF export is not supported by the WPE backend"
                                                                       forKey:NSLocalizedDescriptionKey]];
  if (completionHandler) completionHandler(nil, err);
}

- (NSPrintOperation *)printOperationWithPrintInfo:(NSPrintInfo *)printInfo
{
  (void)printInfo;
  /* Same situation as PDF.  Returning nil is the documented
   * not-supported answer; callers should check and degrade
   * gracefully. */
  return nil;
}

- (void)findString:(NSString *)string
     configuration:(WKFindConfiguration *)configuration
 completionHandler:(void (^)(WKFindResult *))completionHandler
{
  BOOL backwards     = [configuration backwards];
  BOOL caseSensitive = [configuration caseSensitive];
  BOOL wraps         = (configuration != nil) ? [configuration wraps] : YES;
  [_backend findString:string
             backwards:backwards
         caseSensitive:caseSensitive
                 wraps:wraps
            completion:^(BOOL matchFound) {
    if (completionHandler != NULL) {
      WKFindResult *r = [[[WKFindResult alloc] _initWithMatchFound:matchFound] autorelease];
      completionHandler(r);
    }
  }];
}


/* ----------------------------------------------------------- UA */

- (void)setCustomUserAgent:(NSString *)ua
{
  if (ua == _customUserAgent) return;
  [_customUserAgent release];
  _customUserAgent = [ua copy];
  [_backend setCustomUserAgent:ua];
}

- (void)setPageZoom:(CGFloat)zoom
{
  [_backend setPageZoom:zoom];
}

- (CGFloat)pageZoom
{
  return [_backend pageZoom];
}


/* ----------------------------------------- Backend host callbacks */

- (void)backendFrameDidChange:(GSWebKitBackend *)backend
{
  (void)backend;
  [self setNeedsDisplay:YES];
}

- (void)backendDidStartProvisionalNavigation:(GSWebKitBackend *)backend
{
  (void)backend;
  if ([_navigationDelegate respondsToSelector:
          @selector(webView:didStartProvisionalNavigation:)]) {
    [_navigationDelegate webView:self
        didStartProvisionalNavigation:_currentNavigation];
  }
}

- (void)backendDidCommitNavigation:(GSWebKitBackend *)backend
{
  (void)backend;
  /* Append committed URL to back-forward list. */
  NSURL *url = [_backend currentURL];
  if (url != nil) {
    WKBackForwardListItem *item =
        [[[WKBackForwardListItem alloc] _initWithURL:url
                                          initialURL:url
                                               title:_currentTitle] autorelease];
    [_backForwardList _appendItem:item];
  }
  if ([_navigationDelegate respondsToSelector:
          @selector(webView:didCommitNavigation:)]) {
    [_navigationDelegate webView:self didCommitNavigation:_currentNavigation];
  }
}

- (void)backendDidFinishNavigation:(GSWebKitBackend *)backend
{
  (void)backend;
  if ([_navigationDelegate respondsToSelector:
          @selector(webView:didFinishNavigation:)]) {
    [_navigationDelegate webView:self didFinishNavigation:_currentNavigation];
  }
}

- (void)backend:(GSWebKitBackend *)backend
    didFailNavigationWithError:(NSError *)error
                   provisional:(BOOL)provisional
{
  (void)backend;
  if (provisional) {
    if ([_navigationDelegate respondsToSelector:
            @selector(webView:didFailProvisionalNavigation:withError:)]) {
      [_navigationDelegate webView:self
            didFailProvisionalNavigation:_currentNavigation
                                withError:error];
    }
  } else {
    if ([_navigationDelegate respondsToSelector:
            @selector(webView:didFailNavigation:withError:)]) {
      [_navigationDelegate webView:self
                  didFailNavigation:_currentNavigation
                          withError:error];
    }
  }
}

- (void)backend:(GSWebKitBackend *)backend didChangeTitle:(NSString *)title
{
  (void)backend;
  if (title == _currentTitle) return;
  [self willChangeValueForKey:@"title"];
  [_currentTitle release];
  _currentTitle = [title copy];
  [self didChangeValueForKey:@"title"];
}

- (void)backend:(GSWebKitBackend *)backend didChangeURL:(NSURL *)url
{
  (void)backend;
  if ([url isEqual:_currentURL]) return;
  [self willChangeValueForKey:@"URL"];
  [_currentURL release];
  _currentURL = [url copy];
  [self didChangeValueForKey:@"URL"];
}

- (void)backend:(GSWebKitBackend *)backend
    didChangeEstimatedProgress:(double)progress
{
  (void)backend;
  if (progress == _estimatedProgress) return;
  [self willChangeValueForKey:@"estimatedProgress"];
  _estimatedProgress = progress;
  [self didChangeValueForKey:@"estimatedProgress"];
}

- (void)backend:(GSWebKitBackend *)backend didChangeIsLoading:(BOOL)isLoading
{
  (void)backend;
  if (isLoading == _isLoading) return;
  [self willChangeValueForKey:@"loading"];
  _isLoading = isLoading;
  [self didChangeValueForKey:@"loading"];
}

- (void)backendDidChangeBackForwardList:(GSWebKitBackend *)backend
{
  (void)backend;
}

- (void)backend:(GSWebKitBackend *)backend
        didChangeMouseTargetInfo:(NSDictionary *)info
{
  (void)backend;
  if (info == _mouseTargetInfo) return;
  [_mouseTargetInfo release];
  _mouseTargetInfo = [info copy];
}

- (void)backend:(GSWebKitBackend *)backend didChangeMouseCursor:(NSString *)token
{
  (void)backend;
  NSCursor *c;
  if ([token isEqualToString:@"pointer"]) {
    c = [NSCursor pointingHandCursor];
  } else if ([token isEqualToString:@"text"]) {
    c = [NSCursor IBeamCursor];
  } else {
    c = [NSCursor arrowCursor];
  }
  [_engineCursor release];
  _engineCursor = [c retain];
  [c set];
  /* Force AppKit to refresh its idea of the cursor rect for the next
   * mouse-move. */
  [[self window] invalidateCursorRectsForView:self];
}

/* Accessibility -----------------------------------------------------
 *
 * GNUstep's NSAccessibility surface is minimal in 0.32 — no NSView
 * role/attribute methods, no NSAccessibility protocol, no
 * NSAccessibilityWebAreaRole constant.  A meaningful implementation
 * would have to:
 *
 *   1. Bridge WebKit's accessibility tree (AT-SPI internally) into
 *      NSAccessibility, including incremental notifications for
 *      focus / value / structure changes.
 *   2. Surface heading / landmark / link roles from the page's
 *      ARIA so screen readers can navigate.
 *
 * Both are substantial enough to be their own project.  The stub
 * below is a single AT-SPI-compatible hint: -[NSView accessibilityRole]
 * (when GNUstep adds it) should report a web-content role so
 * assistive tech doesn't treat us as a generic group.  Until then
 * this is just a documentation anchor for a future contributor.
 */
- (NSString *)accessibilityRoleDescription
{
  return @"web content";
}

- (void)resetCursorRects
{
  if (_engineCursor != nil) {
    [self addCursorRect:[self visibleRect] cursor:_engineCursor];
  }
}

- (void)cursorUpdate:(NSEvent *)event
{
  (void)event;
  if (_engineCursor != nil) {
    [_engineCursor set];
  }
}

- (void)backend:(GSWebKitBackend *)backend
        didReceiveScriptMessageWithName:(NSString *)name
                                   body:(id)body
{
  (void)backend;
  WKUserContentController *ucc = [_configuration userContentController];
  if (ucc == nil) return;
  NSEnumerator *e = [[ucc _handlers] objectEnumerator];
  _GSWKScriptHandlerRegistration *reg;
  while ((reg = [e nextObject]) != nil) {
    if (![reg->_name isEqualToString:name]) {
      continue;
    }
    id <WKScriptMessageHandler> handler = reg->_handler;
    if (![handler respondsToSelector:
            @selector(userContentController:didReceiveScriptMessage:)]) {
      break;
    }
    WKContentWorld *world = reg->_world ?: [WKContentWorld pageWorld];
    NSString *scheme = [_currentURL scheme] ?: @"";
    NSString *host   = [_currentURL host]   ?: @"";
    WKSecurityOrigin *origin =
        [[[WKSecurityOrigin alloc] _initWithProtocol:scheme
                                                host:host
                                                port:0] autorelease];
    WKFrameInfo *frame =
        [[[WKFrameInfo alloc] _initWithMainFrame:YES
                                           request:nil
                                    securityOrigin:origin
                                           webView:self] autorelease];
    WKScriptMessage *msg =
        [[[WKScriptMessage alloc] _initWithName:name
                                            body:body
                                         webView:self
                                       frameInfo:frame
                                           world:world] autorelease];
    [handler userContentController:ucc didReceiveScriptMessage:msg];
    break;
  }
}


/* UI delegate alert/confirm/prompt fallback windows.  If the embedder
 * provides a UIDelegate that implements the runJavaScript* methods we
 * forward to it; otherwise we drive synchronous NSAlert/NSAlert prompt
 * panels. */

- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptAlertWithMessage:(NSString *)message
                       completion:(void (^)(void))completion
{
  (void)backend;
  if ([_UIDelegate respondsToSelector:
          @selector(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)]) {
    [_UIDelegate webView:self
        runJavaScriptAlertPanelWithMessage:message
                          initiatedByFrame:[self _mainFrameInfo]
                         completionHandler:completion];
    return;
  }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"JavaScript"];
  [alert setInformativeText:message ?: @""];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  if (completion) completion();
}

- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptConfirmWithMessage:(NSString *)message
                         completion:(void (^)(BOOL))completion
{
  (void)backend;
  if ([_UIDelegate respondsToSelector:
          @selector(webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:)]) {
    [_UIDelegate webView:self
        runJavaScriptConfirmPanelWithMessage:message
                            initiatedByFrame:[self _mainFrameInfo]
                           completionHandler:completion];
    return;
  }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"JavaScript"];
  [alert setInformativeText:message ?: @""];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  NSModalResponse r = [alert runModal];
  if (completion) completion(r == NSAlertFirstButtonReturn);
}

- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptPromptWithMessage:(NSString *)message
                        defaultText:(NSString *)defaultText
                         completion:(void (^)(NSString *))completion
{
  (void)backend;
  if ([_UIDelegate respondsToSelector:
          @selector(webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:)]) {
    [_UIDelegate webView:self
        runJavaScriptTextInputPanelWithPrompt:message
                                  defaultText:defaultText
                             initiatedByFrame:[self _mainFrameInfo]
                            completionHandler:completion];
    return;
  }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"JavaScript"];
  [alert setInformativeText:message ?: @""];
  NSTextField *field = [[[NSTextField alloc]
      initWithFrame:NSMakeRect(0, 0, 280, 24)] autorelease];
  [field setStringValue:defaultText ?: @""];
  [alert setAccessoryView:field];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  NSModalResponse r = [alert runModal];
  if (completion) {
    completion((r == NSAlertFirstButtonReturn) ? [field stringValue] : nil);
  }
}

- (void)backend:(GSWebKitBackend *)backend
    didStartDownloadOfFilename:(NSString *)suggestedFilename
                       response:(NSURLResponse *)response
                     completion:(void (^)(NSURL *destinationURL))completion
{
  (void)backend; (void)response;
  NSSavePanel *panel = [NSSavePanel savePanel];
  [panel setNameFieldStringValue:suggestedFilename ?: @"download"];
  NSInteger result = [panel runModal];
  if (result == NSOKButton) {
    completion([panel URL]);
  } else {
    completion(nil);
  }
}

- (void)backend:(GSWebKitBackend *)backend
    didFinishDownloadToURL:(NSURL *)destinationURL
{
  (void)backend; (void)destinationURL;
}

- (void)backend:(GSWebKitBackend *)backend
    didFailDownloadWithError:(NSError *)error
                  destination:(NSURL *)destinationURL
{
  (void)backend; (void)destinationURL;
  NSLog(@"WKWebView: download failed: %@", [error localizedDescription]);
}

- (void)backend:(GSWebKitBackend *)backend
    runFileChooserAllowingMultiple:(BOOL)allowMultiple
                          mimeTypes:(NSArray *)mimeTypes
                         completion:(void (^)(NSArray *fileURLs))completion
{
  (void)backend; (void)mimeTypes;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:NO];
  [panel setAllowsMultipleSelection:allowMultiple];
  /* WPE gives us a list of mime types like "image/png"; mapping mime
   * types to NSOpenPanel.allowedFileTypes (which wants file
   * extensions) is non-trivial.  v1 leaves the filter unset, which
   * matches Safari's behaviour for unknown content-types. */
  NSInteger result = [panel runModal];
  if (result == NSOKButton) {
    completion([panel URLs]);
  } else {
    completion(nil);
  }
}

- (WKFrameInfo *)_mainFrameInfo
{
  NSString *scheme = [_currentURL scheme] ?: @"";
  NSString *host   = [_currentURL host]   ?: @"";
  WKSecurityOrigin *origin =
      [[[WKSecurityOrigin alloc] _initWithProtocol:scheme
                                              host:host
                                              port:0] autorelease];
  return [[[WKFrameInfo alloc] _initWithMainFrame:YES
                                           request:nil
                                    securityOrigin:origin
                                           webView:self] autorelease];
}

@end
