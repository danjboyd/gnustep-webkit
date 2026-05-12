/* GSWebKitWPE.m
 *
 * WPE WebKit backend.  Bridges:
 *   - WebKitWebView (UI process API in libWPEWebKit)
 *   - wpe_view_backend_exportable_fdo (libWPEBackend-fdo) for rendering
 *     and input.
 *   - GLib main context, pumped from the AppKit run loop via NSTimer.
 *
 * Threading model
 * ---------------
 * Everything in this file is intended to run on the AppKit main
 * thread.  The GLib main context is driven by -pumpGLib: which is
 * installed as an NSTimer firing about 60 times per second.  All WPE
 * and WebKit callbacks therefore fire on the main thread, and we can
 * call into our host (WKWebView) without thread hops.
 *
 * Rendering pipeline
 * ------------------
 * WPE WebKit hands us pixel data via the SHM exportable backend.  On
 * each frame:
 *   1. export_shm_buffer is invoked with a wl_shm_buffer.
 *   2. We copy the pixels into a fresh NSBitmapImageRep, swizzling
 *      from BGRA (wl_shm ARGB8888 little-endian) to RGBA (what
 *      NSBitmapImageRep expects without the alpha-first flag).
 *   3. We release the buffer back to WPE and notify our host so that
 *      it can call setNeedsDisplay: on the AppKit side.
 *   4. dispatch_frame_complete is called so WPE will produce the next
 *      frame.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#import "GSWebKitWPE.h"
#import "GSWebKitBackend.h"
#import <WebKit/WKWebViewConfiguration.h>
#import <WebKit/WKPreferences.h>
#import <WebKit/WKError.h>

#include <stdint.h>
#include <string.h>

#include <glib.h>
#include <gio/gio.h>

#include <wpe/wpe.h>
#include <wpe/fdo.h>
#include <wpe/unstable/fdo-shm.h>

#include <wpe/webkit.h>
#include <wayland-server.h>

/* ----------------------------------------------------------------------
 * Forward declarations of static C callbacks (they all trampoline into
 * methods on GSWebKitWPE via the user_data pointer).
 * -------------------------------------------------------------------- */

static void GSWPE_OnExportShmBuffer(void *data, struct wpe_fdo_shm_exported_buffer *buf);
static void GSWPE_OnLoadChanged(WebKitWebView *view, WebKitLoadEvent ev, gpointer ud);
static gboolean GSWPE_OnLoadFailed(WebKitWebView *view, WebKitLoadEvent ev,
                                   const gchar *uri, GError *err, gpointer ud);
static void GSWPE_OnNotifyTitle(GObject *src, GParamSpec *spec, gpointer ud);
static void GSWPE_OnNotifyURI(GObject *src, GParamSpec *spec, gpointer ud);
static void GSWPE_OnNotifyProgress(GObject *src, GParamSpec *spec, gpointer ud);
static void GSWPE_OnNotifyIsLoading(GObject *src, GParamSpec *spec, gpointer ud);
static gboolean GSWPE_OnScriptDialog(WebKitWebView *view,
                                     WebKitScriptDialog *dialog, gpointer ud);
static void GSWPE_OnScriptMessageReceived(WebKitUserContentManager *mgr,
                                          JSCValue *value, gpointer ud);
static void GSWPE_OnEvaluateJavaScriptFinished(GObject *source,
                                               GAsyncResult *result, gpointer ud);

/* Per-message-handler context attached to its signal closure as user
 * data so the callback can recover both the backend and the
 * registered name without external bookkeeping. */
struct GSWPE_HandlerCtx {
  GSWebKitWPE *backend;   /* weak: backend owns the registration */
  gchar       *name;      /* g_strdup'd UTF-8 */
};

static void GSWPE_HandlerCtxFree(gpointer data, GClosure *closure);

/* Convert a JSCValue produced by a finished evaluate_javascript call
 * into an Objective-C object using the same rules WKWebView documents
 * (string -> NSString, number -> NSNumber, etc.).  Returns nil and
 * fills *outError if the value is of an unsupported type. */
static id GSWPE_ConvertJSCValue(JSCValue *value, NSError **outError);


/* ----------------------------------------------------------------------
 * One-time global initialisation.
 * -------------------------------------------------------------------- */

static gboolean GSWPE_globalsInitialized = FALSE;

static void GSWPE_InitializeGlobals(void)
{
  if (GSWPE_globalsInitialized) {
    return;
  }
  /* Load the FDO backend shared library so libwpe can locate it. */
  wpe_loader_init("libWPEBackend-fdo-1.0.so");
  /* SHM path: CPU-side pixel buffers, no EGL/dma-buf required. */
  wpe_fdo_initialize_shm();
  GSWPE_globalsInitialized = TRUE;
}


/* ----------------------------------------------------------------------
 * Pending JavaScript-evaluation contexts.
 *
 * GAsync callbacks need to carry an Objective-C completion block; we
 * heap-allocate a small struct that owns a Block_copy of the block and
 * a back pointer to the owning backend.
 * -------------------------------------------------------------------- */

