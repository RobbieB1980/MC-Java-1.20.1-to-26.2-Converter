#Requires -Version 5.1
<#
.SYNOPSIS
  Read Forge 1.20.1 / NeoForge mod dependencies, resolve NeoForge 26.2 replacements,
  download official artifacts, and convert remaining required mods.
#>

$script:DepUserAgent = 'RB-Legacy-Java-Converter/1.3.0 (https://github.com/RobbieB1980/LegacyJavaConverter)'
$script:CatalogCache = $null

function Initialize-DepTls {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Get-DependencyCatalog {
    param([string]$CatalogPath)
    if ($script:CatalogCache) { return $script:CatalogCache }
    if (-not $CatalogPath) {
        $CatalogPath = Join-Path $PSScriptRoot 'DependencyCatalog.json'
    }
    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        throw "Dependency catalog missing: $CatalogPath"
    }
    $raw = [System.IO.File]::ReadAllText($CatalogPath)
    $script:CatalogCache = $raw | ConvertFrom-Json
    return $script:CatalogCache
}

function Get-CatalogEntry {
    param($Catalog, [string]$ModId)
    $id = $ModId.ToLowerInvariant()
    if ($Catalog.skipModIds -contains $id) {
        return [pscustomobject]@{ Kind = 'skip'; ModId = $id }
    }
    $nc = $Catalog.neverConvert
    if ($nc) {
        foreach ($prop in $nc.PSObject.Properties) {
            $entry = $prop.Value
            $names = @($prop.Name.ToLowerInvariant())
            if ($entry.aliases) { $names += @($entry.aliases | ForEach-Object { $_.ToLowerInvariant() }) }
            if ($names -contains $id) {
                return [pscustomobject]@{
                    Kind     = 'never-convert'
                    ModId    = $prop.Name.ToLowerInvariant()
                    Modrinth = $entry.modrinth
                    Reason   = $entry.reason
                }
            }
        }
    }
    foreach ($lib in @($Catalog.libraries)) {
        $names = @($lib.modId.ToLowerInvariant())
        if ($lib.aliases) { $names += @($lib.aliases | ForEach-Object { $_.ToLowerInvariant() }) }
        if ($names -contains $id) { return $lib }
    }
    return $null
}

function ConvertTo-RequiredBool {
    param($BlockText)
    if ($BlockText -match 'mandatory\s*=\s*false') { return $false }
    if ($BlockText -match 'type\s*=\s*"optional"') { return $false }
    if ($BlockText -match 'type\s*=\s*"excluded"') { return $false }
    return $true
}

function Read-TomlDependencyBlocks {
    param([string]$Text, [string]$SelfModId)
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $Text) { return @() }
    $parts = [regex]::Split($Text, '\[\[dependencies')
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $b = $parts[$i]
        if ($b -notmatch 'modId\s*=\s*"([^"]+)"') { continue }
        $mid = $Matches[1]
        if ($SelfModId -and $mid -eq $SelfModId) { continue }
        $range = ''
        if ($b -match 'versionRange\s*=\s*"([^"]+)"') { $range = $Matches[1] }
        $list.Add([pscustomobject]@{
            ModId        = $mid
            Required     = (ConvertTo-RequiredBool $b)
            VersionRange = $range
            Source       = 'toml'
        }) | Out-Null
    }
    return $list.ToArray()
}

function Read-GradleMavenDependencies {
    param([string]$BuildGradleText)
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $BuildGradleText) { return @() }
    $rx = [regex]'(?:implementation|modImplementation|api|compileOnly|runtimeOnly)\s+(?:fg\.deobf\()?\s*[''"]([^''"]+)[''"]'
    foreach ($m in $rx.Matches($BuildGradleText)) {
        $coord = $m.Groups[1].Value
        if (-not $coord -or $coord -notmatch ':') { continue }
        $expanded = $coord.Replace('${minecraft_version}', '26.2').Replace('${geckolib_version}', '5.5.3').Replace('${smartbrainlib_version}', '2.0.0')
        $artifact = ($expanded -split ':')[1]
        $guess = ($artifact -replace '-forge.*', '' -replace '-neoforge.*', '' -replace '-fabric.*', '')
        $guess = ($guess -replace '\$\{.*\}', '').Trim('-', '_')
        if (-not $guess) { continue }
        $list.Add([pscustomobject]@{
            ModId        = $guess.ToLowerInvariant()
            Required     = $true
            VersionRange = ''
            Source       = "gradle:$coord"
            MavenHint    = $expanded
        }) | Out-Null
    }
    return $list.ToArray()
}

