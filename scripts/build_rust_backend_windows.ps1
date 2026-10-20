# Build the Rust desktop backend (mornye_desktop.dll) on Windows and stage it
# in rust_backend\target\desktop\windows\, where windows\CMakeLists.txt
# installs it next to mornye.exe. This is the Windows counterpart of
# `bash scripts/build_rust_backend.sh desktop`.
#
# Requirements: rustup (the toolchain is pinned by rust_backend\rust-toolchain.toml)
# and the MSVC build tools. LLVM is not needed: rquickjs uses its prebuilt
# Windows MSVC bindings.
#
# Usage, from the repository root:
#   pwsh scripts\build_rust_backend_windows.ps1
#   pwsh scripts\build_rust_backend_windows.ps1 -Target aarch64-pc-windows-msvc

[CmdletBinding()]
param(
    [ValidateSet('x86_64-pc-windows-msvc', 'aarch64-pc-windows-msvc')]
    [string]$Target = 'x86_64-pc-windows-msvc'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $PSScriptRoot
$rustBackendDir = Join-Path $projectDir 'rust_backend'
$targetDir = Join-Path $rustBackendDir 'target'

Push-Location $rustBackendDir
try {
    $env:CARGO_TARGET_DIR = $targetDir

    rustup target add $Target
    if ($LASTEXITCODE -ne 0) { throw "rustup target add $Target failed." }

    cargo build --locked --release -p mornye-desktop --target $Target
    if ($LASTEXITCODE -ne 0) { throw "Building mornye-desktop for $Target failed." }

    # One staged library: the CMake build bundles whichever target was built last.
    $desktopDir = Join-Path $targetDir 'desktop\windows'
    New-Item -ItemType Directory -Force $desktopDir | Out-Null
    Copy-Item -Force (Join-Path $targetDir "$Target\release\mornye_desktop.dll") $desktopDir
    Write-Host "Rust desktop library is staged in $desktopDir."
}
finally {
    Pop-Location
}
