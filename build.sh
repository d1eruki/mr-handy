#!/bin/zsh
set -eu
PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/build/Mr Handy.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$PROJECT_DIR/build/module-cache"
xcrun swiftc "$PROJECT_DIR/main.swift" -o "$APP_DIR/Contents/MacOS/MrHandy" -target arm64-apple-macosx14.0 -framework AppKit -module-cache-path "$PROJECT_DIR/build/module-cache" -O
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
print -r -- "$APP_DIR"
