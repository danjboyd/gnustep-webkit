/* WKPreferences.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 */

#import <WebKit/WKPreferences.h>

@implementation WKPreferences
{
  CGFloat _minimumFontSize;
  BOOL    _javaScriptCanOpenWindowsAutomatically;
  BOOL    _javaScriptEnabled;
  BOOL    _fraudulentWebsiteWarningEnabled;
  BOOL    _elementFullscreenEnabled;
  BOOL    _textInteractionEnabled;
  BOOL    _shouldPrintBackgrounds;
}

@synthesize minimumFontSize = _minimumFontSize;
@synthesize javaScriptCanOpenWindowsAutomatically = _javaScriptCanOpenWindowsAutomatically;
@synthesize javaScriptEnabled = _javaScriptEnabled;
@synthesize fraudulentWebsiteWarningEnabled = _fraudulentWebsiteWarningEnabled;
@synthesize elementFullscreenEnabled = _elementFullscreenEnabled;
@synthesize textInteractionEnabled = _textInteractionEnabled;
@synthesize shouldPrintBackgrounds = _shouldPrintBackgrounds;

- (instancetype)init
{
  self = [super init];
  if (self != nil) {
    _minimumFontSize                       = 0.0;
    _javaScriptCanOpenWindowsAutomatically = NO;
    _javaScriptEnabled                     = YES;
    _fraudulentWebsiteWarningEnabled       = YES;
    _elementFullscreenEnabled              = NO;
    _textInteractionEnabled                = YES;
    _shouldPrintBackgrounds                = NO;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  return [self init];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
}

@end
