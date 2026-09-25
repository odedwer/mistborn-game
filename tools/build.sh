#!/bin/bash
# Build script for Mistborn: Ashes of Luthadel
# Builds the game for Linux and Windows x86_64
# Usage: ./tools/build.sh [--clean]

set -e

# Get the godot binary
GODOT=${GODOT:-godot}

# Parse arguments
CLEAN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --clean)
      CLEAN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Clean build directory if requested
if [ "$CLEAN" = true ]; then
  echo "Cleaning build directory..."
  rm -rf build/
fi

# Create build directories
mkdir -p build/dist
mkdir -p build/linux
mkdir -p build/windows

echo "Running tests..."
if [ -f tools/run_tests.sh ]; then
  bash tools/run_tests.sh
else
  echo "Warning: tests/run_tests.sh not found, skipping tests"
fi

echo "Importing project..."
$GODOT --headless --import 2>&1 | grep -v "^\[" || true

echo "Exporting for Linux x86_64..."
$GODOT --headless --export-release "Linux" build/linux/MistbornAshesOfLuthadel.x86_64

echo "Exporting for Windows x86_64..."
$GODOT --headless --export-release "Windows Desktop" build/windows/MistbornAshesOfLuthadel.exe

echo "Creating distribution packages..."

# Linux package
echo "Packaging Linux build..."
cd build/linux
tar czf ../dist/MistbornAshesOfLuthadel-linux-x86_64.tar.gz \
  MistbornAshesOfLuthadel.x86_64 \
  MistbornAshesOfLuthadel.pck
cd ../..

# Windows package
echo "Packaging Windows build..."
cd build/windows
zip -q ../dist/MistbornAshesOfLuthadel-windows-x86_64.zip \
  MistbornAshesOfLuthadel.exe \
  MistbornAshesOfLuthadel.pck
cd ../..

echo ""
echo "Build completed successfully!"
echo "Artifacts:"
ls -lh build/dist/
