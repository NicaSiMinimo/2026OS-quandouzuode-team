param(
    [string]$LocalProject = ".",
    [string]$DeviceDir = "/cann-install/yolov5_cli",
    [string]$Model = (Join-Path $PSScriptRoot "..\model\yolov5s_ascend310b.om"),
    [string]$Image = (Join-Path $PSScriptRoot "..\example_image\test.jpg")
)

$ErrorActionPreference = "Stop"

hdc shell "mount -o remount,rw / || true"
hdc shell "mkdir -p $DeviceDir $DeviceDir/models $DeviceDir/images $DeviceDir/output $DeviceDir/scripts"

hdc file send (Join-Path $LocalProject "server\main.py") "$DeviceDir/main.py"
hdc file send (Join-Path $LocalProject "requirements\requirements-device.txt") "$DeviceDir/requirements-device.txt"
hdc file send (Join-Path $LocalProject "scripts\run_on_device.sh") "$DeviceDir/scripts/run_on_device.sh"

if ($Model -ne "") {
    hdc file send $Model "$DeviceDir/models/"
}

if ($Image -ne "") {
    hdc file send $Image "$DeviceDir/images/"
}

hdc shell "chmod +x $DeviceDir/scripts/run_on_device.sh"
Write-Host "Deploy finished. Run: hdc shell sh $DeviceDir/scripts/run_on_device.sh"