function Read-JarJarMetadata {
    param([string]$Root)
    $meta = Join-Path $Root 'src\main\resources\META-INF\jarjar\metadata.json'
    if (-not (Test-Path -LiteralPath $meta)) {
        $alt = Get-ChildItem -Path $Root -Recurse -Filter 'metadata.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'jarjar' } | Select-Object -First 1
        if ($alt) { $meta = $alt.FullName } else { return @() }
    }
    try {
        $j = Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json
    } catch { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($jar in @($j.jars)) {
        $art = $null
        if ($jar.identifier) { $art = [string]$jar.identifier.artifact }
        if (-not $art) { continue }
        $list.Add([pscustomobject]@{
            ModId        = ($art.ToLowerInvariant() -replace '-forge.*', '' -replace '-neoforge.*', '')
            Required     = $true
            VersionRange = ''
            Source       = 'jarjar'
        }) | Out-Null
    }
    return $list.ToArray()
}

function Read-ImportDetectedLibraries {
    param([string]$Root, $Catalog)
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path -LiteralPath $javaRoot)) { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($lib in @($Catalog.libraries)) {
        $hit = $false
        foreach ($pat in @($lib.imports)) {
            if (-not $pat) { continue }
            $found = Get-ChildItem -LiteralPath $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
                Select-String -Pattern ([regex]::Escape($pat)) -SimpleMatch -List |
                Select-Object -First 1
            if ($found) { $hit = $true; break }
        }
        if ($hit) {
            $list.Add([pscustomobject]@{
                ModId        = $lib.modId
                Required     = $true
                VersionRange = $lib.tomlVersionRange
                Source       = 'import'
            }) | Out-Null
        }
    }
    return $list.ToArray()
}

function Read-DetectedDependenciesJson {
    param([string]$Root)
    $p = Join-Path $Root 'detected-dependencies.json'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        $out = @()
        # v1.4.0 could write one object with parallel arrays. Accept that
        # shape so an existing decompile does not need to be repeated.
        if ($j.ModId -is [array]) {
            for ($i = 0; $i -lt $j.ModId.Count; $i++) {
                $out += [pscustomobject]@{
                    ModId        = [string]$j.ModId[$i]
                    Required     = [bool]$j.Required[$i]
                    VersionRange = [string]$j.VersionRange[$i]
                    Source       = $(if ($j.Source[$i]) { [string]$j.Source[$i] } else { 'detected-json' })
                    MavenHint    = ''
                }
            }
            return $out
        }
        foreach ($d in @($j)) {
            $out += [pscustomobject]@{
                ModId        = [string]$d.ModId
                Required     = [bool]$d.Required
                VersionRange = [string]$d.VersionRange
                Source       = $(if ($d.Source) { [string]$d.Source } else { 'detected-json' })
                MavenHint    = $(if ($d.MavenHint) { [string]$d.MavenHint } else { '' })
            }
        }
        return $out
    } catch { return @() }
}

function Merge-DependencyRecords {
    param($Items)
    $map = @{}
    foreach ($it in $Items) {
        if (-not $it -or -not $it.ModId) { continue }
        $key = $it.ModId.ToLowerInvariant()
        if ($map.ContainsKey($key)) {
            $cur = $map[$key]
            if ($it.Required) { $cur.Required = $true }
            if ($it.VersionRange -and -not $cur.VersionRange) { $cur.VersionRange = $it.VersionRange }
            if ($it.Source -and $cur.Source -notlike "*$($it.Source)*") {
                $cur.Source = "$($cur.Source);$($it.Source)"
            }
            if ($it.MavenHint -and -not $cur.MavenHint) { $cur.MavenHint = $it.MavenHint }
        } else {
            $map[$key] = [pscustomobject]@{
                ModId        = $key
                Required     = [bool]$it.Required
                VersionRange = [string]$it.VersionRange
                Source       = [string]$it.Source
                MavenHint    = $(if ($it.MavenHint) { [string]$it.MavenHint } else { '' })
            }
        }
    }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($k in $map.Keys) { [void]$out.Add($map[$k]) }
    return $out.ToArray()
}

