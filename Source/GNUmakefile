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
	WKContentWorld.m \
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
# WPE WebKit backend.  Required at build time: any consumer of this
# framework links against WPEWebKit transitively.  Probe for the modern
# 2.0 pkg-config name (Debian 13 / current Igalia), fall back to the
# legacy 1.1 name (older distros) if needed.  Without an engine we
# cannot ship a real web view, so we error out.
# ----------------------------------------------------------------------
WPE_PKGS_2 := wpe-webkit-2.0 wpe-1.0 wpebackend-fdo-1.0
WPE_PKGS_1 := wpe-webkit-1.1 libwpe-1.0 wpebackend-fdo-1.0

ifeq ($(shell pkg-config --exists $(WPE_PKGS_2) && echo yes),yes)
  WPE_PKGS := $(WPE_PKGS_2)
  WPE_DEFINE := -DGS_WEBKIT_WPE_API_2=1
else ifeq ($(shell pkg-config --exists $(WPE_PKGS_1) && echo yes),yes)
  WPE_PKGS := $(WPE_PKGS_1)
  WPE_DEFINE := -DGS_WEBKIT_WPE_API_1=1
else
  $(error WPE WebKit development packages are required. Install \
    libwpewebkit-2.0-dev libwpe-1.0-dev libwpebackend-fdo-1.0-dev \
    (Debian/Ubuntu) or the equivalent for your distribution.)
endif

WPE_CFLAGS := $(shell pkg-config --cflags $(WPE_PKGS))
WPE_LIBS   := $(shell pkg-config --libs   $(WPE_PKGS))

ADDITIONAL_OBJCFLAGS += $(WPE_CFLAGS) $(WPE_DEFINE)
ADDITIONAL_CFLAGS    += $(WPE_CFLAGS) $(WPE_DEFINE)
WebKit_LIBRARIES_DEPEND_UPON += $(WPE_LIBS) -lwayland-server

# Blocks are needed to expose Apple's completionHandler: API style.
# GCC/clang both support them via -fblocks; libBlocksRuntime is part of
# libobjc2 / supplied separately.
ADDITIONAL_OBJCFLAGS += -fblocks
ADDITIONAL_CFLAGS    += -fblocks

include $(GNUSTEP_MAKEFILES)/library.make
