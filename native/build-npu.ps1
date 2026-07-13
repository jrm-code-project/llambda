param(
    [string]$RyzenAiRoot = "C:\Program Files\RyzenAI\1.7.1",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $source "build"

cmake -S $source -B $build -D "RYZEN_AI_ROOT=$RyzenAiRoot"
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed."
}

cmake --build $build --config $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "NPU bridge build failed."
}

Write-Output (Join-Path $build "$Configuration\llambda_npu.dll")
