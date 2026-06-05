#!/bin/bash
set -euo pipefail

cat >&2 <<'EOF'
ERROR: sync_skill_to_hermes.sh is disabled.

This repository is the distributable coredump-analysis skill source of truth.
Do not sync or depend on user-private Hermes cache paths such as:
  ~/.hermes/skills/devops/coredump-analysis

Use the current repository directory directly when packaging or sharing this skill.
Run project-local validation instead:
  python3 check_skill_sync.py
EOF

exit 1
