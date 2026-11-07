APP_NAME     := SnagxViewer
PROJECT      := $(APP_NAME).xcodeproj
DERIVED      := build
DEBUG_APP    := $(DERIVED)/Build/Products/Debug/$(APP_NAME).app
RELEASE_APP  := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR  ?= /Applications
INSTALLED    := $(INSTALL_DIR)/$(APP_NAME).app
BIN_DIR      ?= $(HOME)/.local/bin
NOTARY_PROFILE ?= notary
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Signing: override TEAM with your Apple Developer team ID, or build ad-hoc signed with SIGN=adhoc.
TEAM         ?= QCRM9T8GD4
SIGN         ?= team
ifeq ($(SIGN),adhoc)
SIGN_FLAGS   := CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
else
SIGN_FLAGS   := DEVELOPMENT_TEAM=$(TEAM)
endif
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(APP_NAME) -derivedDataPath $(DERIVED) -quiet $(SIGN_FLAGS)
# Debug builds only the host architecture; release builds are universal.
DEBUG_DEST   := -destination 'platform=macOS,arch=$(shell uname -m)'
RELEASE_DEST := -destination 'generic/platform=macOS'

.PHONY: all project build release test run install uninstall install-cli uninstall-cli notarize clean

all: build

project:
	xcodegen generate

build: project
	$(XCODEBUILD) $(DEBUG_DEST) -configuration Debug build

release: project
	$(XCODEBUILD) $(RELEASE_DEST) -configuration Release build
	codesign --verify --deep --strict "$(RELEASE_APP)"

test:
	cd SnagxCore && swift test

run: build
	open "$(DEBUG_APP)"

install: release
	-pluginkit -r "$(DEBUG_APP)/Contents/PlugIns/SnagxQuickLook.appex" 2>/dev/null
	-pluginkit -r "$(DEBUG_APP)/Contents/PlugIns/SnagxThumbnail.appex" 2>/dev/null
	rm -rf "$(INSTALLED)"
	ditto "$(RELEASE_APP)" "$(INSTALLED)"
	touch "$(INSTALLED)"  # ditto keeps the old bundle mtime, which keeps stale icons cached
	$(LSREGISTER) -f "$(INSTALLED)"
	pluginkit -a "$(INSTALLED)/Contents/PlugIns/SnagxQuickLook.appex"
	pluginkit -a "$(INSTALLED)/Contents/PlugIns/SnagxThumbnail.appex"
	qlmanage -r >/dev/null 2>&1 || true
	qlmanage -r cache >/dev/null 2>&1 || true
	@echo "Installed $(INSTALLED)"

uninstall: uninstall-cli
	-pluginkit -r "$(INSTALLED)/Contents/PlugIns/SnagxQuickLook.appex" 2>/dev/null
	-pluginkit -r "$(INSTALLED)/Contents/PlugIns/SnagxThumbnail.appex" 2>/dev/null
	-$(LSREGISTER) -u "$(INSTALLED)"
	rm -rf "$(INSTALLED)"

install-cli:
	mkdir -p "$(BIN_DIR)"
	ln -sf "$(INSTALLED)/Contents/MacOS/snagx-export" "$(BIN_DIR)/snagx-export"
	@echo "Linked $(BIN_DIR)/snagx-export"

uninstall-cli:
	rm -f "$(BIN_DIR)/snagx-export"

# Requires a notarytool keychain profile:
#   xcrun notarytool store-credentials $(NOTARY_PROFILE) --apple-id <id> --team-id QCRM9T8GD4
notarize: release
	mkdir -p dist
	ditto -c -k --keepParent "$(RELEASE_APP)" dist/$(APP_NAME).zip
	xcrun notarytool submit dist/$(APP_NAME).zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_APP)"
	rm dist/$(APP_NAME).zip
	ditto -c -k --keepParent "$(RELEASE_APP)" dist/$(APP_NAME).zip
	@echo "Notarized: dist/$(APP_NAME).zip"

clean:
	rm -rf $(DERIVED) dist $(PROJECT) SnagxCore/.build
