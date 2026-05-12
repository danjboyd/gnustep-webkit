/* WKHTTPCookieStore.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <WebKit/WKHTTPCookieStore.h>
#import "GSWebKitInternal.h"

#include <glib.h>
#include <gio/gio.h>
#include <wpe/webkit.h>
#include <libsoup/soup.h>

/* Helpers to bridge SoupCookie <-> NSHTTPCookie. */

static NSHTTPCookie *NSHTTPCookieFromSoup(SoupCookie *sc)
{
  if (sc == NULL) return nil;
  NSMutableDictionary *props = [NSMutableDictionary dictionary];
  [props setObject:[NSString stringWithUTF8String:soup_cookie_get_name(sc)]
            forKey:NSHTTPCookieName];
  [props setObject:[NSString stringWithUTF8String:soup_cookie_get_value(sc)]
            forKey:NSHTTPCookieValue];
  const char *dom = soup_cookie_get_domain(sc);
  if (dom) [props setObject:[NSString stringWithUTF8String:dom]
                     forKey:NSHTTPCookieDomain];
  const char *path = soup_cookie_get_path(sc);
  if (path) [props setObject:[NSString stringWithUTF8String:path]
                      forKey:NSHTTPCookiePath];
  if (soup_cookie_get_secure(sc)) {
    [props setObject:@"TRUE" forKey:NSHTTPCookieSecure];
  }
  GDateTime *expires = soup_cookie_get_expires(sc);
  if (expires != NULL) {
    gint64 unix_sec = g_date_time_to_unix(expires);
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)unix_sec];
    [props setObject:d forKey:NSHTTPCookieExpires];
  }
  return [NSHTTPCookie cookieWithProperties:props];
}

static SoupCookie *SoupCookieFromNS(NSHTTPCookie *nsc)
{
  if (nsc == nil) return NULL;
  const char *name   = [[nsc name]   UTF8String];
  const char *value  = [[nsc value]  UTF8String];
  const char *dom    = [[nsc domain] UTF8String] ?: ".";
  const char *path   = [[nsc path]   UTF8String] ?: "/";
  SoupCookie *sc = soup_cookie_new(name, value, dom, path,
                                    [nsc expiresDate] != nil ? -1 : -1);
  if ([nsc expiresDate] != nil) {
    GDateTime *dt = g_date_time_new_from_unix_utc(
        (gint64)[[nsc expiresDate] timeIntervalSince1970]);
    soup_cookie_set_expires(sc, dt);
    g_date_time_unref(dt);
  }
  soup_cookie_set_secure(sc, [nsc isSecure]);
  return sc;
}


/* ----------------------------------------------------------- */

@interface _GSWKCookieGAsyncCtx : NSObject
{
@public
  void (^block)(NSArray *);
  void (^voidBlock)(void);
}
@end
@implementation _GSWKCookieGAsyncCtx @end


@implementation WKHTTPCookieStore
{
  WebKitCookieManager *_cookies;   /* unowned */
  NSMutableArray      *_observers;
}

- (instancetype)_initWithCookieManager:(void *)manager
{
  self = [super init];
  if (self != nil) {
    _cookies = (WebKitCookieManager *)manager;
    _observers = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc
{
  [_observers release];
  [super dealloc];
}

- (void)addObserver:(id <WKHTTPCookieStoreObserver>)observer
{
  [_observers addObject:[NSValue valueWithNonretainedObject:observer]];
}

- (void)removeObserver:(id <WKHTTPCookieStoreObserver>)observer
{
  for (NSUInteger i = 0; i < [_observers count]; i++) {
    if ([[_observers objectAtIndex:i] nonretainedObjectValue] == observer) {
      [_observers removeObjectAtIndex:i];
      return;
    }
  }
}

static void _gswk_get_all_cookies_done(GObject *src, GAsyncResult *res, gpointer ud)
{
  WebKitCookieManager *mgr = (WebKitCookieManager *)src;
  _GSWKCookieGAsyncCtx *ctx = (_GSWKCookieGAsyncCtx *)ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  GError *err = NULL;
  GList *list = webkit_cookie_manager_get_all_cookies_finish(mgr, res, &err);
  NSMutableArray *out = [NSMutableArray array];
  for (GList *l = list; l != NULL; l = l->next) {
    NSHTTPCookie *c = NSHTTPCookieFromSoup((SoupCookie *)l->data);
    if (c) [out addObject:c];
    soup_cookie_free((SoupCookie *)l->data);
  }
  g_list_free(list);
  if (err) g_error_free(err);
  if (ctx->block) {
    ctx->block(out);
    Block_release(ctx->block);
  }
  [ctx release];
  [pool release];
}

- (void)getAllCookies:(void (^)(NSArray *))completionHandler
{
  if (_cookies == NULL) {
    if (completionHandler) completionHandler([NSArray array]);
    return;
  }
  _GSWKCookieGAsyncCtx *ctx = [[_GSWKCookieGAsyncCtx alloc] init];
  ctx->block = Block_copy(completionHandler);
  /* WPE 2.40+ has get_all_cookies which returns the full jar; the
   * older per-URI get_cookies needed a URI and filtered to it. */
  webkit_cookie_manager_get_all_cookies(_cookies, NULL,
                                         _gswk_get_all_cookies_done, ctx);
}

static void _gswk_void_done(GObject *src, GAsyncResult *res, gpointer ud)
{
  (void)src; (void)res;
  _GSWKCookieGAsyncCtx *ctx = (_GSWKCookieGAsyncCtx *)ud;
  if (ctx->voidBlock) {
    ctx->voidBlock();
    Block_release(ctx->voidBlock);
  }
  [ctx release];
}

- (void)setCookie:(NSHTTPCookie *)cookie
   completionHandler:(void (^)(void))completionHandler
{
  if (_cookies == NULL || cookie == nil) {
    if (completionHandler) completionHandler();
    return;
  }
  SoupCookie *sc = SoupCookieFromNS(cookie);
  _GSWKCookieGAsyncCtx *ctx = [[_GSWKCookieGAsyncCtx alloc] init];
  ctx->voidBlock = completionHandler ? Block_copy(completionHandler) : NULL;
  webkit_cookie_manager_add_cookie(_cookies, sc, NULL, _gswk_void_done, ctx);
  soup_cookie_free(sc);
}

- (void)deleteCookie:(NSHTTPCookie *)cookie
    completionHandler:(void (^)(void))completionHandler
{
  if (_cookies == NULL || cookie == nil) {
    if (completionHandler) completionHandler();
    return;
  }
  SoupCookie *sc = SoupCookieFromNS(cookie);
  _GSWKCookieGAsyncCtx *ctx = [[_GSWKCookieGAsyncCtx alloc] init];
  ctx->voidBlock = completionHandler ? Block_copy(completionHandler) : NULL;
  webkit_cookie_manager_delete_cookie(_cookies, sc, NULL, _gswk_void_done, ctx);
  soup_cookie_free(sc);
}

@end
