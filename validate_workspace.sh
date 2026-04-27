#!/bin/bash
# 仓库根目录快捷入口

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/coredump-full-analysis/scripts/validate_workspace.sh" "$@"
