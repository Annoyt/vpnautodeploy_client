#!/usr/bin/env bash
# Is this fork based on FlClash's latest release? Run from the repository
# root with gh signed in (GH_TOKEN in CI). Prints "<our base> <upstream's
# latest>" and exits 0 when the base is current, 10 when upstream has
# released something newer, any other code when it cannot tell.
set -euo pipefail

base="$(sed -n 's/^version: *\([0-9][0-9.]*\)-neko\..*/\1/p' pubspec.yaml)"
latest="$(gh api repos/chen08209/FlClash/releases/latest --jq .tag_name)"
latest="${latest#v}"
if [ -z "$base" ] || [ -z "$latest" ]; then
  echo "base '$base', upstream '$latest': cannot compare" >&2
  exit 1
fi
echo "$base $latest"
newest="$(printf '%s\n%s\n' "$base" "$latest" | sort -V | tail -n 1)"
[ "$newest" = "$base" ] || exit 10
