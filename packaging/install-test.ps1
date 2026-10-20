# Cài thử Diskat dạng gói MSIX trên máy này (trước khi nộp Store) để kiểm tra
# menu Start, icon thanh tác vụ, alias "diskat" và nút "Run as Admin".
#
# Yêu cầu: bật Developer Mode (Settings > Update & Security > For developers > Developer mode).
# Chạy build-msix.ps1 trước, rồi:
#   powershell -ExecutionPolicy Bypass -File packaging\install-test.ps1
# Gỡ bản thử:
#   powershell -ExecutionPolicy Bypass -File packaging\install-test.ps1 -Uninstall
param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$manifest = Join-Path $PSScriptRoot "out\layout\AppxManifest.xml"
$name = ([xml](Get-Content $manifest -Raw)).Package.Identity.Name

Get-AppxPackage -Name $name | ForEach-Object {
    Write-Host "Gỡ bản cũ: $($_.PackageFullName)"
    Remove-AppxPackage $_.PackageFullName
}
if ($Uninstall) { return }

Add-AppxPackage -Register $manifest
Write-Host "Đã cài thử '$name'. Mở Diskat từ menu Start hoặc gõ: diskat"
