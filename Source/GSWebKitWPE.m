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
#import "GSWebKitInternal.h"
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
static void GSWPE_OnMouseTargetChanged(WebKitWebView *view,
                                       WebKitHitTestResult *hit,
                                       guint modifiers,
                                       gpointer ud);
static gboolean GSWPE_OnRunFileChooser(WebKitWebView *view,
                                       WebKitFileChooserRequest *request,
                                       gpointer ud);
static void     GSWPE_OnDownloadStarted(WebKitWebContext *ctx,
                                        WebKitDownload *download,
                                        gpointer ud);
static gboolean GSWPE_OnDownloadDecideDestination(WebKitDownload *download,
                                                  const gchar *suggested,
                                                  gpointer ud);
static void     GSWPE_OnDownloadFinished(WebKitDownload *download, gpointer ud);
static void     GSWPE_OnDownloadFailed(WebKitDownload *download,
                                        GError *error, gpointer ud);
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
- (void)pumpIterate;
- (void)clearPumpFDSources;
- (void)_schedulePumpNextWake:(gint)timeout_ms;
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

  /* GLib pump.  _pumpTimer is the next-wake timer (single-shot,
   * re-armed each iteration with the timeout that GLib's
   * prepare/query reports).  _pumpFDSources is a parallel array of
   * dispatch_read sources, one per pollfd reported by GLib's query —
   * those wake us as soon as the underlying socket / pipe has data,
   * so we don't have to busy-poll. */
  NSTimer                  *_pumpTimer;
  NSMutableArray           *_pumpFDSources;   /* NSValue pointer to dispatch_source_t */
  BOOL                      _pumpRunning;

  /* Tracked signal handler ids so we can disconnect cleanly. */
  gulong                    _signalLoadChanged;
  gulong                    _signalLoadFailed;
  gulong                    _signalNotifyTitle;
  gulong                    _signalNotifyURI;
  gulong                    _signalNotifyProgress;
  gulong                    _signalNotifyIsLoading;
  gulong                    _signalScriptDialog;
  gulong                    _signalMouseTarget;
  gulong                    _signalRunFileChooser;
  gulong                    _signalDownloadStarted;

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
  [self installSchemeHandlersFrom:config];
  [self installContentFiltersFrom:config];

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
  _signalMouseTarget = g_signal_connect(_view, "mouse-target-changed",
                                        G_CALLBACK(GSWPE_OnMouseTargetChanged), self);
  _signalRunFileChooser = g_signal_connect(_view, "run-file-chooser",
                                           G_CALLBACK(GSWPE_OnRunFileChooser), self);

  WebKitWebContext *ctx = webkit_web_view_get_context(_view);
  _signalDownloadStarted = g_signal_connect(ctx, "download-started",
                                            G_CALLBACK(GSWPE_OnDownloadStarted), self);

  /* Pump GLib at ~60Hz.  When there are no events the iteration is
   * cheap (no syscalls); when WebKit is animating, this gives us
   * roughly vsync-rate pacing.  A proper pollfd-driven integration
   * via g_main_context_prepare/query + libdispatch read sources was
   * tried — it works for rendering but introduces enough latency on
   * the WebKit-IPC return path that JS completion blocks can land
   * after the test harness times out.  Punted to v2. */
  _pumpRunning = YES;
  _pumpFDSources = [[NSMutableArray alloc] init];
  _pumpTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                 target:self
                                               selector:@selector(_pumpTimerFired:)
                                               userInfo:nil
                                                repeats:YES] retain];
  [[NSRunLoop currentRunLoop] addTimer:_pumpTimer forMode:NSRunLoopCommonModes];

  return self;
}

