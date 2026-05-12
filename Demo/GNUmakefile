#
# Demo GNUstep application for the WebKit framework.
#
# Run with `make run` from this directory (after `make` from the
# repository root, which builds and stages the library).
#

include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = WebKitDemo

WebKitDemo_OBJC_FILES = \
	main.m \
	WKDAppDelegate.m \
	WKDBrowserWindowController.m

WebKitDemo_PRINCIPAL_CLASS = NSApplication

ADDITIONAL_INCLUDE_DIRS += -I../Headers
ADDITIONAL_LIB_DIRS     += -L../Source/$(GNUSTEP_OBJ_DIR_NAME)
GNUSTEP_SYSTEM_LIBS_DIR := $(shell gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARIES 2>/dev/null)
ifneq ($(GNUSTEP_SYSTEM_LIBS_DIR),)
  ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBS_DIR)
endif

ADDITIONAL_GUI_LIBS  += -lWebKit
ADDITIONAL_OBJC_LIBS += -ldispatch

ADDITIONAL_OBJCFLAGS += -fblocks
ADDITIONAL_CFLAGS    += -fblocks

include $(GNUSTEP_MAKEFILES)/application.make

run: all
	PATH=../Source/$(GNUSTEP_OBJ_DIR_NAME):$$PATH \
	LD_LIBRARY_PATH=../Source/$(GNUSTEP_OBJ_DIR_NAME):$(GNUSTEP_SYSTEM_LIBS_DIR):$$LD_LIBRARY_PATH \
	$(GNUSTEP_BUILD_DIR)/$(APP_NAME).app/$(GNUSTEP_TARGET_LDIR)/$(APP_NAME)$(EXEEXT)

debug: all
	PATH=../Source/$(GNUSTEP_OBJ_DIR_NAME):$$PATH \
	LD_LIBRARY_PATH=../Source/$(GNUSTEP_OBJ_DIR_NAME):$(GNUSTEP_SYSTEM_LIBS_DIR):$$LD_LIBRARY_PATH \
	gdb --args $(GNUSTEP_BUILD_DIR)/$(APP_NAME).app/$(GNUSTEP_TARGET_LDIR)/$(APP_NAME)$(EXEEXT)
