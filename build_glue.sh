#!/bin/bash
# Build nstoolbar_glue.dylib and install it into the LCB extension folder.
# Run from the directory containing LCNSToolbarDelegate.m
# Usage: ./build_glue.sh /path/to/community.livecode.nstoolbar

set -e

EXTENSION_DIR="${1:-.}"

echo "Building arm64..."
clang -x objective-c -dynamiclib -framework Cocoa \
  -arch arm64 \
  -fobjc-arc \
  -undefined dynamic_lookup \
  -o nstoolbar_glue_arm64.dylib LCNSToolbarDelegate.m

echo "Building x86_64..."
clang -x objective-c -dynamiclib -framework Cocoa \
  -arch x86_64 \
  -fobjc-arc \
  -undefined dynamic_lookup \
  -o nstoolbar_glue_x86_64.dylib LCNSToolbarDelegate.m

echo "Creating universal binary..."
lipo -create nstoolbar_glue_arm64.dylib nstoolbar_glue_x86_64.dylib \
  -output nstoolbar_glue.dylib

echo "Installing..."
mkdir -p "$EXTENSION_DIR/code/x86_64-mac"
mkdir -p "$EXTENSION_DIR/code/arm64-mac"
cp nstoolbar_glue.dylib "$EXTENSION_DIR/code/x86_64-mac/nstoolbar_glue.dylib"
cp nstoolbar_glue.dylib "$EXTENSION_DIR/code/arm64-mac/nstoolbar_glue.dylib"

rm nstoolbar_glue_arm64.dylib nstoolbar_glue_x86_64.dylib

echo "Done! Dylib installed to:"
echo "  $EXTENSION_DIR/code/x86_64-mac/nstoolbar_glue.dylib"
echo "  $EXTENSION_DIR/code/arm64-mac/nstoolbar_glue.dylib"
