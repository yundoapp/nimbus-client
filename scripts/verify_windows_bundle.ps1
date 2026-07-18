param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedProductName
)

$ErrorActionPreference = "Stop"

$bundle = Join-Path $PSScriptRoot "..\build\windows\x64\runner\$Configuration"
$executable = Join-Path $bundle "Yundo.exe"
$requiredFiles = @(
    $executable,
    (Join-Path $bundle "YundoService.exe"),
    (Join-Path $bundle "hiddify-core.dll"),
    (Join-Path $bundle "libcronet.dll"),
    (Join-Path $bundle "flutter_windows.dll"),
    (Join-Path $bundle "data\icudtl.dat"),
    (Join-Path $bundle "data\flutter_assets\LICENSE.md")
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Windows bundle is missing required file: $file"
    }
}

$version = (Get-Item -LiteralPath $executable).VersionInfo
if ($version.CompanyName -ne "Yundo") {
    throw "Unexpected CompanyName: $($version.CompanyName)"
}
if ($version.ProductName -ne $ExpectedProductName) {
    throw "Unexpected ProductName: $($version.ProductName)"
}
if ($version.FileDescription -ne $ExpectedProductName) {
    throw "Unexpected FileDescription: $($version.FileDescription)"
}
if ($version.OriginalFilename -ne "Yundo.exe") {
    throw "Unexpected OriginalFilename: $($version.OriginalFilename)"
}

$license = Get-Content -LiteralPath (Join-Path $bundle "data\flutter_assets\LICENSE.md") -Raw
if ($license -notmatch "Hiddify Extended GNU General Public License v3") {
    throw "The bundled Hiddify Extended GPLv3 license is missing"
}

Write-Host "Windows $Configuration bundle verified: $ExpectedProductName"