function Read-ProjectDependencies {
    param(
        [string]$Root,
        [string]$SelfModId = '',
        $Catalog
    )
    if (-not $Catalog) { $Catalog = Get-DependencyCatalog }
    $acc = New-Object System.Collections.Generic.List[object]
    $tomlCandidates = @(
        'src\main\resources\META-INF\mods.toml',
        'src\main\resources\META-INF\neoforge.mods.toml',
        'src\main\templates\META-INF\mods.toml',
        'src\main\templates\META-INF\neoforge.mods.toml',
        'META-INF\mods.toml',
        'META-INF\neoforge.mods.toml'
    )
    foreach ($rel in $tomlCandidates) {
        $p = Join-Path $Root $rel
        if (Test-Path -LiteralPath $p) {
            $txt = [System.IO.File]::ReadAllText($p)
            foreach ($d in (Read-TomlDependencyBlocks -Text $txt -SelfModId $SelfModId)) {
                $acc.Add($d) | Out-Null
            }
        }
    }
    $bg = Join-Path $Root 'build.gradle'
    if (Test-Path -LiteralPath $bg) {
        foreach ($d in (Read-GradleMavenDependencies -BuildGradleText ([System.IO.File]::ReadAllText($bg)))) {
            $acc.Add($d) | Out-Null
        }
    }
    foreach ($d in (Read-JarJarMetadata -Root $Root)) { $acc.Add($d) | Out-Null }
    foreach ($d in (Read-ImportDetectedLibraries -Root $Root -Catalog $Catalog)) { $acc.Add($d) | Out-Null }
    foreach ($d in (Read-DetectedDependenciesJson -Root $Root)) { $acc.Add($d) | Out-Null }
    return Merge-DependencyRecords -Items $acc
}

function Invoke-HttpJson {
    param([string]$Url)
    Initialize-DepTls
    try {
        return Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = $script:DepUserAgent } -TimeoutSec 45
    } catch {
        return $null
    }
}

function Save-HttpFile {
    param([string]$Url, [string]$Dest)
    Initialize-DepTls
    $dir = Split-Path $Dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -Headers @{ 'User-Agent' = $script:DepUserAgent } -UseBasicParsing -TimeoutSec 120
        if ((Test-Path -LiteralPath $Dest) -and ((Get-Item -LiteralPath $Dest).Length -gt 1000)) {
            return $true
        }
    } catch { }
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue }
    return $false
}

function ConvertFrom-MavenCoordinate {
    param([string]$Coordinate)
    $p = $Coordinate.Split(':')
    if ($p.Count -lt 3) { return $null }
    return [pscustomobject]@{
        Group    = $p[0]
        Artifact = $p[1]
        Version  = $p[2]
        FileName = "$($p[1])-$($p[2]).jar"
        Path     = "$($p[0].Replace('.','/'))/$($p[1])/$($p[2])/$($p[1])-$($p[2]).jar"
    }
}

function Save-MavenArtifact {
    param(
        [string]$Coordinate,
        [string[]]$Repositories,
        [string]$DestDir
    )
    $info = ConvertFrom-MavenCoordinate $Coordinate
    if (-not $info) { return $null }
    $dest = Join-Path $DestDir $info.FileName
    if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 1000)) {
        return $dest
    }
    foreach ($repo in @($Repositories)) {
        $base = $repo.TrimEnd('/') + '/'
        $url = $base + $info.Path
        if (Save-HttpFile -Url $url -Dest $dest) { return $dest }
    }
    return $null
}

