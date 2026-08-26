#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macos_dir=${script_dir:h}
bundle_dir="$macos_dir/dist/CodexTime Screenshot Preview.app"
contents_dir="$bundle_dir/Contents"

cd "$macos_dir"
swift build -c debug --product CodexTimeScreenshotPreview

rm -rf "$bundle_dir"
mkdir -p "$contents_dir/MacOS"
cp "$macos_dir/.build/debug/CodexTimeScreenshotPreview" "$contents_dir/MacOS/"

/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string CodexTime Screenshot Preview' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string CodexTimeScreenshotPreview' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.sundaynighttt.codextime.screenshot-preview' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string CodexTimeScreenshotPreview' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$contents_dir/Info.plist"
/usr/bin/codesign --force --deep --sign - "$bundle_dir"

echo "$bundle_dir"
