#! /usr/bin/env bash

gha-add-path() {
    echo "$1" >> "$GITHUB_PATH"
}

gha-set-env() {
    echo "$1=$2" >> "$GITHUB_ENV"
}

fetch-zip() { (
    set -Eeuo pipefail
    out=$1
    url=$2
    tmp=$(mktemp -d)
    curl -o "$tmp/file.zip" -L "$url"
    unzip "$tmp/file.zip" -d "$tmp/unpacked"
    if [[ $(ls -A1 "$tmp/unpacked" | wc -l) == 1 ]]; then
        mv "$tmp/unpacked/$(ls -A1 $tmp/unpacked)" $out
    else
        mv "$tmp/unpacked" "$out"
    fi
    rm -rf "$tmp"
) >&2 ; }

fetch-tarball() { (
    set -Eeuo pipefail
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
) >&2 ; }

get-z3() { (
    set -Eeuo pipefail
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
) }

get-cvc4() { (
    set -Eeuo pipefail
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
) }

get-yices() { (
    set -Eeuo pipefail
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
)}

add-path-github() {
    echo "$1" >> "$GITHUB_PATH"
    export PATH="$PATH:$1"
}

setup-solvers-github() {
    Z3_VERSION=${Z3_VERSION:-""}
    CVC4_VERSION=${CVC4_VERSION:-""}
    YICES_VERSION=${YICES_VERSION:-""}
    solvers=$(mktemp -d)
    if [ -n "$Z3_VERSION" ]; then
        Z3_ROOT="$solvers/z3"
        export Z3_ROOT
        add-path-github "$Z3_ROOT/bin"
        get-z3 "$Z3_ROOT" "$RUNNER_OS" "$Z3_VERSION"
    fi
    if [ -n "$CVC4_VERSION" ]; then
        CVC4_ROOT="$solvers/cvc4"
        export CVC4_ROOT
        add-path-github "$CVC4_ROOT/bin"
        get-cvc4 "$CVC4_ROOT" "$RUNNER_OS" "$CVC4_VERSION"
    fi
    if [ -n "$YICES_VERSION" ]; then
        YICES_ROOT="$solvers/yices"
        export YICES_ROOT
        add-path-github "$YICES_ROOT/bin"
        get-yices "$YICES_ROOT" "$RUNNER_OS" "$YICES_VERSION"
    fi
    wait
}

if test "$#" -gt 0; then
    COMMAND="$1"
    shift
    "$COMMAND" "$@"
fi
