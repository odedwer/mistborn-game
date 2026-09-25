# Build script for Mistborn: Ashes of Luthadel (Windows)
# Builds the game for Linux and Windows x86_64
# Usage: .\tools\build.ps1 [-Clean]

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# Get the godot binary
$GODOT = if ($env:GODOT) { $env:GODOT } else { "godot" }

# Clean build directory if requested
if ($Clean) {
    Write-Host "Cleaning build directory..."
    if (Test-Path "build") {
        Remove-Item -Recurse -Force "build"
    }
}

# Create build directories
New-Item -ItemType Directory -Force -Path "build/dist" | Out-Null
New-Item -ItemType Directory -Force -Path "build/linux" | Out-Null
New-Item -ItemType Directory -Force -Path "build/windows" | Out-Null

Write-Host "Running tests..."
if (Test-Path "tools/run_tests.sh") {
    bash tools/run_tests.sh
} else {
    Write-Host "Warning: tools/run_tests.sh not found, skipping tests"
}

Write-Host "Importing project..."
& $GODOT --headless --import 2>&1 | Out-Null

Write-Host "Exporting for Linux x86_64..."
& $GODOT --headless --export-release "Linux" "build/linux/MistbornAshesOfLuthadel.x86_64"

Write-Host "Exporting for Windows x86_64..."
& $GODOT --headless --export-release "Windows Desktop" "build/windows/MistbornAshesOfLuthadel.exe"

Write-Host "Creating distribution packages..."

# Linux package
Write-Host "Packaging Linux build..."
Push-Location "build/linux"
tar -czf ../dist/MistbornAshesOfLuthadel-linux-x86_64.tar.gz `
    MistbornAshesOfLuthadel.x86_64, `
    MistbornAshesOfLuthadel.pck
Pop-Location

# Windows package
Write-Host "Packaging Windows build..."
Push-Location "build/windows"
Compress-Archive -Path @("MistbornAshesOfLuthadel.exe", "MistbornAshesOfLuthadel.pck") `
    -DestinationPath ../dist/MistbornAshesOfLuthadel-windows-x86_64.zip -Force
Pop-Location

Write-Host ""
Write-Host "Build completed successfully!"
Write-Host "Artifacts:"
Get-ChildItem -Path "build/dist/" | Format-Table -Property Length, Name
