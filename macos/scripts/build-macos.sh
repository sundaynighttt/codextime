#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macos_dir=${script_dir:h}
app_name='Codex Usage Monitor'
bundle_dir="$macos_dir/dist/$app_name.app"
contents_dir="$bundle_dir/Contents"
version=${CODEXTIME_VERSION:-0.1.0}
build_number=${CODEXTIME_BUILD_NUMBER:-1}

cd "$macos_dir"
swift build -c release

if [[ -e "$bundle_dir" ]]; then
  backup_dir="$macos_dir/dist/$app_name.backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$bundle_dir" "$backup_dir"
fi

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$macos_dir/.build/release/CodexUsageMonitor" "$contents_dir/MacOS/CodexUsageMonitor"

/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Codex Usage Monitor' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string CodexUsageMonitor' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.sundaynighttt.codex-usage-monitor' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleInfoDictionaryVersion string 6.0' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string CodexUsageMonitor' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$contents_dir/Info.plist"
if [[ -n ${CODEXTIME_SIGN_IDENTITY:-} ]]; then
  /usr/bin/codesign --force --deep --options runtime --timestamp --sign "$CODEXTIME_SIGN_IDENTITY" "$bundle_dir"
else
  /usr/bin/codesign --force --deep --sign - "$bundle_dir"
fi

echo "$bundle_dir"