function Find-ModrinthProject {
    param([string]$ModId, [string]$PreferredSlug)
    $slugs = @()
    if ($PreferredSlug) { $slugs += $PreferredSlug }
    $slugs += $ModId
    $slugs += ($ModId -replace '_', '-')
    $slugs = $slugs | Select-Object -Unique
    foreach ($slug in $slugs) {
        $proj = Invoke-HttpJson "https://api.modrinth.com/v2/project/$slug"
        if ($proj -and $proj.id) { return $proj }
        Start-Sleep -Milliseconds 150
    }
    $q = [uri]::EscapeDataString($ModId)
    $search = Invoke-HttpJson "https://api.modrinth.com/v2/search?query=$q&limit=8&facets=%5B%5B%22project_type%3Amod%22%5D%5D"
    if ($search -and $search.hits) {
        $want = $ModId.ToLowerInvariant()
        foreach ($h in @($search.hits)) {
            $slug = ([string]$h.slug).ToLowerInvariant()
            $title = ([string]$h.title).ToLowerInvariant() -replace '[^a-z0-9]', ''
            if ($slug -eq $want -or $slug -eq ($want -replace '_', '-') -or $title -eq ($want -replace '[^a-z0-9]', '')) {
                return $h
            }
        }
    }
    return $null
}

function Find-ModrinthVersionFile {
    param(
        [string]$ProjectIdOrSlug,
        [string]$GameVersion,
        [string[]]$Loaders
    )
    foreach ($loader in @($Loaders)) {
        $gv = [uri]::EscapeDataString('["' + $GameVersion + '"]')
        $ld = [uri]::EscapeDataString('["' + $loader + '"]')
        $url = "https://api.modrinth.com/v2/project/$ProjectIdOrSlug/version?game_versions=$gv&loaders=$ld"
        $versions = Invoke-HttpJson $url
        Start-Sleep -Milliseconds 150
        if (-not $versions) { continue }
        foreach ($v in @($versions)) {
            foreach ($f in @($v.files)) {
                if ($f.url -and ([string]$f.filename).ToLowerInvariant().EndsWith('.jar') -and -not $f.filename.ToString().ToLowerInvariant().Contains('sources')) {
                    return [pscustomobject]@{
                        Url      = [string]$f.url
                        FileName = [string]$f.filename
                        Version  = [string]$v.version_number
                        Loader   = $loader
                    }
                }
            }
        }
    }
    return $null
}

