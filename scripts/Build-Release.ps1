<#
.SYNOPSIS
  Build portable package + Windows installer for RB Legacy Java Converter.

.DESCRIPTION
  Produces:
    dist/portable/RB-Legacy-Java-Converter/
    dist/RB-Legacy-Java-Converter-Portable.zip
    dist/portable-payload.zip
    dist/RB-Legacy-Java-Converter-Setup.exe

.EXAMPLE
  .\scripts\Build-Release.ps1
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'
$PortableRoot = Join-Path $Dist 'portable\RB-Legacy-Java-Converter'
$GuiProj = Join-Path $RepoRoot 'src\RB.LegacyJavaConverter\RB.LegacyJavaConverter.csproj'
$SetupProj = Join-Path $RepoRoot 'src\RB.LegacyJavaConverter.Setup\RB.LegacyJavaConverter.Setup.csproj'

Write-Host "==> Cleaning dist" -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Path $PortableRoot -Force | Out-Null

Write-Host "==> Publishing GUI (self-contained $Runtime)" -ForegroundColor Cyan
$guiOut = Join-Path $Dist 'publish-gui'
dotnet publish $GuiProj `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $guiOut

if ($LASTEXITCODE -ne 0) { throw "GUI publish failed" }

Write-Host "==> Assembling portable folder" -ForegroundColor Cyan
$guiExe = Join-Path $guiOut 'RB-Legacy-Java-Converter.exe'
if (-not (Test-Path $guiExe)) { throw "GUI publish missing RB-Legacy-Java-Converter.exe" }
Copy-Item $guiExe $PortableRoot -Force

$toolsSrc = Join-Path $guiOut 'tools'
if (Test-Path $toolsSrc) {
    Copy-Item $toolsSrc (Join-Path $PortableRoot 'tools') -Recurse -Force
}
else {
    New-Item -ItemType Directory -Path (Join-Path $PortableRoot 'tools') -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'Convert-Forge1201-ToNeoForge262.ps1') (Join-Path $PortableRoot 'tools') -Force
    Copy-Item (Join-Path $RepoRoot 'Convert-JarToProject.ps1') (Join-Path $PortableRoot 'tools') -Force
    Copy-Item (Join-Path $RepoRoot 'Convert-OldJarToNeoForge262.ps1') (Join-Path $PortableRoot 'tools') -Force
    Copy-Item (Join-Path $RepoRoot 'README.md') (Join-Path $PortableRoot 'tools') -Force
    if (Test-Path (Join-Path $RepoRoot 'docs')) {
        Copy-Item (Join-Path $RepoRoot 'docs') (Join-Path $PortableRoot 'tools\docs') -Recurse -Force
    }
    if (Test-Path (Join-Path $RepoRoot 'LICENSE')) {
        Copy-Item (Join-Path $RepoRoot 'LICENSE') (Join-Path $PortableRoot 'tools') -Force
    }
}
# Always overwrite tools scripts from repo root (publish output can ship stale copies)
$toolsFinal = Join-Path $PortableRoot 'tools'
if (-not (Test-Path $toolsFinal)) { New-Item -ItemType Directory -Path $toolsFinal -Force | Out-Null }
foreach ($s in @('Convert-JarToProject.ps1','Convert-OldJarToNeoForge262.ps1','Convert-Forge1201-ToNeoForge262.ps1','README.md','LICENSE','CHANGELOG.md')) {
    $src = Join-Path $RepoRoot $s
    if (Test-Path $src) {
        Copy-Item $src $toolsFinal -Force
        Write-Host "    tools/$s (from repo)"
    }
}
if (Test-Path (Join-Path $RepoRoot 'docs')) {
    $docsDest = Join-Path $toolsFinal 'docs'
    if (Test-Path $docsDest) { Remove-Item $docsDest -Recurse -Force }
    Copy-Item (Join-Path $RepoRoot 'docs') $docsDest -Recurse -Force
}
$libSrc = Join-Path $RepoRoot 'lib'
if (Test-Path $libSrc) {
    $libDest = Join-Path $toolsFinal 'lib'
    if (Test-Path $libDest) { Remove-Item $libDest -Recurse -Force }
    Copy-Item $libSrc $libDest -Recurse -Force
    Write-Host "    tools/lib (SRG map + dependency catalog)"
}

@'
@echo off
cd /d "%~dp0"
start "" "%~dp0RB-Legacy-Java-Converter.exe"
'@ | Set-Content (Join-Path $PortableRoot 'Start-Converter.bat') -Encoding ASCII

Copy-Item (Join-Path $RepoRoot 'README.md') (Join-Path $PortableRoot 'README.md') -Force
if (Test-Path (Join-Path $RepoRoot 'LICENSE')) {
    Copy-Item (Join-Path $RepoRoot 'LICENSE') (Join-Path $PortableRoot 'LICENSE.txt') -Force
}
$ico = Join-Path $RepoRoot 'assets\app.ico'
if (Test-Path $ico) {
    Copy-Item $ico (Join-Path $PortableRoot 'app.ico') -Force
    Write-Host "    app.ico (from assets)"
}

Write-Host "==> Creating portable ZIP" -ForegroundColor Cyan
$portableZip = Join-Path $Dist 'RB-Legacy-Java-Converter-Portable.zip'
if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
Compress-Archive -Path (Join-Path $Dist 'portable\RB-Legacy-Java-Converter') -DestinationPath $portableZip -Force

$payloadZip = Join-Path $Dist 'portable-payload.zip'
Copy-Item $portableZip $payloadZip -Force

Write-Host "==> Publishing Setup installer (self-contained $Runtime, payload embedded)" -ForegroundColor Cyan
$setupOut = Join-Path $Dist 'publish-setup'
if (-not (Test-Path $payloadZip)) { throw "portable-payload.zip missing before setup publish" }

dotnet publish $SetupProj `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $setupOut

if ($LASTEXITCODE -ne 0) { throw "Setup publish failed" }

$setupExe = Join-Path $setupOut 'RB-Legacy-Java-Converter-Setup.exe'
if (-not (Test-Path -LiteralPath $setupExe)) {
    throw "Setup publish succeeded but EXE not found: $setupExe"
}

Copy-Item $setupExe $Dist -Force
Copy-Item $setupExe (Join-Path $Dist 'publish-setup\RB-Legacy-Java-Converter-Setup.exe') -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Build complete:" -ForegroundColor Green
Write-Host "  Portable folder : $PortableRoot"
Write-Host "  Portable ZIP    : $portableZip"
Write-Host "  Setup EXE       : $(Join-Path $Dist 'RB-Legacy-Java-Converter-Setup.exe')"
Write-Host ""
Get-ChildItem $Dist -File | Format-Table Name, @{N='MB';E={[math]::Round($_.Length/1MB,2)}}, LastWriteTime
