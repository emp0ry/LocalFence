include $(THEOS)/makefiles/common.mk

TOOL_NAME = localfenced localfencectl

localfenced_FILES = Sources/main.m Sources/LFNetwork.m Sources/LFServer.m ../Shared/LFCore.c
localfenced_FRAMEWORKS = Foundation
localfenced_CFLAGS = -fobjc-arc -Wall -Wextra -I../Shared
localfenced_CODESIGN_FLAGS = -Sentitlements.plist
localfenced_INSTALL_PATH = /usr/libexec/localfence

localfencectl_FILES = Sources/localfencectl.m ../Shared/LFCore.c ../Shared/LFIPCClient.m
localfencectl_FRAMEWORKS = Foundation
localfencectl_CFLAGS = -fobjc-arc -Wall -Wextra -I../Shared
localfencectl_CODESIGN_FLAGS = -Sentitlements.plist
localfencectl_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
