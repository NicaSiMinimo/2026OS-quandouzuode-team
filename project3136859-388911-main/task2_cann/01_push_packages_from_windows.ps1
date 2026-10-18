param(
    [string]$PackageDir = ".",
    [string]$DeviceTemp = "/storage/temp"
)

$ErrorActionPreference = "Stop"

$packages = @(
    "initenv.tar.gz",
    "toolkit.tar.gz",
    "nnal.tar.gz",
    "kernels.tar.gz"
)

Write-Host "Checking hdc device..."
hdc list targets
hdc shell "mkdir -p $DeviceTemp"

foreach ($pkg in $packages) {
    $path = Join-Path $PackageDir $pkg
    if (!(Test-Path $path)) {
        throw "Missing package: $path"
    }
    Write-Host "Sending $path to $DeviceTemp/"
    hdc file send $path "$DeviceTemp/"
}

Write-Host "All CANN packages have been sent to $DeviceTemp/."
