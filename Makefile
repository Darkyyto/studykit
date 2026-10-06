.PHONY: project build run dmg clean

XCODEBUILD = xcodebuild -project FocusKit.xcodeproj -scheme FocusKit -destination 'platform=macOS,arch=arm64' -quiet

project:
	xcodegen generate --quiet

build: project
	$(XCODEBUILD) -configuration Release build

run: project
	$(XCODEBUILD) -configuration Debug build
	pkill -x FocusKit || true
	open "$$(xcodebuild -project FocusKit.xcodeproj -scheme FocusKit -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $$2}')/FocusKit.app"

dmg:
	./Scripts/package.sh

clean:
	rm -rf FocusKit.xcodeproj build dist
