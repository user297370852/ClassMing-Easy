#!/bin/bash
# Batch-run Classming over classes in a user-provided seed corpus and export accepted mutants.
#
# Usage:
#   ./classming.sh batch --input <seed-corpus-dir> --out <output-dir> --iterations 20
#
# Output layout:
#   <out>/manifest.tsv
#   <out>/logs/<seed>.log
#   <out>/testcases/<seed>/<mutant-id>/<package/path/Class.class>

set -u

INPUT="sootOutput/seeds"
CLASSPATH_ROOT=""
OUT="generated-leetcode-tests"
ITERATIONS="10"
TIMEOUT_SECONDS="180"
LIMIT="0"
RUN_ALL="0"
KEEP_HISTORY="0"
WORKDIR=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --input)
            INPUT="$2"
            shift 2
            ;;
        --classpath-root)
            CLASSPATH_ROOT="$2"
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
        --keep-history)
            KEEP_HISTORY="1"
            shift
            ;;
        --workdir)
            WORKDIR="$2"
            shift 2
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

ORIGINAL_INPUT="$INPUT"
if [ -z "$WORKDIR" ]; then
    WORKDIR="$OUT/work/seed-corpus"
fi

rm -rf "$WORKDIR"
mkdir -p "$(dirname "$WORKDIR")"
cp -R "$ORIGINAL_INPUT" "$WORKDIR"
INPUT="$WORKDIR"

if [ -z "$CLASSPATH_ROOT" ]; then
    production_roots=()
    for candidate_root in "$INPUT"/out/production/*; do
        [ -d "$candidate_root" ] || continue
        production_roots+=("$candidate_root")
    done
    if [ "${#production_roots[@]}" -eq 1 ]; then
        CLASSPATH_ROOT="${production_roots[0]}"
    else
        CLASSPATH_ROOT="$INPUT"
    fi
else
    case "$CLASSPATH_ROOT" in
        "$ORIGINAL_INPUT"*)
            CLASSPATH_ROOT="$INPUT${CLASSPATH_ROOT#$ORIGINAL_INPUT}"
            ;;
    esac
fi

if [ ! -d "$CLASSPATH_ROOT" ]; then
    echo "Classpath root not found: $CLASSPATH_ROOT"
    exit 1
fi

if [ ! -d "out/production/classming" ]; then
    ./classming.sh build || exit 1
fi

mkdir -p "$OUT/testcases" "$OUT/logs" "$OUT/raw" tmp AcceptHistory RejectHistory nolivecode

MANIFEST="$OUT/manifest.tsv"
if [ ! -f "$MANIFEST" ]; then
    printf 'seed\tmutant_id\ttestcase_dir\tseed_classpath\trun_command\n' > "$MANIFEST"
fi

CLEAN_CLASSPATH_ROOT="$OUT/work/clean-root"
rm -rf "$CLEAN_CLASSPATH_ROOT"
mkdir -p "$CLEAN_CLASSPATH_ROOT"
cp -R "$CLASSPATH_ROOT"/. "$CLEAN_CLASSPATH_ROOT"/

cp "sootOutput/Print.class" "$CLASSPATH_ROOT/Print.class" 2>/dev/null || true

sanitize_seed() {
    printf '%s' "$1" | tr './$' '___'
}

class_name_from_file() {
    local classfile="$1"
    local rel="${classfile#$CLASSPATH_ROOT/}"
    rel="${rel%.class}"
    printf '%s' "${rel//\//.}"
}

has_main() {
    local cls="$1"
    javap -classpath "$CLASSPATH_ROOT" -public "$cls" 2>/dev/null | rg -q 'public static void main\(java.lang.String\[\]\)'
}

export_mutant() {
    local seed="$1"
    local mutant="$2"
    [ -f "$mutant" ] || return 0

    local base id class_name class_path seed_safe target_dir run_cmd
    base="$(basename "$mutant")"
    id="${base%%.*}"
    class_name="${base#*.}"
    class_name="${class_name%.class}"
    class_path="$(printf '%s' "$class_name" | tr '.' '/').class"
    seed_safe="$(sanitize_seed "$seed")"
    target_dir="$OUT/testcases/$seed_safe/$id"

    mkdir -p "$target_dir/$(dirname "$class_path")"
    java -cp "$(build_strip_cp)" com.classming.util.StripPrintInstrumentation "$mutant" "$target_dir/$class_path"
    cp "$mutant" "$OUT/raw/${id}.${class_name}.class" 2>/dev/null || true

    run_cmd="java -cp \"$target_dir:$CLEAN_CLASSPATH_ROOT\" $seed"
    printf '%s\t%s\t%s\t%s\t%s\n' "$seed" "$id" "$target_dir" "$CLEAN_CLASSPATH_ROOT" "$run_cmd" >> "$MANIFEST"
    rm -f "$mutant"
    echo "[export] $seed -> $target_dir"
}

watch_accept_history() {
    local seed="$1"
    local stop_file="$2"
    while true; do
        for mutant in AcceptHistory/*.class; do
            [ -e "$mutant" ] || continue
            export_mutant "$seed" "$mutant"
        done
        [ -f "$stop_file" ] && break
        sleep 1
    done
    for mutant in AcceptHistory/*.class; do
        [ -e "$mutant" ] || continue
        export_mutant "$seed" "$mutant"
    done
}

run_seed() {
    local seed="$1"
    local seed_safe log_file stop_file watcher_pid exit_code
    seed_safe="$(sanitize_seed "$seed")"
    log_file="$OUT/logs/$seed_safe.log"
    stop_file="tmp/.watch-stop-$seed_safe"

    echo "[seed] $seed"

    local seed_rel="$(printf '%s' "$seed" | tr '.' '/').class"
    if [ -f "$CLEAN_CLASSPATH_ROOT/$seed_rel" ]; then
        mkdir -p "$CLASSPATH_ROOT/$(dirname "$seed_rel")"
        cp "$CLEAN_CLASSPATH_ROOT/$seed_rel" "$CLASSPATH_ROOT/$seed_rel"
    fi
    cp "sootOutput/Print.class" "$CLASSPATH_ROOT/Print.class" 2>/dev/null || true

    rm -rf AcceptHistory RejectHistory nolivecode tmp
    mkdir -p AcceptHistory RejectHistory nolivecode tmp
    rm -f "$stop_file"

    watch_accept_history "$seed" "$stop_file" &
    watcher_pid=$!

    timeout "$TIMEOUT_SECONDS" ./classming.sh run \
        --seed "$seed" \
        --iterations "$ITERATIONS" \
        --classpath "./$CLASSPATH_ROOT/" \
        > "$log_file" 2>&1
    exit_code=$?

    touch "$stop_file"
    wait "$watcher_pid" 2>/dev/null || true

    if [ "$KEEP_HISTORY" != "1" ]; then
        rm -rf RejectHistory nolivecode tmp
        mkdir -p RejectHistory nolivecode tmp
    fi

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
    esac

    seed="$(class_name_from_file "$classfile")"
    case "$seed" in
        Print|GCObj) continue ;;
    esac

    if [ "$RUN_ALL" != "1" ]; then
        if ! has_main "$seed"; then
            continue
        fi
    fi

    processed=$((processed + 1))
    run_seed "$seed"

    if [ "$LIMIT" -gt 0 ] && [ "$processed" -ge "$LIMIT" ]; then
        break
    fi
done < <(rg --files "$CLASSPATH_ROOT" -g '*.class' | sort)

echo "Processed seeds: $processed"
echo "Output: $OUT"
echo "Manifest: $MANIFEST"
