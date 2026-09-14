APP_NAME   := NotchDeck
BUNDLE_ID  := com.cadenburleson.notchdeck
BUILD_DIR  := .build
CONFIG     ?= release
APP_DIR    := $(BUILD_DIR)/$(APP_NAME).app
# Universal (Apple silicon + Intel) by default; ARCHS= for a native-only dev build.
ARCHS      ?= arm64 x86_64
ARCH_FLAGS := $(foreach a,$(ARCHS),--arch $(a))
# SwiftPM puts multi-arch products under .build/apple/Products.
BIN        := $(if $(word 2,$(ARCHS)),$(BUILD_DIR)/apple/Products/$(shell echo $(CONFIG) | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')/$(APP_NAME),$(BUILD_DIR)/$(CONFIG)/$(APP_NAME))
VERSION    ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1.0)
# Sparkle ships as an xcframework inside the SwiftPM artifacts directory.
SPARKLE_FW  = $(shell find $(BUILD_DIR)/artifacts -type d -name Sparkle.framework -path '*macos*' 2>/dev/null | head -1)
# Set SIGN_IDENTITY to a "Developer ID Application: ..." identity for distributable builds.
SIGN_IDENTITY ?= -

.PHONY: all build app run test clean dmg install icon sign

all: app

build:
	swift build -c $(CONFIG) $(ARCH_FLAGS)

test:
	swift test

## Assemble a runnable .app bundle from the SwiftPM binary
app: build icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(BIN)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@if [ -f "$(BUILD_DIR)/AppIcon.icns" ]; then cp "$(BUILD_DIR)/AppIcon.icns" "$(APP_DIR)/Contents/Resources/AppIcon.icns"; fi
	@test -n "$(SPARKLE_FW)" || (echo "Sparkle.framework not found under $(BUILD_DIR)/artifacts" && exit 1)
	mkdir -p "$(APP_DIR)/Contents/Frameworks"
	cp -R "$(SPARKLE_FW)" "$(APP_DIR)/Contents/Frameworks/"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP_DIR)/Contents/Info.plist"
	$(MAKE) sign
	@echo "Built $(APP_DIR) ($(VERSION))"

## Sign the bundle inside-out. Ad-hoc by default; Developer ID when SIGN_IDENTITY is set.
sign:
	@FW="$(APP_DIR)/Contents/Frameworks/Sparkle.framework"; \
	OPTS="--force --timestamp=none"; \
	if [ "$(SIGN_IDENTITY)" != "-" ]; then OPTS="--force --timestamp --options runtime"; fi; \
	codesign $$OPTS --sign "$(SIGN_IDENTITY)" "$$FW/Versions/B/XPCServices/Installer.xpc"; \
	codesign $$OPTS --sign "$(SIGN_IDENTITY)" "$$FW/Versions/B/XPCServices/Downloader.xpc"; \
	codesign $$OPTS --sign "$(SIGN_IDENTITY)" "$$FW/Versions/B/Autoupdate"; \
	codesign $$OPTS --sign "$(SIGN_IDENTITY)" "$$FW/Versions/B/Updater.app"; \
	codesign $$OPTS --sign "$(SIGN_IDENTITY)" "$$FW"; \
	codesign $$OPTS --sign "$(SIGN_IDENTITY)" "$(APP_DIR)"
	codesign --verify --deep --strict "$(APP_DIR)"

## Generate the .icns from Resources/AppIcon.png (if present)
icon:
	@if [ -f Resources/AppIcon.png ] && [ ! -f "$(BUILD_DIR)/AppIcon.icns" ]; then \
		set -e; ICONSET="$(BUILD_DIR)/AppIcon.iconset"; rm -rf "$$ICONSET"; mkdir -p "$$ICONSET"; \
		for s in 16 32 128 256 512; do \
			sips -z $$s $$s Resources/AppIcon.png --out "$$ICONSET/icon_$${s}x$${s}.png" >/dev/null; \
			d=$$((s*2)); sips -z $$d $$d Resources/AppIcon.png --out "$$ICONSET/icon_$${s}x$${s}@2x.png" >/dev/null; \
		done; \
		iconutil -c icns "$$ICONSET" -o "$(BUILD_DIR)/AppIcon.icns"; \
	fi

run: app
	@pkill -x $(APP_NAME) 2>/dev/null || true
	open "$(APP_DIR)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

dmg: app
	rm -f "$(BUILD_DIR)/$(APP_NAME).dmg"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP_DIR)" -ov -format UDZO "$(BUILD_DIR)/$(APP_NAME).dmg"

clean:
	rm -rf $(BUILD_DIR)
