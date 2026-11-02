.PHONY: project build sim device clean open

project:            ## Regenerate InkyTap.xcodeproj from project.yml
	xcodegen generate

build: project      ## Build for the iOS simulator (no signing needed)
	xcodebuild -project InkyTap.xcodeproj -scheme InkyTap -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build -quiet

sim: project        ## Build, install and launch on an iPhone 17 simulator
	xcodebuild -project InkyTap.xcodeproj -scheme InkyTap -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData build -quiet
	xcrun simctl boot "iPhone 17" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "iPhone 17" build/DerivedData/Build/Products/Debug-iphonesimulator/InkyTap.app
	xcrun simctl launch "iPhone 17" io.github.donny.inkytap

device:             ## Build, install and launch on a USB-connected iPhone
	scripts/deploy-device.sh

open: project       ## Open the project in Xcode
	open InkyTap.xcodeproj

clean:
	rm -rf build InkyTap.xcodeproj