typedef void (^GSWPE_JSCompletion)(id result, NSError *error);

struct GSWPE_PendingEval {
  GSWPE_JSCompletion block;   /* retained via Block_copy */
};


/* ----------------------------------------------------------------------
 * GSWebKitWPE
 * -------------------------------------------------------------------- */

@interface GSWebKitWPE ()
- (void)pumpGLib:(NSTimer *)timer;
- (void)deliverFrameFromShmBuffer:(struct wpe_fdo_shm_exported_buffer *)buf;
- (void)handleScriptDialog:(WebKitScriptDialog *)dialog;
- (void)installInitialSettingsFrom:(WKWebViewConfiguration *)config;
@end


@implementation GSWebKitWPE
{
  /* Engine objects (raw glib/webkit pointers, manually g_object_unref'd
   * in -shutdown / -dealloc). */
  WebKitWebView            *_view;
  WebKitWebViewBackend     *_viewBackend;
  WebKitUserContentManager *_userContent;
  WebKitSettings           *_settings;

  /* WPE rendering. */
  struct wpe_view_backend_exportable_fdo *_exportable;
  uint32_t                                _width;
  uint32_t                                _height;

  /* Pixel buffer state.  _frameLock protects the latest-frame ivars
   * because, while WPE callbacks land on the main thread today, the
   * AppKit -drawRect: can be reached from the same thread on a
   * different call stack and we want to keep frame swaps atomic. */
  NSLock                   *_frameLock;
  NSBitmapImageRep         *_currentFrame;
  NSSize                    _currentFrameSize;

  /* GLib pump. */
  NSTimer                  *_pumpTimer;

  /* Tracked signal handler ids so we can disconnect cleanly. */
  gulong                    _signalLoadChanged;
  gulong                    _signalLoadFailed;
  gulong                    _signalNotifyTitle;
  gulong                    _signalNotifyURI;
  gulong                    _signalNotifyProgress;
  gulong                    _signalNotifyIsLoading;
  gulong                    _signalScriptDialog;

  NSMutableDictionary      *_handlerSignalIds;   /* name -> NSNumber(gulong) */

  /* Cached state we want to expose synchronously. */
  NSString                 *_customUserAgent;
}

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)config
{
  self = [super init];
  if (self == nil) {
    return nil;
  }

  GSWPE_InitializeGlobals();

  _frameLock = [[NSLock alloc] init];
  _handlerSignalIds = [[NSMutableDictionary alloc] init];
  _width  = 800;
  _height = 600;

  /* Construct the WPE FDO exportable view backend. */
  static const struct wpe_view_backend_exportable_fdo_client client = {
      .export_buffer_resource = NULL,
      .export_dmabuf_resource = NULL,
      .export_shm_buffer      = GSWPE_OnExportShmBuffer,
      ._wpe_reserved0         = NULL,
      ._wpe_reserved1         = NULL,
  };
  _exportable = wpe_view_backend_exportable_fdo_create(&client, (void *)self,
                                                       _width, _height);
  if (_exportable == NULL) {
    NSLog(@"GSWebKitWPE: wpe_view_backend_exportable_fdo_create failed");
    [self release];
    return nil;
  }

  struct wpe_view_backend *backend =
      wpe_view_backend_exportable_fdo_get_view_backend(_exportable);

  _viewBackend = webkit_web_view_backend_new(backend, NULL, NULL);
  _view = (WebKitWebView *)g_object_ref_sink(g_object_new(WEBKIT_TYPE_WEB_VIEW,
                                                          "backend", _viewBackend,
                                                          NULL));

  _settings    = webkit_web_view_get_settings(_view);          /* unowned */
  _userContent = webkit_web_view_get_user_content_manager(_view); /* unowned */

  [self installInitialSettingsFrom:config];

  /* Connect signals.  GSWPE_ self-pointer goes through the user_data
   * channel; the callbacks trampoline back into Objective-C land. */
  _signalLoadChanged = g_signal_connect(_view, "load-changed",
                                        G_CALLBACK(GSWPE_OnLoadChanged), self);
  _signalLoadFailed  = g_signal_connect(_view, "load-failed",
                                        G_CALLBACK(GSWPE_OnLoadFailed), self);
  _signalNotifyTitle = g_signal_connect(_view, "notify::title",
                                        G_CALLBACK(GSWPE_OnNotifyTitle), self);
  _signalNotifyURI   = g_signal_connect(_view, "notify::uri",
                                        G_CALLBACK(GSWPE_OnNotifyURI), self);
  _signalNotifyProgress = g_signal_connect(_view, "notify::estimated-load-progress",
                                           G_CALLBACK(GSWPE_OnNotifyProgress), self);
  _signalNotifyIsLoading = g_signal_connect(_view, "notify::is-loading",
                                            G_CALLBACK(GSWPE_OnNotifyIsLoading), self);
  _signalScriptDialog = g_signal_connect(_view, "script-dialog",
                                         G_CALLBACK(GSWPE_OnScriptDialog), self);

  /* Pump GLib at ~60Hz.  When there are no events the iteration is
   * cheap; when WebKit is animating, this gives us roughly vsync-rate
   * pacing without us having to wire glib's pollfd set into NSRunLoop. */
  _pumpTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                 target:self
                                               selector:@selector(pumpGLib:)
                                               userInfo:nil
                                                repeats:YES] retain];
  [[NSRunLoop currentRunLoop] addTimer:_pumpTimer forMode:NSRunLoopCommonModes];

  return self;
}

