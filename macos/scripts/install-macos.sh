#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
macos_dir=${script_dir:h}
source_app="$macos_dir/dist/Codex Usage Monitor.app"
install_root="$HOME/Applications"
target_app="$install_root/Codex Usage Monitor.app"

"$script_dir/build-macos.sh" >/dev/null
mkdir -p "$install_root"

if [[ -e "$target_app" ]]; then
  backup_app="$install_root/Codex Usage Monitor.backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$target_app" "$backup_app"
fi

cp -R "$source_app" "$target_app"
open "$target_app"
echo "$target_app"
