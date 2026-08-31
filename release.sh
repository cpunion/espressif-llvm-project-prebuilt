#!/bin/bash
# Espressif LLVM Cross-Platform Release Builder
# Usage: ./release.sh <platform>
# Based on the working Makefile and build script

set -e

# Configuration
TAG="${TAG:-19.1.2_20250312}"
VERSION_STRING="$TAG"
LLVM_PROJECTDIR="${LLVM_PROJECTDIR:-llvm-project}"
BUILD_DIR_BASE="${BUILD_DIR_BASE:-build}"
# Pin the tested Espressif LLVM 19 source revision. The release branch remains
# useful documentation, but it is mutable and therefore cannot define a
# reproducible compiler payload on its own.
LLVM_REVISION="${LLVM_REVISION:-510a078c1ad4aee4460818bcb38ff0ba3fbf6a83}"

# Extract version from TAG to determine branch name
LLVM_VERSION_FROM_TAG="${TAG%%_*}"
LLVM_MAJOR="${LLVM_VERSION_FROM_TAG%%.*}"
LLVM_BRANCH="xtensa_release_${LLVM_VERSION_FROM_TAG}"

# Detect host system
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$WINDIR" ]]; then
    HOST_OS="Windows_NT"
    EXE=".exe"
else
    HOST_OS="$(uname -s)"
    EXE=""
fi

# Set macOS SDK root if on macOS
if [[ "$HOST_OS" == "Darwin" ]]; then
    if [[ -z "$SDKROOT" ]]; then
        export SDKROOT="$(xcrun --show-sdk-path)"
        echo "Setting SDKROOT to: $SDKROOT"
    fi
fi

# Supported build targets (native builds only)
VALID_TARGETS="aarch64-apple-darwin aarch64-linux-gnu aarch64-w64-mingw32 i686-w64-mingw32 x86_64-apple-darwin x86_64-linux-gnu x86_64-w64-mingw32"

# Function to show usage
show_usage() {
    echo "Espressif LLVM Cross-Platform Release Builder"
    echo ""
    echo "Usage: $0 <platform>"
    echo ""
    echo "Supported platforms:"
    for target in $VALID_TARGETS; do
        echo "  - $target"
    done
    echo ""
    echo "Environment variables:"
    echo "  TAG              - Version tag (default: $TAG)"
    echo "  LLVM_PROJECTDIR  - LLVM source directory (default: $LLVM_PROJECTDIR)"
    echo "  BUILD_DIR_BASE   - Build directory base (default: $BUILD_DIR_BASE)"
    echo ""
}

# Function to download LLVM source
download_llvm_source() {
    if [[ ! -d "$LLVM_PROJECTDIR" ]]; then
        echo "Fetching LLVM project revision $LLVM_REVISION from $LLVM_BRANCH..."
        git init "$LLVM_PROJECTDIR"
        git -C "$LLVM_PROJECTDIR" remote add origin https://github.com/espressif/llvm-project
        git -C "$LLVM_PROJECTDIR" fetch --depth=1 origin "$LLVM_REVISION"
        git -C "$LLVM_PROJECTDIR" checkout --detach FETCH_HEAD
    else
        echo "LLVM project directory already exists."
    fi
}

