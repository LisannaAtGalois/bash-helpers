#! /usr/bin/env bash

github-add-path() {
    echo "$1" >> "$GITHUB_PATH"
    export PATH="$PATH:$1"
}

github-set-env() {
    echo "$1=$2" >> "$GITHUB_ENV"
    eval "$1"="$2"
    export "${1?}"
}

fetch-zip() {
    out=$1
    url=$2
    tmp=$(mktemp -d)
    curl -o "$tmp/file.zip" -L "$url" >&2
    unzip "$tmp/file.zip" -d "$tmp/unpacked" >&2
    if [[ $(ls -A1 "$tmp/unpacked" | wc -l) == 1 ]]; then
        mv "$tmp/unpacked/$(ls -A1 $tmp/unpacked)" "$out"
    else
        mv "$tmp/unpacked" "$out"
    fi
    rm -rf "$tmp"
}

fetch-tarball() {
    out=$1
    url=$2
    tmp=$(mktemp -d)
    curl -o "$tmp/file" -L "$url" >&2
    mkdir "$tmp/unpacked"
    tar xfz "$tmp/file" -C "$tmp/unpacked"
    if [[ "$(ls -A1 "$tmp/unpacked" | wc -l | awk '{print $1}')" == 1 ]]; then
        mv "$tmp/unpacked/$(ls -A1 "$tmp/unpacked")" "$out"
    else
        mv "$tmp/unpacked" "$out"
    fi
    rm -rf "$tmp"
}

get-z3() {
    out=$1
    platform=$2
    version=$3
    case $platform in
      Linux | ubuntu | ubuntu-xenial) file="ubuntu-16.04.zip" ;;
      macOS | macos-10.14 | macos-mojave) file="osx-10.14.6.zip" ;;
      Windows) file="win.zip" ;;
      *) echo "unrecognized platform $platform" >&2 && return 1 ;;
    esac
    fetch-zip "$out" "https://github.com/Z3Prover/z3/releases/download/z3-$version/z3-$version-x64-$file"
}

get-cvc4() {
    out=$1
    platform=$2
    version=$3
    EXT=""
    case $platform in
      Linux) file="x86_64-linux-opt" ;;
      macOS) file="macos-opt" ;;
      Windows) file="win64-opt.exe" && EXT=".exe" ;;
      *) echo "unrecognized platform $platform" >&2 && return 1 ;;
    esac
    mkdir -p "$out/bin"
    curl -o "$out/bin/cvc4$EXT" -L "https://github.com/CVC4/CVC4/releases/download/$version/cvc4-$version-$file" >&2
    [ -n "$EXT" ] || chmod +x "$out/bin/cvc4"
}

get-yices() {
    out=$1
    platform=$2
    version=$3
    case $platform in
      Linux) file="pc-linux-gnu-static-gmp.tar.gz" ;;
      macOS) file="apple-darwin18.7.0-static-gmp.tar.gz" ;;
      Windows) file="pc-mingw32-static-gmp.zip" ;;
      *) echo "unrecognized platform $platform" >&2 && return 1 ;;
    esac
    if [[ "$platform" == Windows ]]; then
        fetch-zip "$out" "https://yices.csl.sri.com/releases/$version/yices-$version-x86_64-$file"
    else
        fetch-tarball "$out" "https://yices.csl.sri.com/releases/$version/yices-$version-x86_64-$file"
    fi
}

setup-solvers() {
    # Input
    Z3_VERSION=${Z3_VERSION:-""}
    CVC4_VERSION=${CVC4_VERSION:-""}
    YICES_VERSION=${YICES_VERSION:-""}
    SOLVERS_DIR=${SOLVERS_DIR:-$(mktemp -d)}

    if [ -n "$Z3_VERSION" ]; then
        Z3_ROOT="$SOLVERS_DIR/z3"
        [ -d "$Z3_ROOT" ] || get-z3 "$Z3_ROOT" "$RUNNER_OS" "$Z3_VERSION" &
    fi
    if [ -n "$CVC4_VERSION" ]; then
        CVC4_ROOT="$SOLVERS_DIR/cvc4"
        [ -d "$CVC4_ROOT" ] || get-cvc4 "$CVC4_ROOT" "$RUNNER_OS" "$CVC4_VERSION" &
    fi
    if [ -n "$YICES_VERSION" ]; then
        YICES_ROOT="$SOLVERS_DIR/yices"
        [ -d "$YICES_ROOT" ] || get-yices "$YICES_ROOT" "$RUNNER_OS" "$YICES_VERSION" &
    fi
    wait

    # Check that all requested solvers are usable or fail
    [ -z "$Z3_VERSION" ] || "$Z3_ROOT/bin/z3" --version >/dev/null 2>&1 || return 1
    [ -z "$CVC4_VERSION" ] || "$CVC4_ROOT/bin/cvc4" --version >/dev/null 2>&1 || return 1
    [ -z "$YICES_VERSION" ] || "$YICES_ROOT/bin/yices" --version >/dev/null 2>&1 || return 1

    # Output
    [ -n "$Z3_VERSION" ] && export Z3_ROOT
    [ -n "$CVC4_VERSION" ] && export CVC4_ROOT
    [ -n "$YICES_VERSION" ] && export YICES_ROOT
}

github-setup-solvers() {
    setup-solvers || return 1
    if [ -n "$Z3_ROOT" ]; then
        github-add-path "$Z3_ROOT/bin"
        github-set-env Z3_ROOT "$Z3_ROOT"
    fi
    if [ -n "$CVC4_ROOT" ]; then
        github-add-path "$CVC4_ROOT/bin"
        github-set-env CVC4_ROOT "$CVC4_ROOT"
    fi
    if [ -n "$YICES_ROOT" ]; then
        github-add-path "$YICES_ROOT/bin"
        github-set-env YICES_ROOT "$YICES_ROOT"
    fi
}

if [ "$#" -gt 0 ]; then
    COMMAND="$1"
    shift
    "$COMMAND" "$@"
fi