- (void)installInitialSettingsFrom:(WKWebViewConfiguration *)config
{
  if (_settings == NULL) {
    return;
  }
  WKPreferences *prefs = [config preferences];
  if (prefs != nil) {
    webkit_settings_set_enable_javascript(_settings,
                                          [prefs javaScriptEnabled] ? TRUE : FALSE);
    webkit_settings_set_javascript_can_open_windows_automatically(
        _settings, [prefs javaScriptCanOpenWindowsAutomatically] ? TRUE : FALSE);
    if ([prefs minimumFontSize] > 0.0) {
      webkit_settings_set_minimum_font_size(_settings,
                                            (guint32)[prefs minimumFontSize]);
    }
  }

  NSString *uaSuffix = [config applicationNameForUserAgent];
  if ([uaSuffix length] > 0) {
    webkit_settings_set_user_agent_with_application_details(
        _settings, [uaSuffix UTF8String], NULL);
  }
}

- (void)dealloc
{
  [self shutdown];
  [_frameLock release];
  [_handlerSignalIds release];
  [_currentFrame release];
  [_customUserAgent release];
  [super dealloc];
}

- (void)shutdown
{
  if (_pumpTimer != nil) {
    [_pumpTimer invalidate];
    [_pumpTimer release];
    _pumpTimer = nil;
  }

  if (_view != NULL) {
    if (_signalLoadChanged)     g_signal_handler_disconnect(_view, _signalLoadChanged);
    if (_signalLoadFailed)      g_signal_handler_disconnect(_view, _signalLoadFailed);
    if (_signalNotifyTitle)     g_signal_handler_disconnect(_view, _signalNotifyTitle);
    if (_signalNotifyURI)       g_signal_handler_disconnect(_view, _signalNotifyURI);
    if (_signalNotifyProgress)  g_signal_handler_disconnect(_view, _signalNotifyProgress);
    if (_signalNotifyIsLoading) g_signal_handler_disconnect(_view, _signalNotifyIsLoading);
    if (_signalScriptDialog)    g_signal_handler_disconnect(_view, _signalScriptDialog);
  }
  _signalLoadChanged = _signalLoadFailed = 0;
  _signalNotifyTitle = _signalNotifyURI = 0;
  _signalNotifyProgress = _signalNotifyIsLoading = _signalScriptDialog = 0;

  if (_userContent != NULL && _handlerSignalIds != nil) {
    NSEnumerator *e = [_handlerSignalIds keyEnumerator];
    NSString *name;
    while ((name = [e nextObject]) != nil) {
      NSNumber *sid = [_handlerSignalIds objectForKey:name];
      g_signal_handler_disconnect(_userContent, (gulong)[sid unsignedLongValue]);
      webkit_user_content_manager_unregister_script_message_handler(
          _userContent, [name UTF8String], NULL);
    }
    [_handlerSignalIds removeAllObjects];
  }

  if (_view != NULL) {
    g_object_unref(_view);
    _view = NULL;
  }
  _settings    = NULL;  /* owned by view */
  _userContent = NULL;  /* owned by view */

  if (_viewBackend != NULL) {
    /* webkit_web_view_backend is owned by the WebKitWebView; do not
     * unref here.  It's freed when the view is finalised. */
    _viewBackend = NULL;
  }
  if (_exportable != NULL) {
    wpe_view_backend_exportable_fdo_destroy(_exportable);
    _exportable = NULL;
  }
}


/* ------------------------------------------------------------------ */
#pragma mark Sizing

- (void)setSize:(NSSize)size scale:(CGFloat)scale
{
  uint32_t w = (uint32_t)MAX(1.0, size.width  * scale);
  uint32_t h = (uint32_t)MAX(1.0, size.height * scale);
  if (w == _width && h == _height) {
    return;
  }
  _width  = w;
  _height = h;
  if (_exportable != NULL) {
    struct wpe_view_backend *be =
        wpe_view_backend_exportable_fdo_get_view_backend(_exportable);
    wpe_view_backend_dispatch_set_size(be, _width, _height);
    if (scale > 0.0) {
      wpe_view_backend_dispatch_set_device_scale_factor(be, (float)scale);
    }
  }
}


/* ------------------------------------------------------------------ */
#pragma mark Navigation

