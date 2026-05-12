#
#  Makefile for the WebKit library (libWebKit).
#
#  Installs public headers under <WebKit/...> so consumers can
#  write `#import <WebKit/WebKit.h>` exactly as on Apple platforms.
#

include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = WebKit

# All public Objective-C headers live under ../Headers/WebKit so the
# install path matches the umbrella include style used by Apple's
# WebKit.framework.  HEADER_FILES_INSTALL_DIR is set explicitly so the
# directory name is "WebKit" (not "libWebKit" or similar).
WebKit_HEADER_FILES_DIR        = ../Headers/WebKit
WebKit_HEADER_FILES_INSTALL_DIR = WebKit
WebKit_HEADER_FILES = \
	WebKit.h \
	WKFoundation.h \
	WKError.h \
	WKBackForwardList.h \
	WKBackForwardListItem.h \
	WKContentWorld.h \
	WKContentRuleListStore.h \
	WKDownload.h \
	WKDownloadDelegate.h \
	WKFindConfiguration.h \
	WKHTTPCookieStore.h \
	WKSnapshotConfiguration.h \
	WKURLSchemeHandler.h \
	WKFrameInfo.h \
	WKNavigation.h \
	WKNavigationAction.h \
	WKNavigationDelegate.h \
	WKNavigationResponse.h \
	WKPreferences.h \
	WKProcessPool.h \
	WKScriptMessage.h \
	WKScriptMessageHandler.h \
	WKSecurityOrigin.h \
	WKUIDelegate.h \
	WKUserContentController.h \
	WKUserScript.h \
	WKWebsiteDataStore.h \
	WKWebViewConfiguration.h \
	WKWebView.h

WebKit_OBJC_FILES = \
	WKError.m \
	WKBackForwardList.m \
	WKBackForwardListItem.m \
	WKContentRuleListStore.m \
	WKContentWorld.m \
	WKDownload.m \
	WKFindConfiguration.m \
	WKHTTPCookieStore.m \
	WKSnapshotConfiguration.m \
	WKURLSchemeTask.m \
	WKFrameInfo.m \
	WKNavigation.m \
	WKNavigationAction.m \
	WKNavigationResponse.m \
	WKPreferences.m \
	WKProcessPool.m \
	WKScriptMessage.m \
	WKSecurityOrigin.m \
	WKUserContentController.m \
	WKUserScript.m \
	WKWebsiteDataStore.m \
	WKWebViewConfiguration.m \
	WKWebView.m \
	GSWebKitBackend.m \
	GSWebKitWPE.m

ADDITIONAL_INCLUDE_DIRS += -I../Headers

WebKit_LIBRARIES_DEPEND_UPON = -lgnustep-gui -lgnustep-base
GNUSTEP_SYSTEM_LIBS_DIR := $(shell gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARIES 2>/dev/null)
ifneq ($(GNUSTEP_SYSTEM_LIBS_DIR),)
  ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBS_DIR)
endif
WebKit_LIBRARIES_DEPEND_UPON += -ldispatch

# ----------------------------------------------------------------------
# Engine + optional dependencies.  Prefer the config.make written by
# `./configure`; fall back to inline pkg-config probing so a plain
# `make` from a clean checkout still works on Debian/Ubuntu.
# ----------------------------------------------------------------------
-include ../config.make

ifeq ($(GS_WEBKIT_WPE_CFLAGS),)
  WPE_PKGS_2 := wpe-webkit-2.0 wpe-1.0 wpebackend-fdo-1.0
  WPE_PKGS_1 := wpe-webkit-1.1 libwpe-1.0 wpebackend-fdo-1.0
  ifeq ($(shell pkg-config --exists $(WPE_PKGS_2) && echo yes),yes)
    GS_WEBKIT_WPE_CFLAGS := $(shell pkg-config --cflags $(WPE_PKGS_2)) -DGS_WEBKIT_WPE_API_2=1
    GS_WEBKIT_WPE_LIBS   := $(shell pkg-config --libs   $(WPE_PKGS_2))
  else ifeq ($(shell pkg-config --exists $(WPE_PKGS_1) && echo yes),yes)
    GS_WEBKIT_WPE_CFLAGS := $(shell pkg-config --cflags $(WPE_PKGS_1)) -DGS_WEBKIT_WPE_API_1=1
    GS_WEBKIT_WPE_LIBS   := $(shell pkg-config --libs   $(WPE_PKGS_1))
  else
    $(error WPE WebKit development packages are required.  Run ./configure \
      to see specific missing packages, or install libwpewebkit-2.0-dev \
      libwpe-1.0-dev libwpebackend-fdo-1.0-dev on Debian/Ubuntu.)
  endif
endif

ifeq ($(GS_WEBKIT_WAYLAND_LIBS),)
  GS_WEBKIT_WAYLAND_LIBS := $(shell pkg-config --libs wayland-server)
endif

ADDITIONAL_OBJCFLAGS += $(GS_WEBKIT_WPE_CFLAGS) $(GS_WEBKIT_SOUP_CFLAGS) $(GS_WEBKIT_EXTRA_OBJCFLAGS)
ADDITIONAL_CFLAGS    += $(GS_WEBKIT_WPE_CFLAGS) $(GS_WEBKIT_SOUP_CFLAGS) $(GS_WEBKIT_EXTRA_OBJCFLAGS)
WebKit_LIBRARIES_DEPEND_UPON += $(GS_WEBKIT_WPE_LIBS) $(GS_WEBKIT_WAYLAND_LIBS)

# Blocks are needed to expose Apple's completionHandler: API style.
# GCC/clang both support them via -fblocks; libBlocksRuntime is part of
# libobjc2 / supplied separately.
ADDITIONAL_OBJCFLAGS += -fblocks
ADDITIONAL_CFLAGS    += -fblocks

include $(GNUSTEP_MAKEFILES)/library.make
