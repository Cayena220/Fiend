# Builds Fiend end to end: tests the Rust engine, builds the Flutter app (which also
# builds fiend_core.dll), then packs the release twice, as a per-user installer
# (Inno Setup, installer/fiend.iss) and as a portable zip. Both land in web/downloads
# with their checksums in release.json for the download site.
#   .\scripts\build.ps1            full build
#   .\scripts\build.ps1 -SkipTests
param([switch] $SkipTests)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\.."
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\src\flutter\bin\flutter.bat' }
$iscc = @(
    $env:ISCC
    (Get-Command ISCC -ErrorAction SilentlyContinue).Source
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 is needed for the installer: winget install JRSoftware.InnoSetup (or set $env:ISCC to ISCC.exe)' }

$version = (Select-String -Path "$root\app\pubspec.yaml" -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
Write-Host "Building Fiend $version" -ForegroundColor Magenta

if (-not $SkipTests) {
    Push-Location "$root\core"; cargo test --quiet; if ($LASTEXITCODE) { throw 'Rust tests failed' }; Pop-Location
    Push-Location "$root\app"; & $flutter test; if ($LASTEXITCODE) { throw 'Flutter tests failed' }; Pop-Location
}

Push-Location "$root\app"
& $flutter build windows --release
if ($LASTEXITCODE) { throw 'Flutter build failed' }
Pop-Location

$release = "$root\app\build\windows\x64\runner\Release"
if (-not (Test-Path "$release\fiend_core.dll")) { throw 'fiend_core.dll is missing from the release folder' }

$downloads = "$root\web\downloads"
New-Item -ItemType Directory -Force $downloads | Out-Null
$name = "Fiend-$version-win-x64.zip"
$zip = Join-Path $downloads $name
if (Test-Path $zip) { Remove-Item $zip }
$staging = Join-Path ([IO.Path]::GetTempPath()) "Fiend-$version"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
Copy-Item -Recurse $release $staging
Compress-Archive -Path "$staging\*" -DestinationPath $zip
Remove-Item -Recurse -Force $staging

$setupName = "Fiend-$version-setup.exe"
& $iscc /Q "/DAppVersion=$version" "/DSourceDir=$release" "/DOutputDir=$downloads" "$root\installer\fiend.iss"
if ($LASTEXITCODE) { throw 'Installer build failed' }

function Describe($file) {
    $item = Get-Item (Join-Path $downloads $file)
    [ordered]@{ file = $file; size = $item.Length; sha256 = (Get-FileHash -Algorithm SHA256 $item.FullName).Hash.ToLower() }
}
$info = [ordered]@{
    version   = $version
    built     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    installer = Describe $setupName
    zip       = Describe $name
}
$info | ConvertTo-Json | Set-Content -Encoding ascii "$downloads\release.json"

foreach ($pack in $info.installer, $info.zip) {
    Write-Host "Packed $($pack.file) ($([math]::Round($pack.size / 1MB, 1)) MB)" -ForegroundColor Green
    Write-Host "  SHA-256 $($pack.sha256)"
}
