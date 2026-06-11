#!/bin/bash
# Shared classpath helpers for Classming scripts.
#
# Optional environment variables:
#   CLASSMING_LIB_DIR  Directory containing external jars such as soot-4.1.0.jar.
#                      Defaults to ./lib, then ./dependencies, then common local Maven/cache locations.
#   JAVA8_HOME         JDK 8 home used to locate rt.jar.
#   JAVA_HOME          Used as a fallback for rt.jar when JAVA8_HOME is not set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSMING_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

shopt -s nullglob

die() {
    echo "Error: $*" >&2
    exit 1
}

first_existing_file() {
    local candidate
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

first_matching_file() {
    local pattern candidate
    for pattern in "$@"; do
        for candidate in $pattern; do
            if [ -f "$candidate" ]; then
                printf '%s' "$candidate"
                return 0
            fi
        done
    done
    return 1
}

append_existing_jars() {
    local cp_var_name="$1"
    shift
    local jar
    for jar in "$@"; do
        if [ -f "$jar" ]; then
            if [ -n "${!cp_var_name}" ]; then
                printf -v "$cp_var_name" '%s:%s' "${!cp_var_name}" "$jar"
            else
                printf -v "$cp_var_name" '%s' "$jar"
            fi
        fi
    done
}

build_repo_deps_cp() {
    local cp=""
    local jar
    for jar in "$CLASSMING_ROOT"/dependencies/*.jar; do
        [ -f "$jar" ] || continue
        case "$jar" in
            *guava*|*asm*) ;;
            *) append_existing_jars cp "$jar" ;;
        esac
    done
    printf '%s' "$cp"
}

resolve_lib_dir() {
    if [ -n "${CLASSMING_LIB_DIR:-}" ] && [ -d "$CLASSMING_LIB_DIR" ]; then
        printf '%s' "$CLASSMING_LIB_DIR"
        return 0
    fi
    if [ -d "$CLASSMING_ROOT/lib" ]; then
        printf '%s' "$CLASSMING_ROOT/lib"
        return 0
    fi
    printf '%s' "$CLASSMING_ROOT/lib"
}

build_external_cp() {
    local lib_dir
    lib_dir="$(resolve_lib_dir)"

    local cp=""
    local soot guava failureaccess functionaljava dexlib junit slf4j_api slf4j_simple commons_io
    local asm asm_tree asm_commons asm_util jasmin java_cup heros axml polyglot xmlpull

    soot="$(first_matching_file "$lib_dir"/soot-4.1.0.jar "$lib_dir"/soot-*.jar "$HOME"/.m2/repository/org/soot-oss/soot/*/soot-*.jar 2>/dev/null || true)"
    guava="$(first_matching_file "$lib_dir"/guava-*.jar "$HOME"/.m2/repository/com/google/guava/guava/*/guava-*.jar 2>/dev/null || true)"
    failureaccess="$(first_matching_file "$lib_dir"/failureaccess-*.jar "$HOME"/.m2/repository/com/google/guava/failureaccess/*/failureaccess-*.jar 2>/dev/null || true)"
    functionaljava="$(first_matching_file "$lib_dir"/functionaljava-*.jar "$HOME"/.m2/repository/org/functionaljava/functionaljava/*/functionaljava-*.jar 2>/dev/null || true)"
    dexlib="$(first_matching_file "$lib_dir"/dexlib2-*.jar "$HOME"/.m2/repository/org/smali/dexlib2/*/dexlib2-*.jar 2>/dev/null || true)"
    junit="$(first_matching_file "$lib_dir"/junit-4*.jar "$HOME"/.m2/repository/junit/junit/*/junit-*.jar 2>/dev/null || true)"
    slf4j_api="$(first_matching_file "$lib_dir"/slf4j-api-*.jar "$HOME"/.m2/repository/org/slf4j/slf4j-api/*/slf4j-api-*.jar 2>/dev/null || true)"
    slf4j_simple="$(first_matching_file "$lib_dir"/slf4j-simple-*.jar "$HOME"/.m2/repository/org/slf4j/slf4j-simple/*/slf4j-simple-*.jar 2>/dev/null || true)"
    commons_io="$(first_matching_file "$lib_dir"/commons-io-*.jar "$HOME"/.m2/repository/commons-io/commons-io/*/commons-io-*.jar 2>/dev/null || true)"
    asm="$(first_matching_file "$lib_dir"/asm-7*.jar "$lib_dir"/asm-9*.jar "$HOME"/.m2/repository/org/ow2/asm/asm/*/asm-*.jar 2>/dev/null || true)"
    asm_tree="$(first_matching_file "$lib_dir"/asm-tree-*.jar "$HOME"/.m2/repository/org/ow2/asm/asm-tree/*/asm-tree-*.jar 2>/dev/null || true)"
    asm_commons="$(first_matching_file "$lib_dir"/asm-commons-*.jar "$HOME"/.m2/repository/org/ow2/asm/asm-commons/*/asm-commons-*.jar 2>/dev/null || true)"
    asm_util="$(first_matching_file "$lib_dir"/asm-util-*.jar "$HOME"/.m2/repository/org/ow2/asm/asm-util/*/asm-util-*.jar 2>/dev/null || true)"
    jasmin="$(first_matching_file "$lib_dir"/jasmin-*.jar "$HOME"/.m2/repository/ca/mcgill/sable/jasmin/*/jasmin-*.jar 2>/dev/null || true)"
    java_cup="$(first_matching_file "$lib_dir"/java_cup-*.jar "$lib_dir"/java-cup-*.jar "$HOME"/.m2/repository/java_cup/java_cup/*/java_cup-*.jar "$HOME"/.m2/repository/com/github/vbmacher/java-cup/*/java-cup-*.jar 2>/dev/null || true)"
    heros="$(first_matching_file "$lib_dir"/heros-*.jar "$HOME"/.m2/repository/de/upb/cs/swt/heros/*/heros-*.jar 2>/dev/null || true)"
    axml="$(first_matching_file "$lib_dir"/axml-*.jar "$HOME"/.m2/repository/de/upb/cs/swt/axml/*/axml-*.jar 2>/dev/null || true)"
    polyglot="$(first_matching_file "$lib_dir"/polyglot-*.jar "$HOME"/.m2/repository/ca/mcgill/sable/polyglot/*/polyglot-*.jar 2>/dev/null || true)"
    xmlpull="$(first_matching_file "$lib_dir"/xmlpull-*.jar "$HOME"/.m2/repository/xmlpull/xmlpull/*/xmlpull-*.jar 2>/dev/null || true)"

    [ -n "$soot" ] || die "Soot jar not found. Set CLASSMING_LIB_DIR to a directory containing soot-4.1.0.jar or place jars under ./lib."
    [ -n "$asm" ] || die "ASM jar not found. Set CLASSMING_LIB_DIR or place asm jars under ./lib."
    [ -n "$asm_tree" ] || die "ASM tree jar not found. Set CLASSMING_LIB_DIR or place asm-tree jar under ./lib."

    append_existing_jars cp "$soot" "$guava" "$failureaccess" "$functionaljava" "$dexlib" "$junit" "$slf4j_api" "$slf4j_simple" "$commons_io" "$asm" "$asm_tree" "$asm_commons" "$asm_util" "$jasmin" "$java_cup" "$heros" "$axml" "$polyglot" "$xmlpull"
    printf '%s' "$cp"
}

