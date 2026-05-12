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
- (void)_setCurrentIndex:(NSInteger)index;
@end
@interface WKUserContentController (_Test)
- (NSArray *)_handlers;
- (NSArray *)_ruleLists;
@end
@interface WKSecurityOrigin (_Test)
- (instancetype)_initWithProtocol:(NSString *)protocol
                             host:(NSString *)host
                             port:(NSInteger)port;
@end
@interface WKFrameInfo (_Test)
- (instancetype)_initWithMainFrame:(BOOL)mainFrame
                           request:(NSURLRequest *)request
                    securityOrigin:(WKSecurityOrigin *)origin
                           webView:(WKWebView *)webView;
@end
@interface WKNavigation (_Test)
- (instancetype)_initWithRequest:(NSURLRequest *)request
                       identifier:(uint64_t)identifier;
- (uint64_t)_identifier;
@end
@interface WKNavigationAction (_Test)
- (instancetype)_initWithRequest:(NSURLRequest *)request
                  navigationType:(WKNavigationType)navigationType
                     sourceFrame:(WKFrameInfo *)source
                     targetFrame:(WKFrameInfo *)target;
@end
@interface WKNavigationResponse (_Test)
- (instancetype)_initWithResponse:(NSURLResponse *)response
                     forMainFrame:(BOOL)forMainFrame
                  canShowMIMEType:(BOOL)canShow;
@end
@interface WKScriptMessage (_Test)
- (instancetype)_initWithName:(NSString *)name
                         body:(id)body
                      webView:(WKWebView *)webView
                    frameInfo:(WKFrameInfo *)frame
                        world:(WKContentWorld *)world;
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


static void test_WKBackForwardList_itemAtIndex(void)
{
  fprintf(stderr, "[WKBackForwardList itemAtIndex]\n");
  WKBackForwardList *list = [[[WKBackForwardList alloc] init] autorelease];
  NSURL *u1 = [NSURL URLWithString:@"http://a.example/"];
  NSURL *u2 = [NSURL URLWithString:@"http://b.example/"];
  NSURL *u3 = [NSURL URLWithString:@"http://c.example/"];
  [list _appendItem:[[[WKBackForwardListItem alloc]
      _initWithURL:u1 initialURL:u1 title:@"A"] autorelease]];
  [list _appendItem:[[[WKBackForwardListItem alloc]
      _initWithURL:u2 initialURL:u2 title:@"B"] autorelease]];
  [list _appendItem:[[[WKBackForwardListItem alloc]
      _initWithURL:u3 initialURL:u3 title:@"C"] autorelease]];
  EXPECT([[[list itemAtIndex:0] URL] isEqual:u3], "itemAtIndex:0 = current");
  EXPECT([[[list itemAtIndex:-1] URL] isEqual:u2], "itemAtIndex:-1 = back");
  EXPECT([[[list itemAtIndex:-2] URL] isEqual:u1], "itemAtIndex:-2 = back-2");
  EXPECT([list itemAtIndex:-3] == nil, "itemAtIndex out of range = nil");
  EXPECT([list itemAtIndex:1] == nil, "no forward yet");
  EXPECT([[list backList] count] == 2, "backList count");
  EXPECT([[list forwardList] count] == 0, "forwardList empty");
}

static void test_WKBackForwardListItem(void)
{
  fprintf(stderr, "[WKBackForwardListItem fields]\n");
  NSURL *initial = [NSURL URLWithString:@"http://a.example/"];
  NSURL *current = [NSURL URLWithString:@"http://a.example/page2"];
  WKBackForwardListItem *it = [[[WKBackForwardListItem alloc]
      _initWithURL:current initialURL:initial title:@"Page Two"] autorelease];
  EXPECT([[it URL] isEqual:current], "URL");
  EXPECT([[it initialURL] isEqual:initial], "initialURL distinct from URL");
  EXPECT([[it title] isEqualToString:@"Page Two"], "title");
}

