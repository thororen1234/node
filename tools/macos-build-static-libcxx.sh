#!/bin/sh
# Builds a static, hermetic LLVM libc++/libc++abi for an old macOS deployment
# target, for use with `./configure --macos-static-libcxx=<prefix>`.
#
# The system libc++ before macOS 10.15 lacks std::filesystem (and other C++17/20
# library symbols) that Node.js uses, so binaries targeting macOS 10.13/10.14
# must carry their own libc++. The hermetic build gives it hidden visibility so
# it does not clash with the system libc++ loaded by Apple frameworks.
#
# Usage: tools/macos-build-static-libcxx.sh <install-prefix> [min-version] [arch]
#   e.g. tools/macos-build-static-libcxx.sh "$HOME/libcxx-10.13" 10.13 x86_64
#
# Requires: git, cmake, ninja, and Xcode 15 or newer.

set -eu

PREFIX=${1:?usage: $0 <install-prefix> [min-version] [arch]}
MIN_VERSION=${2:-10.13}
ARCH=${3:-x86_64}
LLVM_VERSION=${LLVM_VERSION:-19.1.7}
WORK=${WORK:-"${TMPDIR:-/tmp}/libcxx-build-$LLVM_VERSION-$ARCH"}

mkdir -p "$WORK"
if [ ! -d "$WORK/llvm-project" ]; then
  git clone --depth 1 --branch "llvmorg-$LLVM_VERSION" \
    --filter=blob:none --sparse \
    https://github.com/llvm/llvm-project.git "$WORK/llvm-project"
  git -C "$WORK/llvm-project" sparse-checkout set \
    cmake libc libcxx libcxxabi libunwind llvm/cmake llvm/utils runtimes
fi

cmake -G Ninja -S "$WORK/llvm-project/runtimes" -B "$WORK/build" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_VERSION" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_STATIC=ON \
  -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXX_CXX_ABI=libcxxabi \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBCXXABI_ENABLE_STATIC=ON \
  -DLIBCXXABI_HERMETIC_STATIC_LIBRARY=ON \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXXABI_USE_LLVM_UNWINDER=OFF

ninja -C "$WORK/build" install-cxx install-cxxabi

echo "libc++ installed to $PREFIX"
echo "Configure Node.js with:"
echo "  ./configure --macos-min-version=$MIN_VERSION --macos-static-libcxx=$PREFIX"
