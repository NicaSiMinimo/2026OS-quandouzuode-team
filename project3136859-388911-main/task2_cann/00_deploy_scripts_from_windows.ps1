param(
    [string]$DeviceDir = "/cann-install/task2_cann"
)

$ErrorActionPreference = "Stop"

$files = @(
    "02_install_cann_on_device.sh",
    "03_set_cann_env.sh",
    "04_install_python_wheels.sh",
    "05_verify_npu.sh",
    "verify_cann_runtime.py"
)

hdc shell "mount -o remount,rw / || true"
hdc shell "mkdir -p $DeviceDir"
hdc shell "mkdir -p /storage/temp"

foreach ($file in $files) {
    $local = Join-Path $PSScriptRoot $file
    if (!(Test-Path $local)) {
        throw "Missing local file: $local"
    }
    hdc file send $local "$DeviceDir/"
}

hdc shell "chmod +x $DeviceDir/*.sh"
Write-Host "Task2 scripts have been deployed to $DeviceDir."
