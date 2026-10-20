# Đóng gói Diskat thành MSIX để nộp lên Microsoft Store.
#
# Lần đầu, script tự tải bộ công cụ Microsoft.Windows.SDK.BuildTools (makeappx, makepri)
# từ nuget.org vào packaging\.tools (không cài gì vào hệ thống) và kiểm tra chữ ký Microsoft.
#
# Nộp Store: lấy 3 giá trị ở Partner Center > app Diskat > Product identity rồi chạy:
#   powershell -ExecutionPolicy Bypass -File packaging\build-msix.ps1 `
#       -IdentityName "12345YourName.Diskat" `
#       -Publisher "CN=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX" `
#       -PublisherDisplayName "Your Name"
#
# File kết quả: packaging\out\Diskat_<version>_x64.msix (Store tự ký khi phát hành).
param(
    [string]$IdentityName = "Diskat.Dev",
    [string]$Publisher = "CN=DiskatDev",
    [string]$PublisherDisplayName = "Diskat",
    [string]$Version = "",   # mặc định: <Version> trong Diskat.csproj + ".0"
    [string]$BuildToolsVersion = "10.0.28000.2705"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$pkgDir = $PSScriptRoot
$out = Join-Path $pkgDir "out"
$layout = Join-Path $out "layout"

if (-not $Version) {
    $csproj = [xml](Get-Content (Join-Path $root "Diskat.csproj") -Raw)
    $Version = ($csproj.Project.PropertyGroup | ForEach-Object { $_.Version } | Where-Object { $_ } | Select-Object -First 1) + ".0"
}
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw "Version phải có dạng a.b.c.0 (Store yêu cầu số cuối là 0)." }

# ---------- 1. Công cụ đóng gói ----------
$toolsDir = Join-Path $pkgDir ".tools\buildtools-$BuildToolsVersion"
if (-not (Test-Path $toolsDir)) {
    $dl = Join-Path $pkgDir ".tools\download"
    New-Item -ItemType Directory -Force $dl | Out-Null
    $nupkg = Join-Path $dl "buildtools-$BuildToolsVersion.zip"
    $url = "https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/$BuildToolsVersion/microsoft.windows.sdk.buildtools.$BuildToolsVersion.nupkg"
    Write-Host "Tải $url"
    Invoke-WebRequest $url -OutFile $nupkg -UseBasicParsing
    Expand-Archive $nupkg -DestinationPath $toolsDir -Force
    Remove-Item $dl -Recurse -Force
}
$binDir = Get-ChildItem $toolsDir -Recurse -Filter makeappx.exe |
    Where-Object { $_.DirectoryName -match '\\x64$' } | Select-Object -First 1 -ExpandProperty DirectoryName
if (-not $binDir) { throw "Không tìm thấy makeappx.exe (x64) trong $toolsDir" }
$makeappx = Join-Path $binDir "makeappx.exe"
$makepri = Join-Path $binDir "makepri.exe"
foreach ($exe in $makeappx, $makepri) {
    $sig = Get-AuthenticodeSignature $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Chữ ký của $exe không hợp lệ ($($sig.Status)). Dừng lại để an toàn."
    }
}

# ---------- 2. Build ứng dụng (self-contained, không cần cài .NET) ----------
$running = Get-Process Diskat -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($out, [StringComparison]::OrdinalIgnoreCase) }
if ($running) { throw "Diskat đang chạy từ $out (PID $($running.Id -join ', ')). Hãy đóng cửa sổ đó rồi chạy lại." }
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $layout | Out-Null
$v3 = ($Version -split '\.')[0..2] -join '.'
dotnet publish (Join-Path $root "Diskat.csproj") -c Release -r win-x64 --self-contained true `
    -p:PublishReadyToRun=true -p:DebugType=none -p:Version=$v3 -o $layout -nologo -v q
if ($LASTEXITCODE -ne 0) { throw "dotnet publish lỗi" }

# ---------- 3. Manifest + assets ----------
Copy-Item (Join-Path $pkgDir "Assets") (Join-Path $layout "Assets") -Recurse
$manifest = [IO.File]::ReadAllText((Join-Path $pkgDir "AppxManifest.template.xml"))
$manifest = $manifest.Replace('$IdentityName$', $IdentityName).Replace('$Publisher$', $Publisher).
    Replace('$PublisherDisplayName$', [Security.SecurityElement]::Escape($PublisherDisplayName)).Replace('$Version$', $Version)
[IO.File]::WriteAllText((Join-Path $layout "AppxManifest.xml"), $manifest, (New-Object Text.UTF8Encoding $false))

# ---------- 4. resources.pri (chọn icon đúng cỡ theo DPI / thanh tác vụ) ----------
$priStage = Join-Path $out "pri-stage"
New-Item -ItemType Directory -Force $priStage | Out-Null
Copy-Item (Join-Path $pkgDir "Assets") (Join-Path $priStage "Assets") -Recurse
$priConfig = Join-Path $out "priconfig.xml"
& $makepri createconfig /cf $priConfig /dq en-US /o | Out-Null
# Gói đơn (không phải bundle): giữ mọi biến thể icon trong một resources.pri, không tách theo scale/ngôn ngữ
$cfg = [xml](Get-Content $priConfig -Raw)
$cfg.SelectNodes("//packaging") | ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
$cfg.Save($priConfig)
& $makepri new /pr $priStage /cf $priConfig /mn (Join-Path $layout "AppxManifest.xml") `
    /of (Join-Path $layout "resources.pri") /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw "makepri lỗi" }
Remove-Item $priStage, $priConfig -Recurse -Force

# ---------- 5. Đóng gói ----------
$msix = Join-Path $out "Diskat_${Version}_x64.msix"
$log = & $makeappx pack /d $layout /p $msix /o 2>&1
if ($LASTEXITCODE -ne 0) { $log | Select-Object -Last 30 | Write-Host; throw "makeappx lỗi" }

Write-Host ""
Write-Host "Xong: $msix ($([math]::Round((Get-Item $msix).Length / 1MB, 1)) MB)"
Write-Host "Identity: $IdentityName | $Publisher | $PublisherDisplayName | v$Version"
