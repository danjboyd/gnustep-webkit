/* WKDownloadDelegate.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 */

#ifndef GNUstep_H_WKDownloadDelegate
#define GNUstep_H_WKDownloadDelegate

#import <WebKit/WKFoundation.h>

@class WKDownload;

NS_ASSUME_NONNULL_BEGIN

@protocol WKDownloadDelegate <NSObject>
@required

- (void)download:(WKDownload *)download
    decideDestinationUsingResponse:(NSURLResponse *)response
                 suggestedFilename:(NSString *)suggestedFilename
                 completionHandler:(void (^)(NSURL * _Nullable destination))completionHandler;

@optional

- (void)downloadDidFinish:(WKDownload *)download;
- (void)download:(WKDownload *)download didFailWithError:(NSError *)error
                                              resumeData:(nullable NSData *)resumeData;

@end

NS_ASSUME_NONNULL_END

#endif
