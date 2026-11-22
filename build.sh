#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

app="build/Trackpad Feedback.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
sample_copy="$(mktemp "$app/Contents/Resources/example.XXXXXX")"
cat Resources/example.mp3 > "$sample_copy"
chmod 644 "$sample_copy"
mv -f "$sample_copy" "$app/Contents/Resources/example.mp3"
xcrun clang -target arm64-apple-macos15 -O2 -c Sources/Trackpad.c -o build/Trackpad.o
xcrun swiftc -swift-version 6 -target arm64-apple-macos15 -O \
    -import-objc-header Sources/Trackpad.h \
    Sources/*.swift build/Trackpad.o -o "$app/Contents/MacOS/TrackpadFeedback"
codesign --force --sign - "$app"
printf '%s\n' "$PWD/$app"
