/* GSWebKitBackend.h
 *
 * Internal abstraction over a web engine.  WKWebView owns a
 * GSWebKitBackend; the only concrete implementation today is the WPE
 * backend (GSWebKitWPE), but the interface is engine-agnostic so an
 * alternative engine (e.g. a future Servo or WebKitGTK fallback) can
 * slot in without touching the public WK* facade.
 *
 * Not installed.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2.1 of the
 * License, or (at your option) any later version.
 */

#ifndef GS_WEBKIT_BACKEND_H
#define GS_WEBKIT_BACKEND_H

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@class WKWebViewConfiguration;
@class WKWebView;
@class GSWebKitBackend;

/* Callbacks that the backend posts up to its WKWebView host.  All
 * methods are delivered on the main thread.
 */
@protocol GSWebKitBackendHost <NSObject>

/* Pixel buffer for the view changed.  The new buffer can be retrieved
 * via -[GSWebKitBackend takeCurrentFrame].  Buffer is in 32-bit BGRA
 * (little-endian ARGB) format, which is what wl_shm/ARGB8888 yields.
 */
- (void)backendFrameDidChange:(GSWebKitBackend *)backend;

/* Navigation lifecycle. */
- (void)backendDidStartProvisionalNavigation:(GSWebKitBackend *)backend;
- (void)backendDidCommitNavigation:(GSWebKitBackend *)backend;
- (void)backendDidFinishNavigation:(GSWebKitBackend *)backend;
- (void)backend:(GSWebKitBackend *)backend
    didFailNavigationWithError:(NSError *)error
                   provisional:(BOOL)provisional;

/* Property changes. */
- (void)backend:(GSWebKitBackend *)backend didChangeTitle:(NSString *)title;
- (void)backend:(GSWebKitBackend *)backend didChangeURL:(NSURL *)url;
- (void)backend:(GSWebKitBackend *)backend didChangeEstimatedProgress:(double)p;
- (void)backend:(GSWebKitBackend *)backend didChangeIsLoading:(BOOL)isLoading;
- (void)backendDidChangeBackForwardList:(GSWebKitBackend *)backend;

/* Script bridge: a posted webkit.messageHandlers.NAME.postMessage(body). */
- (void)backend:(GSWebKitBackend *)backend
        didReceiveScriptMessageWithName:(NSString *)name
                                   body:(id)body;

/* UI delegate dialogs. */
- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptAlertWithMessage:(NSString *)message
                       completion:(void (^)(void))completion;
- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptConfirmWithMessage:(NSString *)message
                         completion:(void (^)(BOOL result))completion;
- (void)backend:(GSWebKitBackend *)backend
    runJavaScriptPromptWithMessage:(NSString *)message
                        defaultText:(NSString *)defaultText
                         completion:(void (^)(NSString *result))completion;

@end


/* Mouse / pointer event mapping.  Mirrors wpe_input_pointer_event_type
 * but is exposed engine-neutrally.
 */
typedef NS_ENUM(NSInteger, GSWebKitPointerEventType) {
  GSWebKitPointerEventMove   = 1,
  GSWebKitPointerEventButton = 2
};


@interface GSWebKitBackend : NSObject

@property (nonatomic, assign) id <GSWebKitBackendHost> host;

/* Engine selection.  Returns nil if no engine is available at runtime. */
+ (GSWebKitBackend *)backendWithConfiguration:(WKWebViewConfiguration *)config;

/* Lifecycle. */
- (void)setSize:(NSSize)size scale:(CGFloat)scale;
- (void)shutdown;

/* Navigation. */
- (void)loadURL:(NSURL *)url;
- (void)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL;
- (void)reload;
- (void)reloadFromOrigin;
- (void)stopLoading;
- (BOOL)canGoBack;
- (BOOL)canGoForward;
- (void)goBack;
- (void)goForward;

/* JS. */
- (void)evaluateJavaScript:(NSString *)javaScript
                completion:(void (^)(id result, NSError *error))completion;

/* User content. */
- (void)addUserScript:(NSString *)source
        injectionTime:(NSInteger)injectionTime
     forMainFrameOnly:(BOOL)mainFrameOnly;
- (void)registerScriptMessageHandlerName:(NSString *)name;
- (void)unregisterScriptMessageHandlerName:(NSString *)name;

/* Properties. */
- (NSString *)currentTitle;
- (NSURL *)currentURL;
- (double)currentEstimatedProgress;
- (BOOL)isLoading;
- (void)setCustomUserAgent:(NSString *)ua;
- (NSString *)customUserAgent;

/* Pixel buffer.  Returns the most recently exported frame as an
 * NSBitmapImageRep (RGBA bytes, premultiplied), or nil if no frame has
 * been delivered yet.  The returned rep is owned by the caller and may
 * outlive the backend's internal buffer rotation.
 */
- (NSBitmapImageRep *)takeCurrentFrame;
- (NSSize)currentFrameSize;

/* Input dispatch. */
- (void)dispatchPointerMoveAt:(NSPoint)point
                    modifiers:(uint32_t)modifiers
                    timestamp:(uint32_t)timestamp;
- (void)dispatchPointerButton:(int)button
                      pressed:(BOOL)pressed
                           at:(NSPoint)point
                    modifiers:(uint32_t)modifiers
                    timestamp:(uint32_t)timestamp;
- (void)dispatchScrollAt:(NSPoint)point
            deltaX:(double)dx
            deltaY:(double)dy
                modifiers:(uint32_t)modifiers
                timestamp:(uint32_t)timestamp;
- (void)dispatchKeyCode:(uint32_t)keysym
              pressed:(BOOL)pressed
                modifiers:(uint32_t)modifiers
                timestamp:(uint32_t)timestamp;

@end

#endif /* GS_WEBKIT_BACKEND_H */
