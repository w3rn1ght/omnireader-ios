TARGET := iphone:clang:12.4:12.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = OmniReader

OmniReader_FILES = $(wildcard Sources/*.m)
OmniReader_FRAMEWORKS = UIKit Foundation WebKit PDFKit QuickLook AVFoundation \
	MediaPlayer AuthenticationServices CoreMedia QuartzCore Security
OmniReader_LIBRARIES = z
OmniReader_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
OmniReader_INSTALL_PATH = /Applications
OmniReader_RESOURCE_DIRS = Resources
OmniReader_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk

# Storyboard is compiled with ibtool (Xcode is required to build Theos apps anyway).
before-OmniReader-all:: Resources/LaunchScreen.storyboardc

Resources/LaunchScreen.storyboardc: Support/LaunchScreen.storyboard
	@mkdir -p Resources
	xcrun ibtool --compile "$@" "$<"
