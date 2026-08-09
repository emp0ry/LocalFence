THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:16.0
ARCHS = arm64

export THEOS_PACKAGE_SCHEME
export TARGET
export ARCHS

SUBPROJECTS += app daemon

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

