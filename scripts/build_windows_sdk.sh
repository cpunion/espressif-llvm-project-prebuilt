#!/usr/bin/env bash
# Build a real Windows/386 LLVM development SDK with the pinned MinGW compiler.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/toolchain.env"
target=i686-w64-mingw32
source_dir="${LLVM_SDK_SOURCE_DIR:-$root/llvm-sdk-source}"
build_root="${LLVM_SDK_BUILD_DIR:-$root/build-sdk}"
jobs="${LLVM_SDK_JOBS:-$(getconf _NPROCESSORS_ONLN)}"
if ! command -v "$target-clang++" >/dev/null; then
    echo 'The pinned llvm-mingw bootstrap is required' >&2
    exit 1
fi
if [[ ! -d "$source_dir/.git" ]]; then
    git init "$source_dir"
    git -C "$source_dir" remote add origin https://github.com/llvm/llvm-project.git
    git -C "$source_dir" fetch --depth=1 origin "$LLVM_WINDOWS_SDK_REF"
    git -C "$source_dir" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$LLVM_WINDOWS_SDK_REF" ]]
[[ -z "$(git -C "$source_dir" status --porcelain)" ]]
common=(
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF
    -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_Z3_SOLVER=OFF
)
cmake -S "$source_dir/llvm" -B "$build_root/native" "${common[@]}" \
    -DLLVM_TARGETS_TO_BUILD=X86
cmake --build "$build_root/native" --target llvm-tblgen llvm-min-tblgen -j"$jobs"
bootstrap="$(dirname "$(command -v "$target-clang")")/.."
cmake -S "$source_dir/llvm" -B "$build_root/$target" "${common[@]}" \
    -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=i686 \
    -DCMAKE_C_COMPILER="$target-clang" -DCMAKE_CXX_COMPILER="$target-clang++" \
    -DCMAKE_RC_COMPILER="$target-windres" \
    -DCMAKE_FIND_ROOT_PATH="$bootstrap/$target" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DLLVM_HOST_TRIPLE="$target" -DLLVM_DEFAULT_TARGET_TRIPLE="$target" \
    -DLLVM_NATIVE_TOOL_DIR="$build_root/native/bin" \
    '-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64;AVR;Mips;RISCV;WebAssembly' \
    -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_EH=ON \
    -DLLVM_BUILD_LLVM_DYLIB=OFF -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DCMAKE_INSTALL_PREFIX="$build_root/install/llvm-sdk"
# Static LLVM libraries avoid PE's export ordinal limit for the C++ API used by
# the Go binding. They are linked into the actual 32-bit compiler, not shipped
# as a 64-bit SDK relabelled with a different target triple.
cmake --build "$build_root/$target" --target install-llvm-headers \
    install-llvm-libraries install-llvm-config install-cmake-exports -j"$jobs"
sdk="$build_root/install/llvm-sdk"
cp "$bootstrap/$target/bin/"*.dll "$sdk/bin/"
mkdir -p "$sdk/third-party-licenses"
cp "$source_dir/LICENSE.TXT" "$sdk/third-party-licenses/LLVM-LICENSE.txt"
# The bootstrap's redistribution notices cover the bundled UCRT/C++ runtimes.
cp "$bootstrap/LICENSE.TXT" "$sdk/third-party-licenses/LLVM-MinGW-LICENSE.txt"
cp "$bootstrap/$target/share/mingw32/"COPYING* "$sdk/third-party-licenses/"
cat > "$sdk/LLGO-LLVM-MANIFEST.txt" <<MANIFEST
host_target=$target
llvm_version=$LLVM_WINDOWS_SDK_VERSION
source_revision=$LLVM_WINDOWS_SDK_REF
windows_bootstrap=llvm-mingw-$LLVM_MINGW_VERSION
link_mode=static
MANIFEST
python3 "$root/scripts/validate_windows.py" "$sdk" "$target"
mkdir -p "$root/dist"
archive="$root/dist/llvm-sdk-$LLVM_WINDOWS_SDK_VERSION-$target.tar.xz"
tar -cJf "$archive" -C "$(dirname "$sdk")" llvm-sdk
(cd "$root/dist" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
