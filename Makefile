export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = Sileo

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SileoBrowserPicker
SileoBrowserPicker_FILES = Tweak.xm
SileoBrowserPicker_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-error=nonnull -Wno-error -Wno-unused-variable -Wno-unused-function
SileoBrowserPicker_FRAMEWORKS = UIKit AuthenticationServices

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += sileopickerprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 Sileo 2>/dev/null || true"
