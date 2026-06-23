.PHONY: all build run debug release bundle test lint format clean install uninstall

APP_NAME := kssh
VERSION := 1.3.0
BUILD_DIR := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(APP_NAME)
DEBUG_BIN := $(BUILD_DIR)/debug/$(APP_NAME)
APP_BUNDLE := $(BUILD_DIR)/release/$(APP_NAME).app
INSTALL_DIR := /Applications/$(APP_NAME).app
SWIFT_FORMAT := xcrun swift-format

all: build

build:
	swift build -c debug

run: build
	$(DEBUG_BIN)

debug: build
	$(DEBUG_BIN)

# Build the release .app bundle without launching it (used by CI and `release`).
bundle:
	swift build -c release
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(APP_BUNDLE)/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '<plist version="1.0">' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '<dict>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleName</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>com.kssh.app</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>$(VERSION)</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleShortVersionString</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>$(VERSION)</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>14.0</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>LSUIElement</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <true/>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>NSHighResolutionCapable</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <true/>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '</dict>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '</plist>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo "  ✓  Built: $(APP_BUNDLE)"

release: bundle
	open "$(APP_BUNDLE)"

test:
	swift test

# Check formatting/style without modifying files (matches CI).
lint:
	$(SWIFT_FORMAT) lint --recursive --strict Sources Tests

# Apply formatting in place.
format:
	$(SWIFT_FORMAT) format -i -r Sources Tests

clean:
	swift package clean

install: bundle
	rm -rf $(INSTALL_DIR)
	cp -R $(APP_BUNDLE) $(INSTALL_DIR)
	@echo "  ✓  Installed: $(INSTALL_DIR)"

uninstall:
	rm -rf $(INSTALL_DIR)
	@echo "  ✓  Uninstalled: $(INSTALL_DIR)"