static void test_WKPreferences_defaults(void)
{
  fprintf(stderr, "[WKPreferences defaults]\n");
  WKPreferences *p = [[[WKPreferences alloc] init] autorelease];
  EXPECT([p javaScriptEnabled] == YES, "JS enabled");
  EXPECT([p fraudulentWebsiteWarningEnabled] == YES, "fraud warning enabled");
  EXPECT([p javaScriptCanOpenWindowsAutomatically] == NO, "JS popups off");
  EXPECT([p minimumFontSize] == 0.0, "min font size 0");
  EXPECT([p isElementFullscreenEnabled] == NO, "fullscreen off");
  EXPECT([p isTextInteractionEnabled] == YES, "text interaction on");
  EXPECT([p shouldPrintBackgrounds] == NO, "print backgrounds off");
}

static void test_WKPreferences_mutations(void)
{
  fprintf(stderr, "[WKPreferences mutations]\n");
  WKPreferences *p = [[[WKPreferences alloc] init] autorelease];
  [p setJavaScriptEnabled:NO];
  EXPECT([p javaScriptEnabled] == NO, "JS off after set");
  [p setMinimumFontSize:12.0];
  EXPECT([p minimumFontSize] == 12.0, "min font 12");
  [p setShouldPrintBackgrounds:YES];
  EXPECT([p shouldPrintBackgrounds] == YES, "print bg on");
}

static void test_WKWebsiteDataStore(void)
{
  fprintf(stderr, "[WKWebsiteDataStore]\n");
  WKWebsiteDataStore *a = [WKWebsiteDataStore defaultDataStore];
  WKWebsiteDataStore *b = [WKWebsiteDataStore defaultDataStore];
  EXPECT(a == b, "defaultDataStore is a singleton");
  EXPECT([a isPersistent] == YES, "default is persistent");
  WKWebsiteDataStore *eph = [WKWebsiteDataStore nonPersistentDataStore];
  EXPECT([eph isPersistent] == NO, "nonPersistent is not persistent");
  EXPECT(eph != a, "nonPersistent is distinct from default");
  NSSet *types = [WKWebsiteDataStore allWebsiteDataTypes];
  EXPECT([types count] >= 5, "allWebsiteDataTypes has multiple entries");
  EXPECT([types containsObject:@"WKWebsiteDataTypeCookies"], "cookies type listed");
}

static void test_WKWebsiteDataStore_cookieStore(void)
{
  fprintf(stderr, "[WKWebsiteDataStore httpCookieStore]\n");
  WKHTTPCookieStore *cs1 =
      [[WKWebsiteDataStore defaultDataStore] httpCookieStore];
  WKHTTPCookieStore *cs2 =
      [[WKWebsiteDataStore defaultDataStore] httpCookieStore];
  EXPECT(cs1 != nil, "cookie store exists");
  EXPECT(cs1 == cs2, "cookie store is cached on the data store");
}

static void test_WKProcessPool(void)
{
  fprintf(stderr, "[WKProcessPool]\n");
  WKProcessPool *a = [[[WKProcessPool alloc] init] autorelease];
  WKProcessPool *b = [[[WKProcessPool alloc] init] autorelease];
  EXPECT(a != nil, "alloc/init returns object");
  EXPECT(a != b, "distinct instances are distinct identities");
}

static void test_WKSecurityOrigin(void)
{
  fprintf(stderr, "[WKSecurityOrigin]\n");
  WKSecurityOrigin *o = [[[WKSecurityOrigin alloc]
      _initWithProtocol:@"https" host:@"example.com" port:443] autorelease];
  EXPECT([[o protocol] isEqualToString:@"https"], "protocol carried");
  EXPECT([[o host] isEqualToString:@"example.com"], "host carried");
  EXPECT([o port] == 443, "port carried");
}

static void test_WKFrameInfo(void)
{
  fprintf(stderr, "[WKFrameInfo]\n");
  WKSecurityOrigin *o = [[[WKSecurityOrigin alloc]
      _initWithProtocol:@"https" host:@"example.com" port:443] autorelease];
  NSURLRequest *r = [NSURLRequest requestWithURL:
      [NSURL URLWithString:@"https://example.com/path"]];
  WKFrameInfo *f = [[[WKFrameInfo alloc]
      _initWithMainFrame:YES request:r securityOrigin:o webView:nil] autorelease];
  EXPECT([f isMainFrame] == YES, "main frame flag");
  EXPECT([f request] == r || [[[f request] URL] isEqual:[r URL]], "request carried");
  EXPECT([[f securityOrigin] host] != nil, "origin carried");

  WKFrameInfo *copy = [[f copy] autorelease];
  EXPECT([copy isMainFrame] == YES, "copy carries mainFrame");
  EXPECT([[[copy securityOrigin] host] isEqualToString:@"example.com"],
         "copy carries origin");
}

