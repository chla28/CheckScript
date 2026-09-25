#!/usr/bin/env bash
# install-git-hooks.sh — Active les hooks du dépôt (.githooks/) : contrôle
# des messages de commit (Conventional Commits).
# Retrait : git config --unset core.hooksPath
set -euo pipefail
cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "✓ hooks actifs (.githooks/commit-msg)"
