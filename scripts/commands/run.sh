#!/bin/bash
# Run Classming on one seed class.
#
# Usage:
#   ./classming.sh run --seed <className> --iterations <N> [options]
#
# Options:
#   --seed <className>       Target class to mutate, e.g. com.classming.Hello
#   --iterations <N>         Number of mutation iterations; default in Java entry is 10
#   --classpath <path>       Directory containing seed class files; default in Java entry is ./sootOutput/
#   --args <arg1,arg2,...>   Program arguments passed to the seed main method
#   --deps <jar1;jar2>       Extra runtime dependencies consumed by ClassmingEntry
#   --jvm-opts <opts>        Extra JVM options used when executing generated classes
#
# Optional environment variables:
#   CLASSMING_LIB_DIR        Directory containing Soot/ASM/Guava/etc jars
#   JAVA8_HOME               JDK 8 home used to locate rt.jar

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

. "$SCRIPT_DIR/scripts/classpath.sh"

if [ ! -d "out/production/classming" ]; then
    echo "Compiled classes not found. Running ./classming.sh build first."
    ./classming.sh build
fi

mkdir -p tmp nolivecode AcceptHistory RejectHistory

echo "Restoring built-in seed classes..."
if [ -d "out/production/classming" ]; then
    rsync -a --include="*/" --include="*.class" --exclude="*" out/production/classming/ sootOutput/ 2>/dev/null || true
fi

echo "=== Classming Runner ==="
echo "Args: $@"
echo ""

java -Xms128m -Xmx20480m -Dfile.encoding=UTF-8 -cp "$(build_runtime_cp)" com.classming.ClassmingEntry "$@"