function Find-LocalDependencyJar {
    param(
        [string]$ModId,
        [string[]]$SearchDirs
    )
    $needles = @(
        $ModId,
        ($ModId -replace '_', '-'),
        ($ModId -replace '-', '_')
    ) | Select-Object -Unique
    foreach ($dir in @($SearchDirs)) {
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
        $jars = Get-ChildItem -LiteralPath $dir -Filter '*.jar' -File -ErrorAction SilentlyContinue
        foreach ($n in $needles) {
            $hit = $jars | Where-Object { $_.BaseName -match [regex]::Escape($n) } | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function New-ResolvedDependency {
    param(
        $Record,
        [string]$Action,
        [string]$Status,
        [string]$Note = '',
        [string]$MavenCoord = '',
        [string[]]$Repositories = @(),
        [string]$TomlRange = '',
        [string]$JarPath = '',
        [string]$ConvertedProject = '',
        [string]$ModrinthSlug = ''
    )
    return [pscustomobject]@{
        ModId             = $Record.ModId
        Required          = [bool]$Record.Required
        Source            = $Record.Source
        Action            = $Action
        Status            = $Status
        Note              = $Note
        MavenCoord        = $MavenCoord
        Repositories      = @($Repositories)
        TomlVersionRange  = $(if ($TomlRange) { $TomlRange } else { $Record.VersionRange })
        JarPath           = $JarPath
        ConvertedProject  = $ConvertedProject
        ModrinthSlug      = $ModrinthSlug
    }
}

function Resolve-AndAcquireDependencies {
    param(
        $Records,
        $Catalog,
        [string]$LibsDir,
        [string]$CacheDir,
        [string]$ConvertedDepsDir,
        [string[]]$LocalJarDirs,
        [string]$ConvertJarScript,
        [string]$MinecraftVersion = '26.2',
        [string]$NeoVersion = '26.2.0.66',
        [string]$GeckoLibVersion = '5.5.3',
        [int]$DependencyDepth = 0,
        [int]$MaxDependencyDepth = 2,
        [string[]]$VisitedModIds = @(),
        [switch]$SkipDownload,
        [switch]$SkipConvert,
        [switch]$ConvertOptional
    )

    if (-not $Catalog) { $Catalog = Get-DependencyCatalog }
    $resolved = New-Object System.Collections.Generic.List[object]
    $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($v in @($VisitedModIds)) { if ($v) { [void]$visited.Add($v) } }

    foreach ($rec in $Records) {
        $id = $rec.ModId
        if ($visited.Contains($id)) {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'skip' -Status 'visited' -Note 'Already handled in this run')) | Out-Null
            continue
        }
        $entry = Get-CatalogEntry -Catalog $Catalog -ModId $id
        if ($entry -and $entry.Kind -eq 'skip') {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'skip' -Status 'platform' -Note 'Minecraft/loader platform dep')) | Out-Null
            continue
        }

        $actionHint = 'official-or-convert'
        $modrinthSlug = $id
        $mavenCoord = ''
        $repos = @()
        $tomlRange = $rec.VersionRange
        if ($entry -and $entry.Kind -eq 'never-convert') {
            $actionHint = 'never-convert'
            if ($entry.Modrinth) { $modrinthSlug = $entry.Modrinth }
        } elseif ($entry -and $entry.modId) {
            $actionHint = $entry.action
            if ($entry.modrinth) { $modrinthSlug = $entry.modrinth }
            if ($entry.maven) {
                $mavenCoord = [string]$entry.maven.coordinate
                $repos = @($entry.maven.repositories)
            }
            if ($entry.tomlVersionRange) { $tomlRange = $entry.tomlVersionRange }
        }

        # --- official maven ---
        if ($mavenCoord -and -not $SkipDownload) {
            $jar = Save-MavenArtifact -Coordinate $mavenCoord -Repositories $repos -DestDir $CacheDir
            if ($jar) {
                if (-not (Test-Path $LibsDir)) { New-Item -ItemType Directory -Path $LibsDir -Force | Out-Null }
                $libCopy = Join-Path $LibsDir (Split-Path $jar -Leaf)
                Copy-Item -LiteralPath $jar -Destination $libCopy -Force
                [void]$visited.Add($id)
                $resolved.Add((New-ResolvedDependency -Record $rec -Action 'maven' -Status 'downloaded' -Note 'Official Maven 26.2 artifact' -MavenCoord $mavenCoord -Repositories $repos -TomlRange $tomlRange -JarPath $libCopy -ModrinthSlug $modrinthSlug)) | Out-Null
                continue
            }
        } elseif ($mavenCoord -and $SkipDownload) {
            [void]$visited.Add($id)
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'maven' -Status 'mapped' -Note 'Maven coordinate mapped (download skipped)' -MavenCoord $mavenCoord -Repositories $repos -TomlRange $tomlRange -ModrinthSlug $modrinthSlug)) | Out-Null
            continue
        }

        # --- CurseMaven (known 26.2 file id) ---
        $curseCoord = ''
        if ($entry -and $entry.curseMaven) { $curseCoord = [string]$entry.curseMaven }
        if ($curseCoord -and $curseCoord -match '^curse\.maven:([^:]+):(\d+)$' -and -not $SkipDownload) {
            $cSlug = $Matches[1]
            $cFile = $Matches[2]
            $cName = "$cSlug-$cFile.jar"
            $cUrl = "https://www.cursemaven.com/curse/maven/$cSlug/$cFile/$cName"
            $cDest = Join-Path $CacheDir $cName
            if (Save-HttpFile -Url $cUrl -Dest $cDest) {
                if (-not (Test-Path $LibsDir)) { New-Item -ItemType Directory -Path $LibsDir -Force | Out-Null }
                $libCopy = Join-Path $LibsDir $cName
                Copy-Item -LiteralPath $cDest -Destination $libCopy -Force
                [void]$visited.Add($id)
                $resolved.Add((New-ResolvedDependency -Record $rec -Action 'cursemaven' -Status 'downloaded' -Note "Official 26.2 jar via CurseMaven $curseCoord" -MavenCoord $curseCoord -Repositories @('https://www.cursemaven.com/') -TomlRange $tomlRange -JarPath $libCopy -ModrinthSlug $modrinthSlug)) | Out-Null
                continue
            }
        }

        # --- Modrinth official 26.2 NeoForge (then Forge 26.2) ---
        $proj = $null
        if (-not $SkipDownload) {
            $proj = Find-ModrinthProject -ModId $id -PreferredSlug $modrinthSlug
        }
        if ($proj) {
            $slug = $(if ($proj.slug) { [string]$proj.slug } else { $modrinthSlug })
            $file = Find-ModrinthVersionFile -ProjectIdOrSlug $slug -GameVersion $MinecraftVersion -Loaders @('neoforge', 'forge')
            if ($file) {
                $dest = Join-Path $CacheDir $file.FileName
                $ok = $true
                if (-not $SkipDownload) { $ok = Save-HttpFile -Url $file.Url -Dest $dest }
                if ($ok -and (Test-Path -LiteralPath $dest)) {
                    if (-not (Test-Path $LibsDir)) { New-Item -ItemType Directory -Path $LibsDir -Force | Out-Null }
                    $libCopy = Join-Path $LibsDir $file.FileName
                    Copy-Item -LiteralPath $dest -Destination $libCopy -Force
                    [void]$visited.Add($id)
                    $resolved.Add((New-ResolvedDependency -Record $rec -Action 'modrinth' -Status 'downloaded' -Note "Official $MinecraftVersion $($file.Loader) jar from Modrinth $($file.Version)" -TomlRange $tomlRange -JarPath $libCopy -ModrinthSlug $slug)) | Out-Null
                    continue
                }
            }
        }

        if ($actionHint -eq 'never-convert' -or $actionHint -eq 'official') {
            $why = if ($entry -and $entry.Reason) { $entry.Reason } else { 'No official NeoForge 26.2 artifact found; auto-convert is disabled for this library.' }
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'gap' -Status 'missing-official' -Note $why -ModrinthSlug $modrinthSlug -TomlRange $tomlRange)) | Out-Null
            continue
        }

        if (-not $rec.Required -and -not $ConvertOptional) {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'optional-gap' -Status 'skipped-optional' -Note 'Optional dependency; pass -ConvertOptionalDependencies to convert/download' -ModrinthSlug $modrinthSlug)) | Out-Null
            continue
        }

        if ($SkipConvert -or $DependencyDepth -ge $MaxDependencyDepth) {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'gap' -Status 'needs-convert' -Note "No 26.2 artifact. Conversion skipped (depth $DependencyDepth / max $MaxDependencyDepth or -SkipDependencyConvert)." -ModrinthSlug $modrinthSlug)) | Out-Null
            continue
        }

        # --- convert 1.20.1 jar ---
        $srcJar = Find-LocalDependencyJar -ModId $id -SearchDirs $LocalJarDirs
        if (-not $srcJar -and -not $SkipDownload) {
            if (-not $proj) { $proj = Find-ModrinthProject -ModId $id -PreferredSlug $modrinthSlug }
            if ($proj) {
                $slug = $(if ($proj.slug) { [string]$proj.slug } else { $modrinthSlug })
                $old = Find-ModrinthVersionFile -ProjectIdOrSlug $slug -GameVersion '1.20.1' -Loaders @('forge', 'neoforge')
                if ($old) {
                    $dest = Join-Path $CacheDir $old.FileName
                    if (Save-HttpFile -Url $old.Url -Dest $dest) { $srcJar = $dest }
                }
            }
        }

        if (-not $srcJar) {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'gap' -Status 'needs-jar' -Note 'No 26.2 artifact and no 1.20.1 jar found locally or on Modrinth. Place the Forge 1.20.1 jar in -DependencyJarDir.' -ModrinthSlug $modrinthSlug)) | Out-Null
            continue
        }

        if (-not $ConvertJarScript -or -not (Test-Path -LiteralPath $ConvertJarScript)) {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'gap' -Status 'needs-convert' -Note "Found 1.20.1 jar but converter script missing: $srcJar" -JarPath $srcJar)) | Out-Null
            continue
        }

        if (-not (Test-Path $ConvertedDepsDir)) { New-Item -ItemType Directory -Path $ConvertedDepsDir -Force | Out-Null }
        $depOut = Join-Path $ConvertedDepsDir "$id-26.2"
        $decompileOut = Join-Path $ConvertedDepsDir "$id-decompiled"
        if (Test-Path -LiteralPath $depOut) {
            $existing = @(Get-ChildItem -LiteralPath $depOut -Force -ErrorAction SilentlyContinue)
            if ($existing.Count -gt 0 -and -not (Test-Path (Join-Path $depOut 'build.gradle'))) {
                $resolved.Add((New-ResolvedDependency -Record $rec -Action 'gap' -Status 'blocked' -Note "Output folder not empty and not a converted project: $depOut")) | Out-Null
                continue
            }
        }

        [void]$visited.Add($id)
        Write-Host "    Converting required dependency '$id' from $srcJar" -ForegroundColor Cyan
        $visitedArg = (($visited | ForEach-Object { $_ }) -join ',')
        $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$ConvertJarScript`" -JarPath `"$srcJar`" -OutputPath `"$depOut`" -DecompilePath `"$decompileOut`" -MinecraftVersion `"$MinecraftVersion`" -NeoVersion `"$NeoVersion`" -GeckoLibVersion `"$GeckoLibVersion`" -DependencyDepth $($DependencyDepth + 1) -MaxDependencyDepth $MaxDependencyDepth -VisitedModIds `"$visitedArg`" -KeepDecompile"
        if ($SkipDownload) { $argLine += ' -SkipDependencyDownload' }
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Wait -PassThru -NoNewWindow
        $code = $proc.ExitCode
        $builtJar = $null
        if ($code -ne 0 -or -not (Test-Path (Join-Path $depOut 'build.gradle'))) {
            $resolved.Add((New-ResolvedDependency -Record $rec -Action 'gap' -Status 'blocked' -Note "Dependency conversion failed (exit $code); no usable Gradle project was produced from $srcJar" -ConvertedProject '')) | Out-Null
            continue
        }
        if (Test-Path (Join-Path $depOut 'build.gradle')) {
            $libs = Join-Path $depOut 'build\libs'
            if (-not (Test-Path $libs)) {
                $gw = Join-Path $depOut 'gradlew.bat'
                if (Test-Path $gw) {
                    Write-Host "    Building converted dependency $id (gradlew jar)" -ForegroundColor DarkCyan
                    Push-Location $depOut
                    try {
                        cmd /c "gradlew.bat jar --no-daemon --stacktrace > dependency-build.log 2>&1"
                    } finally { Pop-Location }
                }
            }
            if (Test-Path $libs) {
                $builtJar = Get-ChildItem -LiteralPath $libs -Filter '*.jar' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch 'sources|javadoc' } |
                    Select-Object -First 1
            }
        }
        $libCopy = ''
        if ($builtJar) {
            if (-not (Test-Path $LibsDir)) { New-Item -ItemType Directory -Path $LibsDir -Force | Out-Null }
            $libCopy = Join-Path $LibsDir $builtJar.Name
            Copy-Item -LiteralPath $builtJar.FullName -Destination $libCopy -Force
        }
        $note = "Converted Forge 1.20.1 jar -> NeoForge 26.2 (converter exit $code)"
        if (-not $libCopy) { $note += '. Project scaffolded but jar build did not produce build/libs; compile the converted-deps project manually.' }
        $resolved.Add((New-ResolvedDependency -Record $rec -Action 'convert' -Status $(if ($libCopy) { 'converted-jar' } else { 'converted-scaffold' }) -Note $note -JarPath $libCopy -ConvertedProject $depOut -TomlRange '[1.0,)' -ModrinthSlug $modrinthSlug)) | Out-Null
    }

    return $resolved.ToArray()
}

