export THEOS = /opt/theos

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = ChaoXingStudy
THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE = 1
ADDITIONAL_CFLAGS += -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.clang-cache/ModuleCache

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_DIR = rootless
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
THEOS_PACKAGE_DIR = roothide
else
THEOS_PACKAGE_DIR = rootful
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChaoxingLaunchAdBlock

ChaoxingLaunchAdBlock_FILES = Tweak.xm
ChaoxingLaunchAdBlock_CFLAGS = -fobjc-arc
ChaoxingLaunchAdBlock_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
