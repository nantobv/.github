#!/usr/bin/env bash
# Refresh the nantobv-shared block in a repo's AGENTS.md from the canonical
# AGENTS.shared.md in nantobv/.github.
#
# Idempotent — running twice produces an identical AGENTS.md.
#
# Usage:
#   ./scripts/sync-agents-shared.sh           # operates on ./AGENTS.md
#   ./scripts/sync-agents-shared.sh path/to/AGENTS.md
#
# Source resolution order:
#   1. $NANTOBV_SHARED_PATH if set (absolute path to AGENTS.shared.md).
#   2. Sibling clone of nantobv/.github at ../.github/ or ../nantobv-.github/.
#   3. Fetch from raw.githubusercontent.com/nantobv/.github@main via curl.
#
# The target AGENTS.md must already contain the marker pair below. If it
# doesn't, the script prints an instructions block and exits non-zero — it
# never invents a location for the block.
#
# Requires: python3, and either curl or a sibling nantobv/.github clone.

set -euo pipefail

TARGET="${1:-AGENTS.md}"
BEGIN='<!-- BEGIN nantobv-shared (sync via nantobv/.github/scripts/sync-agents-shared.sh) -->'
END='<!-- END nantobv-shared -->'

if [ ! -f "$TARGET" ]; then
  echo "error: $TARGET not found" >&2
  exit 1
fi

# Resolve source
SRC=""
CLEANUP_SRC=""
if [ -n "${NANTOBV_SHARED_PATH:-}" ] && [ -f "$NANTOBV_SHARED_PATH" ]; then
  SRC="$NANTOBV_SHARED_PATH"
elif [ -f "../.github/AGENTS.shared.md" ]; then
  SRC="../.github/AGENTS.shared.md"
elif [ -f "../nantobv-.github/AGENTS.shared.md" ]; then
  SRC="../nantobv-.github/AGENTS.shared.md"
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: no local nantobv/.github clone found and curl not installed" >&2
    exit 1
  fi
  SRC="$(mktemp)"
  CLEANUP_SRC="$SRC"
  trap 'rm -f "$CLEANUP_SRC"' EXIT
  curl -sSfL \
    "https://raw.githubusercontent.com/nantobv/.github/main/AGENTS.shared.md" \
    -o "$SRC"
fi

# Verify markers exist in target
if ! grep -qF "$BEGIN" "$TARGET" || ! grep -qF "$END" "$TARGET"; then
  cat >&2 <<EOF
error: $TARGET does not contain the nantobv-shared marker pair.

Add the following block where you want the shared section to appear
(typically after the Project section, before Coding Standards):

$BEGIN
(this body is replaced by sync-agents-shared.sh)
$END

Then re-run this script.
EOF
  exit 2
fi

# Replace the block between markers. Python keeps the logic portable and
# avoids sed -i incompatibilities (notably on FUSE/SSHFS mounts).
python3 - "$TARGET" "$SRC" "$BEGIN" "$END" <<'PY'
import pathlib
import sys

target_path, src_path, begin, end = sys.argv[1:5]
target = pathlib.Path(target_path)
src = pathlib.Path(src_path)

text = target.read_text()
body = src.read_text().rstrip() + "\n"

begin_idx = text.find(begin)
end_idx = text.find(end, begin_idx + len(begin)) if begin_idx != -1 else -1
if begin_idx == -1 or end_idx == -1 or end_idx <= begin_idx:
    sys.exit(f"markers not found in expected order in {target_path}")

new = (
    text[: begin_idx + len(begin)]
    + "\n"
    + body
    + text[end_idx:]
)
if new != text:
    target.write_text(new)
    print(f"synced {target_path}")
else:
    print(f"{target_path} already in sync")
PY
