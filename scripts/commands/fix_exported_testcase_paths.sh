#!/bin/bash
# Fix old exported testcase directories produced with literal backslashes in path names.
#
# Usage:
#   ./classming.sh fix-paths generated-seed-tests

set -e

OUT="${1:-generated-leetcode-tests}"

if [ ! -d "$OUT/testcases" ]; then
    echo "Not a generated testcase output directory: $OUT"
    exit 1
fi

fixed=0

find "$OUT/testcases" -type f -name '*.class' | while IFS= read -r file; do
    case "$file" in
        *'\'*)
            new_file="$(printf '%s' "$file" | tr '\\' '/')"
            mkdir -p "$(dirname "$new_file")"
            if [ "$file" != "$new_file" ]; then
                mv "$file" "$new_file"
                echo "fixed: $file -> $new_file"
            fi
            ;;
    esac
done

find "$OUT/testcases" -name '.DS_Store' -type f -delete
find "$OUT/testcases" -depth -type d | while IFS= read -r dir; do
    case "$dir" in
        *\\*)
            rmdir "$dir" 2>/dev/null || true
            ;;
    esac
done

echo "Done fixing exported testcase paths under $OUT/testcases"
