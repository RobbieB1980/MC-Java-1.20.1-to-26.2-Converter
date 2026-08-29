<#
.SYNOPSIS
  Create/update a GitHub Release and upload portable + setup artifacts from dist/.

.EXAMPLE
  .\scripts\Publish-GitHubRelease.ps1 -Tag v1.5.0
#>
[CmdletBinding()]
param(
    [string]$Tag = 'v1.5.0',
    [string]$Repo = 'RobbieB1980/MC-Java-1.20.1-to-26.2-Converter',
    [string]$Name = 'MC Java 1.20.1 to 26.2 Converter v1.5.0'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'

$setup = Join-Path $Dist 'RB-Legacy-Java-Converter-Setup.exe'
$portable = Join-Path $Dist 'RB-Legacy-Java-Converter-Portable.zip'
if (-not (Test-Path $setup)) { throw "Missing setup EXE in dist/ - run Build-Release.ps1 first" }
if (-not (Test-Path $portable)) { throw "Missing portable ZIP in dist/ - run Build-Release.ps1 first" }

$fill = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = ($fill | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { throw 'Could not obtain GitHub credentials from git credential helper.' }

$headers = @{
    Authorization          = "Bearer $token"
    Accept                 = 'application/vnd.github+json'
    'User-Agent'           = 'RB-Legacy-Java-Converter-Release'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$api = "https://api.github.com/repos/$Repo"

function ConvertTo-JsonUtf8([hashtable]$Object) {
    return $Object | ConvertTo-Json -Depth 20 -Compress
}

function Invoke-GitHubJson([string]$Method, [string]$Uri, [hashtable]$BodyObj = $null) {
    $params = @{
        Headers = $headers
        Uri     = $Uri
        Method  = $Method
    }
    if ($null -ne $BodyObj) {
        $json = ConvertTo-JsonUtf8 $BodyObj
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $params['Body'] = $bytes
        $params['ContentType'] = 'application/json; charset=utf-8'
    }
    return Invoke-RestMethod @params
}

$notes = @"
## RB Legacy Java Converter $Tag

Migration assistant for **Forge/NeoForge 1.20.1 through 26.1** projects and finished jars → **NeoForge 26.2**.

### Downloads

| File | Description |
|------|-------------|
| ``RB-Legacy-Java-Converter-Setup.exe`` | Windows installer (self-contained; embeds portable toolset) |
| ``RB-Legacy-Java-Converter-Portable.zip`` | No install - extract and run ``Start-Converter.bat`` or the EXE |

### What's new in 1.5.0

- Evidence-based source detection and applicable primer-change index
- Complete build verification and structured compile/dependency reports
- NeoForge 26.2 render model, state property, lighting, standalone model and item-tag migrations
- Fixed dependency JSON and official Fusion resolution
- Verified NextGen Furniture 1.21.11 → 26.2 full Gradle build and installable JAR

### Requirements

- Windows x64
- PowerShell 5.1+
- JDK 25 for compile/build of converted projects

### Notes

- Original input is never modified (always writes to output folder).
- Setup installs under ``%LOCALAPPDATA%\RB-Legacy-Java-Converter`` by default (no admin required).
- Conversion scaffold success ≠ always loadable; still run ``gradlew build`` and test in-game.
"@

Write-Host "==> Checking for existing release $Tag" -ForegroundColor Cyan
$release = $null
try {
    $release = Invoke-GitHubJson -Method Get -Uri "$api/releases/tags/$Tag"
    Write-Host "    Release exists (id $($release.id)) - will refresh assets and notes"
    $release = Invoke-GitHubJson -Method Patch -Uri "$api/releases/$($release.id)" -BodyObj @{
        name       = $Name
        body       = $notes
        draft      = $false
        prerelease = $false
    }
}
catch {
    Write-Host "    Creating release $Tag"
    $release = Invoke-GitHubJson -Method Post -Uri "$api/releases" -BodyObj @{
        tag_name   = $Tag
        name       = $Name
        body       = $notes
        draft      = $false
        prerelease = $false
    }
}

function Upload-Asset([string]$FilePath) {
    $name = [IO.Path]::GetFileName($FilePath)
    $release = Invoke-GitHubJson -Method Get -Uri "$api/releases/tags/$Tag"
    if ($release.assets) {
        $existing = $release.assets | Where-Object { $_.name -eq $name }
        foreach ($a in @($existing)) {
            Write-Host "    Deleting existing asset $name"
            Invoke-RestMethod -Headers $headers -Uri "$api/releases/assets/$($a.id)" -Method Delete | Out-Null
        }
        $release = Invoke-GitHubJson -Method Get -Uri "$api/releases/tags/$Tag"
    }
    $uploadUrl = $release.upload_url -replace '\{\?name,label\}', "?name=$([uri]::EscapeDataString($name))"
    Write-Host "    Uploading $name ($([math]::Round((Get-Item $FilePath).Length/1MB,1)) MB)..."
    $bytes = [IO.File]::ReadAllBytes($FilePath)
    $ctype = if ($name.EndsWith('.zip')) { 'application/zip' } else { 'application/octet-stream' }
    $uploadHeaders = @{
        Authorization          = "Bearer $token"
        Accept                 = 'application/vnd.github+json'
        'User-Agent'           = 'RB-Legacy-Java-Converter-Release'
        'X-GitHub-Api-Version' = '2022-11-28'
        'Content-Type'         = $ctype
    }
    $wc = New-Object System.Net.WebClient
    foreach ($k in $uploadHeaders.Keys) { $wc.Headers[$k] = $uploadHeaders[$k] }
    try {
        [void]$wc.UploadData($uploadUrl, 'POST', $bytes)
    }
    finally {
        $wc.Dispose()
    }
    Write-Host "    Uploaded $name" -ForegroundColor Green
}

Upload-Asset $setup
Upload-Asset $portable

Write-Host ""
Write-Host "Release published: https://github.com/$Repo/releases/tag/$Tag" -ForegroundColor Green
