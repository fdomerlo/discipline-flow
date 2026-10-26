#!/usr/bin/env bash
# scripts/package.sh — Build the versioned skill distributable (zip only).
# Single source of truth for packaging, used locally and by CI.
# Content comes from `git archive HEAD` (+ .gitattributes export-ignore),
# so only tracked distributable files travel: SKILL.md, workflows/, scripts/,
# assets/. A VERSION file (tag + commit) is injected into the archive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
cd "$SKILL_DIR"

ALLOW_DIRTY=false
OUT_DIR="dist"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-dirty) ALLOW_DIRTY=true; shift ;;
        -o|--out-dir) OUT_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--allow-dirty] [-o <out-dir>]"
            echo "Builds dist/discipline-flow-<version>.zip + sha256sums.txt from git."
            exit 0
            ;;
        *) echo "Error: Unknown argument '$1'" >&2; exit 1 ;;
    esac
done

for tool in git tar zip sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Error: required tool '$tool' not found." >&2; exit 1; }
done

if [[ -n "$(git status --porcelain)" ]]; then
    if [[ "$ALLOW_DIRTY" != true ]]; then
        echo "Error: working tree is dirty. Commit first or pass --allow-dirty (preview only)." >&2
        exit 1
    fi
    DIRTY_SUFFIX="-dirty"
else
    DIRTY_SUFFIX=""
fi

VERSION="$(git describe --tags --always)"
VERSION="${VERSION}${DIRTY_SUFFIX}"
NAME="discipline-flow-${VERSION}"
mkdir -p "$OUT_DIR"
ARCHIVE="$OUT_DIR/$NAME.zip"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. Export tracked distributable tree (respects .gitattributes export-ignore).
git archive --format=tar --prefix="$NAME/" HEAD | tar -x -C "$TMP"
# 2. Stamp version (release tag + exact commit) inside the archive only.
printf '%s\n%s\n' "$VERSION" "$(git rev-parse HEAD)" > "$TMP/$NAME/VERSION"
# 3. Zip it.
rm -f "$ARCHIVE"
(cd "$TMP" && zip -qr "$OLDPWD/$ARCHIVE" "$NAME")
sha256sum "$ARCHIVE" | sed "s|$OUT_DIR/||" > "$OUT_DIR/sha256sums.txt"

echo "Built: $ARCHIVE"
echo "Contents:"
unzip -l "$ARCHIVE" | awk 'NR>3 && NF {print "  " $4}' | grep -v '^  $' || true
cat "$OUT_DIR/sha256sums.txt"
