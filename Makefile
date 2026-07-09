# FaceGate-Mac Makefile
# Build, package, and distribute FaceGate

APP_NAME = FaceGate
BUNDLE_ID = com.dweep.FaceGate
BUILD_DIR = build
ARCHIVE_PATH = $(BUILD_DIR)/$(APP_NAME).xcarchive
APP_PATH = $(BUILD_DIR)/$(APP_NAME).app
DMG_PATH = $(BUILD_DIR)/$(APP_NAME).dmg
SCHEME = $(APP_NAME)

GEN_BUILD_INFO = FaceGate/Utilities/BuildInfo.swift

.PHONY: all clean generate build archive dmg install generate-build-info

# Generate Xcode project from project.yml
generate:
	@echo "→ Generating Xcode project..."
	xcodegen generate
	@echo "✓ FaceGate.xcodeproj generated"

# Generate BuildInfo.swift with git hash + timestamp
# Appends "-dirty" when the working tree has uncommitted changes.
generate-build-info:
	@echo "→ Generating build info..."
	@COMMIT=$$(git rev-parse --short HEAD 2>/dev/null || echo "no-git"); \
	DIRTY=$$(git status --porcelain 2>/dev/null | head -1 | wc -l | tr -d ' '); \
	if [ "$$DIRTY" != "0" ]; then COMMIT="$${COMMIT}-dirty"; fi; \
	TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	echo "Generating build info: commit=$$COMMIT, time=$$TIMESTAMP"; \
	printf 'import Foundation\n\nenum BuildInfo {\n    static let commitHash = "%s"\n    static let buildDate = "%s"\n    static var identifier: String {\n        "%s-%s"\n    }\n}\n' "$$COMMIT" "$$TIMESTAMP" "$$COMMIT" "$$TIMESTAMP" > $(GEN_BUILD_INFO)
	@echo "✓ $(GEN_BUILD_INFO) generated"

# Build the app (debug)
build: generate generate-build-info
	@echo "→ Building $(APP_NAME) (Debug)..."
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=macOS" \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		build
	@echo "✓ Build complete"

# Archive the app (release)
archive: generate
	@echo "→ Archiving $(APP_NAME) (Release)..."
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-destination "platform=macOS" \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		archive
	@echo "✓ Archive created at $(ARCHIVE_PATH)"

# Export the app from archive
export: archive
	@echo "→ Exporting app..."
	@mkdir -p $(BUILD_DIR)
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportPath $(BUILD_DIR) \
		-exportOptionsPlist ExportOptions.plist 2>/dev/null || \
	cp -R "$(ARCHIVE_PATH)/Products/Applications/$(APP_NAME).app" "$(APP_PATH)"
	@echo "✓ App exported to $(APP_PATH)"

# Create DMG installer
dmg: export
	@echo "→ Creating styled DMG..."
	@rm -f $(DMG_PATH)
	@mkdir -p $(BUILD_DIR)/dmg_staging
	@cp -R $(APP_PATH) $(BUILD_DIR)/dmg_staging/
	create-dmg \
		--volname "$(APP_NAME)" \
		--background "non-app-assets/dmg_background.png" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 100 \
		--icon "$(APP_NAME).app" 180 210 \
		--hide-extension "$(APP_NAME).app" \
		--app-drop-link 480 210 \
		"$(DMG_PATH)" \
		"$(BUILD_DIR)/dmg_staging/"
	@rm -rf $(BUILD_DIR)/dmg_staging
	@echo "✓ Styled DMG created at $(DMG_PATH)"

# Install locally (for development)
install: build
	@echo "→ Installing to /Applications..."
	@BUILD_APP=$$(find $(BUILD_DIR)/DerivedData -name "$(APP_NAME).app" -path "*/Build/Products/Debug/*" | head -1) && \
	if [ -n "$$BUILD_APP" ]; then \
		rm -rf /Applications/$(APP_NAME).app; \
		cp -R "$$BUILD_APP" /Applications/; \
		xattr -cr /Applications/$(APP_NAME).app; \
		echo "✓ Installed to /Applications/$(APP_NAME).app"; \
	else \
		echo "Error: Build artifact not found"; \
		exit 1; \
	fi

# Clean build artifacts
clean:
	@echo "→ Cleaning..."
	@rm -rf $(BUILD_DIR)
	@rm -rf *.xcodeproj
	@rm -rf DerivedData
	@rm -rf ~/Library/Developer/Xcode/DerivedData/$(APP_NAME)-*
	@echo "✓ Clean complete"

# Print help
help:
	@echo "FaceGate-Mac Build System"
	@echo ""
	@echo "  make generate   — Generate .xcodeproj from project.yml"
	@echo "  make build      — Build debug version"
	@echo "  make archive    — Create release archive"
	@echo "  make dmg        — Create DMG installer"
	@echo "  make install    — Build and install to /Applications"
	@echo "  make clean      — Remove all build artifacts"
