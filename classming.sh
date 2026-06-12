#!/bin/bash
# Unified Classming command line entry.
#
# Usage:
#   ./classming.sh <command> [options]
#
# Commands:
#   build              Compile Classming Java sources
#   run                Run Classming on one seed class
#   export             Export AcceptHistory into clean testcase directories
#   clean-export       Clean already exported testcase directories
#   fix-paths          Fix old exported paths containing literal backslashes
#   batch              Batch-run a standard package-layout seed corpus
#   batch-classfiles   Batch-run a corpus with nonstandard class filenames

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/scripts/commands"

usage() {
    cat <<'EOF'
Usage:
  ./classming.sh <command> [options]

Commands:
  build              Compile Classming Java sources
  run                Run Classming on one seed class
  export             Export AcceptHistory into clean testcase directories
  clean-export       Clean already exported testcase directories
  fix-paths          Fix old exported paths containing literal backslashes
  batch              Batch-run a standard package-layout seed corpus
  batch-classfiles   Batch-run a corpus with nonstandard class filenames
EOF
}

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    build)
        exec "$COMMANDS_DIR/build.sh" "$@"
        ;;
    run)
        exec "$COMMANDS_DIR/run.sh" "$@"
        ;;
    export)
        exec "$COMMANDS_DIR/export_testcases.sh" "$@"
        ;;
    clean-export)
        exec "$COMMANDS_DIR/clean_exported_testcases.sh" "$@"
        ;;
    fix-paths)
        exec "$COMMANDS_DIR/fix_exported_testcase_paths.sh" "$@"
        ;;
    batch)
        exec "$COMMANDS_DIR/run_seed_corpus_batch.sh" "$@"
        ;;
    batch-classfiles|package-batch)
        exec "$COMMANDS_DIR/run_classfile_corpus_batch.sh" "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $command"
        usage
        exit 1
        ;;
esac
