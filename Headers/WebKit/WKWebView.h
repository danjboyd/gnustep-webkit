/* WKWebView.h
 *
 * A view that displays interactive web content.  Subclass of NSView so
 * it can be embedded directly in a GNUstep AppKit window/view tree.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#ifndef GNUstep_H_WKWebView
#define GNUstep_H_WKWebView

#import <AppKit/AppKit.h>

#import <WebKit/WKFoundation.h>
#import <WebKit/WKBackForwardList.h>
#import <WebKit/WKContentWorld.h>
#import <WebKit/WKFindConfiguration.h>
#import <WebKit/WKNavigation.h>
#import <WebKit/WKSnapshotConfiguration.h>
#import <WebKit/WKNavigationDelegate.h>
#import <WebKit/WKUIDelegate.h>
#import <WebKit/WKWebViewConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKWebView : NSView

/* Initialisation ---------------------------------------------------- */

- (instancetype)initWithFrame:(NSRect)frame
                configuration:(WKWebViewConfiguration *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithFrame:(NSRect)frame;
- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/* Configuration ----------------------------------------------------- */

@property (nonatomic, readonly, copy) WKWebViewConfiguration *configuration;

/* Delegates --------------------------------------------------------- */

@property (nullable, nonatomic, weak) id <WKNavigationDelegate> navigationDelegate;
@property (nullable, nonatomic, weak) id <WKUIDelegate> UIDelegate;

/* State ------------------------------------------------------------- */

@property (nullable, nonatomic, readonly, copy) NSURL *URL;
@property (nullable, nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) double estimatedProgress;
@property (nonatomic, readonly, getter=isLoading) BOOL loading;
@property (nullable, nonatomic, readonly, copy) NSString *customUserAgent;
@property (nonatomic) BOOL allowsBackForwardNavigationGestures;
@property (nonatomic) CGFloat pageZoom;
@property (nonatomic, readonly, strong) WKBackForwardList *backForwardList;

- (void)setCustomUserAgent:(nullable NSString *)userAgent;

/* Loading ----------------------------------------------------------- */

- (nullable WKNavigation *)loadRequest:(NSURLRequest *)request;
- (nullable WKNavigation *)loadHTMLString:(NSString *)string
                                  baseURL:(nullable NSURL *)baseURL;
- (nullable WKNavigation *)loadData:(NSData *)data
                            MIMEType:(NSString *)MIMEType
               characterEncodingName:(NSString *)characterEncodingName
                             baseURL:(NSURL *)baseURL;
- (nullable WKNavigation *)loadFileURL:(NSURL *)URL
               allowingReadAccessToURL:(NSURL *)readAccessURL;

- (nullable WKNavigation *)reload;
- (nullable WKNavigation *)reloadFromOrigin;
- (void)stopLoading;

- (BOOL)canGoBack;
- (BOOL)canGoForward;
- (nullable WKNavigation *)goBack;
- (nullable WKNavigation *)goForward;
- (nullable WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item;

/* JavaScript evaluation -------------------------------------------- */

- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^ _Nullable)(id _Nullable, NSError * _Nullable))completionHandler;

- (void)evaluateJavaScript:(NSString *)javaScriptString
                  inFrame:(nullable WKFrameInfo *)frame
            inContentWorld:(WKContentWorld *)contentWorld
         completionHandler:(void (^ _Nullable)(id _Nullable, NSError * _Nullable))completionHandler;

/* Find in page ------------------------------------------------------ */

- (void)findString:(NSString *)string
     configuration:(nullable WKFindConfiguration *)configuration
 completionHandler:(void (^ _Nullable)(WKFindResult *result))completionHandler;

/* Snapshot + PDF + Print -------------------------------------------- */

- (void)takeSnapshotWithConfiguration:(nullable WKSnapshotConfiguration *)config
                     completionHandler:(void (^)(NSImage * _Nullable image,
                                                 NSError * _Nullable error))completionHandler;

- (void)createPDFWithConfiguration:(nullable WKPDFConfiguration *)config
                  completionHandler:(void (^)(NSData * _Nullable pdf,
                                              NSError * _Nullable error))completionHandler;

/* Returns an NSPrintOperation already configured for this view's
 * current page contents.  Caller invokes -runOperation or
 * -runOperationModalForWindow:delegate:didRunSelector:contextInfo:.
 * Not supported on the WPE backend; returns nil. */
- (nullable NSPrintOperation *)printOperationWithPrintInfo:(NSPrintInfo *)printInfo;

@end

NS_ASSUME_NONNULL_END

#endif /* GNUstep_H_WKWebView */