static void test_WKNavigation(void)
{
  fprintf(stderr, "[WKNavigation]\n");
  NSURLRequest *r = [NSURLRequest requestWithURL:
      [NSURL URLWithString:@"https://x.example/"]];
  WKNavigation *n = [[[WKNavigation alloc]
      _initWithRequest:r identifier:42] autorelease];
  EXPECT([[[n request] URL] isEqual:[r URL]], "request URL carried");
  EXPECT([n _identifier] == 42, "identifier carried");
}

static void test_WKNavigationAction(void)
{
  fprintf(stderr, "[WKNavigationAction]\n");
  NSURLRequest *r = [NSURLRequest requestWithURL:
      [NSURL URLWithString:@"https://x.example/"]];
  WKNavigationAction *a = [[[WKNavigationAction alloc]
      _initWithRequest:r
        navigationType:WKNavigationTypeLinkActivated
           sourceFrame:nil
           targetFrame:nil] autorelease];
  EXPECT([a navigationType] == WKNavigationTypeLinkActivated, "type");
  EXPECT([[[a request] URL] isEqual:[r URL]], "request");
  EXPECT([a shouldPerformDownload] == NO, "default not download");
}

static void test_WKNavigationResponse(void)
{
  fprintf(stderr, "[WKNavigationResponse]\n");
  NSURLResponse *resp = [[[NSURLResponse alloc]
      initWithURL:[NSURL URLWithString:@"https://x.example/"]
         MIMEType:@"text/html"
   expectedContentLength:100
   textEncodingName:@"utf-8"] autorelease];
  WKNavigationResponse *r = [[[WKNavigationResponse alloc]
      _initWithResponse:resp forMainFrame:YES canShowMIMEType:YES] autorelease];
  EXPECT([r isForMainFrame] == YES, "main frame");
  EXPECT([r canShowMIMEType] == YES, "can show");
  EXPECT([[[r response] MIMEType] isEqualToString:@"text/html"], "MIME");
}

static void test_WKScriptMessage(void)
{
  fprintf(stderr, "[WKScriptMessage]\n");
  WKSecurityOrigin *o = [[[WKSecurityOrigin alloc]
      _initWithProtocol:@"https" host:@"x.example" port:443] autorelease];
  WKFrameInfo *f = [[[WKFrameInfo alloc]
      _initWithMainFrame:YES request:nil securityOrigin:o webView:nil] autorelease];
  WKScriptMessage *m = [[[WKScriptMessage alloc]
      _initWithName:@"bridge"
               body:@"hello"
            webView:nil
          frameInfo:f
              world:[WKContentWorld pageWorld]] autorelease];
  EXPECT([[m name] isEqualToString:@"bridge"], "name");
  EXPECT([[m body] isEqualToString:@"hello"], "body");
  EXPECT([m frameInfo] == f, "frameInfo");
  EXPECT([m world] == [WKContentWorld pageWorld], "world");
}

static void test_WKError_domain(void)
{
  fprintf(stderr, "[WKError]\n");
  EXPECT([WKErrorDomain isEqualToString:@"WKErrorDomain"], "domain string");
  /* Enum sanity-check */
  EXPECT(WKErrorUnknown == 1, "Unknown is 1");
  EXPECT(WKErrorJavaScriptExceptionOccurred == 4, "JS exception is 4");
}

static void test_WKSnapshotConfiguration_copy(void)
{
  fprintf(stderr, "[WKSnapshotConfiguration]\n");
  WKSnapshotConfiguration *s = [[[WKSnapshotConfiguration alloc] init] autorelease];
  EXPECT([s afterScreenUpdates] == YES, "default afterScreenUpdates");
  [s setRect:NSMakeRect(10, 20, 300, 400)];
  [s setSnapshotWidth:640];
  WKSnapshotConfiguration *c = [[s copy] autorelease];
  EXPECT(NSEqualRects([c rect], [s rect]), "rect carried");
  EXPECT([c snapshotWidth] == 640, "width carried");
  EXPECT([c afterScreenUpdates] == YES, "afterScreenUpdates carried");
}

