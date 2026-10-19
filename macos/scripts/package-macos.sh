#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macos_dir=${script_dir:h}
repo_dir=${macos_dir:h}
version=${1:-${CODEXTIME_VERSION:-0.3.0}}
version_pattern='^[0-9]+[.][0-9]+[.][0-9]+$'
if [[ ! "$version" =~ $version_pattern ]]; then
  print -u2 'Version must be x.y.z.'
  exit 1
fi
if [[ ${CODEXTIME_PUBLIC_RELEASE:-0} == 1 ]]; then
  if [[ -z ${CODEXTIME_SIGN_IDENTITY:-} || ${CODEXTIME_SIGN_IDENTITY:-} == - || -z ${CODEXTIME_NOTARY_PROFILE:-} ]]; then
    print -u2 'Public releases require Developer ID signing and an Apple notarization profile.'
    exit 1
  fi
fi
if [[ -n ${CODEXTIME_NOTARY_PROFILE:-} && ( -z ${CODEXTIME_SIGN_IDENTITY:-} || ${CODEXTIME_SIGN_IDENTITY:-} == - ) ]]; then
  print -u2 'Notarization requires Developer ID signing.'
  exit 1
fi

artifact_name="CodexTime-macOS-$version"
stage_dir="$macos_dir/dist/$artifact_name"
dmg_path="$repo_dir/dist/$artifact_name.dmg"
app_path="$macos_dir/dist/Codex Usage Monitor.app"
notary_dir=''
cleanup() {
  if [[ -n "$notary_dir" ]]; then
    rm -rf "$notary_dir"
  fi
}
trap cleanup EXIT

CODEXTIME_VERSION="$version" "$script_dir/build-macos.sh" >/dev/null

if [[ -n ${CODEXTIME_NOTARY_PROFILE:-} ]]; then
  notary_dir=$(mktemp -d "${TMPDIR:-/tmp}/codextime-notary.XXXXXX")
  notary_args=(--keychain-profile "$CODEXTIME_NOTARY_PROFILE")
  if [[ -n ${CODEXTIME_NOTARY_KEYCHAIN:-} ]]; then
    notary_args+=(--keychain "$CODEXTIME_NOTARY_KEYCHAIN")
  fi
  notarize() {
    local artifact_path="$1"
    local result_path="$2"
    xcrun notarytool submit "$artifact_path" "${notary_args[@]}" --wait --output-format json > "$result_path"
    local result_status
    result_status=$(/usr/bin/plutil -extract status raw -o - "$result_path")
    if [[ "$result_status" != Accepted ]]; then
      print -u2 "Apple notarization did not accept ${artifact_path:t}."
      return 1
    fi
  }
  # Staple the app before placing it in the DMG, so copied installations also
  # carry their own ticket when opened without network access.
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notary_dir/app.zip"
  notarize "$notary_dir/app.zip" "$notary_dir/app-result.json"
  xcrun stapler staple "$app_path"
  xcrun stapler validate "$app_path"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
fi

rm -rf "$stage_dir"
mkdir -p "$stage_dir" "$repo_dir/dist"
/usr/bin/ditto "$app_path" "$stage_dir/Codex Usage Monitor.app"
ln -s /Applications "$stage_dir/Applications"
cp "$repo_dir/LICENSE" "$stage_dir/LICENSE.txt"
cp "$macos_dir/Resources/GettingStarted.html" "$stage_dir/시작하기.html"

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
  notarize "$dmg_path" "$notary_dir/dmg-result.json"
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
  /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
fi
/usr/bin/codesign --verify --deep --strict "$app_path"
if [[ -n ${CODEXTIME_SIGN_IDENTITY:-} ]]; then
  /usr/bin/codesign --verify --strict "$dmg_path"
fi
hdiutil verify "$dmg_path" >/dev/null

echo "$dmg_path"
