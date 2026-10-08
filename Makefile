.PHONY: project build run dmg clean

XCODEBUILD = xcodebuild -project FocusKit.xcodeproj -scheme FocusKit -destination 'platform=macOS,arch=arm64' -quiet
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PRODUCTS = $$(xcodebuild -project FocusKit.xcodeproj -scheme FocusKit -configuration $(1) -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $$2}')/FocusKit.app

project:
	xcodegen generate --quiet

build: project
	$(XCODEBUILD) -configuration Release build
	$(LSREGISTER) -u "$(call PRODUCTS,Release)" || true

run: project
	$(XCODEBUILD) -configuration Debug build
	@if [ -f signing/build.keychain-db ] && [ -f signing/p12-password.txt ]; then \
		security unlock-keychain -p "$$(cat signing/p12-password.txt)" "$(CURDIR)/signing/build.keychain-db" && \
		codesign --force --deep --keychain "$(CURDIR)/signing/build.keychain-db" --sign "FocusKit Signing" \
			--entitlements FocusKit/Resources/FocusKit.entitlements "$(call PRODUCTS,Debug)"; \
	fi
	pkill -x FocusKit || true
	open "$$(xcodebuild -project FocusKit.xcodeproj -scheme FocusKit -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $$2}')/FocusKit.app"

dmg:
	./Scripts/package.sh

clean:
	rm -rf FocusKit.xcodeproj build dist
