#!/bin/bash
# Export Classming accepted mutants into runnable classpath overlay directories.
#
# Usage:
#   ./classming.sh export --history AcceptHistory --out generated-tests
#
# Each exported testcase directory contains cleaned mutated classes.
# Run it by putting the testcase directory before the original seed classpath:
#   java -cp generated-tests/<id>:sootOutput/random_seeds_500 <MainClass> [args]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

. "$SCRIPT_DIR/scripts/classpath.sh"

HISTORY="AcceptHistory"
OUT="generated-tests"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --history)
            HISTORY="$2"
            shift 2
            ;;
        --out)
            OUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ ! -d "$HISTORY" ]; then
    echo "History directory not found: $HISTORY"
    exit 1
fi

mkdir -p "$OUT"

if [ ! -d "out/production/classming" ]; then
    ./classming.sh build
fi

count=0
for mutant in "$HISTORY"/*.class; do
    [ -e "$mutant" ] || continue

    base="$(basename "$mutant")"
    id="${base%%.*}"
    class_name="${base#*.}"
    class_name="${class_name%.class}"
    class_path="$(printf '%s' "$class_name" | tr '.' '/').class"

    target_dir="$OUT/$id"
    mkdir -p "$target_dir/$(dirname "$class_path")"
    java -cp "$(build_strip_cp)" com.classming.util.StripPrintInstrumentation "$mutant" "$target_dir/$class_path"

    count=$((count + 1))
done

echo "Exported $count testcase(s) to $OUT"
echo "Run with: java -cp $OUT/<testcase-id>:<original-seed-classpath> <MainClass> [args]"
