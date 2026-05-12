/* wktests.m
 *
 * Unit tests for value-type classes in the WebKit framework.  No
 * NSApplication, no WKWebView (which requires an engine).  Just
 * exercise the API contracts.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#include <stdio.h>

/* Re-declare the small slice of internal API we need to drive the
 * value types from outside the framework's own implementation files. */
@interface WKBackForwardListItem (_Test)
- (instancetype)_initWithURL:(NSURL *)url
                  initialURL:(NSURL *)initialURL
                       title:(NSString *)title;
@end
@interface WKBackForwardList (_Test)
- (void)_appendItem:(WKBackForwardListItem *)item;
@end
@interface WKUserContentController (_Test)
- (NSArray *)_handlers;
@end

static int g_pass = 0;
static int g_fail = 0;

#define EXPECT(cond, msg) do { \
    if (cond) { g_pass++; fprintf(stderr, "  PASS %s\n", msg); } \
    else      { g_fail++; fprintf(stderr, "  FAIL %s\n", msg); } \
  } while (0)


static void test_WKWebViewConfiguration_defaults(void)
{
  fprintf(stderr, "[WKWebViewConfiguration defaults]\n");
  WKWebViewConfiguration *c = [[[WKWebViewConfiguration alloc] init] autorelease];
  EXPECT([c processPool] != nil, "processPool not nil");
  EXPECT([c preferences] != nil, "preferences not nil");
  EXPECT([c userContentController] != nil, "userContentController not nil");
  EXPECT([c websiteDataStore] != nil, "websiteDataStore not nil");
  EXPECT([[c preferences] javaScriptEnabled], "JS enabled by default");
}

static void test_WKWebViewConfiguration_copy(void)
{
  fprintf(stderr, "[WKWebViewConfiguration copy]\n");
  WKWebViewConfiguration *a = [[[WKWebViewConfiguration alloc] init] autorelease];
  [a setApplicationNameForUserAgent:@"TestApp/1"];
  [[a preferences] setJavaScriptCanOpenWindowsAutomatically:YES];
  WKWebViewConfiguration *b = [[a copy] autorelease];
  EXPECT([[b applicationNameForUserAgent] isEqualToString:@"TestApp/1"],
         "applicationNameForUserAgent carried");
  EXPECT([[b preferences] javaScriptCanOpenWindowsAutomatically],
         "preferences carried");
  /* Mutate b; a should be unchanged. */
  [b setApplicationNameForUserAgent:@"TestApp/2"];
  EXPECT([[a applicationNameForUserAgent] isEqualToString:@"TestApp/1"],
         "original unchanged after copy mutation");
}

static void test_WKBackForwardList_appends(void)
{
  fprintf(stderr, "[WKBackForwardList appends]\n");
  WKBackForwardList *list = [[[WKBackForwardList alloc] init] autorelease];
  EXPECT([list currentItem] == nil, "empty list has no current");
  EXPECT([[list backList] count] == 0, "empty back list");

  /* Use private API to append. */
  NSURL *u1 = [NSURL URLWithString:@"http://a.example/"];
  WKBackForwardListItem *i1 =
      [[[WKBackForwardListItem alloc] _initWithURL:u1
                                        initialURL:u1
                                             title:@"A"] autorelease];
  [list _appendItem:i1];
  EXPECT([[list currentItem] URL] != nil, "currentItem after 1 append");
  EXPECT([[[list currentItem] URL] isEqual:u1], "currentItem URL matches");

  NSURL *u2 = [NSURL URLWithString:@"http://b.example/"];
  WKBackForwardListItem *i2 =
      [[[WKBackForwardListItem alloc] _initWithURL:u2
                                        initialURL:u2
                                             title:@"B"] autorelease];
  [list _appendItem:i2];
  EXPECT([[[list currentItem] URL] isEqual:u2], "currentItem advances");
  EXPECT([[list backList] count] == 1, "one item in back list");
  EXPECT([[[list backItem] URL] isEqual:u1], "backItem is u1");
}

static void test_WKUserContentController_scripts(void)
{
  fprintf(stderr, "[WKUserContentController scripts]\n");
  WKUserContentController *ucc =
      [[[WKUserContentController alloc] init] autorelease];
  EXPECT([[ucc userScripts] count] == 0, "no scripts initially");

  WKUserScript *s =
      [[[WKUserScript alloc] initWithSource:@"console.log('hi')"
                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                           forMainFrameOnly:YES] autorelease];
  [ucc addUserScript:s];
  EXPECT([[ucc userScripts] count] == 1, "one script after add");
  EXPECT([[ucc userScripts] containsObject:s], "script returned in list");

  [ucc removeAllUserScripts];
  EXPECT([[ucc userScripts] count] == 0, "scripts cleared");
}