- (void)loadURL:(NSURL *)url
{
  if (_view == NULL || url == nil) {
    return;
  }
  NSString *s = [url absoluteString];
  webkit_web_view_load_uri(_view, [s UTF8String]);
}

- (void)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL
{
  if (_view == NULL || html == nil) {
    return;
  }
  const char *base = NULL;
  if (baseURL != nil) {
    base = [[baseURL absoluteString] UTF8String];
  }
  webkit_web_view_load_html(_view, [html UTF8String], base);
}

- (void)reload
{
  if (_view != NULL) webkit_web_view_reload(_view);
}

- (void)reloadFromOrigin
{
  if (_view != NULL) webkit_web_view_reload_bypass_cache(_view);
}

- (void)stopLoading
{
  if (_view != NULL) webkit_web_view_stop_loading(_view);
}

- (BOOL)canGoBack
{
  return (_view != NULL) ? (BOOL)webkit_web_view_can_go_back(_view) : NO;
}

- (BOOL)canGoForward
{
  return (_view != NULL) ? (BOOL)webkit_web_view_can_go_forward(_view) : NO;
}

- (void)goBack
{
  if (_view != NULL) webkit_web_view_go_back(_view);
}

- (void)goForward
{
  if (_view != NULL) webkit_web_view_go_forward(_view);
}


/* ------------------------------------------------------------------ */
#pragma mark JavaScript

- (void)evaluateJavaScript:(NSString *)javaScript
                completion:(void (^)(id, NSError *))completion
{
  if (_view == NULL || javaScript == nil) {
    if (completion != NULL) completion(nil, nil);
    return;
  }
  struct GSWPE_PendingEval *pending = g_new0(struct GSWPE_PendingEval, 1);
  pending->block = (completion != NULL) ? Block_copy(completion) : NULL;

  webkit_web_view_evaluate_javascript(_view,
                                      [javaScript UTF8String],
                                      -1,         /* length, -1 = NUL-terminated */
                                      NULL,       /* world_name */
                                      NULL,       /* source_uri */
                                      NULL,       /* cancellable */
                                      GSWPE_OnEvaluateJavaScriptFinished,
                                      pending);
}


/* ------------------------------------------------------------------ */
#pragma mark User content

- (void)addUserScript:(NSString *)source
        injectionTime:(NSInteger)injectionTime
     forMainFrameOnly:(BOOL)mainFrameOnly
{
  if (_userContent == NULL || source == nil) {
    return;
  }
  WebKitUserContentInjectedFrames frames = mainFrameOnly
      ? WEBKIT_USER_CONTENT_INJECT_TOP_FRAME
      : WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES;
  WebKitUserScriptInjectionTime time = (injectionTime == 0)
      ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
      : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END;
  WebKitUserScript *script = webkit_user_script_new([source UTF8String],
                                                    frames, time, NULL, NULL);
  webkit_user_content_manager_add_script(_userContent, script);
  webkit_user_script_unref(script);
}

- (void)registerScriptMessageHandlerName:(NSString *)name
{
  if (_userContent == NULL || [name length] == 0) {
    return;
  }
  if ([_handlerSignalIds objectForKey:name] != nil) {
    return;  /* already registered */
  }
  if (!webkit_user_content_manager_register_script_message_handler(
          _userContent, [name UTF8String], NULL)) {
    NSLog(@"GSWebKitWPE: failed to register script message handler '%@'", name);
    return;
  }
  NSString *detailed = [@"script-message-received::" stringByAppendingString:name];
  struct GSWPE_HandlerCtx *ctx = g_new0(struct GSWPE_HandlerCtx, 1);
  ctx->backend = self;
  ctx->name    = g_strdup([name UTF8String]);
  gulong sid = g_signal_connect_data(_userContent,
                                     [detailed UTF8String],
                                     G_CALLBACK(GSWPE_OnScriptMessageReceived),
                                     ctx,
                                     GSWPE_HandlerCtxFree,
                                     (GConnectFlags)0);
  [_handlerSignalIds setObject:[NSNumber numberWithUnsignedLong:(unsigned long)sid]
                        forKey:name];
}

- (void)unregisterScriptMessageHandlerName:(NSString *)name
{
  if (_userContent == NULL || name == nil) {
    return;
  }
  NSNumber *sid = [_handlerSignalIds objectForKey:name];
  if (sid != nil) {
    g_signal_handler_disconnect(_userContent, (gulong)[sid unsignedLongValue]);
    [_handlerSignalIds removeObjectForKey:name];
  }
  webkit_user_content_manager_unregister_script_message_handler(
      _userContent, [name UTF8String], NULL);
}


/* ------------------------------------------------------------------ */
#pragma mark Properties

- (NSString *)currentTitle
{
  if (_view == NULL) return nil;
  const gchar *t = webkit_web_view_get_title(_view);
  return (t != NULL) ? [NSString stringWithUTF8String:t] : nil;
}

