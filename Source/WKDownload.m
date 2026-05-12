/* WKDownload.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <WebKit/WKDownload.h>
#import <WebKit/WKDownloadDelegate.h>
#import "GSWebKitInternal.h"

@implementation WKDownload
{
  id <WKDownloadDelegate> _delegate;
  NSURLRequest *_originalRequest;
  WKWebView    *_webView;
  NSProgress   *_progress;
  /* Opaque pointer back to the engine-side download handle.  Kept as
   * id (NSValue-wrapped) so this header doesn't have to import
   * <wpe/webkit.h>.  See WKDownloadInternal category. */
  id            _engineHandle;
}

@synthesize delegate = _delegate;
@synthesize originalRequest = _originalRequest;
@synthesize webView = _webView;
@synthesize progress = _progress;

- (instancetype)_initWithEngineHandle:(id)handle
                              request:(NSURLRequest *)request
                              webView:(WKWebView *)webView
{
  self = [super init];
  if (self != nil) {
    _engineHandle = [handle retain];
    _originalRequest = [request copy];
    _webView = webView;
    _progress = [[NSProgress alloc] init];
    [_progress setTotalUnitCount:-1];
  }
  return self;
}

- (id)_engineHandle
{
  return _engineHandle;
}

- (void)_setProgressCompletedUnitCount:(int64_t)bytes total:(int64_t)total
{
  [_progress setTotalUnitCount:total];
  [_progress setCompletedUnitCount:bytes];
}

- (void)cancel:(void (^)(NSData *resumeData))completionHandler
{
  /* WPE WebKit's download cancel is fire-and-forget; there's no
   * resume-data concept in libwpewebkit currently.  Honour the API by
   * invoking the completion handler with nil. */
  if (_engineHandle != nil) {
    extern void GSWebKitWPE_CancelDownload(id engineHandle);
    GSWebKitWPE_CancelDownload(_engineHandle);
  }
  if (completionHandler != NULL) {
    completionHandler(nil);
  }
}

- (void)dealloc
{
  [_engineHandle release];
  [_originalRequest release];
  [_progress release];
  [super dealloc];
}

@end
