#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_dir=${script_dir:h:h}

# Generate from the actual product views instead of the legacy hand-drawn card.
python3 "$repo_dir/docs/screenshots/render-macos.py"
echo "$repo_dir/docs/screenshots"
