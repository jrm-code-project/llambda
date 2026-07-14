param(
    [string]$RyzenAiRoot = "C:\Program Files\RyzenAI\1.7.1",
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$OrtRoot = "",
    [string]$OrtRuntimeDir = "",
    [ValidateSet("NPU", "GPU")]
    [string]$Backend = "NPU"
)

$ErrorActionPreference = "Stop"
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$build = Join-Path $source $(if ($Backend -eq "GPU") { "build-gpu" } else { "build" })
if ($Backend -eq "GPU" -and -not $OrtRoot) {
    throw "GPU builds require -OrtRoot pointing to an ONNX Runtime DirectML distribution."
}
if ($Backend -eq "NPU" -and -not $OrtRoot) {
    $OrtRoot = Join-Path $RyzenAiRoot "onnxruntime"
}
$copyRyzenAiDlls = if ($Backend -eq "NPU") { "ON" } else { "OFF" }

$configureArguments = @(
    "-S", $source,
    "-B", $build,
    "-D", "RYZEN_AI_ROOT=$RyzenAiRoot",
    "-D", "ORT_ROOT=$OrtRoot",
    "-D", "LLAMBDA_COPY_RYZEN_AI_DLLS=$copyRyzenAiDlls"
)
if ($OrtRuntimeDir) {
    $configureArguments += @("-D", "ORT_RUNTIME_DIR=$OrtRuntimeDir")
}
cmake @configureArguments
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed."
}

cmake --build $build --config $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "$Backend bridge build failed."
}

Write-Output (Join-Path $build "$Configuration\llambda_npu.dll")