- (NSURL *)currentURL
{
  if (_view == NULL) return nil;
  const gchar *u = webkit_web_view_get_uri(_view);
  return (u != NULL) ? [NSURL URLWithString:[NSString stringWithUTF8String:u]] : nil;
}

- (double)currentEstimatedProgress
{
  if (_view == NULL) return 0.0;
  return (double)webkit_web_view_get_estimated_load_progress(_view);
}

- (BOOL)isLoading
{
  if (_view == NULL) return NO;
  return (BOOL)webkit_web_view_is_loading(_view);
}

- (void)setCustomUserAgent:(NSString *)ua
{
  if (ua == _customUserAgent) return;
  [_customUserAgent release];
  _customUserAgent = [ua copy];
  if (_settings != NULL) {
    webkit_settings_set_user_agent(_settings, (ua != nil) ? [ua UTF8String] : NULL);
  }
}

- (NSString *)customUserAgent
{
  return _customUserAgent;
}


/* ------------------------------------------------------------------ */
#pragma mark Frame buffer

- (NSBitmapImageRep *)takeCurrentFrame
{
  [_frameLock lock];
  NSBitmapImageRep *frame = [_currentFrame retain];
  [_frameLock unlock];
  return [frame autorelease];
}

- (NSSize)currentFrameSize
{
  [_frameLock lock];
  NSSize sz = _currentFrameSize;
  [_frameLock unlock];
  return sz;
}

- (void)deliverFrameFromShmBuffer:(struct wpe_fdo_shm_exported_buffer *)buf
{
  struct wl_shm_buffer *shm = wpe_fdo_shm_exported_buffer_get_shm_buffer(buf);
  if (shm == NULL) {
    wpe_view_backend_exportable_fdo_dispatch_release_shm_exported_buffer(_exportable, buf);
    wpe_view_backend_exportable_fdo_dispatch_frame_complete(_exportable);
    return;
  }

  wl_shm_buffer_begin_access(shm);
  int32_t  w      = wl_shm_buffer_get_width(shm);
  int32_t  h      = wl_shm_buffer_get_height(shm);
  int32_t  stride = wl_shm_buffer_get_stride(shm);
  uint32_t format = wl_shm_buffer_get_format(shm);
  uint8_t *src    = (uint8_t *)wl_shm_buffer_get_data(shm);
  BOOL     hasAlpha = (format == WL_SHM_FORMAT_ARGB8888);

  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL
                    pixelsWide:w
                    pixelsHigh:h
                 bitsPerSample:8
               samplesPerPixel:4
                      hasAlpha:YES
                      isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace
                  bitmapFormat:0
                   bytesPerRow:w * 4
                  bitsPerPixel:32];

  uint8_t *dst       = [rep bitmapData];
  NSInteger dstStride = [rep bytesPerRow];

  /* Swizzle BGRA (little-endian ARGB8888 in memory) -> RGBA. */
  for (int32_t y = 0; y < h; y++) {
    uint8_t *srow = src + (intptr_t)y * stride;
    uint8_t *drow = dst + (intptr_t)y * dstStride;
    for (int32_t x = 0; x < w; x++) {
      uint8_t b = srow[x * 4 + 0];
      uint8_t g = srow[x * 4 + 1];
      uint8_t r = srow[x * 4 + 2];
      uint8_t a = hasAlpha ? srow[x * 4 + 3] : 0xFF;
      drow[x * 4 + 0] = r;
      drow[x * 4 + 1] = g;
      drow[x * 4 + 2] = b;
      drow[x * 4 + 3] = a;
    }
  }
  wl_shm_buffer_end_access(shm);

  [_frameLock lock];
  [_currentFrame release];
  _currentFrame     = rep;          /* take ownership */
  _currentFrameSize = NSMakeSize(w, h);
  [_frameLock unlock];

  wpe_view_backend_exportable_fdo_dispatch_release_shm_exported_buffer(_exportable, buf);
  wpe_view_backend_exportable_fdo_dispatch_frame_complete(_exportable);

  if ([[self host] respondsToSelector:@selector(backendFrameDidChange:)]) {
    [[self host] backendFrameDidChange:self];
  }
}


/* ------------------------------------------------------------------ */
#pragma mark Script dialog -> UI delegate

