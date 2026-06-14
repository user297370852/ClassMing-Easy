#!/bin/bash
# Build all Classming Java sources.
#
# Usage:
#   ./classming.sh build
#
# Optional:
#   CLASSMING_LIB_DIR=/path/to/jars ./classming.sh build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

. "$SCRIPT_DIR/scripts/classpath.sh"

echo "=== Classming Build ==="
echo "Compiling sources..."

rm -rf out/production/classming
mkdir -p out/production/classming

find src -name "*.java" > sources.txt
"$(resolve_javac)" -source 1.8 -target 1.8 -d out/production/classming -cp "$(build_compile_cp)" @sources.txt

echo ""
echo "=== Build Complete ==="
echo "Output: out/production/classming/"
echo ""
echo "To run: ./classming.sh run --seed <className> --iterations <N> [options]"
echo "Example: ./classming.sh run --seed com.classming.Hello --iterations 50"
