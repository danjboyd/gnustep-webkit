/* WKURLSchemeTask.m
 *
 * Concrete _GSWKURLSchemeTask that wraps a WebKitURISchemeRequest and
 * implements the public WKURLSchemeTask protocol.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <WebKit/WKURLSchemeHandler.h>
#import "GSWebKitInternal.h"

#include <glib.h>
#include <gio/gio.h>
#include <wpe/webkit.h>

@interface _GSWKURLSchemeTask : NSObject <WKURLSchemeTask>
- (instancetype)_initWithRequest:(WebKitURISchemeRequest *)req;
@end

@implementation _GSWKURLSchemeTask
{
  WebKitURISchemeRequest *_req;     /* refcounted */
  NSURLRequest           *_nsReq;
  NSURLResponse          *_response;
  /* Buffered data when the consumer streams in chunks; we accumulate
   * and hand the whole thing to webkit_uri_scheme_request_finish
   * at -didFinish. */
  NSMutableData          *_buffer;
  BOOL                    _finished;
}

@synthesize request = _nsReq;

- (instancetype)_initWithRequest:(WebKitURISchemeRequest *)req
{
  self = [super init];
  if (self != nil) {
    _req = (WebKitURISchemeRequest *)g_object_ref(req);
    const char *uri = webkit_uri_scheme_request_get_uri(req);
    NSURL *u = (uri != NULL)
        ? [NSURL URLWithString:[NSString stringWithUTF8String:uri]] : nil;
    _nsReq = (u != nil) ? [[NSURLRequest requestWithURL:u] copy] : nil;
    _buffer = [[NSMutableData alloc] init];
  }
  return self;
}

- (void)dealloc
{
  if (_req != NULL) g_object_unref(_req);
  [_nsReq release];
  [_response release];
  [_buffer release];
  [super dealloc];
}

- (void)didReceiveResponse:(NSURLResponse *)response
{
  if (_finished) return;
  [_response release];
  _response = [response copy];
}

- (void)didReceiveData:(NSData *)data
{
  if (_finished || data == nil) return;
  [_buffer appendData:data];
}

- (void)didFinish
{
  if (_finished) return;
  _finished = YES;
  NSString *mime = [_response MIMEType] ?: @"application/octet-stream";
  GInputStream *stream = g_memory_input_stream_new_from_data(
      [_buffer bytes], (gssize)[_buffer length], NULL);
  webkit_uri_scheme_request_finish(_req, stream,
                                    (gint64)[_buffer length],
                                    [mime UTF8String]);
  g_object_unref(stream);
}

- (void)didFailWithError:(NSError *)error
{
  if (_finished) return;
  _finished = YES;
  GError *gerror = g_error_new(g_quark_from_static_string("WKURLScheme"),
                                (gint)[error code],
                                "%s", [[error localizedDescription] UTF8String] ?: "");
  webkit_uri_scheme_request_finish_error(_req, gerror);
  g_error_free(gerror);
}

@end


/* Static C trampoline that WebKit calls when a URL with a registered
 * custom scheme is loaded.  user_data is the (handler, webview)
 * pair stashed by the framework when the scheme was registered. */
struct _GSWKSchemeReg {
  id <WKURLSchemeHandler> handler;     /* weak per Apple convention */
  __unsafe_unretained id  webView;     /* weak */
};

void _GSWKSchemeReg_Free(void *p)
{
  g_free(p);
}

void _GSWKSchemeCallback(void *req_void, void *user_data)
{
  WebKitURISchemeRequest *req = (WebKitURISchemeRequest *)req_void;
  struct _GSWKSchemeReg *reg = user_data;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  _GSWKURLSchemeTask *task = [[[_GSWKURLSchemeTask alloc] _initWithRequest:req]
                                  autorelease];
  if ([reg->handler respondsToSelector:@selector(webView:startURLSchemeTask:)]) {
    [reg->handler webView:reg->webView startURLSchemeTask:task];
  } else {
    NSError *err = [NSError errorWithDomain:@"WKURLScheme" code:1 userInfo:nil];
    [task didFailWithError:err];
  }
  [pool release];
}