- (void)handleScriptDialog:(WebKitScriptDialog *)dialog
{
  WebKitScriptDialogType type = webkit_script_dialog_get_dialog_type(dialog);
  const gchar *cmsg = webkit_script_dialog_get_message(dialog);
  NSString *msg = (cmsg != NULL) ? [NSString stringWithUTF8String:cmsg] : @"";

  switch (type) {
    case WEBKIT_SCRIPT_DIALOG_ALERT: {
      webkit_script_dialog_ref(dialog);
      if ([[self host] respondsToSelector:
              @selector(backend:runJavaScriptAlertWithMessage:completion:)]) {
        [[self host] backend:self
            runJavaScriptAlertWithMessage:msg
                                completion:^{
          webkit_script_dialog_unref(dialog);
        }];
      } else {
        webkit_script_dialog_unref(dialog);
      }
      break;
    }
    case WEBKIT_SCRIPT_DIALOG_CONFIRM: {
      webkit_script_dialog_ref(dialog);
      if ([[self host] respondsToSelector:
              @selector(backend:runJavaScriptConfirmWithMessage:completion:)]) {
        [[self host] backend:self
            runJavaScriptConfirmWithMessage:msg
                                  completion:^(BOOL ok) {
          webkit_script_dialog_confirm_set_confirmed(dialog, ok ? TRUE : FALSE);
          webkit_script_dialog_unref(dialog);
        }];
      } else {
        webkit_script_dialog_confirm_set_confirmed(dialog, FALSE);
        webkit_script_dialog_unref(dialog);
      }
      break;
    }
    case WEBKIT_SCRIPT_DIALOG_PROMPT: {
      webkit_script_dialog_ref(dialog);
      const gchar *cdef = webkit_script_dialog_prompt_get_default_text(dialog);
      NSString *def = (cdef != NULL) ? [NSString stringWithUTF8String:cdef] : @"";
      if ([[self host] respondsToSelector:
              @selector(backend:runJavaScriptPromptWithMessage:defaultText:completion:)]) {
        [[self host] backend:self
            runJavaScriptPromptWithMessage:msg
                                defaultText:def
                                 completion:^(NSString *result) {
          webkit_script_dialog_prompt_set_text(dialog,
              (result != nil) ? [result UTF8String] : "");
          webkit_script_dialog_unref(dialog);
        }];
      } else {
        webkit_script_dialog_prompt_set_text(dialog, "");
        webkit_script_dialog_unref(dialog);
      }
      break;
    }
    default:
      /* BEFORE_UNLOAD not specifically handled in v1. */
      break;
  }
}


/* ------------------------------------------------------------------ */
#pragma mark Input dispatch

- (void)dispatchPointerMoveAt:(NSPoint)point
                    modifiers:(uint32_t)modifiers
                    timestamp:(uint32_t)timestamp
{
  if (_exportable == NULL) return;
  struct wpe_view_backend *be =
      wpe_view_backend_exportable_fdo_get_view_backend(_exportable);
  struct wpe_input_pointer_event ev = {
      .type      = wpe_input_pointer_event_type_motion,
      .time      = timestamp,
      .x         = (int)point.x,
      .y         = (int)point.y,
      .button    = 0,
      .state     = 0,
      .modifiers = modifiers,
  };
  wpe_view_backend_dispatch_pointer_event(be, &ev);
}

- (void)dispatchPointerButton:(int)button
                      pressed:(BOOL)pressed
                           at:(NSPoint)point
                    modifiers:(uint32_t)modifiers
                    timestamp:(uint32_t)timestamp
{
  if (_exportable == NULL) return;
  struct wpe_view_backend *be =
      wpe_view_backend_exportable_fdo_get_view_backend(_exportable);
  struct wpe_input_pointer_event ev = {
      .type      = wpe_input_pointer_event_type_button,
      .time      = timestamp,
      .x         = (int)point.x,
      .y         = (int)point.y,
      .button    = (uint32_t)button,
      .state     = pressed ? 1u : 0u,
      .modifiers = modifiers,
  };
  wpe_view_backend_dispatch_pointer_event(be, &ev);
}

- (void)dispatchScrollAt:(NSPoint)point
                  deltaX:(double)dx
                  deltaY:(double)dy
               modifiers:(uint32_t)modifiers
               timestamp:(uint32_t)timestamp
{
  if (_exportable == NULL) return;
  struct wpe_view_backend *be =
      wpe_view_backend_exportable_fdo_get_view_backend(_exportable);
  struct wpe_input_axis_2d_event ev = {
      .base = {
          .type      = (enum wpe_input_axis_event_type)
                       (wpe_input_axis_event_type_motion_smooth
                        | wpe_input_axis_event_type_mask_2d),
          .time      = timestamp,
          .x         = (int)point.x,
          .y         = (int)point.y,
          .axis      = 0,
          .value     = 0,
          .modifiers = modifiers,
      },
      .x_axis = dx,
      .y_axis = dy,
  };
  wpe_view_backend_dispatch_axis_event(be, &ev.base);
}

- (void)dispatchKeyCode:(uint32_t)keysym
                pressed:(BOOL)pressed
              modifiers:(uint32_t)modifiers
              timestamp:(uint32_t)timestamp
{
  if (_exportable == NULL) return;
  struct wpe_view_backend *be =
      wpe_view_backend_exportable_fdo_get_view_backend(_exportable);
  struct wpe_input_keyboard_event ev = {
      .time              = timestamp,
      .key_code          = keysym,
      .hardware_key_code = 0,
      .pressed           = pressed ? true : false,
      .modifiers         = modifiers,
  };
  wpe_view_backend_dispatch_keyboard_event(be, &ev);
}


