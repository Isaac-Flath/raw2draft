# Raw2Draft commands
# Run `just` to see available recipes

default:
    @just --list

# Build the app (Release)
build:
    #!/usr/bin/env bash
    set -euo pipefail
    BUILD_NUM=$(date +%Y%m%d%H%M%S)
    echo "Building Raw2Draft (Release) build $BUILD_NUM..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" Raw2Draft/Resources/Info.plist
    xcodebuild -project Raw2Draft.xcodeproj -scheme Raw2Draft -configuration Release -resolvePackageDependencies 2>&1 | tail -3
    xcodebuild -project Raw2Draft.xcodeproj -scheme Raw2Draft -configuration Release build 2>&1 | tail -3
    echo "Done. Build $BUILD_NUM complete."

# Install built app to /Applications (kills running instance)
install:
    #!/usr/bin/env bash
    set -euo pipefail
    APP=$(find ~/Library/Developer/Xcode/DerivedData/Raw2Draft-*/Build/Products/Release/Raw2Draft.app -maxdepth 0 2>/dev/null | head -1)
    if [ -z "$APP" ]; then
        echo "ERROR: No build found. Run 'just build' first."; exit 1
    fi
    pkill -f "Raw2Draft.app" 2>/dev/null && sleep 1 || true
    rm -rf /Applications/Raw2Draft.app
    cp -R "$APP" /Applications/Raw2Draft.app
    mkdir -p ~/.local/bin
    cp "{{justfile_directory()}}/draft" ~/.local/bin/draft
    chmod +x ~/.local/bin/draft
    echo "Installed to /Applications/Raw2Draft.app"
    echo "CLI installed to ~/.local/bin/draft"

# Run tests
test:
    xcodebuild -project Raw2Draft.xcodeproj -scheme Raw2Draft -configuration Debug test 2>&1 | tail -20
