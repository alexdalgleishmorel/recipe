#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------
# Produces the Lambda dist dir that infra/shared's `archive_file` zips (var.lambda_dist_dir).
#
# The dist dir is a flat bundle: every function module at the top level (so the `handler` string
# "<module>.<function>" resolves) plus the shared data-access layer plus any vendored pip deps. The
# deploy workflow (a later issue) runs this before `terraform apply`.
#
# Usage:  ./build.sh            # builds backend/dist
# ---------------------------------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"

echo "==> Cleaning $DIST"
rm -rf "$DIST"
mkdir -p "$DIST"

# 1. Copy each function's module(s) to the top level of the bundle.
echo "==> Copying function handlers"
for fn_dir in "$ROOT"/functions/*/; do
  find "$fn_dir" -maxdepth 1 -name '*.py' -exec cp {} "$DIST/" \;
done

# 2. Copy the shared data-access layer (importable as `data_access`).
echo "==> Copying shared layers"
for layer_dir in "$ROOT"/layers/*/; do
  cp -R "$layer_dir" "$DIST/$(basename "$layer_dir")"
done

# 3. Vendor third-party deps from every requirements.txt into the bundle (skip empty/comment-only).
echo "==> Vendoring dependencies"
for req in "$ROOT"/functions/*/requirements.txt "$ROOT"/layers/*/requirements.txt; do
  [ -f "$req" ] || continue
  if grep -qvE '^\s*(#.*)?$' "$req"; then
    python3 -m pip install -r "$req" --target "$DIST" --quiet
  fi
done

echo "==> Built bundle at $DIST"
