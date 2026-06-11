#!/bin/bash
# Build all Classming Java sources.
#
# Usage:
#   ./build.sh
#
# Optional:
#   CLASSMING_LIB_DIR=/path/to/jars ./build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

. "$SCRIPT_DIR/scripts/classpath.sh"

echo "=== Classming Build ==="
echo "Compiling sources..."

rm -rf out/production/classming
mkdir -p out/production/classming

find src -name "*.java" > sources.txt
javac -d out/production/classming -cp "$(build_compile_cp)" @sources.txt

echo ""
echo "=== Build Complete ==="
echo "Output: out/production/classming/"
echo ""
echo "To run: ./run.sh --seed <className> --iterations <N> [options]"
echo "Example: ./run.sh --seed com.classming.Hello --iterations 50"
