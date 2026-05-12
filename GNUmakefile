#
# Top-level GNUmakefile for gnustep-webkit
#
# This package builds the GNUstep WebKit framework: an Objective-C
# implementation of Apple's WebKit API (WKWebView and friends) on top
# of the WPE WebKit engine.  It is intended for eventual inclusion in
# the GNUstep project as an officially maintained framework.
#

ifeq ($(GNUSTEP_MAKEFILES),)
  GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = gnustep-webkit

SUBPROJECTS = \
	Source \
	Demo

include $(GNUSTEP_MAKEFILES)/aggregate.make
