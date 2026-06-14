#!/bin/bash
# Batch-run Classming over a corpus whose .class files may not be laid out as Java package paths.
#
# This script reads each class file's internal JVM name, creates a per-seed normalized
# classpath root, runs Classming, and exports clean testcases.
#
# Usage:
#   ./classming.sh batch-classfiles --input <classfile-corpus-dir> --out <output-dir> --iterations 20

set -u

INPUT="sootOutput/seeds"
OUT="generated-classfile-tests"
ITERATIONS="10"
TIMEOUT_SECONDS="180"
LIMIT="0"
RUN_ALL="0"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --input)
            INPUT="$2"
            shift 2
            ;;
        --out)
            OUT="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --run-all)
            RUN_ALL="1"
            shift
            ;;
        -h|--help)
            sed -n '1,80p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

. "$SCRIPT_DIR/scripts/classpath.sh"

if [ ! -d "$INPUT" ]; then
    echo "Input directory not found: $INPUT"
    exit 1
fi

if [ ! -d "out/production/classming" ]; then
    ./classming.sh build || exit 1
fi

mkdir -p "$OUT/testcases" "$OUT/logs" "$OUT/raw" "$OUT/work/deps" "$OUT/work/run" tmp AcceptHistory RejectHistory nolivecode

MANIFEST="$OUT/manifest.tsv"
if [ ! -f "$MANIFEST" ]; then
    printf 'seed\tmutant_id\ttestcase_dir\tseed_classpath\trun_command\tsource_class\n' > "$MANIFEST"
fi

sanitize() {
    printf '%s' "$1" | tr './@$' '____'
}

class_internal_name() {
    local classfile="$1"
    javap -public -cp . "$classfile" 2>/dev/null | sed -n -E \
        -e 's/^(public |protected |private |final |abstract |strictfp )*(class|interface|enum) ([^ <{]+).*/\3/p' \
        -e 's/^(public |protected |private |final |abstract |strictfp )*@interface ([^ <{]+).*/\2/p' \
        | sed -n '1p'
}

has_main_classfile() {
    local classfile="$1"
    javap -public -cp . "$classfile" 2>/dev/null | grep -Eq 'public static void main\(java\.lang\.String\[\]\)'
}

copy_common_deps() {
    local target_root="$1"
    if [ -f "$INPUT/GCObj.class" ]; then
        cp "$INPUT/GCObj.class" "$target_root/GCObj.class"
    fi
    cp "sootOutput/HotSpot/GCObj.class" "$target_root/GCObj.class" 2>/dev/null || true
    cp "sootOutput/leetcodes/out/production/leetcodes/GCObj.class" "$target_root/GCObj.class" 2>/dev/null || true
    cp "sootOutput/Print.class" "$target_root/Print.class" 2>/dev/null || true
}

internal_path_for_class() {
    local internal="$1"
    printf '%s.class' "$(printf '%s' "$internal" | tr '.' '/')"
}

