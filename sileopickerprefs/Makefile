export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SileoPickerPrefs
SileoPickerPrefs_FILES = SileoBrowserPickerRootListController.m
SileoPickerPrefs_INSTALL_PATH = /Library/PreferenceBundles
SileoPickerPrefs_FRAMEWORKS = UIKit
SileoPickerPrefs_CFLAGS = -fobjc-arc -Wno-error -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations -I..
SileoPickerPrefs_LDFLAGS = -Wl,-U,_OBJC_CLASS_$_PSListController -Wl,-U,_OBJC_METACLASS_$_PSListController

include $(THEOS_MAKE_PATH)/bundle.mk
