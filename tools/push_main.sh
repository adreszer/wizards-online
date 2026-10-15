#!/usr/bin/env bash
# Rebase on origin/main and push HEAD to main (fast-forward only). Uses the gh CLI's
# HTTPS credentials when the SSH agent has no key loaded.
set -euo pipefail
cd "$(dirname "$0")/.."
R=https://github.com/adreszer/wizards-online.git
H='!gh auth git-credential'
git -c credential.helper="$H" fetch -q "$R" main
git rebase FETCH_HEAD
git -c credential.helper="$H" push "$R" HEAD:main
