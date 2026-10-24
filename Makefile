export TARGET = iphone:clang:latest:16.0
export ARCHS = arm64e
# 本 tweak 只服务 roothide 设备（老板设备 = Relaxin 隐根），单变体省 CI 额度
export THEOS_PACKAGE_SCHEME = roothide
export _THEOS_PLATFORM_DPKG_DEB_COMPRESSION = gzip

TWEAK_NAME = WatchBothNotify

WatchBothNotify_FILES = Tweak.xm
WatchBothNotify_CFLAGS = -fobjc-arc
WatchBothNotify_FRAMEWORKS = UIKit Foundation
# 安全网：别让小警告挂 CI（与 NIP gold standard 一致）
ERROR_ON_WARNINGS = 0

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