function New-DependencyGradlePlan {
    param($Resolved)
    $impl = New-Object System.Collections.Generic.List[string]
    $toml = New-Object System.Collections.Generic.List[string]
    $repos = New-Object System.Collections.Generic.List[string]
    $includes = New-Object System.Collections.Generic.List[string]
    $repoSeen = @{}
    $modSeen = @{}

    foreach ($d in $Resolved) {
        if ($d.Action -in @('skip') -or $d.Status -in @('platform', 'visited')) { continue }
        if ($d.Status -in @('missing-official', 'needs-convert', 'needs-jar', 'blocked', 'skipped-optional')) { continue }

        if ($d.MavenCoord) {
            $impl.Add("    implementation `"$($d.MavenCoord)`"") | Out-Null
            foreach ($r in @($d.Repositories)) {
                if (-not $r) { continue }
                $key = $r.TrimEnd('/').ToLowerInvariant()
                if (-not $repoSeen.ContainsKey($key)) {
                    $repoSeen[$key] = $true
                    $safeName = ($d.ModId -replace '[^a-zA-Z0-9]', '')
                    $repos.Add(@"
    maven {
        name = '$safeName'
        url = '$($r.TrimEnd('/'))/'
    }
"@) | Out-Null
                }
            }
        } elseif ($d.JarPath) {
            $leaf = Split-Path $d.JarPath -Leaf
            $impl.Add("    implementation files('libs/$leaf')") | Out-Null
        }

        if ($d.ConvertedProject -and -not $d.JarPath) {
            $rel = 'converted-deps/' + (Split-Path $d.ConvertedProject -Leaf)
            $includes.Add("includeBuild '$rel'") | Out-Null
        }

        if ($d.ModId -and -not $modSeen.ContainsKey($d.ModId)) {
            $modSeen[$d.ModId] = $true
            $range = $d.TomlVersionRange
            if (-not $range) { $range = '[1.0,)' }
            $toml.Add(@"

[[dependencies.`${mod_id}]]
modId="$($d.ModId)"
type="required"
versionRange="$range"
ordering="AFTER"
side="BOTH"
"@) | Out-Null
        }
    }

    if ($impl.Count -eq 0) {
        $impl.Add('    // No extra mod dependencies detected') | Out-Null
    }

    return [pscustomobject]@{
        ImplementationBlock = ($impl -join "`r`n")
        TomlBlock           = ($toml -join "`r`n")
        RepositoryBlock     = ($repos -join "`r`n")
        IncludeBuildBlock   = ($includes -join "`r`n")
    }
}