resolve_rt_jar() {
    local candidate
    candidate="$(first_existing_file \
        "${JAVA8_HOME:-}/jre/lib/rt.jar" \
        "${JAVA_HOME:-}/jre/lib/rt.jar" \
        "/usr/lib/jvm/java-8-openjdk-amd64/jre/lib/rt.jar" \
        "/usr/lib/jvm/java-8-oracle/jre/lib/rt.jar" \
        2>/dev/null || true)"
    if [ -z "$candidate" ] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
        local java8_home
        java8_home="$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)"
        candidate="$(first_existing_file "$java8_home/jre/lib/rt.jar" 2>/dev/null || true)"
    fi
    printf '%s' "$candidate"
}

build_runtime_cp() {
    local cp
    cp="$CLASSMING_ROOT/out/production/classming"
    local repo_cp external_cp rt_jar
    repo_cp="$(build_repo_deps_cp)"
    external_cp="$(build_external_cp)"
    rt_jar="$(resolve_rt_jar)"

    [ -n "$repo_cp" ] && cp="$cp:$repo_cp"
    [ -n "$external_cp" ] && cp="$cp:$external_cp"
    [ -n "$rt_jar" ] && cp="$cp:$rt_jar"
    printf '%s' "$cp"
}

build_compile_cp() {
    local repo_cp external_cp cp
    repo_cp="$(build_repo_deps_cp)"
    external_cp="$(build_external_cp)"
    cp="$repo_cp"
    [ -n "$cp" ] && cp="$cp:$external_cp" || cp="$external_cp"
    printf '%s' "$cp"
}

build_strip_cp() {
    local cp external_cp
    external_cp="$(build_external_cp)"
    cp="$CLASSMING_ROOT/out/production/classming:$external_cp"
    printf '%s' "$cp"
}
