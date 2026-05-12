include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = wktests
wktests_OBJC_FILES = wktests.m

ADDITIONAL_INCLUDE_DIRS += -I../../Headers
ADDITIONAL_LIB_DIRS     += -L../../Source/$(GNUSTEP_OBJ_DIR_NAME)
GNUSTEP_SYSTEM_LIBS_DIR := $(shell gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARIES 2>/dev/null)
ifneq ($(GNUSTEP_SYSTEM_LIBS_DIR),)
  ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBS_DIR)
endif
wktests_TOOL_LIBS       += -lWebKit -lgnustep-gui -lgnustep-base
ADDITIONAL_OBJC_LIBS    += -ldispatch
ADDITIONAL_OBJCFLAGS    += -fblocks

include $(GNUSTEP_MAKEFILES)/tool.make

run: all
	LD_LIBRARY_PATH=../../Source/$(GNUSTEP_OBJ_DIR_NAME):$$LD_LIBRARY_PATH \
	$(GNUSTEP_BUILD_DIR)/obj/wktests