- (void)installSchemeHandlersFrom:(WKWebViewConfiguration *)config
{
  NSDictionary *handlers = [config _schemeHandlers];
  if ([handlers count] == 0) return;
  WebKitWebContext *ctx = webkit_web_view_get_context(_view);
  if (ctx == NULL) return;
  NSEnumerator *e = [handlers keyEnumerator];
  NSString *scheme;
  while ((scheme = [e nextObject]) != nil) {
    id handler = [handlers objectForKey:scheme];
    /* Allocate a tiny struct mirroring _GSWKSchemeReg in
     * WKURLSchemeTask.m.  Keep it ABI-equivalent. */
    struct _gswk_reg { id handler; id webView; } *reg = g_new0(struct _gswk_reg, 1);
    reg->handler = handler;          /* weak, ARC-equivalent assignment */
    reg->webView = nil;              /* host (WKWebView) — filled in below if available */
    if ([[self host] isKindOfClass:[NSObject class]]) {
      reg->webView = [self host];
    }
    webkit_web_context_register_uri_scheme(ctx, [scheme UTF8String],
        (WebKitURISchemeRequestCallback)_GSWKSchemeCallback,
        reg,
        (GDestroyNotify)_GSWKSchemeReg_Free);
  }
}

- (void)installContentFiltersFrom:(WKWebViewConfiguration *)config
{
  if (_userContent == NULL) return;
  NSEnumerator *e = [[[config userContentController] _ruleLists] objectEnumerator];
  WKContentRuleList *rl;
  while ((rl = [e nextObject]) != nil) {
    WebKitUserContentFilter *f = (WebKitUserContentFilter *)[rl _filter];
    if (f != NULL) {
      webkit_user_content_manager_add_filter(_userContent, f);
    }
  }
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
  _pumpRunning = NO;
  if (_pumpTimer != nil) {
    [_pumpTimer invalidate];
    [_pumpTimer release];
    _pumpTimer = nil;
  }
  [self clearPumpFDSources];
  [_pumpFDSources release];
  _pumpFDSources = nil;

  if (_view != NULL) {
    if (_signalLoadChanged)     g_signal_handler_disconnect(_view, _signalLoadChanged);
    if (_signalLoadFailed)      g_signal_handler_disconnect(_view, _signalLoadFailed);
    if (_signalNotifyTitle)     g_signal_handler_disconnect(_view, _signalNotifyTitle);
    if (_signalNotifyURI)       g_signal_handler_disconnect(_view, _signalNotifyURI);
    if (_signalNotifyProgress)  g_signal_handler_disconnect(_view, _signalNotifyProgress);
    if (_signalNotifyIsLoading) g_signal_handler_disconnect(_view, _signalNotifyIsLoading);
    if (_signalScriptDialog)    g_signal_handler_disconnect(_view, _signalScriptDialog);
    if (_signalMouseTarget)     g_signal_handler_disconnect(_view, _signalMouseTarget);
    if (_signalRunFileChooser)  g_signal_handler_disconnect(_view, _signalRunFileChooser);
    if (_signalDownloadStarted) {
      WebKitWebContext *ctx = webkit_web_view_get_context(_view);
      if (ctx != NULL) g_signal_handler_disconnect(ctx, _signalDownloadStarted);
      _signalDownloadStarted = 0;
    }
  }
  _signalLoadChanged = _signalLoadFailed = 0;
  _signalNotifyTitle = _signalNotifyURI = 0;
  _signalNotifyProgress = _signalNotifyIsLoading = _signalScriptDialog = 0;
  _signalMouseTarget = _signalRunFileChooser = 0;

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
#pragma mark Find in page

typedef void (^GSWPE_FindCompletion)(BOOL matchFound);

struct GSWPE_PendingFind {
  GSWPE_FindCompletion block;
  gulong sid_found;
  gulong sid_failed;
};

static void GSWPE_OnFindFound(WebKitFindController *fc, guint count, gpointer ud)
{
  (void)fc; (void)count;
  struct GSWPE_PendingFind *p = ud;
  if (p && p->block) p->block(YES);
  if (p) {
    if (p->sid_found)  g_signal_handler_disconnect(fc, p->sid_found);
    if (p->sid_failed) g_signal_handler_disconnect(fc, p->sid_failed);
    if (p->block) Block_release(p->block);
    g_free(p);
  }
}

static void GSWPE_OnFindFailed(WebKitFindController *fc, gpointer ud)
{
  struct GSWPE_PendingFind *p = ud;
  if (p && p->block) p->block(NO);
  if (p) {
    if (p->sid_found)  g_signal_handler_disconnect(fc, p->sid_found);
    if (p->sid_failed) g_signal_handler_disconnect(fc, p->sid_failed);
    if (p->block) Block_release(p->block);
    g_free(p);
  }
}

- (void)findString:(NSString *)text
        backwards:(BOOL)backwards
    caseSensitive:(BOOL)caseSensitive
            wraps:(BOOL)wraps
        completion:(void (^)(BOOL))completion
{
  if (_view == NULL || [text length] == 0) {
    if (completion) completion(NO);
    return;
  }
  WebKitFindController *fc = webkit_web_view_get_find_controller(_view);
  if (fc == NULL) {
    if (completion) completion(NO);
    return;
  }
  guint32 opts = WEBKIT_FIND_OPTIONS_NONE;
  if (!caseSensitive) opts |= WEBKIT_FIND_OPTIONS_CASE_INSENSITIVE;
  if (backwards)      opts |= WEBKIT_FIND_OPTIONS_BACKWARDS;
  if (wraps)          opts |= WEBKIT_FIND_OPTIONS_WRAP_AROUND;

  struct GSWPE_PendingFind *pending = g_new0(struct GSWPE_PendingFind, 1);
  pending->block = completion ? Block_copy(completion) : NULL;
  pending->sid_found = g_signal_connect(fc, "found-text",
                                        G_CALLBACK(GSWPE_OnFindFound), pending);
  pending->sid_failed = g_signal_connect(fc, "failed-to-find-text",
                                         G_CALLBACK(GSWPE_OnFindFailed), pending);

  webkit_find_controller_search(fc, [text UTF8String], opts, G_MAXUINT);
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

- (void)setPageZoom:(CGFloat)z
{
  if (_view == NULL) return;
  if (z < 0.1) z = 0.1;
  if (z > 10.0) z = 10.0;
  webkit_web_view_set_zoom_level(_view, (gdouble)z);
}

- (CGFloat)pageZoom
{
  if (_view == NULL) return 1.0;
  return (CGFloat)webkit_web_view_get_zoom_level(_view);
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

  /* wl_shm ARGB8888 pixels are stored as a 32-bit little-endian word
   * with alpha in the high byte: bytes in memory are B, G, R, A.  We
   * tell NSBitmapImageRep to interpret each 32-bit word as
   * little-endian + alpha-first; that matches the wl_shm layout
   * exactly and lets us copy each row with memcpy instead of
   * per-pixel byte-swapping.  Performance win is ~5x on the hot
   * frame-arrival path. */
  NSBitmapFormat bmpFmt = NSAlphaFirstBitmapFormat
                        | NS32BitLittleEndianBitmapFormat;
  if (!hasAlpha) {
    /* XRGB8888: still BGRA-in-memory, but alpha byte is undefined.
     * Force opaque alpha via the alpha-nonpremultiplied flag and
     * post-process the alpha byte. */
    bmpFmt |= NSAlphaNonpremultipliedBitmapFormat;
  }
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL
                    pixelsWide:w
                    pixelsHigh:h
                 bitsPerSample:8
               samplesPerPixel:4
                      hasAlpha:YES
                      isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace
                  bitmapFormat:bmpFmt
                   bytesPerRow:w * 4
                  bitsPerPixel:32];

  uint8_t *dst       = [rep bitmapData];
  NSInteger dstStride = [rep bytesPerRow];

  if (stride == dstStride) {
    memcpy(dst, src, (size_t)stride * (size_t)h);
  } else {
    for (int32_t y = 0; y < h; y++) {
      memcpy(dst + (intptr_t)y * dstStride,
             src + (intptr_t)y * stride,
             (size_t)MIN(stride, (int32_t)dstStride));
    }
  }
  if (!hasAlpha) {
    /* Stamp alpha to 0xFF on every pixel. */
    for (int32_t y = 0; y < h; y++) {
      uint8_t *row = dst + (intptr_t)y * dstStride;
      for (int32_t x = 0; x < w; x++) {
        row[x * 4 + 3] = 0xFF;
      }
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

  /* WebKit's handleMouseDraggedEvent checks that the motion event's
   * "button" field is Left (= 1 in WPE) — that's how it knows the
   * drag should extend a text selection rather than be a plain hover.
   * Motion events with button=0 cause WebKit to short-circuit out of
   * the drag-selection path.  So derive button from the held-buttons
   * bitmask (lowest-numbered held button wins, matching what real
   * X11/Wayland pointer streams produce). */
  uint32_t button = 0;
  if (modifiers & wpe_input_pointer_modifier_button1)      button = 1;
  else if (modifiers & wpe_input_pointer_modifier_button2) button = 2;
  else if (modifiers & wpe_input_pointer_modifier_button3) button = 3;

  struct wpe_input_pointer_event ev = {
      .type      = wpe_input_pointer_event_type_motion,
      .time      = timestamp,
      .x         = (int)point.x,
      .y         = (int)point.y,
      .button    = button,
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

- (void)clearPumpFDSources
{
  for (NSValue *v in _pumpFDSources) {
    dispatch_source_t s = (dispatch_source_t)[v pointerValue];
    dispatch_source_cancel(s);
    dispatch_release(s);
  }
  [_pumpFDSources removeAllObjects];
}

/* Drive the default GMainContext by asking GLib for the pollfds and
 * timeout it would normally poll on, then watching each pollfd with a
 * libdispatch source and arming a single-shot NSTimer for the timeout.
 * When either fires (or both), we run one iteration of the context
 * (which prepares, queries, polls, checks, dispatches internally)
 * and re-arm.  Net effect: zero CPU when nothing's happening, instant
 * wake when a socket has data. */
- (void)pumpIterate
{
  if (!_pumpRunning) return;

  GMainContext *ctx = g_main_context_default();

  /* Drain anything ready right now without blocking.  Calling
   * g_main_context_iteration(ctx, FALSE) in a loop ensures cascading
   * sources (one source's dispatch fires another) all settle before
   * we re-arm. */
  while (g_main_context_iteration(ctx, FALSE)) {
    if (!_pumpRunning) return;
  }

  /* Discover the next pollfd set and timeout. */
  gint max_priority = 0;
  if (g_main_context_acquire(ctx)) {
    g_main_context_prepare(ctx, &max_priority);
    g_main_context_release(ctx);
  } else {
    /* Another thread holds the context; just re-arm a short timer. */
    [self _schedulePumpNextWake:16];
    return;
  }

  GPollFD fds[64];
  gint timeout_ms = -1;
  gint nfds = g_main_context_query(ctx, max_priority,
                                    &timeout_ms, fds, 64);

  /* Reinstall fd watchers.  Cancelling and recreating each iteration
   * is wasteful but the set rarely changes — GLib's IO sources are
   * stable for the lifetime of a network operation — and the cost is
   * dwarfed by the rendering pipeline. */
  [self clearPumpFDSources];
  for (gint i = 0; i < nfds; i++) {
    if (fds[i].events & G_IO_IN) {
      dispatch_source_t s = dispatch_source_create(
          DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fds[i].fd, 0,
          dispatch_get_main_queue());
      __block GSWebKitWPE *unretainedSelf = self;
      dispatch_source_set_event_handler(s, ^{
        /* The backend cancels and releases every dispatch source in
         * -shutdown before -[dealloc] returns, so an in-flight handler
         * running after we've been freed is impossible.  Safe to call
         * straight through without __weak (MRC, no __weak available). */
        [unretainedSelf pumpIterate];
      });
      dispatch_resume(s);
      [_pumpFDSources addObject:[NSValue valueWithPointer:s]];
    }
  }

  [self _schedulePumpNextWake:timeout_ms];
}

- (void)_schedulePumpNextWake:(gint)timeout_ms
{
  [_pumpTimer invalidate];
  [_pumpTimer release];
  _pumpTimer = nil;
  NSTimeInterval iv;
  if (timeout_ms < 0) {
    /* GLib has nothing scheduled.  A 1-second backstop is a safety net
     * (if our fd watchers miss anything, we still iterate every
     * second; in practice they don't miss). */
    iv = 1.0;
  } else if (timeout_ms == 0) {
    iv = 0.0;
  } else {
    iv = (NSTimeInterval)timeout_ms / 1000.0;
  }
  _pumpTimer = [[NSTimer scheduledTimerWithTimeInterval:iv
                                                 target:self
                                               selector:@selector(_pumpTimerFired:)
                                               userInfo:nil
                                                repeats:NO] retain];
  [[NSRunLoop currentRunLoop] addTimer:_pumpTimer forMode:NSRunLoopCommonModes];
}

- (void)_pumpTimerFired:(NSTimer *)timer
{
  (void)timer;
  if (!_pumpRunning) return;
  GMainContext *ctx = g_main_context_default();
  while (g_main_context_iteration(ctx, FALSE)) {
    if (!_pumpRunning) return;
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

static void
GSWPE_OnMouseTargetChanged(WebKitWebView *view, WebKitHitTestResult *hit,
                           guint modifiers, gpointer ud)
{
  (void)view; (void)modifiers;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  BOOL isLink     = webkit_hit_test_result_context_is_link(hit);
  BOOL isImage    = webkit_hit_test_result_context_is_image(hit);
  BOOL isMedia    = webkit_hit_test_result_context_is_media(hit);
  BOOL isEditable = webkit_hit_test_result_context_is_editable(hit);
  BOOL isSelection= webkit_hit_test_result_context_is_selection(hit);

  NSString *token = @"default";
  if (isLink) {
    token = @"pointer";
  } else if (isEditable || isSelection) {
    token = @"text";
  }

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  [info setObject:[NSNumber numberWithBool:isLink]      forKey:GSWebKitMouseTargetIsLink];
  [info setObject:[NSNumber numberWithBool:isImage]     forKey:GSWebKitMouseTargetIsImage];
  [info setObject:[NSNumber numberWithBool:isMedia]     forKey:GSWebKitMouseTargetIsMedia];
  [info setObject:[NSNumber numberWithBool:isEditable]  forKey:GSWebKitMouseTargetIsEditable];
  [info setObject:[NSNumber numberWithBool:isSelection] forKey:GSWebKitMouseTargetIsSelection];
  if (isLink) {
    const gchar *u = webkit_hit_test_result_get_link_uri(hit);
    if (u != NULL) [info setObject:[NSString stringWithUTF8String:u]
                            forKey:GSWebKitMouseTargetLinkURL];
  }
  if (isImage) {
    const gchar *u = webkit_hit_test_result_get_image_uri(hit);
    if (u != NULL) [info setObject:[NSString stringWithUTF8String:u]
                            forKey:GSWebKitMouseTargetImageURL];
  }
  if (isMedia) {
    const gchar *u = webkit_hit_test_result_get_media_uri(hit);
    if (u != NULL) [info setObject:[NSString stringWithUTF8String:u]
                            forKey:GSWebKitMouseTargetMediaURL];
  }

  id <GSWebKitBackendHost> host = [self host];
  if ([host respondsToSelector:@selector(backend:didChangeMouseCursor:)]) {
    [host backend:self didChangeMouseCursor:token];
  }
  if ([host respondsToSelector:@selector(backend:didChangeMouseTargetInfo:)]) {
    [host backend:self didChangeMouseTargetInfo:info];
  }
  [pool release];
}

/* ------------------------------------------------------------------ */
#pragma mark Download bridge

/* The user_data pointer we attach to each WebKitDownload's signal
 * closures.  Carries the backend back-pointer and the cached
 * destination URL (NSURL strong reference; explicitly released on
 * finish/fail). */
struct GSWPE_DownloadCtx {
  GSWebKitWPE *backend;
  NSURL       *destination;       /* retained */
};

static void GSWPE_DownloadCtxFree(gpointer data, GClosure *closure)
{
  (void)closure;
  struct GSWPE_DownloadCtx *c = data;
  if (c == NULL) return;
  [c->destination release];
  g_free(c);
}

static void
GSWPE_OnDownloadStarted(WebKitWebContext *ctx, WebKitDownload *download, gpointer ud)
{
  (void)ctx;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;

  /* Hook the per-download signals.  Each gets its own context so we
   * can stash the chosen destination for the finished/failed
   * callbacks. */
  struct GSWPE_DownloadCtx *c = g_new0(struct GSWPE_DownloadCtx, 1);
  c->backend = self;
  g_signal_connect_data(download, "decide-destination",
                        G_CALLBACK(GSWPE_OnDownloadDecideDestination),
                        c, GSWPE_DownloadCtxFree, (GConnectFlags)0);
  g_signal_connect(download, "finished",
                   G_CALLBACK(GSWPE_OnDownloadFinished), self);
  g_signal_connect(download, "failed",
                   G_CALLBACK(GSWPE_OnDownloadFailed), self);
}

static gboolean
GSWPE_OnDownloadDecideDestination(WebKitDownload *download,
                                  const gchar *suggested,
                                  gpointer ud)
{
  struct GSWPE_DownloadCtx *c = ud;
  if (c == NULL) return FALSE;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  WebKitURIResponse *uri_resp = webkit_download_get_response(download);
  NSString *mime = nil;
  if (uri_resp != NULL) {
    const gchar *m = webkit_uri_response_get_mime_type(uri_resp);
    if (m) mime = [NSString stringWithUTF8String:m];
  }
  NSURLResponse *response =
      [[[NSURLResponse alloc] initWithURL:nil
                                  MIMEType:mime
                     expectedContentLength:-1
                          textEncodingName:nil] autorelease];
  NSString *name = (suggested != NULL)
      ? [NSString stringWithUTF8String:suggested]
      : @"download";

  id <GSWebKitBackendHost> host = [c->backend host];

  /* The destination decision is synchronous from WebKit's point of
   * view (we must call set_destination before returning).  We block
   * the GMain loop until the host's NSSavePanel returns by running an
   * inner NSRunLoop spin.  This is the same pattern Cocoa uses for
   * modal panels driven from a non-main thread... except we ARE on
   * the main thread, so we just run the panel inline. */
  __block NSURL *chosen = nil;
  __block BOOL responded = NO;
  if ([host respondsToSelector:
          @selector(backend:didStartDownloadOfFilename:response:completion:)]) {
    [host backend:c->backend
        didStartDownloadOfFilename:name
                          response:response
                        completion:^(NSURL *dest) {
      chosen = [dest retain];
      responded = YES;
    }];
    /* The NSSavePanel runs modal so by here responded should be YES.
     * If it isn't (delegate-async style), fall through to cancel. */
  }
  if (!responded || chosen == nil) {
    webkit_download_cancel(download);
    [pool release];
    return TRUE;
  }
  c->destination = chosen;  /* take ownership */
  NSString *fileURI = [NSString stringWithFormat:@"file://%@", [chosen path]];
  webkit_download_set_destination(download, [fileURI UTF8String]);
  [pool release];
  return TRUE;
}

static void
GSWPE_OnDownloadFinished(WebKitDownload *download, gpointer ud)
{
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  const gchar *dest = webkit_download_get_destination(download);
  NSURL *destURL = nil;
  if (dest != NULL) {
    NSString *path = [NSString stringWithUTF8String:dest];
    if ([path hasPrefix:@"file://"]) {
      path = [path substringFromIndex:7];
    }
    destURL = [NSURL fileURLWithPath:path];
  }
  id <GSWebKitBackendHost> host = [self host];
  if ([host respondsToSelector:@selector(backend:didFinishDownloadToURL:)]) {
    [host backend:self didFinishDownloadToURL:destURL];
  }
  [pool release];
}

static void
GSWPE_OnDownloadFailed(WebKitDownload *download, GError *err, gpointer ud)
{
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *desc = (err && err->message) ? [NSString stringWithUTF8String:err->message]
                                          : @"Download failed";
  NSError *nserr = [NSError errorWithDomain:WKErrorDomain
                                       code:WKErrorUnknown
                                   userInfo:[NSDictionary dictionaryWithObject:desc
                                                                        forKey:NSLocalizedDescriptionKey]];
  const gchar *dest = webkit_download_get_destination(download);
  NSURL *destURL = nil;
  if (dest != NULL) {
    NSString *path = [NSString stringWithUTF8String:dest];
    if ([path hasPrefix:@"file://"]) path = [path substringFromIndex:7];
    destURL = [NSURL fileURLWithPath:path];
  }
  id <GSWebKitBackendHost> host = [self host];
  if ([host respondsToSelector:@selector(backend:didFailDownloadWithError:destination:)]) {
    [host backend:self didFailDownloadWithError:nserr destination:destURL];
  }
  [pool release];
}

void GSWebKitWPE_CancelDownload(id engineHandle)
{
  /* Stub for WKDownload's -cancel: — the public WKDownload API hands
   * us an engine handle wrapping the WebKitDownload*.  v1 doesn't
   * carry the original WebKitDownload through to the public side, so
   * this is a no-op.  Cancel of an in-flight download isn't yet wired
   * end-to-end; documented as a v1 follow-up. */
  (void)engineHandle;
}


static gboolean
GSWPE_OnRunFileChooser(WebKitWebView *view, WebKitFileChooserRequest *request, gpointer ud)
{
  (void)view;
  GSWebKitWPE *self = (GSWebKitWPE *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  gboolean multiple = webkit_file_chooser_request_get_select_multiple(request);
  const gchar * const *mimes = webkit_file_chooser_request_get_mime_types(request);
  NSMutableArray *mimeTypes = [NSMutableArray array];
  if (mimes != NULL) {
    for (int i = 0; mimes[i] != NULL; i++) {
      [mimeTypes addObject:[NSString stringWithUTF8String:mimes[i]]];
    }
  }

  /* Keep the request alive across the async NSOpenPanel callback. */
  g_object_ref(request);

  id <GSWebKitBackendHost> host = [self host];
  if (![host respondsToSelector:
          @selector(backend:runFileChooserAllowingMultiple:mimeTypes:completion:)]) {
    webkit_file_chooser_request_cancel(request);
    g_object_unref(request);
    [pool release];
    return TRUE;
  }

  [host backend:self
      runFileChooserAllowingMultiple:(BOOL)multiple
                           mimeTypes:mimeTypes
                          completion:^(NSArray *urls) {
    if ([urls count] == 0) {
      webkit_file_chooser_request_cancel(request);
    } else {
      NSUInteger n = [urls count];
      const gchar **paths = g_new0(const gchar *, n + 1);
      for (NSUInteger i = 0; i < n; i++) {
        NSURL *u = [urls objectAtIndex:i];
        paths[i] = [[u path] UTF8String];
      }
      webkit_file_chooser_request_select_files(request, paths);
      g_free(paths);
    }
    g_object_unref(request);
  }];

  [pool release];
  return TRUE;
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
