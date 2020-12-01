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
    if [[ $(ls -A1 "$tmp/unpacked" | wc -l | awk '{print $1}') == 1 ]]; then
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

github-setup-yasm-pkgmgr-latest() {
    case "$RUNNER_OS" in
      Linux) sudo apt-get update -q && sudo apt-get install -y yasm ;;
      macOS) brew install yasm ;;
      Windows) choco install yasm ;;
    esac
}

github-setup-solvers() {
    Z3_VERSION=${Z3_VERSION:-""}
    CVC4_VERSION=${CVC4_VERSION:-""}
    YICES_VERSION=${YICES_VERSION:-""}
    YASM_VERSION=${YASM_VERSION:-""}
    if [ -n "$YASM_VERSION" ] && [[ "$YASM_VERSION" != pkgmgr-latest ]]; then
        echo "error: only YASM_VERSION=pkgmgr-latest is supported for setting up YASM" >&2
        return 1
    fi
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
    if [ -n "$YASM_VERSION" ]; then
        github-setup-yasm-pkgmgr-latest &
    fi
    wait
    [ -n "$Z3_VERSION" ] && github-add-path "$Z3_ROOT/bin"
    [ -n "$CVC4_VERSION" ] && github-add-path "$CVC4_ROOT/bin"
    [ -n "$YICES_VERSION" ] && github-add-path "$YICES_ROOT/bin"

    [ -z "$Z3_VERSION" ] || z3 --version >/dev/null 2>&1 || return 1
    [ -z "$CVC4_VERSION" ] || cvc4 --version >/dev/null 2>&1 || return 1
    [ -z "$YICES_VERSION" ] || yices --version >/dev/null 2>&1 || return 1
    [ -z "$YASM_VERSION" ] || yasm --version >/dev/null 2>&1 || return 1
}

if [ "$#" -gt 0 ]; then
    COMMAND="$1"
    shift
    "$COMMAND" "$@"
fi