/* ------------------------------------------------------------------ */
#pragma mark GLib pumping

- (void)pumpGLib:(NSTimer *)timer
{
  (void)timer;
  GMainContext *ctx = g_main_context_default();
  /* Pull off everything that is ready, but do not block. */
  while (g_main_context_iteration(ctx, FALSE)) {
    /* loop */
  }
}

@end


/* ======================================================================
 * Static C callbacks: trampoline into Objective-C.
 * ==================================================================== */

static void
GSWPE_OnExportShmBuffer(void *data, struct wpe_fdo_shm_exported_buffer *buf)
{
  GSWebKitWPE *self = (GSWebKitWPE *)data;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [self deliverFrameFromShmBuffer:buf];
  [pool release];
}

static void
GSWPE_OnLoadChanged(WebKitWebView *view, WebKitLoadEvent ev, gpointer ud)
{
  (void)view;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  id <GSWebKitBackendHost> host = [self host];
  switch (ev) {
    case WEBKIT_LOAD_STARTED:
      if ([host respondsToSelector:@selector(backendDidStartProvisionalNavigation:)]) {
        [host backendDidStartProvisionalNavigation:self];
      }
      break;
    case WEBKIT_LOAD_COMMITTED:
      if ([host respondsToSelector:@selector(backendDidCommitNavigation:)]) {
        [host backendDidCommitNavigation:self];
      }
      break;
    case WEBKIT_LOAD_FINISHED:
      if ([host respondsToSelector:@selector(backendDidFinishNavigation:)]) {
        [host backendDidFinishNavigation:self];
      }
      break;
    default:
      break;
  }
  [pool release];
}

static gboolean
GSWPE_OnLoadFailed(WebKitWebView *view, WebKitLoadEvent ev,
                   const gchar *uri, GError *err, gpointer ud)
{
  (void)view; (void)uri;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  id <GSWebKitBackendHost> host = [self host];

  NSString *desc = (err != NULL && err->message != NULL)
      ? [NSString stringWithUTF8String:err->message]
      : @"Navigation failed";
  NSDictionary *info = [NSDictionary dictionaryWithObject:desc
                                                   forKey:NSLocalizedDescriptionKey];
  NSError *nserr = [NSError errorWithDomain:WKErrorDomain
                                       code:WKErrorUnknown
                                   userInfo:info];

  BOOL provisional = (ev == WEBKIT_LOAD_STARTED || ev == WEBKIT_LOAD_REDIRECTED);
  if ([host respondsToSelector:@selector(backend:didFailNavigationWithError:provisional:)]) {
    [host backend:self didFailNavigationWithError:nserr provisional:provisional];
  }
  [pool release];
  return FALSE;  /* let default handler run too */
}

static void
GSWPE_OnNotifyTitle(GObject *src, GParamSpec *spec, gpointer ud)
{
  (void)spec;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  const gchar *t = webkit_web_view_get_title(WEBKIT_WEB_VIEW(src));
  NSString *title = (t != NULL) ? [NSString stringWithUTF8String:t] : @"";
  id <GSWebKitBackendHost> host = [self host];
  if ([host respondsToSelector:@selector(backend:didChangeTitle:)]) {
    [host backend:self didChangeTitle:title];
  }
  [pool release];
}

static void
GSWPE_OnNotifyURI(GObject *src, GParamSpec *spec, gpointer ud)
{
  (void)spec;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  const gchar *u = webkit_web_view_get_uri(WEBKIT_WEB_VIEW(src));
  NSURL *url = (u != NULL)
      ? [NSURL URLWithString:[NSString stringWithUTF8String:u]]
      : nil;
  id <GSWebKitBackendHost> host = [self host];
  if (url != nil
      && [host respondsToSelector:@selector(backend:didChangeURL:)]) {
    [host backend:self didChangeURL:url];
  }
  [pool release];
}

static void
GSWPE_OnNotifyProgress(GObject *src, GParamSpec *spec, gpointer ud)
{
  (void)spec;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  gdouble p = webkit_web_view_get_estimated_load_progress(WEBKIT_WEB_VIEW(src));
  id <GSWebKitBackendHost> host = [self host];
  if ([host respondsToSelector:@selector(backend:didChangeEstimatedProgress:)]) {
    [host backend:self didChangeEstimatedProgress:(double)p];
  }
  [pool release];
}

static void
GSWPE_OnNotifyIsLoading(GObject *src, GParamSpec *spec, gpointer ud)
{
  (void)spec;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  gboolean loading = webkit_web_view_is_loading(WEBKIT_WEB_VIEW(src));
  id <GSWebKitBackendHost> host = [self host];
  if ([host respondsToSelector:@selector(backend:didChangeIsLoading:)]) {
    [host backend:self didChangeIsLoading:(BOOL)loading];
  }
  [pool release];
}

static gboolean
GSWPE_OnScriptDialog(WebKitWebView *view, WebKitScriptDialog *dialog, gpointer ud)
{
  (void)view;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [self handleScriptDialog:dialog];
  [pool release];
  return TRUE;  /* tell WebKit we'll deal with it */
}

