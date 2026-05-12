/* WKContentRuleListStore.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <WebKit/WKContentRuleListStore.h>
#import "GSWebKitInternal.h"

#include <glib.h>
#include <gio/gio.h>
#include <wpe/webkit.h>

@implementation WKContentRuleList
{
  NSString *_identifier;
  WebKitUserContentFilter *_filter;   /* refcounted */
}

@synthesize identifier = _identifier;

- (instancetype)_initWithIdentifier:(NSString *)ident
                              filter:(WebKitUserContentFilter *)filter
{
  self = [super init];
  if (self != nil) {
    _identifier = [ident copy];
    _filter = (filter != NULL) ? (WebKitUserContentFilter *)webkit_user_content_filter_ref(filter) : NULL;
  }
  return self;
}

- (WebKitUserContentFilter *)_filter
{
  return _filter;
}

- (void)dealloc
{
  [_identifier release];
  if (_filter != NULL) webkit_user_content_filter_unref(_filter);
  [super dealloc];
}
@end


/* ------------------------------------------------------------------ */

@implementation WKContentRuleListStore
{
  WebKitUserContentFilterStore *_store;   /* refcounted */
  NSString                     *_path;
}

+ (WKContentRuleListStore *)defaultStore
{
  static WKContentRuleListStore *gDefault = nil;
  static NSLock *gLock = nil;
  if (gLock == nil) gLock = [[NSLock alloc] init];
  [gLock lock];
  if (gDefault == nil) {
    NSString *root = NSTemporaryDirectory();
    NSString *path = [root stringByAppendingPathComponent:@"WebKitContentRuleLists"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    gDefault = [[WKContentRuleListStore alloc] _initWithStoragePath:path];
  }
  [gLock unlock];
  return gDefault;
}

+ (WKContentRuleListStore *)storeForURL:(NSURL *)url
{
  if (url == nil) return nil;
  return [[[WKContentRuleListStore alloc] _initWithStoragePath:[url path]] autorelease];
}

- (instancetype)_initWithStoragePath:(NSString *)path
{
  self = [super init];
  if (self != nil) {
    _path = [path copy];
    _store = webkit_user_content_filter_store_new([path UTF8String]);
  }
  return self;
}

- (void)dealloc
{
  if (_store != NULL) g_object_unref(_store);
  [_path release];
  [super dealloc];
}

struct _gswk_filter_ctx {
  void (^block)(WKContentRuleList *, NSError *);
  NSString *identifier;   /* retained */
};

static void _gswk_filter_compile_done(GObject *src, GAsyncResult *res, gpointer ud)
{
  WebKitUserContentFilterStore *store = (WebKitUserContentFilterStore *)src;
  struct _gswk_filter_ctx *c = ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  GError *err = NULL;
  WebKitUserContentFilter *filter =
      webkit_user_content_filter_store_save_finish(store, res, &err);
  if (filter != NULL) {
    WKContentRuleList *list =
        [[[WKContentRuleList alloc] _initWithIdentifier:c->identifier
                                                  filter:filter] autorelease];
    webkit_user_content_filter_unref(filter);
    if (c->block) c->block(list, nil);
  } else {
    NSString *msg = (err && err->message) ? [NSString stringWithUTF8String:err->message]
                                          : @"Failed to compile content rule list";
    NSError *nse = [NSError errorWithDomain:@"WKContentRuleList" code:1
                                   userInfo:[NSDictionary dictionaryWithObject:msg
                                                                        forKey:NSLocalizedDescriptionKey]];
    if (c->block) c->block(nil, nse);
    if (err) g_error_free(err);
  }
  if (c->block) Block_release(c->block);
  [c->identifier release];
  g_free(c);
  [pool release];
}

- (void)compileContentRuleListForIdentifier:(NSString *)identifier
              encodedContentRuleList:(NSString *)json
                  completionHandler:(void (^)(WKContentRuleList *, NSError *))completion
{
  if (_store == NULL || [identifier length] == 0 || [json length] == 0) {
    if (completion) completion(nil, [NSError errorWithDomain:@"WKContentRuleList"
                                                          code:2 userInfo:nil]);
    return;
  }
  struct _gswk_filter_ctx *c = g_new0(struct _gswk_filter_ctx, 1);
  c->block = Block_copy(completion);
  c->identifier = [identifier copy];
  GBytes *bytes = g_bytes_new([json UTF8String], (gsize)[json lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
  webkit_user_content_filter_store_save(_store, [identifier UTF8String], bytes,
                                         NULL, _gswk_filter_compile_done, c);
  g_bytes_unref(bytes);
}

static void _gswk_filter_load_done(GObject *src, GAsyncResult *res, gpointer ud)
{
  WebKitUserContentFilterStore *store = (WebKitUserContentFilterStore *)src;
  struct _gswk_filter_ctx *c = ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  GError *err = NULL;
  WebKitUserContentFilter *filter =
      webkit_user_content_filter_store_load_finish(store, res, &err);
  if (filter != NULL) {
    WKContentRuleList *list =
        [[[WKContentRuleList alloc] _initWithIdentifier:c->identifier
                                                  filter:filter] autorelease];
    webkit_user_content_filter_unref(filter);
    if (c->block) c->block(list, nil);
  } else {
    NSString *msg = (err && err->message) ? [NSString stringWithUTF8String:err->message]
                                          : @"Content rule list not found";
    NSError *nse = [NSError errorWithDomain:@"WKContentRuleList" code:3
                                   userInfo:[NSDictionary dictionaryWithObject:msg
                                                                        forKey:NSLocalizedDescriptionKey]];
    if (c->block) c->block(nil, nse);
    if (err) g_error_free(err);
  }
  if (c->block) Block_release(c->block);
  [c->identifier release];
  g_free(c);
  [pool release];
}

- (void)lookUpContentRuleListForIdentifier:(NSString *)identifier
                          completionHandler:(void (^)(WKContentRuleList *, NSError *))completion
{
  if (_store == NULL || [identifier length] == 0) {
    if (completion) completion(nil, nil);
    return;
  }
  struct _gswk_filter_ctx *c = g_new0(struct _gswk_filter_ctx, 1);
  c->block = Block_copy(completion);
  c->identifier = [identifier copy];
  webkit_user_content_filter_store_load(_store, [identifier UTF8String], NULL,
                                         _gswk_filter_load_done, c);
}

struct _gswk_filter_remove_ctx {
  void (^block)(NSError *);
};

static void _gswk_filter_remove_done(GObject *src, GAsyncResult *res, gpointer ud)
{
  WebKitUserContentFilterStore *store = (WebKitUserContentFilterStore *)src;
  struct _gswk_filter_remove_ctx *c = ud;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  GError *err = NULL;
  gboolean ok = webkit_user_content_filter_store_remove_finish(store, res, &err);
  if (!ok) {
    NSString *msg = (err && err->message) ? [NSString stringWithUTF8String:err->message]
                                          : @"Failed to remove rule list";
    NSError *nse = [NSError errorWithDomain:@"WKContentRuleList" code:4
                                   userInfo:[NSDictionary dictionaryWithObject:msg
                                                                        forKey:NSLocalizedDescriptionKey]];
    if (c->block) c->block(nse);
    if (err) g_error_free(err);
  } else {
    if (c->block) c->block(nil);
  }
  if (c->block) Block_release(c->block);
  g_free(c);
  [pool release];
}

- (void)removeContentRuleListForIdentifier:(NSString *)identifier
                          completionHandler:(void (^)(NSError *))completion
{
  if (_store == NULL || [identifier length] == 0) {
    if (completion) completion(nil);
    return;
  }
  struct _gswk_filter_remove_ctx *c = g_new0(struct _gswk_filter_remove_ctx, 1);
  c->block = Block_copy(completion);
  webkit_user_content_filter_store_remove(_store, [identifier UTF8String], NULL,
                                           _gswk_filter_remove_done, c);
}

@end