# Base CMake arguments - common to all platforms
get_base_cmake_args() {
    cat << 'EOF'
-G Ninja
-DCMAKE_BUILD_TYPE=Release
-DLLVM_INCLUDE_TESTS=OFF
-DLLVM_ENABLE_TERMINFO=OFF
-DLLVM_ENABLE_ZSTD=OFF
-DLLVM_ENABLE_Z3_SOLVER=OFF
-DLLVM_ENABLE_OCAMLDOC=OFF
-DLLVM_ENABLE_LIBXML2=OFF
-DLLVM_TOOL_CLANG_TOOLS_EXTRA_BUILD=OFF
-DCLANG_ENABLE_ARCMT=OFF
-DLLVM_TARGETS_TO_BUILD=X86;ARM;AArch64;AVR;Mips;RISCV;WebAssembly
-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
-DLLVM_ENABLE_PROJECTS=clang;lld
-DLLVM_ENABLE_RUNTIMES=compiler-rt;libcxx;libcxxabi;libunwind
-DLLVM_POLLY_LINK_INTO_TOOLS=ON
-DLLVM_BUILD_EXTERNAL_COMPILER_RT=ON
-DLLVM_ENABLE_EH=ON
-DLLVM_ENABLE_RTTI=ON
-DLLVM_INCLUDE_DOCS=OFF
-DLLVM_INCLUDE_EXAMPLES=OFF
-DLLVM_INCLUDE_TESTS=OFF
-DLLVM_INCLUDE_BENCHMARKS=OFF
-DLLVM_BUILD_DOCS=OFF
-DLLVM_ENABLE_DOXYGEN=OFF
-DLLVM_INSTALL_UTILS=OFF
-DLLVM_ENABLE_Z3_SOLVER=OFF
-DLLVM_ENABLE_LIBEDIT=OFF
-DLLVM_OPTIMIZED_TABLEGEN=ON
-DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON
-DLLVM_SOURCE_PREFIX=.
-DLIBCXX_INSTALL_MODULES=ON
-DCLANG_FORCE_MATCHING_LIBCLANG_SOVERSION=OFF
-DCOMPILER_RT_BUILD_SANITIZERS=OFF
-DCOMPILER_RT_BUILD_XRAY=OFF
-DCOMPILER_RT_BUILD_LIBFUZZER=OFF
-DCOMPILER_RT_BUILD_PROFILE=OFF
-DCOMPILER_RT_BUILD_MEMPROF=OFF
-DCOMPILER_RT_BUILD_ORC=OFF
-DCOMPILER_RT_BUILD_GWP_ASAN=OFF
-DCOMPILER_RT_BUILD_CTX_PROFILE=OFF
-DCMAKE_POSITION_INDEPENDENT_CODE=ON
-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON
-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON
-DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=OFF
-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON
-DLIBCXX_USE_COMPILER_RT=ON
-DLIBCXX_HAS_ATOMIC_LIB=OFF
-DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=OFF
-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON
-DLIBCXXABI_USE_COMPILER_RT=ON
-DLIBCXXABI_USE_LLVM_UNWINDER=ON
-DLIBUNWIND_USE_COMPILER_RT=ON
-DSANITIZER_CXX_ABI=libc++
-DSANITIZER_TEST_CXX=libc++
-DLLVM_LINK_LLVM_DYLIB=ON
-DCLANG_LINK_CLANG_DYLIB=ON
-DCMAKE_STRIP=/usr/bin/strip
EOF
}

# macOS-specific CMake arguments
get_macos_cmake_args() {
    local target="$1"
    local arch

    if [[ "$target" == "aarch64-apple-darwin" ]]; then
        arch="arm64"
    else
        arch="x86_64"
    fi

    cat << EOF
-DLLVM_BUILD_LLVM_C_DYLIB=ON
-DLLVM_ENABLE_LIBCXX=ON
-DLIBCXX_PSTL_BACKEND=libdispatch
-DCMAKE_OSX_SYSROOT=$SDKROOT
-DCMAKE_OSX_ARCHITECTURES=$arch
-DLIBCXXABI_USE_SYSTEM_LIBS=ON
EOF
}

# Linux-specific CMake arguments
get_linux_cmake_args() {
    cat << 'EOF'
-DLLVM_ENABLE_LIBXML2=OFF
-DLLVM_ENABLE_LIBCXX=OFF
-DCLANG_DEFAULT_CXX_STDLIB=libstdc++
-DLLVM_BUILD_LLVM_DYLIB=ON
-DCOMPILER_RT_USE_LLVM_UNWINDER=ON
EOF
}

# Windows payloads are built with an architecture-native llvm-mingw bootstrap.
# This keeps the resulting clang, LLVM library, and helper tools native to the
# archive architecture while still using the UCRT and the normal Windows API;
# no MSYS or Cygwin ABI is introduced.
get_windows_cmake_args() {
    local bootstrap_root="${LLVM_MINGW_ROOT//\\//}"
    cat << EOF
-DCMAKE_C_COMPILER=$bootstrap_root/bin/clang.exe
-DCMAKE_CXX_COMPILER=$bootstrap_root/bin/clang++.exe
-DCMAKE_AR=$bootstrap_root/bin/llvm-ar.exe
-DCMAKE_RANLIB=$bootstrap_root/bin/llvm-ranlib.exe
-DCMAKE_RC_COMPILER=$bootstrap_root/bin/llvm-rc.exe
-DCMAKE_STRIP=$bootstrap_root/bin/llvm-strip.exe
-DLLVM_BUILD_LLVM_DYLIB=ON
-DLLVM_BUILD_LLVM_C_DYLIB=OFF
-DLLVM_ENABLE_LIBCXX=ON
-DLLVM_ENABLE_PIC=OFF
-DLLVM_ENABLE_RUNTIMES=
-DLLVM_BUILD_EXTERNAL_COMPILER_RT=OFF
-DLLVM_USE_LINKER=lld
-DCLANG_DEFAULT_CXX_STDLIB=libc++
EOF
}

