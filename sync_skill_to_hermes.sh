#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
TARGET_DIR="${1:-$HOME/.hermes/skills/devops/coredump-analysis}"

mkdir -p "$TARGET_DIR/references"

copy_if_exists() {
    local src="$1"
    local dst="$2"
    if [[ -f "$src" ]]; then
        cp "$src" "$dst"
        echo "synced: $dst"
    fi
}

for name in README.md enhanced-analysis.md automatic-deep-dive-policy.md fixer-architecture.md; do
    copy_if_exists "$REPO_DIR/references/$name" "$TARGET_DIR/references/$name"
done

python3 "$REPO_DIR/check_skill_sync.py" --rewrite-external-skill "$TARGET_DIR"

echo "done: synced repo-managed skill docs to $TARGET_DIR"