static void test_WKUserContentController_handlers(void)
{
  fprintf(stderr, "[WKUserContentController message handlers]\n");
  WKUserContentController *ucc =
      [[[WKUserContentController alloc] init] autorelease];
  /* Use NSObject as a stand-in handler; we only need a non-nil object. */
  id handler = [[[NSObject alloc] init] autorelease];
  [ucc addScriptMessageHandler:(id <WKScriptMessageHandler>)handler name:@"foo"];
  [ucc addScriptMessageHandler:(id <WKScriptMessageHandler>)handler name:@"bar"];
  EXPECT([[ucc _handlers] count] == 2, "two handlers registered");
  [ucc removeScriptMessageHandlerForName:@"foo"];
  EXPECT([[ucc _handlers] count] == 1, "one after removeScriptMessageHandlerForName");
  [ucc removeAllScriptMessageHandlers];
  EXPECT([[ucc _handlers] count] == 0, "cleared by removeAll");
}

static void test_WKUserScript_copy(void)
{
  fprintf(stderr, "[WKUserScript copy]\n");
  WKUserScript *s =
      [[[WKUserScript alloc] initWithSource:@"42"
                              injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                           forMainFrameOnly:NO] autorelease];
  WKUserScript *c = [[s copy] autorelease];
  EXPECT([[s source] isEqualToString:[c source]], "source carried");
  EXPECT([s injectionTime] == [c injectionTime], "injectionTime carried");
  EXPECT([s isForMainFrameOnly] == [c isForMainFrameOnly], "forMainFrameOnly carried");
}

static void test_WKFindConfiguration_defaults(void)
{
  fprintf(stderr, "[WKFindConfiguration defaults]\n");
  WKFindConfiguration *fc = [[[WKFindConfiguration alloc] init] autorelease];
  EXPECT([fc wraps] == YES, "wraps defaults to YES");
  EXPECT([fc backwards] == NO, "backwards defaults to NO");
  EXPECT([fc caseSensitive] == NO, "caseSensitive defaults to NO");
}

static void test_WKContentWorld_singletons(void)
{
  fprintf(stderr, "[WKContentWorld singletons]\n");
  WKContentWorld *a = [WKContentWorld pageWorld];
  WKContentWorld *b = [WKContentWorld pageWorld];
  EXPECT(a == b, "pageWorld is singleton");
  WKContentWorld *x = [WKContentWorld worldWithName:@"my-world"];
  WKContentWorld *y = [WKContentWorld worldWithName:@"my-world"];
  EXPECT(x == y, "named worlds are interned");
  EXPECT([[x name] isEqualToString:@"my-world"], "name preserved");
}

static void test_WKWebViewConfiguration_schemeHandlers(void)
{
  fprintf(stderr, "[WKWebViewConfiguration scheme handlers]\n");
  WKWebViewConfiguration *c = [[[WKWebViewConfiguration alloc] init] autorelease];
  id handler = [[[NSObject alloc] init] autorelease];
  [c setURLSchemeHandler:(id <WKURLSchemeHandler>)handler forURLScheme:@"myapp"];
  EXPECT([c urlSchemeHandlerForURLScheme:@"myapp"] == handler,
         "scheme handler stored");
  EXPECT([c urlSchemeHandlerForURLScheme:@"MYAPP"] == handler,
         "scheme lookup is case insensitive");
  [c setURLSchemeHandler:nil forURLScheme:@"myapp"];
  EXPECT([c urlSchemeHandlerForURLScheme:@"myapp"] == nil,
         "scheme handler cleared with nil");
}


int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  test_WKWebViewConfiguration_defaults();
  test_WKWebViewConfiguration_copy();
  test_WKBackForwardList_appends();
  test_WKUserContentController_scripts();
  test_WKUserContentController_handlers();
  test_WKUserScript_copy();
  test_WKFindConfiguration_defaults();
  test_WKContentWorld_singletons();
  test_WKWebViewConfiguration_schemeHandlers();

  fprintf(stderr, "\n==== %d passed, %d failed ====\n", g_pass, g_fail);
  [pool release];
  return (g_fail == 0) ? 0 : 1;
}