# Function to get platform-specific CMake arguments
get_platform_cmake_args() {
    local target="$1"

    case "$target" in
        *-apple-darwin)
            get_macos_cmake_args "$target"
            ;;
        *-linux-gnu*)
            get_linux_cmake_args
            ;;
        *-w64-mingw32)
            get_windows_cmake_args
            ;;
        *)
            echo "Unknown target platform: $target" >&2
            return 1
            ;;
    esac
}

# Function to set up build environment (native builds only)
setup_build_env() {
    local target="$1"

    # All builds are native, no cross-compilation setup needed
    echo "Setting up native build environment for $target"
}

# Function to get number of CPU cores
get_cpu_cores() {
    if [[ "$HOST_OS" == "Darwin" ]]; then
        sysctl -n hw.ncpu
    elif [[ "$HOST_OS" == "Linux" ]]; then
        nproc
    elif [[ "$HOST_OS" == "Windows_NT" ]]; then
        echo "${NUMBER_OF_PROCESSORS:-4}"
    else
        echo "4"
    fi
}

# Function to create release directory structure
create_release_structure() {
    local target="$1"
    local install_dir="$2"
    local release_dir="dist/${target}/esp-clang"

    echo "Creating release structure in $release_dir..."

    # Create release directory
    rm -rf "dist/${target}"
    mkdir -p "$release_dir"

    # Copy installation files
    if [[ -d "$install_dir" ]]; then
        cp -r "$install_dir"/* "$release_dir"/
    else
        echo "Warning: Install directory $install_dir not found"
        return 1
    fi

    if [[ "$HOST_OS" == "Windows_NT" ]]; then
        if [[ -z "${LLVM_MINGW_ROOT:-}" ]]; then
            echo "Error: LLVM_MINGW_ROOT is required for a Windows package" >&2
            return 1
        fi
        # LLVM and clang are linked against llvm-mingw's libc++ runtime. Copy
        # only their native UCRT dependencies; libwinpthread is deliberately
        # neither needed nor shipped.
        for dll in libc++.dll libunwind.dll; do
            if [[ ! -f "$LLVM_MINGW_ROOT/bin/$dll" ]]; then
                echo "Error: Windows bootstrap runtime is missing $dll" >&2
                return 1
            fi
            cp "$LLVM_MINGW_ROOT/bin/$dll" "$release_dir/bin/$dll"
        done
        validate_release "$target" "$release_dir"
    fi

    echo "Release directory created: $release_dir"
    echo "Contents:"
    ls -la "$release_dir"

    # Create tarball
    echo "Creating tarball package..."
    mkdir -p dist
    cd "dist/${target}"
    tar -cJf "../clang-esp-${VERSION_STRING}-${target}.tar.xz" esp-clang/
    cd - > /dev/null

    echo "Tarball created: dist/clang-esp-${VERSION_STRING}-${target}.tar.xz"
    echo "Package size: $(du -h "dist/clang-esp-${VERSION_STRING}-${target}.tar.xz" | cut -f1)"
}

resolve_release_tool() {
    local release_dir="$1"
    local tool="$2"
    if [[ -x "$release_dir/bin/$tool" ]]; then
        printf '%s\n' "$release_dir/bin/$tool"
        return
    fi
    if [[ -x "$release_dir/bin/$tool.exe" ]]; then
        printf '%s\n' "$release_dir/bin/$tool.exe"
        return
    fi
    return 1
}

validate_release() {
    local target="$1"
    local release_dir="$2"
    local tool path actual_version targets target_name

    for tool in clang clang++ ld.lld lld llvm-ar llvm-config llvm-nm llvm-readobj; do
        if ! resolve_release_tool "$release_dir" "$tool" >/dev/null; then
            echo "Error: required tool $tool is missing from $release_dir/bin" >&2
            return 1
        fi
    done

    actual_version="$("$(resolve_release_tool "$release_dir" llvm-config)" --version)"
    if [[ "$actual_version" != "$LLVM_VERSION_FROM_TAG"* ]]; then
        echo "Error: llvm-config reports $actual_version, expected $LLVM_VERSION_FROM_TAG.x" >&2
        return 1
    fi
    targets="$("$(resolve_release_tool "$release_dir" llvm-config)" --targets-built)"
    for target_name in X86 ARM AArch64 AVR Mips RISCV WebAssembly Xtensa; do
        if [[ " $targets " != *" $target_name "* ]]; then
            echo "Error: required LLVM target $target_name is missing: $targets" >&2
            return 1
        fi
    done
    if [[ ! -f "$release_dir/include/llvm-c/Core.h" ]]; then
        echo "Error: llvm-c/Core.h is missing" >&2
        return 1
    fi

    if [[ "$target" == *-w64-mingw32 ]]; then
        local readobj machine expected_machine input imports
        readobj="$(resolve_release_tool "$release_dir" llvm-readobj)"
        case "$target" in
            i686-*) expected_machine=IMAGE_FILE_MACHINE_I386 ;;
            x86_64-*) expected_machine=IMAGE_FILE_MACHINE_AMD64 ;;
            aarch64-*) expected_machine=IMAGE_FILE_MACHINE_ARM64 ;;
        esac
        machine="$("$readobj" --file-headers "$(resolve_release_tool "$release_dir" clang)" | grep -o "$expected_machine" | head -n 1)"
        if [[ "$machine" != "$expected_machine" ]]; then
            echo "Error: clang is not a native $target executable" >&2
            return 1
        fi
        for input in "$release_dir/bin/clang.exe" "$release_dir/bin/libLLVM-$LLVM_MAJOR.dll"; do
            if [[ ! -f "$input" ]]; then
                echo "Error: required Windows payload file is missing: $input" >&2
                return 1
            fi
            imports="$("$readobj" --coff-imports "$input")"
            if grep -Eiq '(^|[^[:alnum:]_])(msys-2\.0|cygwin1|libwinpthread[^[:space:]]*)\.dll([^[:alnum:]_]|$)' <<<"$imports"; then
                echo "Error: $input has an unsupported POSIX-runtime dependency" >&2
                return 1
            fi
        done
    fi

    echo "Validated LLVM $actual_version payload with targets: $targets"
}

# Main build function (native builds only)
build_platform() {
    local target="$1"

    echo "Building LLVM for platform: $target"
    echo "Version: $VERSION_STRING"
    echo "Host OS: $HOST_OS"
    echo "LLVM Branch: $LLVM_BRANCH"
    echo ""

    # Create build and install directories
    local build_dir="$BUILD_DIR_BASE/$target"
    local install_dir="$PWD/install/$target"

    mkdir -p "$build_dir"
    mkdir -p "$install_dir"

    # Set up build environment
    setup_build_env "$target"

    # Prepare CMake arguments
    local cmake_args_file=$(mktemp)
    {
        get_base_cmake_args
        get_platform_cmake_args "$target"
        echo "-DCMAKE_INSTALL_PREFIX=$install_dir"
    } > "$cmake_args_file"

    echo "CMake configuration:"
    cat "$cmake_args_file"
    echo ""

    # Configure
    echo "Configuring build for $target..."
    cd "$build_dir"
    cmake "../../$LLVM_PROJECTDIR/llvm" $(cat "$cmake_args_file" | tr '\n' ' ')

    # Build
    echo "Building $target..."
    local cores=$(get_cpu_cores)
    echo "Using $cores CPU cores for build"

    # Build only essential tools to significantly reduce build time
    # LLGo currently only requires libLLVM.dylib for dynamic libraries, and this dylib will be built with the following targets
    ninja -j"$cores" clang llvm-config llvm-ar llvm-nm lld

    # Install
    echo "Installing $target..."
    ninja install

    # Return to original directory
    cd - > /dev/null

    # Clean up temporary file
    rm -f "$cmake_args_file"

    # Create release directory structure
    create_release_structure "$target" "$install_dir"

    echo ""
    echo "Build completed successfully for $target!"
    echo "Release directory: dist/${target}/esp-clang"
    echo "Install directory: $install_dir"
    echo "Tarball: dist/clang-esp-${VERSION_STRING}-${target}.tar.xz"
}

# Main script logic
main() {
    if [[ $# -ne 1 ]]; then
        show_usage
        exit 1
    fi

    local target="$1"

    # Validate target
    local target_valid=0
    for valid_target in $VALID_TARGETS; do
        if [[ "$target" == "$valid_target" ]]; then
            target_valid=1
            break
        fi
    done

    if [[ $target_valid -eq 0 ]]; then
        echo "Error: Invalid target '$target'"
        echo ""
        show_usage
        exit 1
    fi

    # Check for required tools
    if ! command -v cmake >/dev/null 2>&1; then
        echo "Error: cmake is required but not installed"
        exit 1
    fi

    if ! command -v ninja >/dev/null 2>&1; then
        echo "Error: ninja is required but not installed"
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required but not installed"
        exit 1
    fi

    # Download LLVM source
    download_llvm_source

    # Build the platform
    build_platform "$target"
}

# Run main function
main "$@"