static void
GSWPE_OnScriptMessageReceived(WebKitUserContentManager *mgr,
                              JSCValue *value, gpointer ud)
{
  (void)mgr;
  struct GSWPE_HandlerCtx *ctx = (struct GSWPE_HandlerCtx *)ud;
  if (ctx == NULL || ctx->backend == nil) {
    return;
  }
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  id body = GSWPE_ConvertJSCValue(value, NULL);
  NSString *name = (ctx->name != NULL)
      ? [NSString stringWithUTF8String:ctx->name] : @"";
  id <GSWebKitBackendHost> host = [ctx->backend host];
  if ([host respondsToSelector:@selector(backend:didReceiveScriptMessageWithName:body:)]) {
    [host backend:ctx->backend
        didReceiveScriptMessageWithName:name
                                   body:body];
  }
  [pool release];
}

static void
GSWPE_HandlerCtxFree(gpointer data, GClosure *closure)
{
  (void)closure;
  struct GSWPE_HandlerCtx *ctx = (struct GSWPE_HandlerCtx *)data;
  if (ctx == NULL) return;
  if (ctx->name != NULL) g_free(ctx->name);
  g_free(ctx);
}

static void
GSWPE_OnEvaluateJavaScriptFinished(GObject *source, GAsyncResult *result, gpointer ud)
{
  WebKitWebView *view = WEBKIT_WEB_VIEW(source);
  struct GSWPE_PendingEval *pending = (struct GSWPE_PendingEval *)ud;

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  GError *gerror = NULL;
  JSCValue *value = webkit_web_view_evaluate_javascript_finish(view, result, &gerror);

  id objcResult  = nil;
  NSError *nserr = nil;

  if (gerror != NULL) {
    NSString *desc = (gerror->message != NULL)
        ? [NSString stringWithUTF8String:gerror->message]
        : @"JavaScript evaluation failed";
    nserr = [NSError errorWithDomain:WKErrorDomain
                                code:WKErrorJavaScriptExceptionOccurred
                            userInfo:[NSDictionary dictionaryWithObject:desc
                                                                 forKey:NSLocalizedDescriptionKey]];
    g_error_free(gerror);
  } else if (value != NULL) {
    NSError *convErr = nil;
    objcResult = GSWPE_ConvertJSCValue(value, &convErr);
    if (convErr != nil && objcResult == nil) {
      nserr = convErr;
    }
    g_object_unref(value);
  }

  if (pending != NULL) {
    if (pending->block != NULL) {
      pending->block(objcResult, nserr);
      Block_release(pending->block);
    }
    g_free(pending);
  }
  [pool release];
}


static id
GSWPE_ConvertJSCValue(JSCValue *value, NSError **outError)
{
  if (value == NULL || jsc_value_is_undefined(value)) {
    return nil;
  }
  if (jsc_value_is_null(value)) {
    return [NSNull null];
  }
  if (jsc_value_is_boolean(value)) {
    return [NSNumber numberWithBool:(BOOL)jsc_value_to_boolean(value)];
  }
  if (jsc_value_is_number(value)) {
    return [NSNumber numberWithDouble:(double)jsc_value_to_double(value)];
  }
  if (jsc_value_is_string(value)) {
    gchar *s = jsc_value_to_string(value);
    NSString *out = (s != NULL) ? [NSString stringWithUTF8String:s] : @"";
    g_free(s);
    return out;
  }
  if (jsc_value_is_array(value)) {
    NSMutableArray *arr = [NSMutableArray array];
    gint32 i = 0;
    while (TRUE) {
      JSCValue *elem = jsc_value_object_get_property_at_index(value, (guint32)i);
      if (elem == NULL || jsc_value_is_undefined(elem)) {
        if (elem != NULL) g_object_unref(elem);
        break;
      }
      id converted = GSWPE_ConvertJSCValue(elem, NULL);
      [arr addObject:(converted != nil) ? converted : (id)[NSNull null]];
      g_object_unref(elem);
      i++;
    }
    return arr;
  }
  if (jsc_value_is_object(value)) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    gchar **names = jsc_value_object_enumerate_properties(value);
    if (names != NULL) {
      for (gchar **p = names; *p != NULL; p++) {
        JSCValue *prop = jsc_value_object_get_property(value, *p);
        if (prop != NULL) {
          id converted = GSWPE_ConvertJSCValue(prop, NULL);
          if (converted != nil) {
            [dict setObject:converted forKey:[NSString stringWithUTF8String:*p]];
          }
          g_object_unref(prop);
        }
      }
      g_strfreev(names);
    }
    return dict;
  }

  if (outError != NULL) {
    *outError = [NSError errorWithDomain:WKErrorDomain
                                    code:WKErrorJavaScriptResultTypeIsUnsupported
                                userInfo:nil];
  }
  return nil;
}