static void test_WKPDFConfiguration_copy(void)
{
  fprintf(stderr, "[WKPDFConfiguration]\n");
  WKPDFConfiguration *p = [[[WKPDFConfiguration alloc] init] autorelease];
  [p setRect:NSMakeRect(0, 0, 612, 792)];
  [p setAllowTransparentBackground:YES];
  WKPDFConfiguration *c = [[p copy] autorelease];
  EXPECT(NSEqualRects([c rect], [p rect]), "rect carried");
  EXPECT([c allowTransparentBackground] == YES, "alpha bg carried");
}

static void test_WKFindConfiguration_copy(void)
{
  fprintf(stderr, "[WKFindConfiguration copy]\n");
  WKFindConfiguration *f = [[[WKFindConfiguration alloc] init] autorelease];
  [f setBackwards:YES];
  [f setCaseSensitive:YES];
  [f setWraps:NO];
  WKFindConfiguration *c = [[f copy] autorelease];
  EXPECT([c backwards] == YES, "backwards");
  EXPECT([c caseSensitive] == YES, "caseSensitive");
  EXPECT([c wraps] == NO, "wraps");
}

static void test_WKFindResult(void)
{
  fprintf(stderr, "[WKFindResult]\n");
  /* Internal initializer is exposed through GSWebKitInternal.h so the
   * test re-declares it the same way the production callsite does. */
  Class cls = [WKFindResult class];
  EXPECT(cls != nil, "class exists");
}

static void test_WKUserScript_defaults(void)
{
  fprintf(stderr, "[WKUserScript content world default]\n");
  WKUserScript *s = [[[WKUserScript alloc]
      initWithSource:@"1+1"
       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
    forMainFrameOnly:NO] autorelease];
  EXPECT([s contentWorld] == [WKContentWorld pageWorld],
         "defaults to pageWorld");
  WKUserScript *s2 = [[[WKUserScript alloc]
      initWithSource:@"2"
       injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
    forMainFrameOnly:YES
        contentWorld:[WKContentWorld defaultClientWorld]] autorelease];
  EXPECT([s2 contentWorld] == [WKContentWorld defaultClientWorld],
         "explicit world honoured");
}

static void test_WKContentWorld_defaultClient(void)
{
  fprintf(stderr, "[WKContentWorld defaultClientWorld]\n");
  WKContentWorld *a = [WKContentWorld defaultClientWorld];
  WKContentWorld *b = [WKContentWorld defaultClientWorld];
  EXPECT(a == b, "defaultClientWorld is a singleton");
  EXPECT(a != [WKContentWorld pageWorld],
         "defaultClientWorld != pageWorld");
}

static void test_WKUserContentController_ruleList(void)
{
  fprintf(stderr, "[WKUserContentController rule lists]\n");
  WKUserContentController *ucc =
      [[[WKUserContentController alloc] init] autorelease];
  EXPECT([[ucc _ruleLists] count] == 0, "no rule lists initially");
  /* Add a stand-in rule list (constructor isn't public; verify the
   * collection-mutator API still works structurally). */
  Class cls = [WKContentRuleList class];
  EXPECT(cls != nil, "WKContentRuleList class exists");
  [ucc removeAllContentRuleLists];
  EXPECT([[ucc _ruleLists] count] == 0, "removeAll on empty is safe");
}

static void test_WKContentRuleListStore(void)
{
  fprintf(stderr, "[WKContentRuleListStore]\n");
  WKContentRuleListStore *a = [WKContentRuleListStore defaultStore];
  WKContentRuleListStore *b = [WKContentRuleListStore defaultStore];
  EXPECT(a == b, "defaultStore is a singleton");
  EXPECT(a != nil, "defaultStore exists");
  NSURL *tmp = [NSURL fileURLWithPath:NSTemporaryDirectory()];
  WKContentRuleListStore *c = [WKContentRuleListStore storeForURL:tmp];
  EXPECT(c != nil, "storeForURL non-nil for valid path");
  EXPECT(c != a, "storeForURL is distinct from default");
}

static void test_WKDownload(void)
{
  fprintf(stderr, "[WKDownload]\n");
  /* WKDownload is normally constructed by the engine; here we just
   * confirm the class loads and the public surface exists. */
  Class cls = [WKDownload class];
  EXPECT(cls != nil, "WKDownload class exists");
  EXPECT([cls instancesRespondToSelector:@selector(cancel:)], "responds to cancel:");
  EXPECT([cls instancesRespondToSelector:@selector(progress)], "responds to progress");
  EXPECT([cls instancesRespondToSelector:@selector(originalRequest)],
         "responds to originalRequest");
}

