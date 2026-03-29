#!/bin/sh

set -e
set -x

SOURCE_DIR="$1"
BUILD_DIR="$2"
OPENSSL_DIR="$3"
TARGET_ARCHS="${ARCHS:-arm64 x86_64}"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ] || [ -z "$OPENSSL_DIR" ]; then
    echo "Usage: $0 SOURCE_DIR BUILD_DIR OPENSSL_DIR"
    echo "Example: $0 /path/to/td /path/to/build /path/to/openssl"
    exit 1
fi

openssl_crypto_library="${OPENSSL_DIR}/lib/libcrypto.a"
options=""
options="$options -DOPENSSL_FOUND=1"
#options="$options -DOPENSSL_CRYPTO_LIBRARY=${openssl_crypto_library}"
options="$options -DOPENSSL_INCLUDE_DIR=${OPENSSL_DIR}/include"
options="$options -DCMAKE_BUILD_TYPE=Release"

build_one_arch() {
    arch="$1"
    arch_dir="$BUILD_DIR/$arch"
    echo "Building for ${arch}..."
    rm -rf "$arch_dir"
    mkdir -p "$arch_dir"
    pushd "$arch_dir"
    cmake "$SOURCE_DIR" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        $options
    cmake --build . --target tde2e -j$(sysctl -n hw.ncpu)
    popd
}

# Step 1: Generate TDLib source files once
GEN_DIR="$BUILD_DIR/native-gen"
mkdir -p "$GEN_DIR"
pushd "$GEN_DIR"
cmake -DTD_GENERATE_SOURCE_FILES=ON "$SOURCE_DIR"
cmake --build . -- -j$(sysctl -n hw.ncpu)
popd

FIRST_ARCH=""
TDE2E_INPUTS=""
TDUTILS_INPUTS=""
ARCH_COUNT=0
for arch in $TARGET_ARCHS; do
    build_one_arch "$arch"
    if [ -z "$FIRST_ARCH" ]; then
        FIRST_ARCH="$arch"
    fi
    TDE2E_INPUTS="$TDE2E_INPUTS $BUILD_DIR/$arch/tde2e/libtde2e.a"
    TDUTILS_INPUTS="$TDUTILS_INPUTS $BUILD_DIR/$arch/tdutils/libtdutils.a"
    ARCH_COUNT=$((ARCH_COUNT + 1))
done

# Step 4: Create universal binary
echo "Creating universal binary..."
UNIVERSAL_DIR="$BUILD_DIR/tde2e"
mkdir -p "$UNIVERSAL_DIR/lib"

if [ "$ARCH_COUNT" -gt 1 ]; then
    lipo -create $TDE2E_INPUTS -output "$UNIVERSAL_DIR/lib/libtde2e.a"
else
    cp "$BUILD_DIR/$FIRST_ARCH/tde2e/libtde2e.a" "$UNIVERSAL_DIR/lib/libtde2e.a"
fi

echo "Universal binary created at $UNIVERSAL_DIR/lib/libtde2e.a"


if [ "$ARCH_COUNT" -gt 1 ]; then
    lipo -create $TDUTILS_INPUTS -output "$UNIVERSAL_DIR/lib/libtdutils.a"
else
    cp "$BUILD_DIR/$FIRST_ARCH/tdutils/libtdutils.a" "$UNIVERSAL_DIR/lib/libtdutils.a"
fi

echo "Universal binary created at $UNIVERSAL_DIR/lib/libtdutils.a"
