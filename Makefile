APP_NAME   := NotchDeck
BUNDLE_ID  := com.cadenburleson.notchdeck
BUILD_DIR  := .build
CONFIG     ?= release
APP_DIR    := $(BUILD_DIR)/$(APP_NAME).app
BIN        := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
VERSION    ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.1.0)

.PHONY: all build app run test clean dmg install icon

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

## Assemble a runnable .app bundle from the SwiftPM binary
app: build icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(BIN)" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	@if [ -f "$(BUILD_DIR)/AppIcon.icns" ]; then cp "$(BUILD_DIR)/AppIcon.icns" "$(APP_DIR)/Contents/Resources/AppIcon.icns"; fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_DIR)/Contents/Info.plist" || true
	codesign --force --deep --sign - "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

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
