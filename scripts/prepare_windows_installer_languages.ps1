$ErrorActionPreference = "Stop"

$candidateDirectories = @()
if (-not [string]::IsNullOrWhiteSpace($env:INNO_SETUP_PATH)) {
  $candidateDirectories += $env:INNO_SETUP_PATH
}
if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
  $candidateDirectories += (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6")
}
if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
  $candidateDirectories += (Join-Path $env:ProgramFiles "Inno Setup 6")
}

$innoSetupDirectory = $candidateDirectories |
  Where-Object { Test-Path (Join-Path $_ "ISCC.exe") } |
  Select-Object -First 1

if ($null -eq $innoSetupDirectory) {
  throw "Inno Setup 6 was not found. Set INNO_SETUP_PATH before packaging the Windows EXE."
}

$officialLanguageDirectory = Join-Path $innoSetupDirectory "Languages"
$pinnedTranslationCommit = "c495623a97376d524f298b1b160e8fd612375c62"
$officialTranslationBaseUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/$pinnedTranslationCommit/Files/Languages"
$requiredOfficialLanguages = [ordered]@{
  "Arabic.isl" = "5cfbd5fe899f7c8d9fe86b17168d8f54d86a367e2ad785fca8e557759aed660e"
  "BrazilianPortuguese.isl" = "d7718875674948a77b607041c262f481fe97735b0ad6bfcb1771d93e086ca1b2"
  "ChineseSimplified.isl" = "6753be2c5e2740d859900fd902824db2ec568da5c5b52486524c9762d778b0b0"
  "ChineseTraditional.isl" = "cbde191fa061890174108ec52955c52a061ecf8ec713583664abf53a5675948a"
  "French.isl" = "5dd8367b662b7f250bbfb6859e32a5ff98ac98a677bc1211f635d287e23cb801"
  "Russian.isl" = "0def13d0a979bd3d062ef7ce960264df17f908fb62af46bb81970e2abee53919"
  "Spanish.isl" = "cb071274c70d7de4b774b306c6750edef7e8b662f71bb551333a7ed84c5a2634"
  "Turkish.isl" = "430f1c78382f4024c1254bbeeff5e1205fedd770c656cff984b3cb4d435cd838"
}

foreach ($languageFile in $requiredOfficialLanguages.Keys) {
  $languagePath = Join-Path $officialLanguageDirectory $languageFile
  if (-not (Test-Path $languagePath)) {
    $sourceUrl = "$officialTranslationBaseUrl/$languageFile"
    $temporaryDownloadPath = Join-Path ([IO.Path]::GetTempPath()) "yundo-inno-$languageFile"
    Write-Host "Downloading missing official Inno Setup language: $languageFile"
    Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $temporaryDownloadPath

    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryDownloadPath).Hash.ToLowerInvariant()
    $expectedHash = $requiredOfficialLanguages[$languageFile]
    if ($actualHash -ne $expectedHash) {
      Remove-Item -LiteralPath $temporaryDownloadPath -Force
      throw "Downloaded Inno Setup language file failed SHA256 verification: $languageFile"
    }

    Copy-Item -LiteralPath $temporaryDownloadPath -Destination $languagePath -Force
    Remove-Item -LiteralPath $temporaryDownloadPath -Force
  }
}

$sourceDirectory = Join-Path $PSScriptRoot "..\windows\packaging\exe\languages"
$unofficialLanguageDirectory = Join-Path $officialLanguageDirectory "Unofficial"
New-Item -ItemType Directory -Path $unofficialLanguageDirectory -Force | Out-Null

foreach ($languageFile in @("Farsi.isl", "Indonesian.isl")) {
  $sourcePath = Join-Path $sourceDirectory $languageFile
  if (-not (Test-Path $sourcePath)) {
    throw "Vendored installer language file is missing: $sourcePath"
  }
  Copy-Item -LiteralPath $sourcePath -Destination $unofficialLanguageDirectory -Force
}

Write-Host "Prepared 11 Windows installer languages in $innoSetupDirectory"
