#!/bin/bash
# Remove Print.logPrint instrumentation from already-exported testcases and delete Print.class helpers.
#
# Usage:
#   ./classming.sh clean-export <generated-output-dir>
#
# Example:
#   ./classming.sh clean-export generated-tests

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

. "$SCRIPT_DIR/scripts/classpath.sh"

OUT="${1:-generated-leetcode-tests}"

if [ ! -d "$OUT/testcases" ]; then
    echo "Not a generated testcase output directory: $OUT"
    exit 1
fi

if [ ! -d "out/production/classming" ]; then
    ./classming.sh build
fi

STRIP_CP="$(build_strip_cp)"

count=0
find "$OUT/testcases" -type f -name '*.class' | while IFS= read -r class_file; do
    case "$(basename "$class_file")" in
        Print.class)
            rm -f "$class_file"
            ;;
        *)
            tmp_file="$class_file.clean.tmp"
            java -cp "$STRIP_CP" com.classming.util.StripPrintInstrumentation "$class_file" "$tmp_file"
            mv "$tmp_file" "$class_file"
            count=$((count + 1))
            ;;
    esac
done

find "$OUT/testcases" -name '.DS_Store' -type f -delete
find "$OUT/testcases" -depth -type d -empty -delete

echo "Cleaned exported testcases under $OUT/testcases"