copy_seed_family() {
    local classfile="$1"
    local internal="$2"
    local deps_root="$3"
    local internal_path sibling sibling_internal sibling_path top_level sibling_top_level

    internal_path="$(internal_path_for_class "$internal")"
    mkdir -p "$deps_root/$(dirname "$internal_path")"
    cp "$classfile" "$deps_root/$internal_path"

    top_level="${internal%%\$*}"
    for sibling in "$(dirname "$classfile")"/*.class; do
        [ -f "$sibling" ] || continue
        [ "$sibling" != "$classfile" ] || continue
        sibling_internal="$(class_internal_name "$sibling")"
        [ -n "$sibling_internal" ] || continue
        sibling_top_level="${sibling_internal%%\$*}"
        [ "$sibling_top_level" = "$top_level" ] || continue
        sibling_path="$(internal_path_for_class "$sibling_internal")"
        mkdir -p "$deps_root/$(dirname "$sibling_path")"
        cp "$sibling" "$deps_root/$sibling_path"
    done
}

export_mutant() {
    local seed="$1"
    local seed_id="$2"
    local deps_root="$3"
    local source_class="$4"
    local mutant="$5"
    [ -f "$mutant" ] || return 0

    local base id class_name class_path target_dir run_cmd
    base="$(basename "$mutant")"
    id="${base%%.*}"
    class_name="${base#*.}"
    class_name="${class_name%.class}"
    class_path="$(printf '%s' "$class_name" | tr '.' '/').class"
    target_dir="$OUT/testcases/$seed_id/$id"

    mkdir -p "$target_dir/$(dirname "$class_path")"
    "$(resolve_java8)" -cp "$(build_strip_cp)" com.classming.util.StripPrintInstrumentation "$mutant" "$target_dir/$class_path"
    cp "$mutant" "$OUT/raw/${id}.${class_name}.class" 2>/dev/null || true

    run_cmd="java -cp \"$target_dir:$deps_root\" $seed"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$seed" "$id" "$target_dir" "$deps_root" "$run_cmd" "$source_class" >> "$MANIFEST"
    rm -f "$mutant"
    echo "[export] $seed -> $target_dir"
}

watch_accept_history() {
    local seed="$1"
    local seed_id="$2"
    local deps_root="$3"
    local source_class="$4"
    local stop_file="$5"
    while true; do
        for mutant in AcceptHistory/*.class; do
            [ -e "$mutant" ] || continue
            export_mutant "$seed" "$seed_id" "$deps_root" "$source_class" "$mutant"
        done
        [ -f "$stop_file" ] && break
        sleep 1
    done
    for mutant in AcceptHistory/*.class; do
        [ -e "$mutant" ] || continue
        export_mutant "$seed" "$seed_id" "$deps_root" "$source_class" "$mutant"
    done
}

run_classfile_seed() {
    local classfile="$1"
    local internal seed seed_id internal_path deps_root run_root log_file stop_file watcher_pid exit_code

    internal="$(class_internal_name "$classfile")"
    if [ -z "$internal" ]; then
        echo "[skip] cannot read internal class name: $classfile"
        return 2
    fi

    seed="$(printf '%s' "$internal" | tr '/' '.')"
    seed_id="$(sanitize "$seed")__$(basename "$classfile" .class | tr '@' '_')"
    internal_path="$(internal_path_for_class "$internal")"
    deps_root="$OUT/work/deps/$seed_id"
    run_root="$OUT/work/run/$seed_id"
    log_file="$OUT/logs/$seed_id.log"
    stop_file="tmp/.watch-stop-$seed_id"

    echo "[seed] $seed ($classfile)"

    rm -rf "$deps_root" "$run_root" AcceptHistory RejectHistory nolivecode tmp
    mkdir -p "$deps_root/$(dirname "$internal_path")" "$run_root" AcceptHistory RejectHistory nolivecode tmp

    copy_seed_family "$classfile" "$internal" "$deps_root"
    copy_common_deps "$deps_root"
    cp -R "$deps_root"/. "$run_root"/
    cp "sootOutput/Print.class" "$run_root/Print.class" 2>/dev/null || true

    rm -f "$stop_file"
    watch_accept_history "$seed" "$seed_id" "$deps_root" "$classfile" "$stop_file" &
    watcher_pid=$!

    timeout "$TIMEOUT_SECONDS" ./classming.sh run \
        --seed "$seed" \
        --iterations "$ITERATIONS" \
        --classpath "./$run_root/" \
        > "$log_file" 2>&1
    exit_code=$?

    touch "$stop_file"
    wait "$watcher_pid" 2>/dev/null || true

    if [ "$exit_code" -eq 0 ]; then
        echo "[done] $seed"
    elif [ "$exit_code" -eq 124 ]; then
        echo "[timeout] $seed after ${TIMEOUT_SECONDS}s (see $log_file)"
    else
        echo "[skip] $seed failed with exit code $exit_code (see $log_file)"
    fi
}

processed=0
while IFS= read -r classfile; do
    case "$classfile" in
        *\$*.class) continue ;;
        */GCObj.class) continue ;;
    esac

    if [ "$RUN_ALL" != "1" ]; then
        if ! has_main_classfile "$classfile"; then
            continue
        fi
    fi

    run_classfile_seed "$classfile"
    run_result=$?
    if [ "$run_result" -eq 2 ]; then
        continue
    fi
    processed=$((processed + 1))

    if [ "$LIMIT" -gt 0 ] && [ "$processed" -ge "$LIMIT" ]; then
        break
    fi
done < <(find "$INPUT" -type f -name '*.class' | sort)

echo "Processed seeds: $processed"
echo "Output: $OUT"
echo "Manifest: $MANIFEST"
