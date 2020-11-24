#! /usr/bin/env bash

gha-add-path() {
    echo $1 >> $GITHUB_PATH
}

gha-set-env() {
    echo "$1=$2" >> $GITHUB_ENV
}

hash-stdio() {
    if which shasum >/dev/null; then
        h=shasum
    else
        h=md5sum
    fi
    echo "using $h" >&2
    $h | awk '{print $1}'
}

hash-str() {
    echo "$1" | hash-stdio
}

# clean-uncached() {
#     rm -rfv $STORE/uncached.*
# }

# STORE=${STORE:-~/.bash-helpers-store}
# setout() {
#     mkdir -p $STORE
#     CACHE_KEY=${CACHE_KEY:-""}
#     out=""
#     if [ -z "$CACHE_KEY" ]; then
#         until (set -o noclobber; [ ! -z "$out" ] && >$out.lock) &>/dev/null; do
#             export out=$(mktemp --tmpdir=$STORE uncached.XXXXXXXXXX)
#             rm $out
#             return 1
#         done
#     elif [ -e $STORE/$CACHE_KEY.lock ]; then
#         echo "waiting for $STORE/$CACHE_KEY" >&2
#         while [ -e $STORE/$CACHE_KEY.lock ]; do sleep 0.1; done
#         export out=$STORE/$CACHE_KEY
#         return 0
#     elif [ -e $STORE/$CACHE_KEY ] && [ ! -e $STORE/$CACHE_KEY.lock ]; then
#         echo "using cached $STORE/$CACHE_KEY" >&2
#         export out=$STORE/$CACHE_KEY
#         return 0
#     elif (set -o noclobber; >$STORE/$CACHE_KEY.lock) &>/dev/null; then
#         export out=$STORE/$CACHE_KEY
#         return 1
#     else
#         export out=$STORE/$CACHE_KEY
#         return 0
#     fi
# }

STORE=${STORE:-~/.bash-helpers-store}
USE_CACHE=true
setout() {
    name=$1
    CACHE_KEY=${2:-""}
    mkdir -p $STORE
    out=""
    if [ -z "$CACHE_KEY" ] || ! $USE_CACHE; then
        until (set -o noclobber; [ ! -z "$out" ] && >$out.lock) &>/dev/null; do
            export out=$(mktemp --tmpdir=$STORE uncached.XXXXXXXXXX)-$name
            rm $out
            echo "building $out" >&2
            return 1
        done
    else
        export out=$STORE/$(hash-str "$CACHE_KEY $name")-$name
        if [ -e $out ]; then
            echo "using cached $out ($CACHE_KEY)" >&2
            return 0
        else
            echo "building $out ($CACHE_KEY)" >&2
            return 1
        fi
    fi
}

fetch-url() { (
    set -Eeuo pipefail
    name=$1
    url=$2
    setout $name "${FUNCNAME[0]} $url" && echo $out && return 0 || :
    curl -o $out -L $url >&2
    echo $out
) }

fetch-zip() { (
    set -Eeuo pipefail
    name=$1
    url=$2
    setout $name "${FUNCNAME[0]} $url" && echo $out && return 0 || :
    tmp=$(mktemp -d)
    curl -o $tmp/file.zip -L $url >&2
    unzip $tmp/file.zip -d $tmp/unpacked >&2
    if [[ $(ls -A1 $tmp/unpacked | wc -l) == 1 ]]; then
        mv $tmp/unpacked/$(ls -A1 $tmp/unpacked) $out
    else
        mv $tmp/unpacked $out
    fi
    rm -rf $tmp
    echo $out
) }

fetch-tarball() { (
    set -Eeuo pipefail
    name=$1
    url=$2
    setout $name "${FUNCNAME[0]} $url" && echo $out && return 0 || :
    tmp=$(mktemp -d)
    curl -o $tmp/file -L $url >&2
    mkdir $tmp/unpacked
    tar xfz $tmp/file -C $tmp/unpacked
    if [[ $(ls -A1 $tmp/unpacked | wc -l) == 1 ]]; then
        mv $tmp/unpacked/$(ls -A1 $tmp/unpacked) $out
    else
        mv $tmp/unpacked $out
    fi
    rm -rf $tmp
    echo $out
) }

get-z3() { (
    set -Eeuo pipefail
    platform=$1
    version=$2
    case $platform in
      Linux | ubuntu | ubuntu-xenial) file="ubuntu-16.04.zip" ;;
      macOS | macos-10.14 | macos-mojave) file="osx-10.14.6.zip" ;;
      Windows) file="win.zip" ;;
      *) echo "unrecognized platform $platform" >&2 && return 1 ;;
    esac
    fetch-zip z3 https://github.com/Z3Prover/z3/releases/download/z3-$version/z3-$version-x64-$file
) }

get-cvc4() { (
    set -Eeuo pipefail
    platform=$1
    version=$2
    setout cvc4 "${FUNCNAME[0]} $platform $version" && echo $out && return 0 || :
    EXT=""
    case $platform in
      Linux) file="x86_64-linux-opt" ;;
      macOS) file="macos-opt" ;;
      Windows) file="win64-opt.exe" && EXT=".exe" ;;
      *) echo "unrecognized platform $platform" >&2 && return 1 ;;
    esac
    mkdir -p $out/bin
    mv $(fetch-url $file "https://github.com/CVC4/CVC4/releases/download/$version/cvc4-$version-$file") $out/bin/cvc4$EXT
    [ -z "$EXT" ] && chmod +x $out/bin/cvc4
    echo $out
) }

get-yices() { (
    set -Eeuo pipefail
    platform=$1
    version=$2
    ext=".tar.gz"
    case $platform in
      Linux) file="pc-linux-gnu-static-gmp.tar.gz" ;;
      macOS) file="apple-darwin18.7.0-static-gmp.tar.gz" ;;
      Windows) file="pc-mingw32-static-gmp.zip" && ext=".zip" ;;
      *) echo "unrecognized platform $platform" >&2 && return 1 ;;
    esac
    if [[ $ext == ".tar.gz" ]]; then
        fetch-tarball yices "https://yices.csl.sri.com/releases/$version/yices-$version-x86_64-$file"
    else
        fetch-zip yices "https://yices.csl.sri.com/releases/$version/yices-$version-x86_64-$file"
    fi
)}

add-path-github() {
    echo "$1" >> $GITHUB_PATH
    export PATH="$PATH:$1"
}

setup-solvers-github() {
    Z3_VERSION=${Z3_VERSION:-""}
    CVC4_VERSION=${CVC4_VERSION:-""}
    YICES_VERSION=${YICES_VERSION:-""}
    [ -z "$Z3_VERSION" ] || get-z3 $RUNNER_OS $Z3_VERSION >/dev/null &
    [ -z "$CVC4_VERSION" ] || get-cvc4 $RUNNER_OS $CVC4_VERSION >/dev/null &
    [ -z "$YICES_VERSION" ] || get-yices $RUNNER_OS $YICES_VERSION >/dev/null &
    wait
    [ -z "$Z3_VERSION" ] || add-path-github $(get-z3 $RUNNER_OS $Z3_VERSION)/bin
    [ -z "$CVC4_VERSION" ] || add-path-github $(get-cvc4 $RUNNER_OS $CVC4_VERSION)/bin
    [ -z "$YICES_VERSION" ] || add-path-github $(get-yices $RUNNER_OS $YICES_VERSION)/bin
}

if test "$#" -gt 0; then
    COMMAND="$1"
    shift
    "$COMMAND" "$@"
fi
