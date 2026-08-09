include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LocalFence

LocalFence_FILES = $(wildcard Sources/*.m) ../Shared/LFCore.c ../Shared/LFIPCClient.m
LocalFence_FRAMEWORKS = UIKit Foundation CoreLocation
LocalFence_LIBRARIES = sqlite3
LocalFence_CFLAGS = -fobjc-arc -Wall -Wextra -I../Shared
LocalFence_CODESIGN_FLAGS = -Sentitlements.plist
LocalFence_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