static void test_WKWebViewConfiguration_processPool_swap(void)
{
  fprintf(stderr, "[WKWebViewConfiguration processPool swap]\n");
  WKWebViewConfiguration *c = [[[WKWebViewConfiguration alloc] init] autorelease];
  WKProcessPool *originalPool = [c processPool];
  WKProcessPool *newPool = [[[WKProcessPool alloc] init] autorelease];
  [c setProcessPool:newPool];
  EXPECT([c processPool] == newPool, "process pool replaced");
  EXPECT([c processPool] != originalPool, "no longer points at the default");
}

static void test_WKWebViewConfiguration_websiteDataStore_swap(void)
{
  fprintf(stderr, "[WKWebViewConfiguration websiteDataStore swap]\n");
  WKWebViewConfiguration *c = [[[WKWebViewConfiguration alloc] init] autorelease];
  WKWebsiteDataStore *eph = [WKWebsiteDataStore nonPersistentDataStore];
  [c setWebsiteDataStore:eph];
  EXPECT([c websiteDataStore] == eph, "websiteDataStore replaced");
  EXPECT([[c websiteDataStore] isPersistent] == NO, "set ephemeral persists");
}

static void test_WKBackForwardList_setCurrentIndex(void)
{
  fprintf(stderr, "[WKBackForwardList setCurrentIndex]\n");
  WKBackForwardList *list = [[[WKBackForwardList alloc] init] autorelease];
  NSURL *u1 = [NSURL URLWithString:@"http://a/"];
  NSURL *u2 = [NSURL URLWithString:@"http://b/"];
  NSURL *u3 = [NSURL URLWithString:@"http://c/"];
  [list _appendItem:[[[WKBackForwardListItem alloc] _initWithURL:u1 initialURL:u1 title:@"A"] autorelease]];
  [list _appendItem:[[[WKBackForwardListItem alloc] _initWithURL:u2 initialURL:u2 title:@"B"] autorelease]];
  [list _appendItem:[[[WKBackForwardListItem alloc] _initWithURL:u3 initialURL:u3 title:@"C"] autorelease]];
  /* Currently at index 2 (C).  Move back to index 0 (A). */
  [list _setCurrentIndex:0];
  EXPECT([[[list currentItem] URL] isEqual:u1], "currentItem after setIndex 0");
  EXPECT([[list forwardList] count] == 2, "two items forward");
  EXPECT([[list backList] count] == 0, "no items back");
}


int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  /* Existing tests */
  test_WKWebViewConfiguration_defaults();
  test_WKWebViewConfiguration_copy();
  test_WKBackForwardList_appends();
  test_WKUserContentController_scripts();
  test_WKUserContentController_handlers();
  test_WKUserScript_copy();
  test_WKFindConfiguration_defaults();
  test_WKContentWorld_singletons();
  test_WKWebViewConfiguration_schemeHandlers();

  /* New value-type coverage */
  test_WKBackForwardList_itemAtIndex();
  test_WKBackForwardList_setCurrentIndex();
  test_WKBackForwardListItem();
  test_WKPreferences_defaults();
  test_WKPreferences_mutations();
  test_WKWebsiteDataStore();
  test_WKWebsiteDataStore_cookieStore();
  test_WKProcessPool();
  test_WKSecurityOrigin();
  test_WKFrameInfo();
  test_WKNavigation();
  test_WKNavigationAction();
  test_WKNavigationResponse();
  test_WKScriptMessage();
  test_WKError_domain();
  test_WKSnapshotConfiguration_copy();
  test_WKPDFConfiguration_copy();
  test_WKFindConfiguration_copy();
  test_WKFindResult();
  test_WKUserScript_defaults();
  test_WKContentWorld_defaultClient();
  test_WKUserContentController_ruleList();
  test_WKContentRuleListStore();
  test_WKDownload();
  test_WKWebViewConfiguration_processPool_swap();
  test_WKWebViewConfiguration_websiteDataStore_swap();

  fprintf(stderr, "\n==== %d passed, %d failed ====\n", g_pass, g_fail);
  [pool release];
  return (g_fail == 0) ? 0 : 1;
}
