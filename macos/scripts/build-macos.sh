#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macos_dir=${script_dir:h}
app_name='Codex Usage Monitor'
bundle_dir="$macos_dir/dist/$app_name.app"
contents_dir="$bundle_dir/Contents"
version=${CODEXTIME_VERSION:-0.3.0}
build_number=${CODEXTIME_BUILD_NUMBER:-2026101907}
# A single architecture can be requested for local development only.
archs=(${=CODEXTIME_ARCHS:-arm64 x86_64})
version_pattern='^[0-9]+[.][0-9]+[.][0-9]+$'
build_pattern='^[0-9]+([.][0-9]+){0,2}$'

if [[ ! "$version" =~ $version_pattern || ! "$build_number" =~ $build_pattern ]]; then
  print -u2 'Version must be x.y.z and build number must contain only numeric components.'
  exit 1
fi
if (( ${#archs} == 0 )); then
  print -u2 'At least one supported architecture is required.'
  exit 1
fi
for arch in "${archs[@]}"; do
  if [[ "$arch" != arm64 && "$arch" != x86_64 ]]; then
    print -u2 "Unsupported architecture: $arch"
    exit 1
  fi
done
archs=(${(u)archs})
if [[ ${CODEXTIME_PUBLIC_RELEASE:-0} == 1 ]]; then
  if [[ -z ${CODEXTIME_SIGN_IDENTITY:-} || ${CODEXTIME_SIGN_IDENTITY:-} == - ]]; then
    print -u2 'Public releases require a Developer ID Application signing identity.'
    exit 1
  fi
  if (( ${#archs} != 2 )); then
    print -u2 'Public releases must include arm64 and x86_64.'
    exit 1
  fi
fi

build_args=(-c release --product CodexUsageMonitor)
for arch in "${archs[@]}"; do
  build_args+=(--arch "$arch")
done
cd "$macos_dir"
swift build "${build_args[@]}"
binary_dir=$(swift build "${build_args[@]}" --show-bin-path)
for arch in "${archs[@]}"; do
  /usr/bin/lipo "$binary_dir/CodexUsageMonitor" -verify_arch "$arch"
done

if [[ -e "$bundle_dir" ]]; then
  backup_dir="$macos_dir/dist/$app_name.backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$bundle_dir" "$backup_dir"
fi

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/CodexUsageMonitor" "$contents_dir/MacOS/CodexUsageMonitor"
cp "$macos_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
# SwiftPM's resource accessor resolves the bundle from app Resources at runtime.
resource_bundles=("$binary_dir"/*.bundle(N))
for resource_bundle in "${resource_bundles[@]}"; do
  cp -R "$resource_bundle" "$contents_dir/Resources/"
done
# Keep direct template logos for the menu-bar resource fallback.
cp "$macos_dir/Sources/CodexUsageMonitor/Resources/"*.png "$contents_dir/Resources/"
if [[ -f "$macos_dir/../docs/third-party-notices.md" ]]; then
  cp "$macos_dir/../docs/third-party-notices.md" "$contents_dir/Resources/ThirdPartyNotices.md"
fi

/usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Codex Usage Monitor' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string CodexUsageMonitor' "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$contents_dir/Info.plist"
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
/usr/bin/codesign --verify --deep --strict "$bundle_dir"
if [[ ${CODEXTIME_PUBLIC_RELEASE:-0} == 1 ]]; then
  signing_details=$(/usr/bin/codesign --display --verbose=4 "$bundle_dir" 2>&1)
  if [[ "$signing_details" != *'Authority=Developer ID Application:'* ]]; then
    print -u2 'The app was not signed with a Developer ID Application certificate.'
    exit 1
  fi
fi

echo "$bundle_dir"