function Write-DependencyReport {
    param(
        [string]$Path,
        $Records,
        $Resolved
    )
    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add('# Dependency report') | Out-Null
    $rows.Add('') | Out-Null
    $rows.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')") | Out-Null
    $rows.Add('') | Out-Null
    $rows.Add('The converter reads `mods.toml` / `neoforge.mods.toml`, Gradle coordinates, jar-in-jar metadata, and Java imports.') | Out-Null
    $rows.Add('Official NeoForge 26.2 artifacts are downloaded. Required mods with no 26.2 build are decompiled and converted.') | Out-Null
    $rows.Add('') | Out-Null
    $rows.Add('| Mod ID | Required | Action | Status | Detail |') | Out-Null
    $rows.Add('|--------|----------|--------|--------|--------|') | Out-Null
    foreach ($d in $Resolved) {
        $detail = ([string]$d.Note) -replace '\|', '/'
        if ($d.MavenCoord) { $detail += " ($($d.MavenCoord))" }
        if ($d.JarPath) { $detail += " jar=$(Split-Path $d.JarPath -Leaf)" }
        $rows.Add("| $($d.ModId) | $($d.Required) | $($d.Action) | $($d.Status) | $detail |") | Out-Null
    }
    $gaps = @($Resolved | Where-Object { $_.Status -in @('missing-official', 'needs-convert', 'needs-jar', 'blocked') })
    if ($null -eq $gaps) { $gaps = @() }
    $rows.Add('') | Out-Null
    $rows.Add('## Gaps') | Out-Null
    $rows.Add('') | Out-Null
    if ($gaps.Count -eq 0) {
        $rows.Add('- None recorded.') | Out-Null
    } else {
        foreach ($g in $gaps) {
            $rows.Add("- **$($g.ModId)** ($($g.Status)): $($g.Note)") | Out-Null
        }
        $rows.Add('') | Out-Null
        $rows.Add('Place missing 1.20.1 jars in `-DependencyJarDir` and re-run, or wait for an official 26.2 port.') | Out-Null
    }
    $rows.Add('') | Out-Null
    $rows.Add('## Detected (pre-resolve)') | Out-Null
    $rows.Add('') | Out-Null
    foreach ($r in $Records) {
        $rows.Add("- $($r.ModId) required=$($r.Required) source=$($r.Source) $($r.VersionRange)") | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, (($rows -join "`r`n") + "`r`n"))
}

function Write-DetectedDependenciesJson {
    param([string]$Path, $Records)
    $payload = @(@($Records) | ForEach-Object {
            [pscustomobject]@{
                ModId        = $_.ModId
                Required     = $_.Required
                VersionRange = $_.VersionRange
                Source       = $_.Source
            }
        })
    # -InputObject preserves the JSON array even when there is one record.
    ConvertTo-Json -InputObject $payload -Depth 4 | Set-Content -Path $Path -Encoding UTF8
}
