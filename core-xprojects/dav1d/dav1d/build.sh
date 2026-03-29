#!/bin/sh

set -e

SOURCE_DIR="$1"
BUILD_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_ARCHS="${ARCHS:-arm64 x86_64}"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ]; then
    echo "Usage: $0 SOURCE_DIR BUILD_DIR"
    echo "Example: $0 /path/to/dav1d/source /path/to/build/directory"
    exit 1
fi

MESON_OPTIONS="--buildtype=release --default-library=static -Denable_tools=false -Denable_tests=false"

cross_file_for_arch() {
    case "$1" in
        arm64)
            echo "$SCRIPT_DIR/../dav1d-arm64.meson"
            ;;
        x86_64)
            echo "$SCRIPT_DIR/../dav1d-x86_64.meson"
            ;;
        *)
            echo "Unsupported architecture: $1" >&2
            exit 1
            ;;
    esac
}

build_one_arch() {
    arch="$1"
    cross_file="$(cross_file_for_arch "$arch")"
    echo "Building for ${arch}..."
    rm -rf "$BUILD_DIR/$arch"
    mkdir -p "$BUILD_DIR/$arch"
    pushd "$BUILD_DIR/$arch"
    meson setup "$SOURCE_DIR" --cross-file="$cross_file" $MESON_OPTIONS
    ninja
    popd
}

# Ensure build directory exists
mkdir -p "$BUILD_DIR"

FIRST_ARCH=""
LIB_INPUTS=""
ARCH_COUNT=0
for arch in $TARGET_ARCHS; do
    build_one_arch "$arch"
    if [ -z "$FIRST_ARCH" ]; then
        FIRST_ARCH="$arch"
    fi
    LIB_INPUTS="$LIB_INPUTS $BUILD_DIR/$arch/src/libdav1d.a"
    ARCH_COUNT=$((ARCH_COUNT + 1))
done

# Create universal binary
echo "Creating universal binary..."
mkdir -p "$BUILD_DIR/dav1d/lib"
if [ "$ARCH_COUNT" -gt 1 ]; then
    lipo -create $LIB_INPUTS -output "$BUILD_DIR/dav1d/lib/libdav1d.a"
else
    cp "$BUILD_DIR/$FIRST_ARCH/src/libdav1d.a" "$BUILD_DIR/dav1d/lib/libdav1d.a"
fi

# Copy include files from the source directory
echo "Copying include files from source directory..."
mkdir -p "$BUILD_DIR/dav1d/include"
cp -R "$SOURCE_DIR/include/dav1d" "$BUILD_DIR/dav1d/include/"

echo "Universal library created at $BUILD_DIR/dav1d/lib/libdav1d.a"
echo "Headers copied to $BUILD_DIR/dav1d/include/"
