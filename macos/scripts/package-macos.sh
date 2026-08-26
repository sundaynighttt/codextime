#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macos_dir=${script_dir:h}
repo_dir=${macos_dir:h}
version=${1:-${CODEXTIME_VERSION:-0.1.0}}
artifact_name="CodexTime-macOS-$version"
stage_dir="$macos_dir/dist/$artifact_name"
dmg_path="$repo_dir/dist/$artifact_name.dmg"

CODEXTIME_VERSION="$version" "$script_dir/build-macos.sh" >/dev/null

rm -rf "$stage_dir"
mkdir -p "$stage_dir" "$repo_dir/dist"
cp -R "$macos_dir/dist/Codex Usage Monitor.app" "$stage_dir/"
ln -s /Applications "$stage_dir/Applications"
cp "$repo_dir/LICENSE" "$stage_dir/LICENSE.txt"

rm -f "$dmg_path"
hdiutil create \
  -volname "CodexTime $version" \
  -srcfolder "$stage_dir" \
  -format UDZO \
  -ov \
  "$dmg_path" >/dev/null

if [[ -n ${CODEXTIME_SIGN_IDENTITY:-} ]]; then
  /usr/bin/codesign --force --timestamp --sign "$CODEXTIME_SIGN_IDENTITY" "$dmg_path"
fi

if [[ -n ${CODEXTIME_NOTARY_PROFILE:-} ]]; then
  xcrun notarytool submit "$dmg_path" --keychain-profile "$CODEXTIME_NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_path"
fi

echo "$dmg_path"
