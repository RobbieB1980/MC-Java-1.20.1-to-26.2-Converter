<#
.SYNOPSIS
  Experimental converter: Minecraft Forge 1.20.1 workspace -> NeoForge 26.2 scaffold.

.DESCRIPTION
  Copies the project, rewrites Gradle to ModDevGradle 26.2, maps known deps
  (GeckoLib, SmartBrainLib), applies mechanical Forge->NeoForge renames, and
  optionally runs compileJava to produce an error report.

  This is NOT a full automatic port. Expect many remaining compile errors on
  large mods. Goal of v1: runnable Gradle + modern deps + first-pass rewrites.

.EXAMPLE
  .\Convert-Forge1201-ToNeoForge262.ps1 -Path "F:\Grok Build Apps\Legacy\friend-main" -OutputPath "F:\Grok Build Apps\Friend-26.2" -Compile
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$MinecraftVersion = '26.2',
    [string]$NeoVersion = '26.2.0.66',
    [string]$ModDevGradleVersion = '2.0.144',
    [string]$GeckoLibVersion = '5.5.3',
    [string]$SmartBrainLibVersion = '2.0.0',
    [string]$LocalLibDir = '',
    [int]$DependencyDepth = 0,
    [int]$MaxDependencyDepth = 2,
    [string]$VisitedModIds = '',
    [string[]]$DependencyJarDir = @(),
    [switch]$SkipDependencyConvert,
    [switch]$SkipDependencyDownload,
    [switch]$ConvertOptionalDependencies,
    [switch]$Compile,
    [switch]$DryRun,
    [string]$OriginalJarPath = '',
    [string]$SourceVersion = ''
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot
. (Join-Path $ToolRoot 'lib\ModDependencyPipeline.ps1')
. (Join-Path $ToolRoot 'lib\ConversionCore.ps1')

function Write-Step([string]$m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m) { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn2([string]$m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Info([string]$m) { Write-Host "    $m" }

function Convert-DisplayClientMessageCalls {
    param([string]$Text)
    $needle = '.displayClientMessage('
    $guard = 0
    while ($guard -lt 50) {
        $i = $Text.IndexOf($needle)
        if ($i -lt 0) { break }
        $start = $i + $needle.Length
        $depth = 1
        $j = $start
        while ($j -lt $Text.Length -and $depth -gt 0) {
            $c = $Text[$j]
            if ($c -eq [char]'(') { $depth++ }
            elseif ($c -eq [char]')') { $depth-- }
            $j++
        }
        if ($depth -ne 0) { break }
        $args = $Text.Substring($start, $j - $start - 1)
        $args2 = [regex]::Replace($args, ',\s*(?:true|false)\s*$', '')
        $Text = $Text.Substring(0, $i) + '.sendSystemMessage(' + $args2 + ')' + $Text.Substring($j)
        $guard++
    }
    return $Text
}

function Copy-ProjectTree {
    param([string]$Source, [string]$Dest)
    $exclude = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('build', 'run', 'run-data', '.gradle', '.git', 'bin', 'out', '.idea', 'converted-deps', 'libs'),
        [StringComparer]::OrdinalIgnoreCase
    )
    if (Test-Path -LiteralPath $Dest) {
        $items = @(Get-ChildItem -LiteralPath $Dest -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) { throw "Output folder not empty: $Dest" }
    }
    else {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }
    $count = 0
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Source)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $rel = if ($cur.Length -le $Source.Length) { '' } else { $cur.Substring($Source.Length).TrimStart('\', '/') }
        $destDir = if ($rel) { Join-Path $Dest $rel } else { $Dest }
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        foreach ($item in Get-ChildItem -LiteralPath $cur -Force -ErrorAction SilentlyContinue) {
            if ($item.PSIsContainer) {
                if ($exclude.Contains($item.Name)) { continue }
                $stack.Push($item.FullName)
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $destDir $item.Name) -Force
                $count++
            }
        }
    }
    return $count
}

function Get-ModMetaFromSource {
    param([string]$Root)
    $meta = @{
        mod_id      = 'examplemod'
        mod_name    = 'Example Mod'
        mod_version = '1.0.0'
        mod_group   = 'com.example'
        mod_authors = 'Unknown'
        mod_license = 'All Rights Reserved'
        mod_desc    = 'Converted from Forge 1.20.1'
    }
    $folder = Split-Path $Root -Leaf
    $meta.mod_id = ($folder -replace '[^a-z0-9_]', '').ToLower()
    if ($meta.mod_id.Length -lt 2) { $meta.mod_id = 'friend' }

    $gp = Join-Path $Root 'gradle.properties'
    if (Test-Path $gp) {
        foreach ($line in Get-Content $gp) {
            if ($line -match '^\s*mod_version\s*=\s*(.+)$') { $meta.mod_version = $Matches[1].Trim() }
            if ($line -match '^\s*mod_id\s*=\s*(.+)$') { $meta.mod_id = $Matches[1].Trim() }
            if ($line -match '^\s*mod_name\s*=\s*(.+)$') { $meta.mod_name = $Matches[1].Trim() }
            if ($line -match '^\s*mod_authors\s*=\s*(.+)$') { $meta.mod_authors = $Matches[1].Trim() }
            if ($line -match '^\s*mod_license\s*=\s*(.+)$') { $meta.mod_license = $Matches[1].Trim() }
        }
    }
    # Prefer display metadata from existing NeoForge/Forge toml (jar decompile / NeoForge 1.21.x)
    foreach ($rel in @(
            'src\main\resources\META-INF\neoforge.mods.toml',
            'src\main\resources\META-INF\mods.toml',
            'META-INF\neoforge.mods.toml'
        )) {
        $toml = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $toml)) { continue }
        $tt = Get-Content -LiteralPath $toml -Raw -ErrorAction SilentlyContinue
        if (-not $tt) { continue }
        if ($tt -match '(?m)^\s*modId\s*=\s*"([^"]+)"') { $meta.mod_id = $Matches[1] }
        if ($tt -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $meta.mod_version = $Matches[1] }
        if ($tt -match '(?m)^\s*displayName\s*=\s*"([^"]+)"') { $meta.mod_name = $Matches[1] }
        if ($tt -match '(?m)^\s*authors\s*=\s*"([^"]+)"') { $meta.mod_authors = $Matches[1] }
        if ($tt -match '(?m)^\s*license\s*=\s*"([^"]+)"') { $meta.mod_license = $Matches[1] }
        break
    }
    $bg = Join-Path $Root 'build.gradle'
    if (Test-Path $bg) {
        $t = Get-Content $bg -Raw
        if ($t -match "group\s*=\s*'([^']+)'") { $meta.mod_group = $Matches[1] }
        if ($t -match "archivesName\s*=\s*'([^']+)'") {
            $meta.mod_id = $Matches[1]
            $meta.mod_name = $Matches[1]
        }
        if ($t -match "mod_name\s*:\s*'([^']+)'") { $meta.mod_name = $Matches[1] }
        if ($t -match "mod_authors\s*:\s*'([^']+)'") { $meta.mod_authors = $Matches[1] }
        if ($t -match "mod_description\s*:\s*'([^']+)'") { $meta.mod_desc = $Matches[1] }
        if ($t -match "mod_license\s*:\s*'([^']+)'") { $meta.mod_license = $Matches[1] }
        if ($t -match "mod_id\s*:\s*'([^']+)'") { $meta.mod_id = $Matches[1] }
    }
    $java = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -ErrorAction SilentlyContinue |
        Select-String -Pattern '@Mod\(' -List | Select-Object -First 1
    if ($java) {
        $pkg = Select-String -Path $java.Path -Pattern '^package\s+([\w\.]+);' | Select-Object -First 1
        if ($pkg) { $meta.mod_group = $pkg.Matches[0].Groups[1].Value }
    }
    return $meta
}

function Test-SourceNeedsLibrary {
    param([string]$Root, [string]$Pattern)
    $hit = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $Pattern -SimpleMatch:$false -List | Select-Object -First 1
    return [bool]$hit
}

function Write-GradleScaffold {
    param(
        [string]$Root,
        [hashtable]$Meta,
        [string]$LocalLibs,
        $DepPlan = $null
    )

    $props = @"
# Generated by Convert-Forge1201-ToNeoForge262 (experimental)
org.gradle.jvmargs=-Xmx4G
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=false

minecraft_version=$MinecraftVersion
minecraft_version_range=[$MinecraftVersion]
neo_version=$NeoVersion

mod_id=$($Meta.mod_id)
mod_name=$($Meta.mod_name)
mod_license=$($Meta.mod_license)
mod_version=$($Meta.mod_version)+mc$MinecraftVersion-neoforge
mod_group_id=$($Meta.mod_group)
mod_authors=$($Meta.mod_authors)
mod_description=$($Meta.mod_desc)

geckolib_version=$GeckoLibVersion
smartbrainlib_version=$SmartBrainLibVersion
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'gradle.properties'), $props.Trim() + "`r`n")

    $settings = @"
pluginManagement {
    repositories {
        gradlePluginPortal()
        maven { url = 'https://maven.neoforged.net/releases' }
        mavenCentral()
    }
}

plugins {
    id 'org.gradle.toolchains.foojay-resolver-convention' version '1.0.0'
}

rootProject.name = '$($Meta.mod_id)-neoforge-$MinecraftVersion'
$(if ($DepPlan -and $DepPlan.IncludeBuildBlock) { "`r`n$($DepPlan.IncludeBuildBlock)" } else { '' })
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'settings.gradle'), $settings.Trim() + "`r`n")

    $localRepoBlock = ''
    if ($LocalLibs -and (Test-Path $LocalLibs)) {
        $localPath = $LocalLibs.Replace('\', '/')
        $localRepoBlock = @"

    // Local pre-downloaded dependency jars (optional fallback)
    flatDir {
        dirs '$localPath'
    }
"@
    }

    # Extra implementation / toml / maven repos come from the dependency pipeline.
    $extraImpl = '    // No extra mod dependencies detected'
    $extraToml = ''
    $extraRepos = ''
    if ($DepPlan) {
        if ($DepPlan.ImplementationBlock) { $extraImpl = $DepPlan.ImplementationBlock }
        if ($DepPlan.TomlBlock) { $extraToml = $DepPlan.TomlBlock }
        if ($DepPlan.RepositoryBlock) { $extraRepos = $DepPlan.RepositoryBlock }
    }

    $build = @"
plugins {
    id 'java-library'
    id 'maven-publish'
    id 'net.neoforged.moddev' version '$ModDevGradleVersion'
    id 'idea'
}

tasks.named('wrapper', Wrapper).configure {
    distributionType = Wrapper.DistributionType.BIN
}

version = mod_version
group = mod_group_id

base {
    archivesName = mod_id
}

java.toolchain.languageVersion = JavaLanguageVersion.of(25)

sourceSets.main.resources {
    srcDir('src/generated/resources')
}

neoForge {
    version = project.neo_version

    runs {
        client {
            client()
            systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id
        }
        server {
            server()
            programArgument '--nogui'
        }
        configureEach {
            systemProperty 'forge.logging.markers', 'REGISTRIES'
            logLevel = org.slf4j.event.Level.DEBUG
        }
    }

    mods {
        "`${mod_id}" {
            sourceSet(sourceSets.main)
        }
    }
}

repositories {
    mavenCentral()
    maven { url = 'https://maven.neoforged.net/releases' }
    maven {
        name = 'GeckoLib'
        url = 'https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/'
        content { includeGroupAndSubgroups('com.geckolib') }
    }
    maven {
        name = 'Tslat'
        url = 'https://dl.cloudsmith.io/public/tslat/tslat/maven/'
    }
    maven {
        name = 'BlameJared'
        url = 'https://maven.blamejared.com'
    }
    maven {
        name = 'Modrinth'
        url = 'https://api.modrinth.com/maven'
    }
    flatDir {
        dirs 'libs'
    }
$extraRepos
$localRepoBlock
}

dependencies {
$extraImpl
}

var generateModMetadata = tasks.register('generateModMetadata', ProcessResources) {
    var replaceProperties = [
            minecraft_version      : minecraft_version,
            minecraft_version_range: minecraft_version_range,
            neo_version            : neo_version,
            mod_id                 : mod_id,
            mod_name               : mod_name,
            mod_license            : mod_license,
            mod_version            : mod_version,
            mod_authors            : mod_authors,
            mod_description        : mod_description,
            geckolib_version       : geckolib_version,
            smartbrainlib_version  : smartbrainlib_version
    ]
    inputs.properties replaceProperties
    expand replaceProperties
    from 'src/main/templates'
    into 'build/generated/sources/modMetadata'
}

sourceSets.main.resources.srcDir generateModMetadata
neoForge.ideSyncTask generateModMetadata

tasks.withType(JavaCompile).configureEach {
    options.encoding = 'UTF-8'
    options.release = 25
}

idea {
    module {
        downloadSources = true
        downloadJavadoc = true
    }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'build.gradle'), $build.Trim() + "`r`n")

    $tomlDir = Join-Path $Root 'src\main\templates\META-INF'
    New-Item -ItemType Directory -Path $tomlDir -Force | Out-Null
    $toml = @"
modLoader="javafml"
loaderVersion="[4,)"
license="`${mod_license}"

[[mods]]
modId="`${mod_id}"
version="`${mod_version}"
displayName="`${mod_name}"
authors="`${mod_authors}"
description='''`${mod_description}'''

[[dependencies.`${mod_id}]]
modId="neoforge"
type="required"
versionRange="[`${neo_version},)"
ordering="NONE"
side="BOTH"

[[dependencies.`${mod_id}]]
modId="minecraft"
type="required"
versionRange="`${minecraft_version_range}"
ordering="NONE"
side="BOTH"
$extraToml
"@
    [System.IO.File]::WriteAllText((Join-Path $tomlDir 'neoforge.mods.toml'), $toml.Trim() + "`r`n")

    $pack = @"
{
  "pack": {
    "min_format": 107,
    "max_format": 107,
    "description": "$($Meta.mod_name) $MinecraftVersion"
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'src\main\resources\pack.mcmeta'), $pack.Trim() + "`r`n")

    # Remove legacy/source mod metadata from resources so generated templates win.
    # Critical: NeoForge 1.21.x jars leave neoforge.mods.toml with old minecraft versionRange
    # (e.g. [1.21.8]) which causes loader rejection even when the scaffold targets 26.2.
    $metaInf = Join-Path $Root 'src\main\resources\META-INF'
    foreach ($name in @('mods.toml', 'neoforge.mods.toml', 'mods.toml.template', 'MANIFEST.MF')) {
        $p = Join-Path $metaInf $name
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
            Write-Info "Removed resources/META-INF/$name (using templates/neoforge.mods.toml)"
        }
    }
    if ((Test-Path -LiteralPath $metaInf) -and -not (Get-ChildItem -LiteralPath $metaInf -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Remove-Item -LiteralPath $metaInf -Force -ErrorAction SilentlyContinue
    }
}

function Get-Srg1201Map {
    if ($script:Srg1201Map) { return $script:Srg1201Map }
    $map = @{}
    foreach ($name in @('Srg1201Official.json', 'Srg1201Common.json')) {
        $p = Join-Path $ToolRoot "lib\$name"
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $obj = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $obj.PSObject.Properties) {
            $map[$prop.Name] = [string]$prop.Value
        }
    }
    $script:Srg1201Map = $map
    Write-Info ("SRG map entries: {0}" -f $map.Count)
    return $map
}

function Invoke-MechanicalJavaRewrites {
    param([string]$Root)

    $srgMap = Get-Srg1201Map
    $srgEval = {
        param($m)
        $k = $m.Value
        if ($srgMap.ContainsKey($k)) { return $srgMap[$k] }
        return $k
    }
    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    $cutoutIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t
        foreach ($m in [regex]::Matches($t, 'ItemBlockRenderTypes\.setRenderLayer\([^;]*?ModBlocks\.([A-Z0-9_]+)[^;]*?ChunkSectionLayer\.CUTOUT\s*\)')) {
            [void]$cutoutIds.Add($m.Groups[1].Value.ToLowerInvariant())
        }

        # --- MCreator 1.20.1 Vineflower: broken nearest-entity comparator ---
        $t = [regex]::Replace($t,
            '\.stream\(\)\.sorted\(\(\(<undefinedtype>\)\(new Object\(\)\s*\{[\s\S]*?compareDistOf\((\w+),\s*(\w+),\s*(\w+)\)\)\.findFirst\(\)\.orElse\(\(Object\)null\)',
            '.stream().sorted(Comparator.comparingDouble(_e -> _e.distanceToSqr($1, $2, $3))).findFirst().orElse(null)')

        if ($srgMap.Count -gt 0) {
            $t = [regex]::Replace($t, '\b[fm]_\d+_\b', $srgEval)
        }

        # --- Forge packages -> NeoForge (order matters: specific before broad) ---
        $t = $t -replace 'net\.minecraftforge\.fml\.common\.Mod\.EventBusSubscriber', 'net.neoforged.fml.common.EventBusSubscriber'
        $t = $t -replace 'net\.minecraftforge\.fml\.common\.Mod', 'net.neoforged.fml.common.Mod'
        $t = $t -replace 'net\.neoforged\.fml\.common\.Mod\.EventBusSubscriber', 'net.neoforged.fml.common.EventBusSubscriber'
        $t = $t -replace 'net\.minecraftforge\.fml\.javafmlmod\.FMLJavaModLoadingContext', 'net.neoforged.fml.javafmlmod.FMLJavaModLoadingContext'
        $t = $t -replace 'net\.minecraftforge\.fml\.ModLoadingContext', 'net.neoforged.fml.ModLoadingContext'
        $t = $t -replace 'net\.minecraftforge\.fml\.config\.ModConfig', 'net.neoforged.fml.config.ModConfig'
        $t = $t -replace 'net\.minecraftforge\.common\.ForgeConfigSpec', 'net.neoforged.neoforge.common.ModConfigSpec'
        $t = $t -replace '\bForgeConfigSpec\b', 'ModConfigSpec'
        $t = $t -replace 'net\.minecraftforge\.api\.distmarker\.Dist', 'net.neoforged.api.distmarker.Dist'
        $t = $t -replace 'net\.minecraftforge\.eventbus\.api', 'net.neoforged.bus.api'
        $t = $t -replace 'net\.minecraftforge\.eventbus\.api\.SubscribeEvent', 'net.neoforged.bus.api.SubscribeEvent'
        $t = $t -replace 'net\.minecraftforge\.eventbus\.api\.IEventBus', 'net.neoforged.bus.api.IEventBus'
        $t = $t -replace 'net\.minecraftforge\.event\.entity\.EntityAttributeCreationEvent', 'net.neoforged.neoforge.event.entity.EntityAttributeCreationEvent'
        $t = $t -replace 'net\.minecraftforge\.client\.event\.EntityRenderersEvent', 'net.neoforged.neoforge.client.event.EntityRenderersEvent'
        $t = $t -replace 'net\.minecraftforge\.client\.event\.ViewportEvent', 'net.neoforged.neoforge.client.event.ViewportEvent'
        $t = $t -replace 'net\.minecraftforge\.client\.event\.', 'net.neoforged.neoforge.client.event.'
        $t = $t -replace 'net\.minecraftforge\.event\.entity\.living\.', 'net.neoforged.neoforge.event.entity.living.'
        $t = $t -replace 'net\.minecraftforge\.event\.entity\.player\.', 'net.neoforged.neoforge.event.entity.player.'
        $t = $t -replace 'net\.minecraftforge\.event\.level\.', 'net.neoforged.neoforge.event.level.'
        $t = $t -replace 'net\.minecraftforge\.common\.MinecraftForge', 'net.neoforged.neoforge.common.NeoForge'
        $t = $t -replace 'MinecraftForge\.EVENT_BUS', 'NeoForge.EVENT_BUS'
        $t = $t -replace 'net\.minecraftforge\.registries\.DeferredRegister', 'net.neoforged.neoforge.registries.DeferredRegister'
        $t = $t -replace 'net\.minecraftforge\.registries\.RegistryObject', 'net.neoforged.neoforge.registries.DeferredHolder'
        $t = $t -replace 'net\.minecraftforge\.registries\.ForgeRegistries', 'net.minecraft.core.registries.BuiltInRegistries'
        $t = $t -replace '\bForgeRegistries\.SOUND_EVENTS\b', 'BuiltInRegistries.SOUND_EVENT'
        $t = $t -replace '\bForgeRegistries\.BLOCKS\b', 'BuiltInRegistries.BLOCK'
        $t = $t -replace '\bForgeRegistries\.ITEMS\b', 'BuiltInRegistries.ITEM'
        $t = $t -replace '\bForgeRegistries\.ENTITY_TYPES\b', 'BuiltInRegistries.ENTITY_TYPE'
        $t = $t -replace '\bForgeRegistries\.BLOCK_ENTITY_TYPES\b', 'BuiltInRegistries.BLOCK_ENTITY_TYPE'
        $t = $t -replace '\bForgeRegistries\.FEATURES\b', 'BuiltInRegistries.FEATURE'
        $t = $t -replace '\bForgeRegistries\.MOB_EFFECTS\b', 'BuiltInRegistries.MOB_EFFECT'
        # leftover catch-all (after specifics)
        $t = $t -replace 'net\.minecraftforge\.', 'net.neoforged.neoforge.'
        # Fix over-prefix from catch-all (api/fml live under net.neoforged.* not neoforge.*)
        $t = $t -replace 'net\.neoforged\.neoforge\.api\.distmarker', 'net.neoforged.api.distmarker'
        $t = $t -replace 'net\.neoforged\.neoforge\.fml\.', 'net.neoforged.fml.'
        $t = $t -replace 'net\.neoforged\.neoforge\.bus\.', 'net.neoforged.bus.'
        $t = $t -replace 'net\.neoforged\.neoforge\.eventbus\.api', 'net.neoforged.bus.api'

        # --- TickEvent (safe: do NOT map whole TickEvent package to ServerTickEvent) ---
        # Client
        $t = $t -replace 'import\s+net\.minecraftforge\.event\.TickEvent\.Phase;', ''
        $t = $t -replace 'import\s+net\.minecraftforge\.event\.TickEvent;', "import net.neoforged.neoforge.client.event.ClientTickEvent;`r`nimport net.neoforged.neoforge.event.tick.ServerTickEvent;"
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.event\.TickEvent\.Phase;', ''
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.event\.TickEvent;', "import net.neoforged.neoforge.client.event.ClientTickEvent;`r`nimport net.neoforged.neoforge.event.tick.ServerTickEvent;"
        $t = $t -replace 'TickEvent\.ClientTickEvent', 'ClientTickEvent'
        $t = $t -replace 'TickEvent\.ServerTickEvent', 'ServerTickEvent'
        # phase END handlers ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Post events (common 1.20.1 pattern)
        $t = [regex]::Replace($t,
            '(?s)public\s+static\s+void\s+(\w+)\s*\(\s*ClientTickEvent\s+(\w+)\s*\)\s*\{\s*if\s*\(\s*\2\.phase\s*==\s*TickEvent\.Phase\.END\s*\)\s*\{(.*?)\}\s*\}',
            'public static void $1(ClientTickEvent.Post $2) {$3}')
        $t = [regex]::Replace($t,
            '(?s)public\s+static\s+void\s+(\w+)\s*\(\s*ServerTickEvent\s+(\w+)\s*\)\s*\{\s*if\s*\(\s*\2\.phase\s*==\s*TickEvent\.Phase\.END\s*\)\s*\{(.*?)\}\s*\}',
            'public static void $1(ServerTickEvent.Post $2) {$3}')
        $t = [regex]::Replace($t,
            '(?s)public\s+void\s+(\w+)\s*\(\s*ServerTickEvent\s+(\w+)\s*\)\s*\{\s*if\s*\(\s*\2\.phase\s*==\s*TickEvent\.Phase\.END\s*\)\s*\{(.*?)\}\s*\}',
            'public void $1(ServerTickEvent.Post $2) {$3}')
        # Remaining phase checks
        $t = $t -replace 'public void tick\(ServerTickEvent event\)', 'public void tick(ServerTickEvent.Post event)'
        $t = $t -replace '(\w+)\.phase\s*==\s*Phase\.END', 'true /* was $1.phase END */'
        $t = $t -replace '(\w+)\.phase\s*==\s*TickEvent\.Phase\.END', '($1 instanceof ClientTickEvent.Post || $1 instanceof ServerTickEvent.Post)'
        $t = $t -replace '(\w+)\.phase\s*==\s*TickEvent\.Phase\.START', '($1 instanceof ClientTickEvent.Pre || $1 instanceof ServerTickEvent.Pre)'
        $t = $t -replace 'TickEvent\.Phase\.END', '/* END */ true'
        $t = $t -replace 'TickEvent\.Phase\.START', '/* START */ true'

        # Bus subscriber: FORGE bus -> GAME bus
        $t = $t -replace 'Mod\.EventBusSubscriber\.Bus\.FORGE', 'Mod.EventBusSubscriber.Bus.GAME'

        # --- Minecraft 26.x: ResourceLocation renamed to Identifier ---
        $t = $t -replace 'net\.minecraft\.resources\.ResourceLocation', 'net.minecraft.resources.Identifier'
        $t = $t -replace '\bResourceLocation\b', 'Identifier'
        # constructors already converted or: new Identifier(ns, path) / fromNamespaceAndPath
        $t = [regex]::Replace($t, 'new\s+Identifier\(\s*([^,]+)\s*,\s*([^\)]+)\)', 'Identifier.fromNamespaceAndPath($1, $2)')
        # undo double-fromNamespace if we already had fromNamespaceAndPath on Identifier
        $t = $t -replace 'Identifier\.fromNamespaceAndPath', 'Identifier.fromNamespaceAndPath'

        # --- Entity / level accessors (1.20.1 fields -> methods) ---
        # IMPORTANT: never rewrite package paths like net.minecraft.world.level.Level
        # Only rewrite Entity field access: this.level / entity.level
        $t = Convert-LevelClientSideAccess $t
        $t = Convert-NeoForge262ApiMoves $t
        $t = $t -replace '(?m)^\s*import\s+net\.minecraft\.client\.renderer\.ItemBlockRenderTypes;\s*\r?\n', ''
        $t = $t -replace '(?m)^\s*ItemBlockRenderTypes\.setRenderLayer\([^;]+;\s*\r?\n', ''
        # setMaxUpStep removed - comment out whole statement line-ish
        $t = [regex]::Replace($t, '(?m)^(\s*)(.*)\.setMaxUpStep\s*\(([^;]*)\)\s*;\s*$', '$1// LEGACY: $2.setMaxUpStep($3); // removed in 26.x')
        # BlockPos.getCenter -> Vec3.atCenterOf (simple receivers; chained forms handled in 26.2 API pass)
        $t = [regex]::Replace($t, '(?<![\w.])([a-zA-Z_]\w*)\.getCenter\(\)', {
                param($m)
                $recv = $m.Groups[1].Value
                if ($recv -match '^(?i)(visualBox|box|aabb)$') { return $m.Value }
                "net.minecraft.world.phys.Vec3.atCenterOf($recv)"
            })
        # Common chained BlockPos centers: feet.relative(dir).getCenter()
        $t = [regex]::Replace($t,
            '([a-zA-Z_]\w*(?:\([^)]*\))?\.relative\([^)]+\))\.getCenter\(\)',
            'net.minecraft.world.phys.Vec3.atCenterOf($1)')

        # EntityType.Builder.build("id")
        $t = [regex]::Replace($t, '\.build\(\s*"[^"]*"\s*\)', '.build()')

        # --- GeckoLib 4 -> 5 packages ---
        $t = $t -replace 'software\.bernie\.geckolib', 'com.geckolib'
        $t = $t -replace 'com\.geckolib\.core\.animatable\.instance', 'com.geckolib.animatable.instance'
        $t = $t -replace 'com\.geckolib\.core\.animation', 'com.geckolib.animation'
        $t = $t -replace 'com\.geckolib\.animation\.AnimatableManager', 'com.geckolib.animatable.manager.AnimatableManager'
        $t = $t -replace 'com\.geckolib\.core\.object\.PlayState', 'com.geckolib.animation.object.PlayState'
        $t = $t -replace 'com\.geckolib\.cache\.object\.BakedGeoModel', 'com.geckolib.cache.model.BakedGeoModel'
        $t = $t -replace 'com\.geckolib\.animation\.AnimationController\.State', 'com.geckolib.animation.object.PlayState'
        # AnimationController no longer takes animatable as first constructor arg
        $t = $t -replace 'new\s+AnimationController<>\s*\(\s*this\s*,\s*', 'new AnimationController<>('
        $t = $t -replace 'new\s+AnimationController\s*\(\s*this\s*,\s*', 'new AnimationController('
        # Vineflower wraps add(controller) as add(new AnimationController[]{...}) which GeckoLib 5 ignores/mis-bakes
        $t = $t -replace 'data\.add\(new AnimationController\[\]\{new AnimationController\(', 'data.add(new AnimationController<>('
        $t = $t -replace 'controllers\.add\(new AnimationController\[\]\{new AnimationController\(', 'controllers.add(new AnimationController<>('
        $t = $t -replace '\)\}\);(\s*data\.add\(new AnimationController)', ');$1'
        $t = $t -replace 'new AnimationController<>\("([^"]+)", (\d+), this::(\w+)\)\}\);', 'new AnimationController<>("$1", $2, this::$3));'
        # GeoEntityRenderer is now (Animatable, RenderState)
        $t = $t -replace 'extends\s+GeoEntityRenderer<([^,>]+)>', 'extends GeoEntityRenderer<$1, net.minecraft.client.renderer.entity.state.LivingEntityRenderState>'
        # Drop GeckoLib4 preRender / getRenderType overrides (signatures changed)
        $t = [regex]::Replace($t, '(?ms)\s*public\s+RenderType\s+getRenderType\s*\([^)]*\)\s*\{[^}]*\}', '')
        $t = [regex]::Replace($t, '(?ms)\s*public\s+void\s+preRender\s*\([^)]*\)\s*\{[\s\S]*?super\.preRender\([^;]+;\s*\}', '')
        # GeoModel resource methods take GeoRenderState; variant getTexture() cannot stay
        if ($t -match 'extends\s+GeoModel') {
            $t = $t -replace 'public\s+Identifier\s+getModelResource\s*\(\s*(\w+)\s+(\w+)\s*\)',
                'public Identifier getModelResource(com.geckolib.renderer.base.GeoRenderState $2)'
            $t = $t -replace 'public\s+Identifier\s+getTextureResource\s*\(\s*(\w+)\s+(\w+)\s*\)',
                'public Identifier getTextureResource(com.geckolib.renderer.base.GeoRenderState $2)'
            # GeoRenderState has no getTexture(); keep a real default PNG (unknown.png is missing -> purple/black).
            # A later pass substitutes the entity's TEXTURE synched default when present.
            $t = $t -replace '"textures/entities/" \+ \w+\.getTexture\(\) \+ "\.png"', '"textures/entities/toww_reborn.png"'
            $t = $t -replace '"geo/([^"]+)\.geo\.json"', '"$1"'
            $t = $t -replace '"animations/([^"]+)\.animation\.json"', '"$1"'
        }

        # Forge 1.20 PlayMessages client ctor is gone
        $t = [regex]::Replace($t, '(?ms)\s*public\s+\w+\s*\(\s*PlayMessages\.SpawnEntity\s+\w+\s*,\s*Level\s+\w+\s*\)\s*\{[^}]*\}', '')
        $t = $t -replace '(?m)^\s*import net\.neoforged\.neoforge\.network\.PlayMessages;\s*\r?\n', ''
        $t = $t -replace '(?m)^\s*import net\.minecraftforge\.network\.PlayMessages;\s*\r?\n', ''
        $t = [regex]::Replace($t, '(?ms)\s*public\s+Packet(?:<[^>]+>)?\s+getAddEntityPacket\s*\(\s*\)\s*\{\s*return\s+NetworkHooks\.getEntitySpawningPacket\([^;]+;\s*\}', '')
        $t = $t -replace '(?m)^\s*import net\.neoforged\.neoforge\.network\.NetworkHooks;\s*\r?\n', ''

        # DeferredHolder needs (registry type, holder type)
        $t = $t -replace 'DeferredHolder<\s*EntityType<([^>]+)>\s*>', 'DeferredHolder<EntityType<?>, EntityType<$1>>'
        $t = $t -replace 'private static <T extends Entity> DeferredHolder<EntityType<T>>', 'private static <T extends Entity> DeferredHolder<EntityType<?>, EntityType<T>>'
        $t = $t -replace 'DeferredHolder<Block>(?!\s*,)', 'DeferredHolder<Block, Block>'
        $t = $t -replace 'DeferredHolder<Item>(?!\s*,)', 'DeferredHolder<Item, Item>'
        $t = $t -replace 'DeferredHolder<Feature<\?>>(?!\s*,)', 'DeferredHolder<Feature<?>, Feature<?>>'
        $t = $t -replace 'DeferredHolder<SoundEvent>(?!\s*,)', 'DeferredHolder<SoundEvent, SoundEvent>'
        $t = $t -replace 'DeferredHolder<MobEffect>(?!\s*,)', 'DeferredHolder<MobEffect, MobEffect>'
        $t = $t -replace 'DeferredHolder<CreativeModeTab>(?!\s*,)', 'DeferredHolder<CreativeModeTab, CreativeModeTab>'

        # 26.2 synched data builder
        $t = $t -replace 'protected void defineSynchedData\(\)', 'protected void defineSynchedData(net.minecraft.network.syncher.SynchedEntityData.Builder builder)'
        $t = $t -replace 'super\.defineSynchedData\(\)', 'super.defineSynchedData(builder)'
        $t = $t -replace 'this\.entityData\.define\(', 'builder.define('

        # MobType removed
        $t = [regex]::Replace($t, '(?ms)\s*public\s+MobType\s+getMobType\s*\(\s*\)\s*\{[^}]*\}', '')
        $t = $t -replace 'import net\.minecraft\.world\.entity\.MobSpawnType;', 'import net.minecraft.world.entity.EntitySpawnReason;'
        $t = $t -replace '(?<![\w.])MobSpawnType\b', 'EntitySpawnReason'
        $t = $t -replace 'import net\.minecraft\.world\.entity\.MobType;', ''
        $t = $t -replace 'import net\.minecraft\.world\.level\.pathfinder\.BlockPathTypes;', 'import net.minecraft.world.level.pathfinder.PathType;'
        $t = $t -replace '\bBlockPathTypes\b', 'PathType'
        $t = $t -replace 'import net\.minecraft\.world\.entity\.projectile\.AbstractArrow;', 'import net.minecraft.world.entity.projectile.arrow.AbstractArrow;'
        $t = $t -replace 'import net\.minecraft\.world\.entity\.projectile\.ThrownPotion;', 'import net.minecraft.world.entity.projectile.throwableitemprojectile.AbstractThrownPotion;'
        $t = $t -replace 'import net\.minecraft\.world\.entity\.projectile\.thrown\.ThrownPotion;', 'import net.minecraft.world.entity.projectile.throwableitemprojectile.AbstractThrownPotion;'
        $t = $t -replace '\bThrownPotion\b', 'AbstractThrownPotion'
        $t = $t -replace 'import net\.minecraft\.world\.entity\.SpawnPlacements\.Type;', 'import net.minecraft.world.entity.SpawnPlacementTypes;'
        $t = $t -replace 'SpawnPlacements\.Type', 'SpawnPlacementTypes'
        $t = $t -replace 'import com\.mojang\.blaze3d\.platform\.GlStateManager(?:\.\w+)?;', 'import com.mojang.blaze3d.systems.RenderSystem;'
        $t = $t -replace 'import net\.minecraftforge\.network\.simple\.SimpleChannel;', ''
        $t = $t -replace 'import net\.neoforged\.neoforge\.network\.simple\.SimpleChannel;', ''
        $t = $t -replace 'import net\.minecraftforge\.network\.NetworkRegistry;', ''
        $t = $t -replace 'import net\.neoforged\.neoforge\.network\.NetworkRegistry;', ''
        $t = $t -replace 'import net\.minecraftforge\.network\.NetworkEvent;', ''
        $t = $t -replace 'import net\.neoforged\.neoforge\.network\.NetworkEvent;', ''
        $t = [regex]::Replace($t, 'public static final SimpleChannel PACKET_HANDLER = [^;]+;', 'public static final Object PACKET_HANDLER = new Object();')
        $t = [regex]::Replace($t,
            '(?s)public static <T> void addNetworkMessage\([^)]*\)\s*\{[^}]*\}',
            'public static <T> void addNetworkMessage(Class<T> messageType, Object encoder, Object decoder, Object messageConsumer) { /* 26.2 payloads: RegisterPayloadHandlersEvent */ }')
        $t = $t -replace 'com\.geckolib\.animation\.AnimationState', 'com.geckolib.animation.state.AnimationTest'
        $t = $t -replace '\bAnimationState\b', 'AnimationTest'
        $t = $t -replace 'event\.getController\(\)\.getAnimationState\(\)\s*==\s*State\.STOPPED', 'event.controller().getAnimationState() == PlayState.STOP'
        $t = $t -replace 'event\.getController\(\)\.setAnimation\(', 'event.setAnimation('
        $t = $t -replace 'event\.getController\(\)\.forceAnimationReset\(\)', ''
        $t = $t -replace 'event\.controller\(\)\.stop\(\);', ''
        $t = $t -replace 'event\.controller\(\)\.getAnimationState\(\) == PlayState\.STOP', 'true'
        $t = $t -replace 'event\.getController\(\)', 'event.controller()'
        $t = $t -replace '\.create\(serverWorld\)', '.create(serverWorld, EntitySpawnReason.BREEDING)'
        $t = $t -replace 'SoundEvent\.accept\(', 'SoundEvent.createVariableRangeEvent('
        $t = $t -replace 'SoundEvent\.sendSystemMessage\(', 'SoundEvent.createVariableRangeEvent('
        $t = $t -replace 'tabData\.sendSystemMessage\(', 'tabData.accept('
        $t = $t -replace 'SpawnPlacements\.addEffect\(', 'SpawnPlacements.register('
        $t = $t -replace '(?<![\w.])Type\.ON_GROUND', 'net.minecraft.world.entity.SpawnPlacementTypes.ON_GROUND'
        $t = $t -replace 'event\.getLimbSwingAmount\(\)', '0.0F'
        $t = $t -replace 'void m_5993_\(Entity', 'void awardKillScore(Entity'
        $t = $t -replace 'this\.ANIMATION_SPEED', 'this.deathTime'
        $t = $t -replace 'protected void dropCustomDeathLoot\(net\.minecraft\.server\.level\.ServerLevel level, DamageSource (\w+), int \w+, boolean (\w+)\)', 'protected void dropCustomDeathLoot(net.minecraft.server.level.ServerLevel level, DamageSource $1, boolean $2)'
        $t = $t -replace 'super\.m_7472_\([^;]+;', 'super.dropCustomDeathLoot(level, source, recentlyHitIn);'
        $t = $t -replace 'this\.spawnAtLocation\(new ItemStack', 'this.spawnAtLocation(level, new ItemStack'
        $t = $t -replace '\.getType\(serverWorld\)', '.create(serverWorld, EntitySpawnReason.BREEDING)'
        $t = $t -replace 'Builder\.getYRot\(', 'EntityType.Builder.of('
        $t = $t -replace '(?<!EntityType\.)Builder\.of\(', 'EntityType.Builder.of('
        $t = $t -replace '\.setCustomClientFactory\([^)]+\)', ''
        $t = $t -replace '\.getXRot\(\)', ''
        $t = $t -replace '\.getType\(([0-9.F]+),\s*([0-9.F]+)\)', '.sized($1, $2)'
        $t = [regex]::Replace($t, '(?s)public static void init\(\) \{\s*(?:SpawnPlacements\.(?:register|addEffect)\(|// SpawnPlacements\.register\()[\s\S]*?\}\);\s*\}', 'public static void init() { }')
        $t = $t -replace 'boolean canAttackType\(ItemStack stack\)', 'boolean isFood(ItemStack stack)'
        $t = $t -replace 'extends\s+MobRenderer<([^,>]+),\s*([^>]+)>', 'extends MobRenderer<$1, net.minecraft.client.renderer.entity.state.LivingEntityRenderState, $2>'

        # NeoForge 26 EventBusSubscriber has no nested Bus
        $t = $t -replace 'import net\.neoforged\.fml\.common\.EventBusSubscriber\.Bus;\s*', ''
        $t = $t -replace 'import net\.neoforged\.fml\.common\.Mod\.EventBusSubscriber\.Bus;\s*', ''
        $t = [regex]::Replace($t, '(?s)@EventBusSubscriber\(\s*bus\s*=\s*Bus\.MOD\s*,\s*value\s*=\s*\{?\s*Dist\.CLIENT\s*\}?\s*\)', '@EventBusSubscriber(Dist.CLIENT)')
        $t = [regex]::Replace($t, '(?s)@EventBusSubscriber\(\s*value\s*=\s*\{?\s*Dist\.CLIENT\s*\}?\s*,\s*bus\s*=\s*Bus\.MOD\s*\)', '@EventBusSubscriber(Dist.CLIENT)')
        $t = [regex]::Replace($t, '(?s)@EventBusSubscriber\(\s*bus\s*=\s*Bus\.MOD\s*\)', '@EventBusSubscriber')
        $t = [regex]::Replace($t, '(?s)@EventBusSubscriber\(\s*bus\s*=\s*Bus\.GAME\s*\)', '@EventBusSubscriber')
        $t = [regex]::Replace($t, '@EventBusSubscriber\(\s*value\s*=\s*Dist\.CLIENT\s*,\s*bus\s*=\s*Bus\.MOD\s*\)', '@EventBusSubscriber(Dist.CLIENT)')

        $t = $t -replace 'LivingEvent\.LivingTickEvent', 'net.neoforged.neoforge.event.tick.EntityTickEvent.Post'
        $t = $t -replace 'TickEvent\.PlayerTickEvent', 'net.neoforged.neoforge.event.tick.PlayerTickEvent.Post'
        $t = $t -replace 'TickEvent\.LevelTickEvent', 'net.neoforged.neoforge.event.tick.LevelTickEvent.Post'
        $t = $t -replace 'TickEvent\.RenderTickEvent', 'net.neoforged.neoforge.client.event.RenderFrameEvent.Post'

        $t = $t -replace 'net\.minecraftforge\.common\.ForgeSpawnEggItem', 'net.minecraft.world.item.SpawnEggItem'
        $t = $t -replace 'net\.neoforged\.neoforge\.common\.ForgeSpawnEggItem', 'net.minecraft.world.item.SpawnEggItem'
        $t = $t -replace 'new\s+ForgeSpawnEggItem\s*\(([^,]+),\s*[^,]+,\s*[^,]+,\s*([^)]+)\)', 'new SpawnEggItem($2.spawnEgg($1.get()))'

        $t = $t -replace 'Supplier<NetworkEvent\.Context>', 'Object'
        $t = $t -replace 'NetworkEvent\.Context', 'Object'
        $t = $t -replace 'import net\.neoforged\.neoforge\.network\.NetworkEvent;\s*', ''

        $t = $t -replace 'import net\.minecraft\.world\.entity\.animal\.IronGolem;', 'import net.minecraft.world.entity.animal.golem.IronGolem;'
        $t = $t -replace 'import net\.minecraft\.client\.gui\.screens\.inventory\.EffectRenderingInventoryScreen;', ''
        $t = $t -replace '\.offset\(OffsetType\.XZ\)', ''
        $t = $t -replace '\.offset\(OffsetType\.XYZ\)', ''
        $t = $t -replace 'getItem\(\)\s*!=\s*this\.getName\(\)', 'getItem() != this.asItem()'
        $t = $t -replace 'super\.getFluidState\(state\)', 'Fluids.EMPTY.defaultFluidState()'
        $t = [regex]::Replace($t,
            'public BlockState updateShape\(BlockState state, Direction facing, BlockState facingState, LevelAccessor world, BlockPos currentPos, BlockPos facingPos\)',
            'protected BlockState updateShape(BlockState state, net.minecraft.world.level.LevelReader world, net.minecraft.world.level.ScheduledTickAccess ticks, BlockPos currentPos, Direction facing, BlockPos facingPos, BlockState facingState, net.minecraft.util.RandomSource random)')
        $t = $t -replace 'super\.updateShape\(state, facing, facingState, world, currentPos, facingPos\)', 'super.updateShape(state, world, ticks, currentPos, facing, facingPos, facingState, random)'
        $t = $t -replace 'world\.scheduleTick\(currentPos, Fluids\.WATER, Fluids\.WATER\.getTickDelay\(world\)\)', 'ticks.scheduleTick(currentPos, Fluids.WATER, Fluids.WATER.getTickDelay(world))'

        # 26.2 EntityModel is EntityRenderState-typed, not Entity
        $t = $t -replace 'class (\w+)<T extends Entity> extends EntityModel<T>', 'class $1 extends EntityModel<net.minecraft.client.renderer.entity.state.LivingEntityRenderState>'
        $t = $t -replace 'void setupAnim\(T ', 'void setupAnim(net.minecraft.client.renderer.entity.state.LivingEntityRenderState '
        $t = $t -replace 'void renderToBuffer\(PoseStack ([^,]+), VertexConsumer ([^,]+), int ([^,]+), int ([^,]+), float [^,]+, float [^,]+, float [^,]+, float [^)]+\)', 'void renderToBuffer(PoseStack $1, VertexConsumer $2, int $3, int $4)'
        $t = $t -replace 'PartPose\.rotation\(([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^)]+)\)', 'PartPose.offsetAndRotation($1,$2,$3,$4,$5,$6)'
        $t = $t -replace 'meshdefinition\.bake\(\)', 'meshdefinition.getRoot()'
        $t = $t -replace '\.addBox\(\)\.addBox\(', '.addBox('
        $t = $t -replace '\.m_171480_\(\)\.', '.'
        $t = [regex]::Replace($t, 'public (\w+)\(ModelPart root\) \{\s*this\.', "public `$1(ModelPart root) {`r`n      super(root);`r`n      this.")
        $t = $t -replace '(Model(?:The_)?[\w]+)<[^>]+>', '$1'
        $t = $t -replace 'getTextureLocation\(\w+ entity\)', 'getTextureLocation(net.minecraft.client.renderer.entity.state.LivingEntityRenderState state)'
        $t = $t -replace 'new Identifier\("([^"]+)"\)', 'Identifier.parse("$1")'
        $t = $t -replace 'Identifier\.fromNamespaceAndPath\("([^"]*)"\)', 'Identifier.parse("$1")'
        $t = $t -replace 'Identifier\.parse\(""\)', 'Identifier.parse("minecraft:empty")'

        $t = $t -replace 'public boolean hurt\(DamageSource (\w+), float (\w+)\)', 'public boolean hurtServer(net.minecraft.server.level.ServerLevel level, DamageSource $1, float $2)'
        $t = $t -replace 'super\.hurt\((\w+), (\w+)\)', 'super.hurtServer(level, $1, $2)'
        $t = $t -replace 'public EntityDimensions getDimensions\(Pose ', 'public EntityDimensions getDefaultDimensions(Pose '
        $t = $t -replace 'super\.getDimensions\(', 'super.getDefaultDimensions('
        $t = $t -replace 'super\.finalizeSpawn\((\w+), (\w+), (\w+), (\w+), (\w+)\)', 'super.finalizeSpawn($1, $2, $3, $4)'
        $t = $t -replace 'public SpawnGroupData finalizeSpawn\(([^)]+), @Nullable CompoundTag \w+\)', 'public SpawnGroupData finalizeSpawn($1)'
        $t = $t -replace 'this\.dropFromLootTable\(\);', ''

        if ($t -match 'extends Animal' -and $t -notmatch 'boolean isFood\(') {
            $t = [regex]::Replace($t, '(public static void init\(\) \{\s*\})', "`$1`r`n`r`n   public boolean isFood(net.minecraft.world.item.ItemStack stack) { return false; }")
        }
        if ($t -match 'extends MobRenderer<' -and $t -notmatch 'createRenderState\(') {
            $t = [regex]::Replace($t, '(public \w+\(EntityRendererProvider\.Context[^\)]*\) \{[^}]+\})', "`$1`r`n`r`n   public net.minecraft.client.renderer.entity.state.LivingEntityRenderState createRenderState() { return new net.minecraft.client.renderer.entity.state.LivingEntityRenderState(); }")
        }
        $t = $t -replace 'void setupAnim\(T entity,', 'void setupAnim(net.minecraft.client.renderer.entity.state.LivingEntityRenderState entity,'
        $t = $t -replace 'void m_6973_\(T entity,', 'void setupAnim(net.minecraft.client.renderer.entity.state.LivingEntityRenderState entity,'
        $t = $t -replace ', red, green, blue, alpha\)', ')'
        $t = $t -replace 'new Identifier\(""\)', 'Identifier.parse("minecraft:empty")'
        $t = $t -replace 'Blocks\.([A-Z0-9_]+)\.getName\(\)', 'Blocks.$1.asItem()'
        $t = $t -replace 'finalizeSpawn\(([^,]+), ([^,]+), ([^,]+), ([^,]+), \(CompoundTag\)null\)', 'finalizeSpawn($1, $2, $3, $4)'
        $t = $t -replace 'this\.(\w+)\.renderToBuffer\(poseStack, vertexConsumer, packedLight, packedOverlay\)', 'this.$1.render(poseStack, vertexConsumer, packedLight, packedOverlay)'
        $t = [regex]::Replace($t, '(?s)public void addAdditionalSaveData\(DamageSource (\w+)\) \{\s*super\.addAdditionalSaveData\(\1\);\s*\}', 'public void die(DamageSource $1) { super.die($1); }')
        $t = [regex]::Replace($t, 'protected void defineSynchedData\(DamageSource (\w+), int \w+, boolean (\w+)\) \{\s*super\.defineSynchedData\([^;]+;\s*this\.spawnAtLocation\(', 'protected void dropCustomDeathLoot(net.minecraft.server.level.ServerLevel level, DamageSource $1, boolean $2) { super.dropCustomDeathLoot(level, $1, $2); this.spawnAtLocation(level, ')
        $t = [regex]::Replace($t, '(?s)public void readAdditionalSaveData\(Entity \w+, int \w+, DamageSource \w+\) \{\s*super\.readAdditionalSaveData\([^;]+;\s*\}', '')
        $t = $t -replace 'void m_7472_\(DamageSource', 'void dropCustomDeathLoot(net.minecraft.server.level.ServerLevel level, DamageSource'
        $t = $t -replace 'void m_6667_\(DamageSource', 'void die(DamageSource'
        $t = $t -replace 'super\.m_6667_\(source\)', 'super.die(source)'
        $t = $t -replace 'void m_6667_\(CompoundTag', 'void addAdditionalSaveData(net.minecraft.world.level.storage.ValueOutput'
        $t = $t -replace 'void m_5993_\(CompoundTag', 'void readAdditionalSaveData(net.minecraft.world.level.storage.ValueInput'
        $t = $t -replace 'void addAdditionalSaveData\(CompoundTag', 'void addAdditionalSaveData(net.minecraft.world.level.storage.ValueOutput'
        $t = $t -replace 'void readAdditionalSaveData\(CompoundTag', 'void readAdditionalSaveData(net.minecraft.world.level.storage.ValueInput'

        # Annotations
        $t = $t -replace 'import javax\.annotation\.Nullable;', 'import org.jetbrains.annotations.Nullable;'
        $t = $t -replace 'import javax\.annotation\.Nonnull;', 'import org.jetbrains.annotations.NotNull;'

        # Mod constructor injection hint
        if ($t -match 'FMLJavaModLoadingContext') {
            $t = $t -replace 'FMLJavaModLoadingContext\.get\(\)\.getModEventBus\(\)',
                '/* TODO inject IEventBus */ FMLJavaModLoadingContext.get().getModEventBus()'
        }

        # RegistryObject residual type name (import already DeferredHolder)
        $t = $t -replace '\bRegistryObject\b', 'DeferredHolder'

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }

    # ItemBlockRenderTypes was removed. Preserve CUTOUT intent in the model
    # metadata supported by NeoForge's model loader.
    $modelRoot = Join-Path $Root 'src\main\resources\assets'
    if (Test-Path -LiteralPath $modelRoot) {
        foreach ($id in $cutoutIds) {
            foreach ($model in @(Get-ChildItem -LiteralPath $modelRoot -Recurse -File -Filter "$id*.json" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '[\\/]models[\\/]block[\\/]' })) {
                try {
                    $json = Get-Content -LiteralPath $model.FullName -Raw | ConvertFrom-Json
                    if (-not $json.PSObject.Properties['render_type']) { $json | Add-Member NoteProperty render_type 'minecraft:cutout' }
                    [IO.File]::WriteAllText($model.FullName, ($json | ConvertTo-Json -Depth 100))
                } catch { Write-Warning "Could not add CUTOUT metadata to $($model.FullName): $($_.Exception.Message)" }
            }
        }
    }

    $needsCompat = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue |
        Select-String -SimpleMatch 'rb.legacy.converter.compat.Legacy262Compat' -Quiet
    if ($needsCompat) {
        $compatPath = Join-Path $Root 'src\main\java\rb\legacy\converter\compat\Legacy262Compat.java'
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($compatPath)) | Out-Null
        $compat = @'
package rb.legacy.converter.compat;

import java.util.ArrayList;
import java.util.List;
import net.minecraft.client.renderer.block.dispatch.BlockStateModel;
import net.minecraft.client.renderer.block.dispatch.BlockStateModelPart;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.Property;

/** Mechanical bridge for APIs removed between Minecraft 1.21.x and 26.2. */
public final class Legacy262Compat {
    private Legacy262Compat() {}

    @SuppressWarnings("deprecation")
    public static List<BlockStateModelPart> modelParts(BlockStateModel model) {
        List<BlockStateModelPart> parts = new ArrayList<>();
        model.collectParts(RandomSource.create(), parts);
        return parts;
    }

    public static BlockState copyValue(BlockState target, Property.Value<?> value) {
        return copyCaptured(target, value);
    }

    @SuppressWarnings("unchecked")
    private static <T extends Comparable<T>> BlockState copyCaptured(BlockState target, Property.Value<T> value) {
        Property<T> property = (Property<T>) target.getBlock().getStateDefinition().getProperty(value.property().getName());
        return property == null ? target : target.setValue(property, value.value());
    }
}

'@
        [IO.File]::WriteAllText($compatPath, $compat)
    }
    return $touched
}

function Invoke-ExactPrimerMigrationRules {
    param([string]$Root, $Profile, [string]$ModId)

    $rules = @(Get-PrimerMigrationRules -SourceVersion ([string]$Profile.SourceVersion))
    $touched = 0
    $javaRoot = Join-Path $Root 'src\main\java'

    foreach ($file in @(Get-ChildItem -LiteralPath $javaRoot -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue)) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $original = $text
        if ($rules -contains 'legacy-direction-property') {
            $text = $text.Replace('import net.minecraft.world.level.block.state.properties.DirectionProperty;', 'import net.minecraft.world.level.block.state.properties.EnumProperty;')
            $text = $text.Replace('DirectionProperty', 'EnumProperty<Direction>')
            $text = $text.Replace('.getNormal()', '.getUnitVec3i()')
        }
        if ($text -ne $original) {
            [IO.File]::WriteAllText($file.FullName, $text)
            $touched++
        }
    }

    if ($rules -contains 'legacy-datagen-isolation') {
        $legacyDatagen = Get-ChildItem -LiteralPath $javaRoot -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue |
            Select-String -Pattern 'client\.model\.generators|ExistingFileHelper|IConditionBuilder' -Quiet
        $gradlePath = Join-Path $Root 'build.gradle'
        if ($legacyDatagen -and (Test-Path -LiteralPath $gradlePath)) {
            $gradle = [IO.File]::ReadAllText($gradlePath)
            if ($gradle -notmatch "exclude '\*\*/datagen/\*\*'") {
                $gradle += "`r`n// 1.21.x datagen output is already present in resources; its generator API was removed.`r`nsourceSets.main.java {`r`n    exclude '**/datagen/**'`r`n    exclude '**/*DataGenerators.java'`r`n}`r`n"
                [IO.File]::WriteAllText($gradlePath, $gradle)
                $touched++
            }
        }
    }

    if ([string]$Profile.SourceVersion -eq '1.21.1' -and $ModId -eq 'nextgen_furniture' -and
        (Test-Path -LiteralPath (Join-Path $javaRoot 'net\nhatjs\nextgen_furniture\blockentity\renderer\ConsoleRenderer.java'))) {
        $overlay = Join-Path $ToolRoot 'lib\overlays\nextgen-furniture\1.21.1'
        if (Test-Path -LiteralPath $overlay) {
            foreach ($file in @(Get-ChildItem -LiteralPath $overlay -Recurse -File)) {
                $relative = $file.FullName.Substring($overlay.Length).TrimStart('\', '/')
                Copy-FileLongPath -Source $file.FullName -Destination (Join-Path $Root $relative)
                $touched++
            }
        }
    }

    return [pscustomobject]@{ Touched=$touched; Rules=$rules }
}

function Invoke-NeoForge26ApiRewritePass {
    <#
    .SYNOPSIS
      Second-pass Minecraft/NeoForge 26.2 API renames proven on Friend-26.2 and The Knocker.
      Safe mechanical transforms only - does not invent gameplay logic.
    #>
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- NBT 26.x ---
        # getList(key, type) / getListOrEmpty(key, type) -> single-arg list accessors
        $t = $t -replace '\.getListOrEmpty\(([^,]+),\s*Tag\.[A-Z_]+\)', '.getListOrEmpty($1)'
        $t = $t -replace '\.getList\(([^,]+),\s*Tag\.[A-Z_]+\)', '.getListOrEmpty($1)'
        # Prefer OrEmpty compound accessors (Optional-based getCompound in 26.x)
        # Negative lookahead avoids rewriting getCompoundOrEmpty itself
        $t = $t -replace '\.getCompound(?!OrEmpty)\(([^)]+)\)', '.getCompoundOrEmpty($1)'

        # --- BlockState ---
        $t = $t -replace '\.isSolidRender\([^)]*\)', '.isSolidRender()'

        # --- PathNavigation: NEVER rename navigation.moveTo to snapTo ---
        # Entity absolute placement often becomes snapTo; only convert bare entity moveTo with 5 args (x,y,z,yaw,pitch)
        $t = [regex]::Replace($t,
            '(?<!getNavigation\(\)\.)(?<!Navigation\.)\bmoveTo\((\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*[^)]+)\)',
            'snapTo($1)')
        # If a prior pass wrongly converted navigation to snapTo, restore
        $t = $t -replace '\.getNavigation\(\)\.snapTo\(', '.getNavigation().moveTo('

        # --- EntityType.create needs spawn reason ---
        $t = $t -replace '\.create\((\s*(?:level|serverLevel|world)\s*)\)',
            '.create($1, net.minecraft.world.entity.EntitySpawnReason.MOB_SUMMONED)'

        # --- Server access: use level().getServer() (Entity.getServer is gone / private in places) ---
        # Do NOT touch net.minecraft.server.* imports/packages
        $t = $t -replace '(?<![\w.])(player|serverPlayer|owner|self|_player|_ent|entity|_entity|living|sourceentity|immediatesourceentity)\.server\.', '$1.level().getServer().'
        $t = $t -replace '(?<![\w.])(player|serverPlayer|owner|self|_player|_ent|entity|_entity|living|sourceentity|immediatesourceentity)\.getServer\(\)', '$1.level().getServer()'

        # --- Spawn / respawn (LevelData + ServerPlayer.RespawnConfig shape in 26.2) ---
        $t = $t -replace '\.getSharedSpawnPos\(\)', '.getRespawnData().pos()'
        $t = $t -replace '\.getLevelData\(\)\.getSpawnPos\(\)', '.getLevelData().getRespawnData().pos()'
        $t = $t -replace '\.getRespawnConfig\(\)\.pos\(\)', '.getRespawnConfig().respawnData().pos()'
        $t = $t -replace '\.getRespawnConfig\(\)\.dimension\(\)', '.getRespawnConfig().respawnData().dimension()'
        # Player respawn: prefer RespawnConfig when present (manual polish often still needed)
        $t = $t -replace '(\w+)\.getRespawnPosition\(\)',
            '($1.getRespawnConfig() != null ? $1.getRespawnConfig().respawnData().pos() : null)'

        # --- Player chat / actionbar (displayClientMessage removed; nested Component.literal args) ---
        $t = Convert-DisplayClientMessageCalls -Text $t
        $t = $t -replace '\.displayClientMessage\(([^,]+)\s*,\s*(?:true|false)\s*\)', '.sendSystemMessage($1)'

        # --- FML dist accessor ---
        $t = $t -replace 'FMLEnvironment\.dist\b', 'FMLEnvironment.getDist()'

        # --- DeferredRegister items: registerItem(name, fn, new Properties()) no longer matches ---
        $t = $t -replace '\.registerItem\(([^,]+),\s*([^,]+),\s*new\s+(?:Item\.)?Properties\(\)\s*\)', '.registerItem($1, $2)'

        # --- SpawnEggItem(EntityType, Properties) -> Properties + ENTITY_DATA component (26.x) ---
        $t = [regex]::Replace($t,
            'new\s+SpawnEggItem\(\s*(\([^)]*EntityType[^)]*\)[^,]+|\w+(?:\.\w+)*(?:\(\))?)\s*,\s*([A-Za-z_][\w]*)\s*\)',
            'new SpawnEggItem($2.component(net.minecraft.core.component.DataComponents.ENTITY_DATA, net.minecraft.world.item.component.TypedEntityData.of($1, new net.minecraft.nbt.CompoundTag())))')

        # --- CommandSourceStack permission int -> LevelBasedPermissionSet ---
        # MCreator / common: CommandSourceStack(..., serverLevelOrNull, 4, name, ...)
        $t = $t -replace '(_level|_serverLevel|serverLevel|level)\s*,\s*4\s*,',
            '$1, net.minecraft.server.permissions.LevelBasedPermissionSet.OWNER,'
        $t = $t -replace '(_level|_serverLevel|serverLevel|level)\s*,\s*2\s*,',
            '$1, net.minecraft.server.permissions.LevelBasedPermissionSet.GAMEMASTER,'
        $t = $t -replace '(_level|_serverLevel|serverLevel|level)\s*,\s*3\s*,',
            '$1, net.minecraft.server.permissions.LevelBasedPermissionSet.ADMIN,'
        $t = $t -replace '(\?\s*\(ServerLevel\)[^,]+?\s*:\s*null)\s*,\s*4\s*,',
            '$1, net.minecraft.server.permissions.LevelBasedPermissionSet.OWNER,'
        $t = $t -replace '(\?\s*\(ServerLevel\)[^,]+?\s*:\s*null)\s*,\s*2\s*,',
            '$1, net.minecraft.server.permissions.LevelBasedPermissionSet.GAMEMASTER,'

        # --- Client render package moves (common humanoid / glow layers) ---
        $t = $t -replace 'import\s+net\.minecraft\.client\.renderer\.MultiBufferSource\s*;',
            'import net.minecraft.client.renderer.SubmitNodeCollector;'
        $t = $t -replace 'import\s+net\.minecraft\.client\.renderer\.RenderType\s*;',
            'import net.minecraft.client.renderer.rendertype.RenderTypes;'
        # Only rewrite classic RenderType static factories; leave other RenderType mentions.
        $t = $t -replace '\bRenderType\.(eyes|entityCutout|entityCutoutNoCull|entityTranslucent|entityTranslucentEmissive)\b', 'RenderTypes.$1'
        $t = $t -replace '\bMultiBufferSource\b', 'SubmitNodeCollector'
        # Armor layer: dual bakeLayer(INNER/OUTER) -> ArmorModelSet.bake (do NOT rename INNER/OUTER tokens;
        # PLAYER_ARMOR is ArmorModelSet, not a ModelLayerLocation, so bakeLayer(PLAYER_ARMOR) does not compile).
        $t = [regex]::Replace($t,
            'new\s+HumanoidArmorLayer(?:<>)?\s*\(\s*this\s*,\s*new\s+HumanoidModel(?:<>)?\s*\(\s*context\.bakeLayer\(\s*ModelLayers\.PLAYER_INNER_ARMOR\s*\)\s*\)\s*,\s*new\s+HumanoidModel(?:<>)?\s*\(\s*context\.bakeLayer\(\s*ModelLayers\.PLAYER_OUTER_ARMOR\s*\)\s*\)\s*,\s*context\.getEquipmentRenderer\(\)\s*\)',
            'new HumanoidArmorLayer(this, net.minecraft.client.renderer.entity.ArmorModelSet.bake(ModelLayers.PLAYER_ARMOR, context.getModelSet(), HumanoidModel::new), context.getEquipmentRenderer())',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        # MCreator glow overlay: RenderLayer.render(PoseStack, SubmitNodeCollector, ...) is submit in 26.2
        $t = [regex]::Replace($t,
            'public\s+void\s+render\s*\(\s*PoseStack\s+(\w+)\s*,\s*SubmitNodeCollector\s+',
            'public void submit(PoseStack $1, SubmitNodeCollector ')
        # getBuffer(eyes)+renderToBuffer (plain or inside if) -> submitModel
        $t = [regex]::Replace($t,
            'VertexConsumer\s+\w+\s*=\s*(\w+)\.getBuffer\(\s*RenderTypes\.eyes\(([^;]+?)\)\s*\)\s*;\s*(?:\(\(HumanoidModel\)this\.getParentModel\(\)\)|this\.getParentModel\(\))\s*\.renderToBuffer\(\s*(\w+)\s*,\s*\w+\s*,\s*(\w+)\s*,\s*LivingEntityRenderer\.getOverlayCoords\((\w+)\s*,\s*[^)]+\)\s*\)\s*;',
            '$1.order(0).submitModel(this.getParentModel(), $5, $3, RenderTypes.eyes($2), $4, LivingEntityRenderer.getOverlayCoords($5, 0.0F), -1, null, $5.outlineColor, null);')
        # PlayerSkin.texture() -> body().texturePath()
        $t = $t -replace '\.getSkin\(\)\.texture\(\)', '.getSkin().body().texturePath()'

        # --- Legacy NeoForge item capability API (transfer rewrite is manual) ---
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.capabilities\.Capabilities\.ItemHandler\s*;\s*', ''
        $t = $t -replace '(?m)^(\s*)event\.registerBlockEntity\(\s*ItemHandler\.BLOCK\s*,.+$',
            '$1// TODO 26.2: item handler capability moved to Capabilities.Item + transfer API (registerBlockEntity removed by converter)'

        # --- Effects / entity packages ---
        $t = $t -replace 'MobEffects\.MOVEMENT_SPEED', 'MobEffects.SPEED'
        $t = $t -replace 'net\.minecraft\.world\.entity\.monster\.Zombie\b',
            'net.minecraft.world.entity.monster.zombie.Zombie'
        $t = $t -replace 'net\.minecraft\.world\.entity\.animal\.Cat\b',
            'net.minecraft.world.entity.animal.feline.Cat'
        $t = $t -replace 'net\.minecraft\.world\.entity\.animal\.Wolf\b',
            'net.minecraft.world.entity.animal.wolf.Wolf'

        # --- NeoForge break event package (26.2) ---
        $t = $t -replace 'net\.neoforged\.neoforge\.event\.level\.BlockEvent\.BreakEvent',
            'net.neoforged.neoforge.event.level.block.BreakBlockEvent'
        $t = $t -replace '\bBlockEvent\.BreakEvent\b', 'BreakBlockEvent'
        # Ensure import when BreakBlockEvent is used without FQN
        if ($t -match '\bBreakBlockEvent\b' -and $t -notmatch 'import\s+net\.neoforged\.neoforge\.event\.level\.block\.BreakBlockEvent') {
            if ($t -match 'import\s+net\.neoforged\.neoforge\.event\.level\.BlockEvent;') {
                $t = $t -replace 'import\s+net\.neoforged\.neoforge\.event\.level\.BlockEvent;',
                    "import net.neoforged.neoforge.event.level.BlockEvent;`r`nimport net.neoforged.neoforge.event.level.block.BreakBlockEvent;"
            }
            elseif ($t -match '(?m)^package\s+[^;]+;') {
                $t = [regex]::Replace($t, '(?m)^(package\s+[^;]+;\s*)',
                    "`$1`r`nimport net.neoforged.neoforge.event.level.block.BreakBlockEvent;`r`n", 1)
            }
        }

        # --- Commands: hasPermission(int) -> PermissionSet ---
        $t = $t -replace '\.hasPermission\(\s*2\s*\)',
            '.permissions().hasPermission(net.minecraft.server.permissions.Permissions.COMMANDS_GAMEMASTER)'
        $t = $t -replace '\.hasPermission\(\s*4\s*\)',
            '.permissions().hasPermission(net.minecraft.server.permissions.Permissions.COMMANDS_OWNER)'
        $t = $t -replace '\.hasPermission\(\s*3\s*\)',
            '.permissions().hasPermission(net.minecraft.server.permissions.Permissions.COMMANDS_ADMIN)'

        # --- ResourceKey: dimension().location() -> identifier() ---
        $t = $t -replace '\.dimension\(\)\.location\(\)', '.dimension().identifier()'

        # --- Camera only (avoid rewriting unrelated getPosition) ---
        $t = $t -replace '\bcamera\.getPosition\(\)', 'camera.position()'
        $t = $t -replace '\bevent\.getCamera\(\)\.getPosition\(\)', 'event.getCamera().position()'

        # --- DeferredHolder single type param (SoundEvent etc.) ---
        $t = $t -replace 'DeferredHolder<\s*SoundEvent\s*>(?!\s*,)', 'DeferredHolder<SoundEvent, SoundEvent>'

        # --- ClipContext null entity ambiguity ---
        $t = $t -replace 'ClipContext\.Fluid\.NONE\s*,\s*null\)',
            'ClipContext.Fluid.NONE, net.minecraft.world.phys.shapes.CollisionContext.empty())'

        # --- EntityType.VANILLA_FIELD => EntityTypes (registry objects moved in 26.2) ---
        $tEntity = [regex]::Replace($t, '\bEntityType\.([A-Z][A-Z0-9_]*)\b', 'EntityTypes.$1')
        if ($tEntity -ne $t) {
            $t = $tEntity
            if ($t -notmatch 'import\s+net\.minecraft\.world\.entity\.EntityTypes;') {
                if ($t -match 'import\s+net\.minecraft\.world\.entity\.EntityType;') {
                    $t = $t -replace 'import\s+net\.minecraft\.world\.entity\.EntityType;',
                        "import net.minecraft.world.entity.EntityType;`r`nimport net.minecraft.world.entity.EntityTypes;"
                }
                elseif ($t -match '(?m)^package\s+[^;]+;') {
                    $t = [regex]::Replace($t, '(?m)^(package\s+[^;]+;\s*)',
                        "`$1`r`nimport net.minecraft.world.entity.EntityTypes;`r`n", 1)
                }
            }
        }

        # --- Camera / buffers accessors ---
        $t = $t -replace '\.getMainCamera\(\)', '.mainCamera()'
        $t = [regex]::Replace(
            $t,
            'Minecraft\.getInstance\(\)\.renderBuffers\(\)',
            'Minecraft.getInstance().gameRenderer.renderBuffers()'
        )
        $t = $t -replace 'Minecraft\.getInstance\(\)\.gameRenderer\.gameRenderer\.renderBuffers\(\)',
            'Minecraft.getInstance().gameRenderer.renderBuffers()'

        # --- Colored Items/Blocks (ColorCollection) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â full dye grid ---
        $t = Convert-ColorCollectionConstants $t

        # --- Weather / day-time (best-effort; many dims fix time in data) ---
        $t = $t -replace '(\w+)\.setWeatherParameters\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*false\s*,\s*false\s*\)',
            '{ var __w = $1.getWeatherData(); __w.setClearWeatherTime((int)($2)); __w.setRainTime(0); __w.setThunderTime(0); __w.setRaining(false); __w.setThundering(false); }'
        $t = $t -replace '(\w+)\.setWeatherParameters\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*true\s*,\s*true\s*\)',
            '{ var __w = $1.getWeatherData(); __w.setClearWeatherTime(0); __w.setRainTime((int)($3)); __w.setThunderTime((int)($3)); __w.setRaining(true); __w.setThundering(true); }'
        $t = $t -replace '(\w+)\.setDayTime\((\d+L|[\w.]+)\)',
            '$1.dimensionType().defaultClock().ifPresent(__clock -> $1.clockManager().setTotalTicks(__clock, $2))'

        # --- Teleport cross-dimension 6-arg (level, x,y,z, yaw, pitch) ---
        # Avoid nested-paren receivers; only simple identifier first arg (level/world vars)
        $t = [regex]::Replace($t,
            '(\w+)\.teleportTo\(\s*([A-Za-z_][\w]*)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^)]+)\)',
            {
                param($m)
                $recv = $m.Groups[1].Value
                $a1 = $m.Groups[2].Value
                $a2 = $m.Groups[3].Value.Trim()
                $a3 = $m.Groups[4].Value.Trim()
                $a4 = $m.Groups[5].Value.Trim()
                $a5 = $m.Groups[6].Value.Trim()
                $a6 = $m.Groups[7].Value.Trim()
                if ($a5 -match 'emptySet|Relative|Set\.') { return $m.Value }
                if ($a6 -match '^\s*(true|false)\s*$' -and $a5 -match 'emptySet|Set\.') { return $m.Value }
                # skip same-dimension 3-double style misparse (first arg looks numeric via var unlikely)
                if ($a1 -match '^(?i)(x|y|z|dx|dy|dz)$') { return $m.Value }
                "$recv.teleportTo($a1, $a2, $a3, $a4, java.util.Collections.emptySet(), $a5, $a6, true)"
            })

        # --- Advancement lookup ---
        $t = $t -replace '\.getAdvancements\(\)\.getAdvancement\(', '.getAdvancements().get('

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-Mcreator1218ToNeoForge262Pass {
    <#
    .SYNOPSIS
      MCreator / NeoForge 1.21.x jar decompile lessons (MOAdecor BATH etc.) for Minecraft 26.2.
      Bulk-safe transforms: fluid overlay stubs, noCollision, client GUI extract API, isClientSide(),
      removed Tuple, and broken ItemHandler capability lookups.
    #>
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- BlockBehaviour spelling (1.21.x British / old mapping) ---
        $t = $t -replace '\.noCollission\(\)', '.noCollision()'

        # --- Forge fluid overlay on Block (method no longer on Block in 26.2) ---
        # Drop entire method body; decorative MCreator blocks always returned true.
        $t = [regex]::Replace($t,
            '(?ms)^\s*(?:@Override\s*)?public\s+boolean\s+shouldDisplayFluidOverlay\s*\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\}\s*',
            '')
        $t = $t -replace 'import\s+net\.minecraft\.world\.level\.BlockAndTintGetter\s*;\s*\r?\n', ''
        # Client-only type lives under renderer.block in 26.2 (if any remaining refs)
        $t = $t -replace 'net\.minecraft\.world\.level\.BlockAndTintGetter',
            'net.minecraft.client.renderer.block.BlockAndTintGetter'

        # --- Level.isClientSide field is private; always call method ---
        $t = [regex]::Replace($t, '\.isClientSide\b(?!\s*\()', '.isClientSide()')

        # --- GuiGraphics -> GuiGraphicsExtractor (26.x extract pipeline) ---
        $t = [regex]::Replace($t, '\bGuiGraphics\b(?!Extractor)', 'GuiGraphicsExtractor')
        $t = $t -replace 'import\s+net\.minecraft\.client\.gui\.GuiGraphicsExtractor\s*;',
            'import net.minecraft.client.gui.GuiGraphicsExtractor;'
        $t = $t -replace 'import\s+net\.minecraft\.client\.gui\.GuiGraphics\s*;',
            'import net.minecraft.client.gui.GuiGraphicsExtractor;'

        # Common Screen method renames used by MCreator container screens
        $t = $t -replace '\bprotected\s+void\s+renderBg\s*\(', 'public void extractBackground('
        $t = $t -replace '\bpublic\s+void\s+renderBg\s*\(', 'public void extractBackground('
        $t = $t -replace '\.renderTooltip\s*\(', '.extractTooltip('
        $t = $t -replace '\bprotected\s+void\s+renderLabels\s*\(', 'protected void extractLabels('
        $t = $t -replace '\bpublic\s+void\s+renderLabels\s*\(', 'public void extractLabels('
        # render(...) that was the old Screen render hook often becomes extractRenderState
        $t = [regex]::Replace($t,
            '(?m)^(\s*)public\s+void\s+render\s*\(\s*GuiGraphicsExtractor\s+',
            '$1public void extractRenderState(GuiGraphicsExtractor ')

        # imageWidth/imageHeight are final ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â pass size into super(...)
        # Immediate form: super(...); this.imageWidth = W; this.imageHeight = H;
        $t = [regex]::Replace($t,
            'super\(([^;]+?)\);\s*this\.imageWidth\s*=\s*(\d+)\s*;\s*this\.imageHeight\s*=\s*(\d+)\s*;',
            'super($1, $2, $3);')
        # MCreator form: super(...); field assigns...; this.imageWidth = W; this.imageHeight = H;
        $t = [regex]::Replace($t,
            'super\((\s*\w+\s*,\s*\w+\s*,\s*\w+\s*)\);((?:\s*this\.\w+\s*=\s*[^;]+;){0,8})\s*this\.imageWidth\s*=\s*(\d+)\s*;\s*this\.imageHeight\s*=\s*(\d+)\s*;',
            'super($1, $3, $4);$2')

        # Drop trivial extractRenderState that only calls super + extractTooltip (base already does this)
        $t = [regex]::Replace($t,
            '(?ms)^\s*(?:@Override\s*)?public\s+void\s+extractRenderState\s*\(\s*GuiGraphicsExtractor\s+\w+\s*,\s*int\s+\w+\s*,\s*int\s+\w+\s*,\s*float\s+\w+\s*\)\s*\{\s*super\.(?:extractRenderState|render)\([^;]+;\s*this\.extractTooltip\([^;]+;\s*\}\s*',
            '')

        # Fix extractBackground arg order if still (graphics, float, int, int) from old renderBg
        $t = [regex]::Replace($t,
            '(public|protected)\s+void\s+extractBackground\s*\(\s*GuiGraphicsExtractor\s+(\w+)\s*,\s*float\s+(\w+)\s*,\s*int\s+(\w+)\s*,\s*int\s+(\w+)\s*\)',
            '$1 void extractBackground(GuiGraphicsExtractor $2, int $4, int $5, float $3)')

        # keyPressed(int,int,int) -> KeyEvent (ESC close handled by Screen; keep override when custom)
        if ($t -match 'boolean\s+keyPressed\s*\(\s*int\s+\w+\s*,\s*int\s+\w+\s*,\s*int\s+\w+\s*\)') {
            if ($t -notmatch 'import\s+net\.minecraft\.client\.input\.KeyEvent\s*;') {
                if ($t -match '(?m)^package\s+[^;]+;') {
                    $t = [regex]::Replace($t, '(?m)^(package\s+[^;]+;\s*)',
                        "`$1`r`nimport net.minecraft.client.input.KeyEvent;`r`n", 1)
                }
            }
            # Simple ESC close pattern from MCreator
            $t = [regex]::Replace($t,
                '(?ms)public\s+boolean\s+keyPressed\s*\(\s*int\s+(\w+)\s*,\s*int\s+\w+\s*,\s*int\s+\w+\s*\)\s*\{\s*if\s*\(\s*\1\s*==\s*256\s*\)\s*\{\s*this\.minecraft\.player\.closeContainer\(\)\s*;\s*return\s+true\s*;\s*\}\s*else\s*\{\s*return\s+super\.keyPressed\s*\(\s*\1\s*,\s*\w+\s*,\s*\w+\s*\)\s*;\s*\}\s*\}',
                @'
public boolean keyPressed(KeyEvent event) {
      if (event.key() == 256) {
         this.minecraft.player.closeContainer();
         return true;
      } else {
         return super.keyPressed(event);
      }
   }
'@)
            # Any remaining 3-arg keyPressed calls to super
            $t = [regex]::Replace($t,
                'super\.keyPressed\s*\(\s*(\w+)\s*,\s*\w+\s*,\s*\w+\s*\)',
                'super.keyPressed(event)')
            $t = [regex]::Replace($t,
                'public\s+boolean\s+keyPressed\s*\(\s*int\s+\w+\s*,\s*int\s+\w+\s*,\s*int\s+\w+\s*\)',
                'public boolean keyPressed(KeyEvent event)')
        }

        # --- net.minecraft.util.Tuple removed: MCreator delayed work queue ---
        if ($t -match 'net\.minecraft\.util\.Tuple' -or $t -match '\bTuple\s*<\s*Runnable') {
            $t = $t -replace 'import\s+net\.minecraft\.util\.Tuple\s*;\s*\r?\n', ''
            $t = $t -replace 'Collection<\s*Tuple<\s*Runnable\s*,\s*Integer\s*>\s*>', 'Collection<Object[]>'
            $t = $t -replace 'List<\s*Tuple<\s*Runnable\s*,\s*Integer\s*>\s*>', 'List<Object[]>'
            $t = $t -replace 'new\s+Tuple\s*(?:<\s*Runnable\s*,\s*Integer\s*>)?\s*\(\s*([^,]+)\s*,\s*([^)]+)\)', 'new Object[] { $1, $2 }'
            $t = $t -replace '\(Tuple<\s*Runnable\s*,\s*Integer\s*>\)\s*', ''
            # work.setB((Integer)work.getB() - 1)
            $t = [regex]::Replace($t,
                '(\w+)\.setB\(\s*\(Integer\)\1\.getB\(\)\s*-\s*1\s*\)',
                '$1[1] = (Integer)$1[1] - 1')
            $t = [regex]::Replace($t, '\(Integer\)(\w+)\.getB\(\)', '(Integer)$1[1]')
            $t = [regex]::Replace($t, '\(\(Runnable\)(\w+)\.getA\(\)\)', '((Runnable)$1[0])')
            $t = [regex]::Replace($t, '(\w+)\.getA\(\)', '$1[0]')
            $t = [regex]::Replace($t, '(\w+)\.getB\(\)', '$1[1]')
        }

        # --- ItemHandler.ITEM / .ENTITY capability symbols (1.21 MCreator menus) ---
        # Capabilities.Item now uses ResourceHandler + ItemAccess; skip transfer binding and keep ItemStackHandler.
        if ($t -match 'ItemHandler\.(ITEM|ENTITY|BLOCK)\b') {
            # Item stack capability bind block
            $nl = [Environment]::NewLine
            $t = [regex]::Replace($t,
                '(?ms)IItemHandler\s+cap\s*=\s*\(IItemHandler\)\s*itemstack\.getCapability\s*\(\s*ItemHandler\.ITEM\s*\)\s*;\s*if\s*\(\s*cap\s*!=\s*null\s*\)\s*\{\s*this\.internal\s*=\s*cap\s*;\s*this\.bound\s*=\s*true\s*;\s*\}',
                ("// 26.2: Capabilities.Item.ITEM needs ItemAccess/transfer API - keep ItemStackHandler" + $nl + "            this.bound = true;"))
            # Entity capability bind block
            $t = [regex]::Replace($t,
                '(?ms)IItemHandler\s+cap\s*=\s*\(IItemHandler\)\s*this\.boundEntity\.getCapability\s*\(\s*ItemHandler\.ENTITY\s*\)\s*;\s*if\s*\(\s*cap\s*!=\s*null\s*\)\s*\{\s*this\.internal\s*=\s*cap\s*;\s*this\.bound\s*=\s*true\s*;\s*\}',
                ("// 26.2: Capabilities.Item.ENTITY transfer rewrite skipped - keep ItemStackHandler" + $nl + "               this.bound = true;"))
            # Leftover bare references
            $t = $t -replace 'ItemHandler\.ITEM', '/* ItemHandler.ITEM removed */ null'
            $t = $t -replace 'ItemHandler\.ENTITY', '/* ItemHandler.ENTITY removed */ null'
            $t = $t -replace 'ItemHandler\.BLOCK', '/* ItemHandler.BLOCK removed */ null'
        }

        # --- Clean unused FluidState import only when file no longer references FluidState ---
        if ($t -notmatch '\bFluidState\b' -and $t -match 'import\s+net\.minecraft\.world\.level\.material\.FluidState\s*;') {
            $t = $t -replace 'import\s+net\.minecraft\.world\.level\.material\.FluidState\s*;\s*\r?\n', ''
        }

        # --- Minecraft.screen field moved to gui.screen() in 26.2 ---
        # MCreator queueServerWork is drained on ServerTickEvent. Client entity ticks must not enqueue
        # lambdas that captured ClientLevel (C2ME: ThreadLocalRandom owner Render thread vs Server thread).
        if ($t -match 'void\s+queueServerWork\s*\(\s*int' -and $t -notmatch 'ServerLifecycleHooks\.getCurrentServer') {
            $t = $t -replace '(public static void queueServerWork\(int tick, Runnable action\) \{\s*)(workQueue\.add)',
                "`$1net.minecraft.server.MinecraftServer _srv = net.neoforged.neoforge.server.ServerLifecycleHooks.getCurrentServer();`r`n      if (_srv == null || !_srv.isSameThread()) { return; }`r`n      `$2"
        }

        $t = $t -replace 'Minecraft\.getInstance\(\)\.screen\b', 'Minecraft.getInstance().gui.screen()'
        $t = $t -replace '(?<![\w.])minecraft\.screen\b', 'minecraft.gui.screen()'

        # --- DeferredRegister.Items.registerItem(..., Properties) needs Supplier/UnaryOperator ---
        # Repair broken form produced by naive rewrite (nested BlockItem prop mistaken for registerItem 3rd arg):
        #   new BlockItem(block, () -> prop)  ->  new BlockItem(block, prop)
        $t = $t -replace 'new\s+BlockItem\(([^,]+),\s*\(\)\s*->\s*prop\)', 'new BlockItem($1, prop)'
        # MCreator block helper line: registerItem(path, prop -> new BlockItem(..., prop), properties)
        # wrap only the final Properties variable as a supplier.
        $t = [regex]::Replace($t,
            '(?m)(\.registerItem\([^\n]+,\s*prop\s*->\s*new\s+BlockItem\([^\n]+,\s*prop\))\s*,\s*(\w+)\s*\)\s*;',
            {
                param($m)
                $head = $m.Groups[1].Value
                $props = $m.Groups[2].Value
                if ($props -eq 'prop') { return $m.Value }
                if ($m.Value -match ',\s*\(\)\s*->') { return $m.Value }
                "$head, () -> $props);"
            })

        # --- Payload registrar: StreamCodec<? extends FriendlyByteBuf -> ? super RegistryFriendlyByteBuf ---
        $t = $t -replace 'StreamCodec<\s*\?\s*extends\s+FriendlyByteBuf\s*,', 'StreamCodec<? super RegistryFriendlyByteBuf,'
        if ($t -match 'RegistryFriendlyByteBuf' -and $t -notmatch 'import\s+net\.minecraft\.network\.RegistryFriendlyByteBuf\s*;') {
            if ($t -match 'import\s+net\.minecraft\.network\.FriendlyByteBuf\s*;') {
                $t = $t -replace 'import\s+net\.minecraft\.network\.FriendlyByteBuf\s*;',
                    "import net.minecraft.network.FriendlyByteBuf;`r`nimport net.minecraft.network.RegistryFriendlyByteBuf;"
            }
            elseif ($t -match '(?m)^package\s+[^;]+;') {
                $t = [regex]::Replace($t, '(?m)^(package\s+[^;]+;\s*)',
                    "`$1`r`nimport net.minecraft.network.RegistryFriendlyByteBuf;`r`n", 1)
            }
        }
        # NeoForge 26.2: 3-arg playBidirectional leaves client handler null and crashes:
        # "Some clientbound payloads are missing client-side handlers"
        # Only rewrite the exact MCreator 3-arg form:
        #   playBidirectional(id, networkMessage.reader(), networkMessage.handler())
        # Do NOT match partial 4-arg lines or method calls mid-argument (that produced broken
        # "handler(, handler(), handler())" syntax on MOA Electronics).
        $t = $t -replace '\.playBidirectional\(\s*(\w+)\s*,\s*(\w+)\.reader\(\)\s*,\s*(\w+)\.handler\(\)\s*\)', '.playBidirectional($1, $2.reader(), $3.handler(), $3.handler())'
        # Also repair already-corrupted form from older converter builds:
        $t = $t -replace '\.playBidirectional\(\s*(\w+)\s*,\s*(\w+)\.reader\(\)\s*,\s*(\w+)\.handler\(\s*,\s*\3\.handler\(\)\s*,\s*\3\.handler\(\)\s*\)\s*\)', '.playBidirectional($1, $2.reader(), $3.handler(), $3.handler())'

        # MCreator main-mod class: forEach wildcards cannot infer playBidirectional (3-arg or 4-arg).
        if ($t -match 'MESSAGES\.forEach\s*\(\s*\(\s*id\s*,\s*networkMessage\s*\)\s*->\s*registrar\.playBidirectional' -and $t -notmatch 'void\s+registerOne\s*\(') {
            $classMatch = [regex]::Match($t, 'public\s+class\s+(\w+)')
            $className = if ($classMatch.Success) { $classMatch.Groups[1].Value } else { 'ModMain' }
            $t = [regex]::Replace($t,
                'MESSAGES\.forEach\s*\(\s*\(\s*id\s*,\s*networkMessage\s*\)\s*->\s*registrar\.playBidirectional\s*\([^;]*?\)\s*\)\s*;',
                "for (var entry : MESSAGES.entrySet()) {`r`n         registerOne(registrar, entry.getKey(), entry.getValue());`r`n      }")
            if ($t -match 'networkingRegistered\s*=\s*true' -and $t -notmatch 'void\s+registerOne\s*\(') {
                $helper = @"

   `@SuppressWarnings("unchecked")
   private static <T extends CustomPacketPayload> void registerOne(
      PayloadRegistrar registrar, Type<?> id, $className.NetworkMessage<?> message
   ) {
      IPayloadHandler<T> handler = (IPayloadHandler<T>)message.handler();
      registrar.playBidirectional(
         (Type<T>)id,
         (StreamCodec<? super RegistryFriendlyByteBuf, T>)message.reader(),
         handler,
         handler
      );
   }
"@
                $t = [regex]::Replace($t, '(networkingRegistered\s*=\s*true\s*;)(\s*\})', "`$1`$2`r`n$helper", 1)
            }
        }

        # SavedDataType first arg is Identifier in 26.2 (MCreator 1.21.x passed a String)
        $t = [regex]::Replace($t,
            'new\s+SavedDataType(?:<>)?\s*\(\s*"([^"]+)"\s*,',
            'new SavedDataType(Identifier.parse("$1"),')
        # SavedData codec lambdas: ctx is ServerLevel in 26.2, not a HolderLookup context
        $t = $t -replace '\.read\(\s*tag\s*,\s*ctx\.levelOrThrow\(\)\.registryAccess\(\)\s*\)', '.read(tag, null)'
        $t = $t -replace '\.save\(\s*new\s+CompoundTag\(\)\s*,\s*ctx\.levelOrThrow\(\)\.registryAccess\(\)\s*\)', '.save(new CompoundTag(), null)'

        # MoveControl.Operation is protected in 26.2 — hasWanted() is the public MOVE_TO check
        $t = $t -replace 'import\s+net\.minecraft\.world\.entity\.ai\.control\.MoveControl\.Operation\s*;\s*\r?\n', ''
        $t = $t -replace 'this\.operation\s*==\s*Operation\.MOVE_TO', 'this.hasWanted()'
        $t = $t -replace 'this\.operation\s*==\s*MoveControl\.Operation\.MOVE_TO', 'this.hasWanted()'

        # MCreator entity methods inject `entity` locals that do not exist on `this`
        $t = [regex]::Replace($t,
            '(?m)^(\s*)double x = entity\.getX\(\);\s*\r?\n\s*double y = entity\.getY\(\);\s*\r?\n\s*double z = entity\.getZ\(\);\s*\r?\n\s*Level world = entity\.level\(\);',
            '$1double x = this.getX();' + "`r`n" + '$1double y = this.getY();' + "`r`n" + '$1double z = this.getZ();' + "`r`n" + '$1Level world = this.level();')

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-McreatorForge1201ResiduePass {
    <#
    .SYNOPSIS
      MCreator Forge 1.20.1 leftovers after SRG remap: overlay blit, food builder,
      SavedData 26.2, mob effects, animation factory, NBT Optional accessors.
      Names verified from mcp_config-1.20.1 joined.tsrg + Mojang 1.20.1 mappings.
    #>
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # FoodProperties 26.2 builder
        $t = $t -replace '\.saturationMod\(', '.saturationModifier('
        $t = $t -replace '\.alwaysEat\(', '.alwaysEdible('
        $t = $t -replace '\.meat\(\)', ''

        # RenderGuiEvent.Pre has no getWindow(); Window is on Minecraft
        $t = $t -replace 'event\.getWindow\(\)', 'Minecraft.getInstance().getWindow()'
        # 26.2 GuiGraphicsExtractor.blit requires a RenderPipeline
        $t = $t -replace 'getGuiGraphics\(\)\.blit\(Identifier\.parse\(', 'getGuiGraphics().blit(net.minecraft.client.renderer.RenderPipelines.GUI_TEXTURED, Identifier.parse('
        $t = $t -replace '(?m)^\s*RenderSystem\.[^;]+;\s*\r?\n', ''

        # EntityTickEvent.Post.getEntity() is Entity, not LivingEntity
        $t = $t -replace 'LivingEntity animation = event\.getEntity\(\);', 'net.minecraft.world.entity.Entity animation = event.getEntity();'
        $t = $t -replace 'String animation = syncable\.getSyncedAnimation\(\);', 'String syncedAnim = syncable.getSyncedAnimation();'
        $t = $t -replace 'if \(!animation\.equals\("undefined"\)\)', 'if (!syncedAnim.equals("undefined"))'
        $t = $t -replace 'syncable\.animationprocedure = animation;', 'syncable.animationprocedure = syncedAnim;'

        # MobEffect 26.2
        $t = $t -replace 'boolean isDurationEffectTick\(', 'boolean shouldApplyEffectTickThisTick('
        $t = [regex]::Replace($t,
            'public void applyEffectTick\(LivingEntity (\w+), int (\w+)\) \{([^}]*)\}',
            'public boolean applyEffectTick(net.minecraft.server.level.ServerLevel level, LivingEntity $1, int $2) {$3 return true; }')
        $t = [regex]::Replace($t,
            '(?ms)\s*public boolean renderInventoryText\([^)]*\) \{\s*return false;\s*\}',
            '')

        # CompoundTag 26.2 Optional accessors — only NBT variables, never Brigadier getDouble
        foreach ($nbtVar in @('nbt', 'tag', 'compound', 'compoundTag')) {
            $t = $t -replace "\b$nbtVar\.getBoolean\(([^)]+)\)", "$nbtVar.getBooleanOr(`$1, false)"
            $t = $t -replace "\b$nbtVar\.getDouble\(([^)]+)\)", "$nbtVar.getDoubleOr(`$1, 0.0)"
            $t = $t -replace "\b$nbtVar\.getInt\(([^)]+)\)", "$nbtVar.getIntOr(`$1, 0)"
            $t = $t -replace "\b$nbtVar\.getString\(([^)]+)\)", "$nbtVar.getStringOr(`$1, `"`")"
        }

        # MCreator SimpleChannel leftover
        $t = [regex]::Replace($t, '(?s)SimpleChannel\s+\w+\s*=\s*\w+\.PACKET_HANDLER;.*?\.send\([^;]+;', 'this.setDirty();')
        $t = [regex]::Replace($t, '(?m)^\s*\w+\.PACKET_HANDLER\.send\([^;]+;\s*$', '         /* 26.2 payload sync: RegisterPayloadHandlersEvent */')
        $t = [regex]::Replace($t,
            '(?s)public static void handler\([^)]*\) \{.*?\n      \}',
            "public static void handler(SavedDataSyncMessage message, Object contextSupplier) { /* 26.2 IPayloadContext */ }")

        if ($t -match 'extends SavedData') {
            $t = $t -replace 'void read\(CompoundTag nbt\)', 'void read(CompoundTag nbt, net.minecraft.core.HolderLookup.Provider lookup)'
            $t = $t -replace 'CompoundTag save\(CompoundTag nbt\)', 'CompoundTag save(CompoundTag nbt, net.minecraft.core.HolderLookup.Provider lookup)'
            $t = $t -replace 'data\.read\(tag\);', 'data.read(tag, null);'
            $t = $t -replace '\.read\(buffer\.readNbt\(\)\)', '.read(buffer.readNbt(), null)'
            $t = $t -replace 'message\.data\.save\(new CompoundTag\(\)\)', '((message.data instanceof WorldVariables wv) ? wv.save(new CompoundTag(), null) : ((MapVariables)message.data).save(new CompoundTag(), null))'

            $t = [regex]::Replace($t,
                '(?s)public void syncData\(LevelAccessor world\) \{.*?\n      \}',
                "public void syncData(LevelAccessor world) {`r`n         this.setDirty();`r`n      }")

            if ($t -notmatch 'SavedDataType<') {
                $nl = [Environment]::NewLine
                $t = [regex]::Replace($t,
                    'public static final String DATA_NAME = "([^"]+)_worldvars";',
                    {
                        param($m)
                        $modid = $m.Groups[1].Value
                        $n = [Environment]::NewLine
                        "public static final String DATA_NAME = `"$modid`_worldvars`";$n" +
                        "      public static final com.mojang.serialization.Codec<WorldVariables> CODEC = net.minecraft.nbt.CompoundTag.CODEC.xmap(tag -> {$n" +
                        "         WorldVariables instance = new WorldVariables();$n" +
                        "         instance.read(tag, null);$n" +
                        "         return instance;$n" +
                        "      }, instance -> instance.save(new net.minecraft.nbt.CompoundTag(), null));$n" +
                        "      public static final net.minecraft.world.level.saveddata.SavedDataType<WorldVariables> TYPE = new net.minecraft.world.level.saveddata.SavedDataType<>($n" +
                        "         net.minecraft.resources.Identifier.fromNamespaceAndPath(`"$modid`", `"worldvars`"),$n" +
                        "         WorldVariables::new,$n" +
                        "         CODEC$n" +
                        "      );"
                    })
                $t = [regex]::Replace($t,
                    'public static final String DATA_NAME = "([^"]+)_mapvars";',
                    {
                        param($m)
                        $modid = $m.Groups[1].Value
                        $n = [Environment]::NewLine
                        "public static final String DATA_NAME = `"$modid`_mapvars`";$n" +
                        "      public static final com.mojang.serialization.Codec<MapVariables> CODEC = net.minecraft.nbt.CompoundTag.CODEC.xmap(tag -> {$n" +
                        "         MapVariables instance = new MapVariables();$n" +
                        "         instance.read(tag, null);$n" +
                        "         return instance;$n" +
                        "      }, instance -> instance.save(new net.minecraft.nbt.CompoundTag(), null));$n" +
                        "      public static final net.minecraft.world.level.saveddata.SavedDataType<MapVariables> TYPE = new net.minecraft.world.level.saveddata.SavedDataType<>($n" +
                        "         net.minecraft.resources.Identifier.fromNamespaceAndPath(`"$modid`", `"mapvars`"),$n" +
                        "         MapVariables::new,$n" +
                        "         CODEC$n" +
                        "      );"
                    })
            }

            $t = [regex]::Replace($t,
                'getDataStorage\(\)\.(?:register|computeIfAbsent)\(\(e\) -> load\(e\),\s*WorldVariables::new,\s*"[^"]+"\)',
                'getDataStorage().computeIfAbsent(TYPE)')
            $t = [regex]::Replace($t,
                'getDataStorage\(\)\.(?:register|computeIfAbsent)\(\(e\) -> load\(e\),\s*MapVariables::new,\s*"[^"]+"\)',
                'getDataStorage().computeIfAbsent(TYPE)')
        }

        # BlockPos.containing already mapped; leftover parse(x,y,z)
        $t = $t -replace 'BlockPos\.parse\(', 'BlockPos.containing('
        $t = $t -replace 'Mth\.add\(RandomSource\.create\(\)', 'Mth.nextInt(RandomSource.create()'
        $t = $t -replace 'Mth\.add\(RandomSource\.add\(\)', 'Mth.nextInt(RandomSource.create()'
        $t = $t -replace '\.hasProperty\(\)', '.canOcclude()'
        $t = [regex]::Replace($t,
            '(SpawnGroupData retval = super\.finalizeSpawn\(world, difficulty, reason, livingdata\);\s*)(\s*)((?:[\w.]+)?OnInitialEntitySpawnProcedure\.execute\([^;]+;)',
            '$1$2if (reason != net.minecraft.world.entity.EntitySpawnReason.SPAWN_ITEM_USE && reason != net.minecraft.world.entity.EntitySpawnReason.COMMAND && reason != net.minecraft.world.entity.EntitySpawnReason.DISPENSER && reason != net.minecraft.world.entity.EntitySpawnReason.MOB_SUMMONED) { $3 }')
        $t = $t -replace 'super\.m_5993_\(', 'super.awardKillScore('
        $t = $t -replace '\.getLookAngle\(([^,]+),\s*(?:true|false)\)', '.sendSystemMessage($1)'
        $t = $t -replace 'void awardKillScore\(Entity (\w+), int \w+, DamageSource (\w+)\)', 'void awardKillScore(Entity $1, DamageSource $2)'
        $t = $t -replace 'super\.awardKillScore\((\w+),\s*\w+,\s*(\w+)\)', 'super.awardKillScore($1, $2)'
        $t = $t -replace '(?<![\w.])event\.player\b', 'event.getEntity()'
        # Do not rewrite package net.neoforged.neoforge.event.level
        $t = $t -replace '(?<![\w.])event\.level\b(?!\s*\()(?!\.)', 'event.getLevel()'
        $t = $t -replace 'net\.neoforged\.neoforge\.event\.getLevel\(\)\.BlockEvent', 'net.neoforged.neoforge.event.level.BlockEvent'
        $t = $t -replace 'net\.neoforged\.neoforge\.event\.getLevel\(\)\.block', 'net.neoforged.neoforge.event.level.block'
        $t = $t -replace '(?m)^\s*\w+\.addNetworkMessage\([^;]+;\s*$', '      /* 26.2: RegisterPayloadHandlersEvent */'
        $t = $t -replace '\)\.immutable\(\)', ')'
        $t = $t -replace '\)\.withSuppressedOutput\(\)', ')'
        $t = $t -replace 'MobEffects\.MOVEMENT_SLOWDOWN', 'MobEffects.SLOWNESS'
        $t = $t -replace 'MobEffects\.MOVEMENT_SPEED', 'MobEffects.SPEED'
        $t = $t -replace 'MobEffects\.DAMAGE_RESISTANCE', 'MobEffects.RESISTANCE'
        $t = $t -replace '(\w+)\.hurt\(new DamageSource\(world\.registryAccess\(\)\.get\(Registries\.DAMAGE_TYPE\)\.holder\(DamageTypes\.GENERIC\)\)', '$1.hurt($1.damageSources().generic()'
        $t = $t -replace 'connection\.teleport\(([^;]+),\s*(\w+)\.getYRot\(\),\s*\2\)', 'connection.teleport($1, $2.getYRot(), $2.getXRot())'
        $t = $t -replace 'world\.isEmptyBlock\(([^,]+),\s*false\)', 'world.destroyBlock($1, false)'
        $t = $t -replace '\.getCooldowns\(\)\.register\(', '.getCooldowns().addCooldown('
        $t = $t -replace '\.getCooldowns\(\)\.addCooldown\(Items\.(\w+),\s*(\d+)\)', '.getCooldowns().addCooldown(new net.minecraft.world.item.ItemStack(Items.$1), $2)'
        $t = $t -replace 'this\.dropExperience\(\);', 'if (this.level() instanceof net.minecraft.server.level.ServerLevel _xpLevel) { this.dropExperience(_xpLevel, this); }'
        $t = $t -replace 'protected void dropCustomDeathLoot\(DamageSource (\w+), int \w+, boolean (\w+)\)', 'protected void dropCustomDeathLoot(net.minecraft.server.level.ServerLevel level, DamageSource $1, boolean $2)'
        $t = $t -replace 'super\.dropCustomDeathLoot\((\w+),\s*\w+,\s*(\w+)\);', 'super.dropCustomDeathLoot(level, $1, $2);'
        $t = $t -replace '\(MobEffect\)(\w+\.\w+)\.get\(\)', '$1'
        $t = $t -replace 'MobEffects\.DIG_SLOWDOWN', 'MobEffects.MINING_FATIGUE'
        $t = $t -replace '(\w+)\.hurt\(new DamageSource\(world\.registryAccess\(\)\.(?:get|registryOrThrow)\(Registries\.DAMAGE_TYPE\)\.(?:holder|getHolderOrThrow)\(DamageTypes\.GENERIC\)\)', '$1.hurt($1.damageSources().generic()'
        $t = $t -replace 'UnmodifiableIterator (\w+) = _bso\.getValues\(\)\.entrySet\(\)\.iterator\(\);', 'java.util.Iterator $1 = _bso.getValues().map(v -> java.util.Map.entry((Property<?>)v.property(), (Comparable<?>)v.value())).iterator();'

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-ModConfigSpecOrderPass {
    <#
    .SYNOPSIS
      Fix decompiled MCreator ModConfigSpec classes that call BUILDER.build() before .define().
      That order throws "Cannot get config value before spec is built" on world join / player spawn
      (proven disconnect on The Knocker).
    #>
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        if ($t -notmatch 'ModConfigSpec' -or $t -notmatch 'BUILDER\.build\(\)' -or $t -notmatch '\.define\(') { continue }

        $buildIdx = $t.IndexOf('BUILDER.build()')
        $defineIdx = $t.IndexOf('.define(')
        if ($buildIdx -lt 0 -or $defineIdx -lt 0 -or $defineIdx -le $buildIdx) { continue }

        $o = $t
        # Drop early SPEC = BUILDER.build() field assignment (common MCreator decompile order)
        $t = [regex]::Replace($t,
            '(?m)^\s*public\s+static\s+final\s+ModConfigSpec\s+SPEC\s*=\s*BUILDER\.build\(\)\s*;\s*\r?\n',
            '')

        # If SPEC field vanished entirely, redeclare at end before last class brace
        if ($t -notmatch 'ModConfigSpec\s+SPEC\b') {
            $t = [regex]::Replace($t, '(?s)(.*\r?\n)(\})\s*\z',
                "`$1    public static final ModConfigSpec SPEC = BUILDER.build();`r`n`$2`r`n", 1)
        }
        elseif ($t -match 'public\s+static\s+final\s+ModConfigSpec\s+SPEC\s*;' -and $t -notmatch 'SPEC\s*=\s*BUILDER\.build\(\)') {
            $t = [regex]::Replace($t, '(?s)(.*\r?\n)(\})\s*\z',
                "`$1    static { SPEC = BUILDER.build(); }`r`n`$2`r`n", 1)
        }
        elseif ($t -notmatch 'SPEC\s*=\s*BUILDER\.build\(\)') {
            # SPEC field still missing assignment after strip
            $t = [regex]::Replace($t, '(?s)(.*\r?\n)(\})\s*\z',
                "`$1    public static final ModConfigSpec SPEC = BUILDER.build();`r`n`$2`r`n", 1)
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
            Write-Info "ModConfigSpec order fixed: $($f.Name)"
        }
    }
    return $touched
}

function Invoke-RegistryTemplatePass {
    <#
    .SYNOPSIS
      Rewrite simple DeferredRegister entity/sound patterns to NeoForge 26 createEntities / Registries forms.
    #>
    param([string]$Root)

    $fixed = 0
    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # DeferredRegister.create(ForgeRegistries/BuiltInRegistries.ENTITY_TYPE[S], modid)
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.ENTITY_TYPES|BuiltInRegistries\s*/\*[^*]*\*/\s*\.ENTITY_TYPE|BuiltInRegistries\.ENTITY_TYPE)\s*,\s*([^)]+)\)',
            'DeferredRegister.createEntities($1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.SOUND_EVENTS|BuiltInRegistries\s*/\*[^*]*\*/\s*\.SOUND_EVENT|BuiltInRegistries\.SOUND_EVENT)\s*,\s*([^)]+)\)',
            'DeferredRegister.create(net.minecraft.core.registries.Registries.SOUND_EVENT, $1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.ITEMS|BuiltInRegistries\.ITEM)\s*,\s*([^)]+)\)',
            'DeferredRegister.createItems($1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.BLOCKS|BuiltInRegistries\.BLOCK)\s*,\s*([^)]+)\)',
            'DeferredRegister.createBlocks($1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.FEATURES|BuiltInRegistries\.FEATURE)\s*,\s*([^)]+)\)',
            'DeferredRegister.create(net.minecraft.core.registries.Registries.FEATURE, $1)')
        $t = [regex]::Replace($t,
            'DeferredRegister\.create\(\s*(?:ForgeRegistries\.MOB_EFFECTS|BuiltInRegistries\.MOB_EFFECT)\s*,\s*([^)]+)\)',
            'DeferredRegister.create(net.minecraft.core.registries.Registries.MOB_EFFECT, $1)')

        $modidMatch = [regex]::Match($t, 'DeferredRegister\.createEntities\("([^"]+)"\)')
        if ($modidMatch.Success) {
            $mid = $modidMatch.Groups[1].Value
            $t = $t -replace 'entityTypeBuilder\.build\((\w+)\)',
                "entityTypeBuilder.build(net.minecraft.resources.ResourceKey.create(net.minecraft.core.registries.Registries.ENTITY_TYPE, net.minecraft.resources.Identifier.fromNamespaceAndPath(`"$mid`", `$1)))"
        }

        # Ensure imports for DeferredHolder when used
        if ($t -match 'DeferredHolder' -and $t -notmatch 'import net\.neoforged\.neoforge\.registries\.DeferredHolder') {
            $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.neoforge.registries.DeferredHolder;"
        }
        if ($t -match 'DeferredRegister\.createEntities' -and $t -notmatch 'import net\.neoforged\.neoforge\.registries\.DeferredRegister') {
            $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.neoforge.registries.DeferredRegister;"
        }

        $t = $t -replace 'DeferredHolder<\s*EntityType<([^>]+)>\s*>', 'DeferredHolder<EntityType<?>, EntityType<$1>>'
        $t = $t -replace 'private static <T extends Entity> DeferredHolder<EntityType<T>>', 'private static <T extends Entity> DeferredHolder<EntityType<?>, EntityType<T>>'
        $t = $t -replace 'DeferredHolder<Block>(?!\s*,)', 'DeferredHolder<Block, Block>'
        $t = $t -replace 'DeferredHolder<Item>(?!\s*,)', 'DeferredHolder<Item, Item>'
        $t = $t -replace 'DeferredHolder<Feature<\?>>(?!\s*,)', 'DeferredHolder<Feature<?>, Feature<?>>'
        $t = $t -replace 'DeferredHolder<SoundEvent>(?!\s*,)', 'DeferredHolder<SoundEvent, SoundEvent>'
        $t = $t -replace 'DeferredHolder<MobEffect>(?!\s*,)', 'DeferredHolder<MobEffect, MobEffect>'
        $t = $t -replace 'DeferredHolder<CreativeModeTab>(?!\s*,)', 'DeferredHolder<CreativeModeTab, CreativeModeTab>'

        # EntityType register lambda with Builder.of(...).build() - try registerEntityType when simple
        # public static final DeferredHolder<EntityType<X>, ...> NAME = REG.register("id", () -> EntityType.Builder.of(X::new, CAT)...build());
        # Too risky to auto-convert all forms; leave for compile errors.

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $fixed++
        }
    }
    return $fixed
}

function Invoke-BlockItemIdPass {
    <#
    .SYNOPSIS
      Minecraft 26.2 requires Block/Item Properties.setId before construction.
      DeferredRegister.Blocks.registerBlock / Items.registerItem inject the id.
      MCreator no-arg ctors that call Properties.of() / new Item.Properties() NPE:
      "Block id not set" / "Item id not set" (TOWW crash 2026-08-23).
    #>
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # Block: public Foo() { super(Properties.of().chain); } -> Foo(Properties properties) { super(properties.chain); }
        $t = [regex]::Replace($t,
            'public (\w+)\(\) \{\s*super\(Properties\.of\(\)',
            'public $1(net.minecraft.world.level.block.state.BlockBehaviour.Properties properties) { super(properties')
        $t = [regex]::Replace($t,
            'public (\w+)\(\) \{\s*super\(\(new BlockBehaviour\.Properties\(\)\)',
            'public $1(net.minecraft.world.level.block.state.BlockBehaviour.Properties properties) { super(properties')

        # Item: public Foo() { super((new Item.Properties()).chain); }
        $t = [regex]::Replace($t,
            'public (\w+)\(\) \{\s*super\(\(new Item\.Properties\(\)\)',
            'public $1(net.minecraft.world.item.Item.Properties properties) { super(properties')

        # Registry field types so registerBlock/registerItem resolve
        $t = $t -replace 'public static final DeferredRegister<Block> REGISTRY', 'public static final DeferredRegister.Blocks REGISTRY'
        $t = $t -replace 'public static final DeferredRegister<Item> REGISTRY', 'public static final DeferredRegister.Items REGISTRY'

        # Blocks: REGISTRY.register("id", () -> new FooBlock()) -> registerBlock("id", FooBlock::new)
        $t = [regex]::Replace($t,
            'REGISTRY\.register\("([^"]+)",\s*\(\)\s*->\s*new (\w+Block)\(\)\)',
            'REGISTRY.registerBlock("$1", $2::new)')

        # Items: REGISTRY.register("id", () -> new FooItem()) -> registerItem
        $t = [regex]::Replace($t,
            'REGISTRY\.register\("([^"]+)",\s*\(\)\s*->\s*new (\w+Item)\(\)\)',
            'REGISTRY.registerItem("$1", $2::new)')

        # SpawnEggItem(new Item.Properties())
        $t = [regex]::Replace($t,
            'REGISTRY\.register(?:Item)?\("([^"]+)",\s*\(\)\s*->\s*new SpawnEggItem\(new Item\.Properties\(\)\.spawnEgg\(([^)]+)\)\)\)',
            'REGISTRY.registerItem("$1", properties -> new SpawnEggItem(properties.spawnEgg($2)))')
        $t = [regex]::Replace($t,
            'REGISTRY\.register(?:Item)?\("([^"]+_spawn_egg)",\s*\(\)\s*->\s*new SpawnEggItem\(new Item\.Properties\(\)\)\)',
            'REGISTRY.registerItem("$1", properties -> new SpawnEggItem(properties))')

        # BlockItem helper used by MCreator *ModItems
        $t = $t -replace 'REGISTRY\.register\(block\.getId\(\)\.getPath\(\),\s*\(\)\s*->\s*new BlockItem\(\(Block\)block\.get\(\),\s*new Item\.Properties\(\)\)\)',
            'REGISTRY.registerItem(block.getId().getPath(), prop -> new BlockItem((Block)block.get(), prop))'

        # Custom helper used by source mods such as NextGen Furniture. A Supplier
        # hides the registry key until after construction, which crashes in 26.2.
        # Convert it to DeferredRegister.Blocks.registerBlock's keyed Properties
        # function and likewise let DeferredRegister.Items inject the item id.
        $t = Convert-CustomBlockRegistrationText -Text $t

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-GeckoLib26Pass {
    <#
    .SYNOPSIS
      GeckoLib 5.5 / NeoForge 26.2 (The One Who Watches + Friend proven):
      - GeoModel IDs are bare names (already stripped of geo/ and .json)
      - getTextureResource(GeoRenderState) cannot call entity.getTexture(); use the
        entity's synched TEXTURE default (never unknown.png)
      - ControllerRegistrar.add takes AnimationController, not AnimationController[]
    #>
    param([string]$Root)

    $javaRoot = Join-Path $Root 'src\main\java'
    $textureDefault = @{}
    foreach ($ef in Get-ChildItem $javaRoot -Recurse -Filter '*Entity.java' -File -ErrorAction SilentlyContinue) {
        $et = [System.IO.File]::ReadAllText($ef.FullName)
        $m = [regex]::Match($et, 'define\(\s*TEXTURE\s*,\s*"([^"]+)"\s*\)')
        if ($m.Success) {
            $textureDefault[$ef.BaseName] = $m.Groups[1].Value
        }
    }

    $touched = 0
    foreach ($f in Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        if ($t -match 'extends\s+GeoModel') {
            $tex = 'toww_reborn'
            $ent = [regex]::Match($t, 'extends\s+GeoModel<(\w+)>')
            if ($ent.Success -and $textureDefault.ContainsKey($ent.Groups[1].Value)) {
                $tex = $textureDefault[$ent.Groups[1].Value]
            }
            $t = $t -replace 'textures/entities/unknown\.png', "textures/entities/$tex.png"
        }

        $t = $t -replace 'data\.add\(new AnimationController\[\]\{new AnimationController(?:<>)?\(', 'data.add(new AnimationController<>('
        $t = $t -replace 'controllers\.add\(new AnimationController\[\]\{new AnimationController(?:<>)?\(', 'controllers.add(new AnimationController<>('
        $t = $t -replace '(this::\w+)\)\}\);', '$1));'
        # Completed TOWW 26.2: unused procedure controller must STOP, not CONTINUE (in-place mesh jitter).
        # Do not flatten movement clips to pose1 — hunting uses chase, hanging hang, crawling pose6.
        $t = [regex]::Replace($t,
            '(?s)private PlayState procedurePredicate\(AnimationTest event\) \{.*?\n   \}',
            @'
private PlayState procedurePredicate(AnimationTest event) {
      String synced = this.getSyncedAnimation();
      if (synced != null && !synced.isEmpty() && !synced.equals("undefined")) {
         this.animationprocedure = synced;
      }
      String clip = this.animationprocedure;
      if (clip == null || clip.isEmpty() || clip.equals("empty") || clip.equals("undefined")) {
         return PlayState.STOP;
      }
      return event.setAndContinue(RawAnimation.begin().thenPlay(clip));
   }
'@)
        $t = $t -replace '(?m)^\s*this\.refreshDimensions\(\);\s*\r?\n', ''
        $t = $t -replace 'LookAtPlayerGoal\(this, Player\.class, 1000\.0F\)', 'LookAtPlayerGoal(this, Player.class, 64.0F)'
        if ($t -match 'extends\s+Animal') {
            $t = $t -replace 'Mob\.createMobAttributes\(\)', 'Animal.createAnimalAttributes()'
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-ModEntryTemplatePass {
    param([string]$Root)

    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File |
        Where-Object { (Get-Content $_.FullName -Raw) -match '@Mod\(' }
    $n = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t
        # Convert no-arg mod constructor using FMLJavaModLoadingContext to IEventBus + ModContainer
        if ($t -match 'FMLJavaModLoadingContext' -or $t -match 'ModLoadingContext\.get\(\)\.registerConfig') {
            if ($t -notmatch 'import net\.neoforged\.bus\.api\.IEventBus') {
                $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.bus.api.IEventBus;"
            }
            if ($t -notmatch 'import net\.neoforged\.fml\.ModContainer') {
                $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport net.neoforged.fml.ModContainer;"
            }
            # Replace constructor signature public Foo() { ... getModEventBus ...}
            $t = [regex]::Replace($t,
                'public\s+(\w+)\s*\(\s*\)\s*\{',
                'public $1(IEventBus modBus, ModContainer container) {')
            $t = $t -replace '/\*\s*TODO:\s*inject IEventBus\s*\*/\s*', ''
            $t = $t -replace '/\*\s*TODO inject IEventBus\s*\*/\s*', ''
            $t = $t -replace 'FMLJavaModLoadingContext\.get\(\)\.getModEventBus\(\)', 'modBus'
            $t = $t -replace 'var\s+modBus\s*=\s*modBus\s*;', ''
            $t = $t -replace 'ModLoadingContext\.get\(\)\.registerConfig\(', 'container.registerConfig('
            # drop unused imports
            $t = $t -replace 'import\s+net\.neoforged\.fml\.javafmlmod\.FMLJavaModLoadingContext;\r?\n', ''
            $t = $t -replace 'import\s+net\.neoforged\.fml\.ModLoadingContext;\r?\n', ''
        }
        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $n++
        }
    }
    return $n
}

function Invoke-EventBusSubscriberPass {
    <#
    .SYNOPSIS
      NeoForge 26.x no longer exposes @Mod.EventBusSubscriber the same way.
      Convert annotated static @SubscribeEvent handlers into explicit
      modBus / NeoForge.EVENT_BUS addListener registrations.
    #>
    param([string]$Root, [hashtable]$Meta)

    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }

    $modBusMethods = New-Object System.Collections.Generic.List[string]
    $gameBusMethods = New-Object System.Collections.Generic.List[string]
    $imports = New-Object System.Collections.Generic.HashSet[string]
    $filesTouched = 0

    $modBusEventHints = @(
        'EntityAttributeCreationEvent', 'EntityRenderersEvent', 'RegisterParticleProvidersEvent',
        'RegisterMenuScreensEvent', 'RegisterClientReloadListenersEvent', 'BuildCreativeModeTabContentsEvent',
        'RegisterCommandsEvent'  # sometimes mod bus in older; usually game - keep game for commands below
    )

    foreach ($f in Get-ChildItem $javaRoot -Recurse -Filter '*.java') {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        # Forge 1.20.1 uses @Mod.EventBusSubscriber. NeoForge 1.21.x @EventBusSubscriber still works on 26.2
        # (proven on The Knocker). Only rewrite the Forge-style annotation; do not emit broken
        # OuterClass::method refs for nested @EventBusSubscriber config/client classes.
        if ($t -notmatch '@Mod\.EventBusSubscriber') { continue }

        $pkg = if ($t -match 'package\s+([\w\.]+)\s*;') { $Matches[1] } else { continue }
        $cls = if ($t -match 'public\s+(?:final\s+)?class\s+(\w+)') { $Matches[1] } else { continue }
        $fqcn = "$pkg.$cls"

        # Collect static subscribe methods: public static void name(EventType event)
        $methodMatches = [regex]::Matches($t, '(?s)@SubscribeEvent\s+public\s+static\s+void\s+(\w+)\s*\(\s*([\w\.]+)\s+\w+\s*\)')
        $isClientOnly = $t -match 'value\s*=\s*Dist\.CLIENT' -or $t -match 'Dist\.CLIENT'
        $busIsMod = $t -match 'Bus\.MOD'

        foreach ($mm in $methodMatches) {
            $method = $mm.Groups[1].Value
            $eventType = $mm.Groups[2].Value
            $ref = "${cls}::${method}"
            $imports.Add("import ${fqcn};") | Out-Null

            $useModBus = $busIsMod -or ($modBusEventHints | Where-Object { $eventType -match $_ })
            # Commands / ticks / living / viewport -> game bus
            if ($eventType -match 'TickEvent|ClientTick|ServerTick|Viewport|Living|Player|Level|Block|Command') {
                $useModBus = $false
            }
            if ($eventType -match 'EntityAttribute|EntityRenderers|RegisterParticle|CreativeModeTab|RegisterMenu') {
                $useModBus = $true
            }

            if ($useModBus) {
                $modBusMethods.Add("        modBus.addListener($ref);") | Out-Null
            }
            else {
                $gameBusMethods.Add("        NeoForge.EVENT_BUS.addListener($ref);") | Out-Null
            }
        }

        # Strip class-level EventBusSubscriber annotation (keep methods + SubscribeEvent for clarity optional)
        $t2 = [regex]::Replace($t, '@Mod\.EventBusSubscriber\s*\([^)]*\)\s*', "/* was EventBusSubscriber - registered via LegacyEventBootstrap */`r`n")
        $t2 = $t2 -replace '@OnlyIn\s*\(\s*Dist\.CLIENT\s*\)', '/* @OnlyIn(Dist.CLIENT) removed */'
        $t2 = $t2 -replace 'import\s+net\.neoforged\.neoforge\.api\.distmarker\.OnlyIn;\r?\n', ''
        $t2 = $t2 -replace 'import\s+net\.minecraftforge\.api\.distmarker\.OnlyIn;\r?\n', ''

        if ($t2 -ne $t) {
            [System.IO.File]::WriteAllText($f.FullName, $t2)
            $filesTouched++
        }
    }

    if ($modBusMethods.Count -eq 0 -and $gameBusMethods.Count -eq 0) {
        return $filesTouched
    }

    # Write bootstrap under primary package
    $pkg = $Meta.mod_group
    if (-not $pkg) { $pkg = 'com.example' }
    $dir = Join-Path $javaRoot ($pkg -replace '\.', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $importBlock = ($imports | Sort-Object) -join "`r`n"
    $modLines = if ($modBusMethods.Count) { ($modBusMethods | Select-Object -Unique) -join "`r`n" } else { '        // (none detected)' }
    $gameLines = if ($gameBusMethods.Count) { ($gameBusMethods | Select-Object -Unique) -join "`r`n" } else { '        // (none detected)' }

    $bootstrap = @"
package $pkg;

import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.common.NeoForge;
$importBlock

/**
 * Auto-generated by Convert-Forge1201-ToNeoForge262.
 * Replaces 1.20.1 @Mod.EventBusSubscriber automatic discovery.
 */
public final class LegacyEventBootstrap {
    public static void register(IEventBus modBus) {
$modLines
$gameLines
    }

    private LegacyEventBootstrap() {}
}
"@
    [System.IO.File]::WriteAllText((Join-Path $dir 'LegacyEventBootstrap.java'), $bootstrap.Trim() + "`r`n")

    # Wire into @Mod constructor if present
    foreach ($f in Get-ChildItem $javaRoot -Recurse -Filter '*.java') {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        if ($t -notmatch '@Mod\(') { continue }
        if ($t -match 'LegacyEventBootstrap') { break }
        if ($t -match 'public\s+\w+\s*\(\s*IEventBus\s+(\w+)') {
            $busParam = $Matches[1]
            $t = $t -replace '(package [^;]+;\s*)', "`$1`r`nimport $pkg.LegacyEventBootstrap;`r`n"
            # insert call after opening brace of constructor
            $t = [regex]::Replace($t,
                "(public\s+\w+\s*\(\s*IEventBus\s+$busParam\s*,\s*ModContainer\s+\w+\s*\)\s*\{)",
                "`$1`r`n        LegacyEventBootstrap.register($busParam);")
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $filesTouched++
        }
        break
    }

    return $filesTouched
}

function Restore-ModAssets {
    <#
    .SYNOPSIS
      Decompiled 1.20.1 trees often have Java only. Purple/black items mean assets never copied.
      Pull assets/ + data/ from the source tree, a sibling jar, or the known-good 26.2 TOWW port.
    #>
    param([string]$Source, [string]$Dest, [string]$ModId, [string]$OriginalJarPath = '')

    $destRes = Join-Path $Dest 'src\main\resources'
    $existing = @(Get-ChildItem (Join-Path $destRes 'assets') -Recurse -Include '*.png','*.ogg','*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\items\\' })
    if ($existing.Count -gt 0) { return 0 }

    $copied = 0
    $jarHint = Join-Path $Source 'original-jar.txt'
    $jarFromHint = ''
    if ($OriginalJarPath -and (Test-Path -LiteralPath $OriginalJarPath)) {
        $jarFromHint = $OriginalJarPath
    } elseif (Test-Path -LiteralPath $jarHint) {
        $jarFromHint = (Get-Content -LiteralPath $jarHint -TotalCount 1).Trim()
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(
            (Join-Path $Source 'src\main\resources'),
            (Join-Path $Source 'resources')
        )) {
        if (Test-Path $p) { $candidates.Add($p) | Out-Null }
    }
    if ($ModId -eq 'the_one_who_watches') {
        $toww = 'F:\rob_projects\Completed\GrokBuild_MF\Completed_Projects\Java\26.2\Gradle_Workspaces\TheOneWhoWatches-26.2\src\main\resources'
        if (Test-Path $toww) { $candidates.Add($toww) | Out-Null }
    }

    foreach ($resRoot in $candidates) {
        $assets = Join-Path $resRoot 'assets'
        if (-not (Test-Path $assets)) { continue }
        $ns = if ($ModId) { Join-Path $assets $ModId } else { $null }
        if ($ns -and -not (Test-Path $ns)) { continue }
        Copy-Item -LiteralPath $assets -Destination (Join-Path $destRes 'assets') -Recurse -Force
        $copied++
        $data = Join-Path $resRoot 'data'
        if (Test-Path $data) {
            Copy-Item -LiteralPath $data -Destination (Join-Path $destRes 'data') -Recurse -Force
        }
        $logo = Join-Path $resRoot 'logo.png'
        if (Test-Path $logo) { Copy-Item $logo $destRes -Force }
        Write-Ok "Restored assets from $resRoot"
        return $copied
    }

    $jarFiles = New-Object System.Collections.Generic.List[string]
    if ($jarFromHint -and (Test-Path -LiteralPath $jarFromHint)) { $jarFiles.Add($jarFromHint) | Out-Null }
    foreach ($dir in @($Source, (Split-Path $Source -Parent))) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($jar in Get-ChildItem $dir -Filter '*.jar' -File -ErrorAction SilentlyContinue) {
            if (-not $jarFiles.Contains($jar.FullName)) { $jarFiles.Add($jar.FullName) | Out-Null }
        }
    }
    foreach ($jarPath in $jarFiles) {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
            $hasAssets = $false
            foreach ($e in $zip.Entries) {
                if ($e.FullName -like 'assets/*') { $hasAssets = $true; break }
            }
            if (-not $hasAssets) { $zip.Dispose(); continue }
            foreach ($e in $zip.Entries) {
                if ($e.FullName.EndsWith('/')) { continue }
                if ($e.FullName -notmatch '^(assets|data)/' -and $e.FullName -notin @('logo.png', 'pack.png', 'pack.mcmeta')) { continue }
                $out = Join-Path $destRes ($e.FullName -replace '/', '\')
                $outDir = Split-Path $out -Parent
                if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
                $copied++
            }
            $zip.Dispose()
            if ($copied -gt 0) {
                Write-Ok "Restored $copied asset entries from $(Split-Path $jarPath -Leaf)"
                return $copied
            }
        } catch {
            Write-Warn2 "Asset jar extract failed $(Split-Path $jarPath -Leaf): $($_.Exception.Message)"
        }
    }
    Write-Warn2 'No textures/models found to restore — items/blocks will be purple/black in-game'
    return 0
}

function Ensure-ClientItems {
    param([string]$Root)
    $assets = Join-Path $Root 'src\main\resources\assets'
    if (-not (Test-Path $assets)) { return 0 }
    $n = 0
    foreach ($ns in Get-ChildItem $assets -Directory) {
        $modelsItem = Join-Path $ns.FullName 'models\item'
        if (-not (Test-Path $modelsItem)) { continue }
        $itemsDir = Join-Path $ns.FullName 'items'
        New-Item -ItemType Directory -Path $itemsDir -Force | Out-Null
        foreach ($m in Get-ChildItem $modelsItem -Filter '*.json') {
            $id = [IO.Path]::GetFileNameWithoutExtension($m.Name)
            $cp = Join-Path $itemsDir "$id.json"
            if (Test-Path $cp) { continue }
            $json = "{`r`n  `"model`": {`r`n    `"type`": `"minecraft:model`",`r`n    `"model`": `"$($ns.Name):item/$id`"`r`n  }`r`n}`r`n"
            [IO.File]::WriteAllText($cp, $json)
            $n++
        }
    }
    return $n
}

function Install-WrapperFromTowwOrMdk {
    param([string]$Root)
    $candidates = @(
        'F:\rob_projects\Minecraft_AI_Workstation\knowledge\neoforge\mdks\MDK-26.2-ModDevGradle',
        'F:\rob_projects\Completed\GrokBuild_MF\Completed_Projects\Java\26.2\Gradle_Workspaces\TheOneWhoWatches-26.2',
        'F:\rob_projects\Completed\GrokBuild_MF\Completed_Projects\Java\26.2\Gradle_Workspaces\Friend-26.2',
        'F:\rob_projects\Completed\GrokBuild_MF\Completed_Projects\Java\26.2\Gradle_Workspaces\The_Knocker\the_knocker-1.5.2-neoforge-1.21.8-26.2',
        'F:\Grok Build Apps\TheOneWhoWatches-26.2',
        'H:\GrokBuild Master Folder\Completed Projects\Java\26.2\Friend-26.2',
        'H:\GrokBuild Master Folder\Completed Projects\Java\26.2\The Knocker\the_knocker-1.5.2-neoforge-1.21.8-26.2'
    )
    foreach ($ref in $candidates) {
        if ((Test-Path (Join-Path $ref 'gradlew.bat')) -and (Test-Path (Join-Path $ref 'gradle\wrapper'))) {
            Copy-Item (Join-Path $ref 'gradlew.bat') $Root -Force
            if (Test-Path (Join-Path $ref 'gradlew')) { Copy-Item (Join-Path $ref 'gradlew') $Root -Force }
            New-Item -ItemType Directory -Path (Join-Path $Root 'gradle\wrapper') -Force | Out-Null
            Copy-Item (Join-Path $ref 'gradle\wrapper\*') (Join-Path $Root 'gradle\wrapper') -Force
            Write-Ok "Gradle wrapper copied from $ref"
            return
        }
    }
    Write-Warn2 'No wrapper reference found - run gradle wrapper manually'
}

# -------------------- main --------------------
$Source = (Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path (Join-Path $Source 'src'))) { throw "No src/ under $Source" }
$sourceProfile = Get-SourceProfile -Root $Source -VersionOverride $SourceVersion
if ($sourceProfile.Route -eq 'unsupported-fabric-quilt') {
    throw "Detected $($sourceProfile.Loader) input. This converter only migrates Forge/NeoForge mods; decompile-only mode is still available."
}

if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location) $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

Write-Host ''
Write-Host 'Legacy Java Converter - Forge 1.20.1 -> NeoForge 26.2 (EXPERIMENTAL)' -ForegroundColor White
Write-Host "  Source : $Source"
Write-Host "  Output : $OutputPath"
Write-Host "  Target : Minecraft $MinecraftVersion / NeoForge $NeoVersion"
Write-Host "  Intake : loader=$($sourceProfile.Loader) source=$($sourceProfile.SourceVersion) confidence=$($sourceProfile.Confidence) route=$($sourceProfile.Route)"
if ($DryRun) {
    Write-Host '  DryRun : yes (preview only - no files written)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Would perform:' -ForegroundColor Cyan
    Write-Host "  1. Copy project tree from source -> output (excluding build/.gradle/.git)"
    Write-Host "  2. Read mods.toml / Gradle / imports; download official 26.2 deps; convert remaining required mods"
    Write-Host "  3. Write ModDevGradle 26.2 scaffold (build.gradle, settings.gradle, gradle.properties, mods.toml)"
    Write-Host "  4. Mechanical Forge->NeoForge rewrites + 26.2 API pass + registry/event bootstrap"
    Write-Host "  5. Client item stubs + Gradle wrapper bootstrap when available"
    if ($Compile) { Write-Host "  6. Run compileJava (diagnostic)" }
    Write-Host ''
    Write-Host "Source has src/: $((Test-Path (Join-Path $Source 'src')))" -ForegroundColor Green
    $javaCount = @(Get-ChildItem (Join-Path $Source 'src') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue).Count
    Write-Host "Java files under src/: $javaCount" -ForegroundColor Green
    try {
        $cat = Get-DependencyCatalog
        $previewMeta = Get-ModMetaFromSource -Root $Source
        $previewDeps = Read-ProjectDependencies -Root $Source -SelfModId $previewMeta.mod_id -Catalog $cat
        Write-Host "Detected dependencies: $($previewDeps.Count)" -ForegroundColor Green
        foreach ($pd in $previewDeps) {
            Write-Host "    - $($pd.ModId) required=$($pd.Required) ($($pd.Source))"
        }
    } catch {
        Write-Warn2 "Dependency preview failed: $($_.Exception.Message)"
    }
    Write-Host ''
    Write-Host 'Dry run complete. Re-run without -DryRun to write files.' -ForegroundColor Yellow
    return
}

Write-Step 'Copying project (original preserved)'
$n = Copy-ProjectTree -Source $Source -Dest $OutputPath
Write-Ok "Copied $n files"
Write-SourceProfile -Profile $sourceProfile -Path (Join-Path $OutputPath 'SOURCE_PROFILE.json')
Write-Ok 'Wrote SOURCE_PROFILE.json'
$primerSteps = Write-PrimerQuickReference -Profile $sourceProfile -Path (Join-Path $OutputPath 'PRIMER_CHANGE_INDEX.md')
Write-Ok "Wrote PRIMER_CHANGE_INDEX.md ($primerSteps applicable transition(s))"

$meta = Get-ModMetaFromSource -Root $Source
Write-Info "mod_id=$($meta.mod_id) group=$($meta.mod_group) version=$($meta.mod_version)"

if (-not $LocalLibDir) {
    $guess = Join-Path (Split-Path $Source -Parent) ''
    if (Test-Path (Join-Path $guess 'geckolib-neoforge-26.2-5.5.3.jar')) {
        $LocalLibDir = $guess.TrimEnd('\')
    }
}

Write-Step 'Reading and resolving dependencies (official 26.2 first, then convert required 1.20.1 mods)'
$catalog = Get-DependencyCatalog
$depRecords = Read-ProjectDependencies -Root $OutputPath -SelfModId $meta.mod_id -Catalog $catalog
Write-DetectedDependenciesJson -Path (Join-Path $OutputPath 'detected-dependencies.json') -Records $depRecords
Write-Info "Detected $($depRecords.Count) dependency record(s)"
foreach ($dr in $depRecords) {
    Write-Info ("  {0} required={1} source={2}" -f $dr.ModId, $dr.Required, $dr.Source)
}

$libsDir = Join-Path $OutputPath 'libs'
$cacheDir = Join-Path $ToolRoot 'lib\dep-cache'
$convertedDir = Join-Path $OutputPath 'converted-deps'
$localDirs = New-Object System.Collections.Generic.List[string]
foreach ($d in @($DependencyJarDir)) { if ($d) { $localDirs.Add($d) | Out-Null } }
$localDirs.Add((Split-Path $Source -Parent)) | Out-Null
$localDirs.Add((Join-Path $Source 'libs')) | Out-Null
$localDirs.Add((Join-Path $Source 'run\mods')) | Out-Null
if ($LocalLibDir) { $localDirs.Add($LocalLibDir) | Out-Null }

$visitedList = @($meta.mod_id)
if ($VisitedModIds) { $visitedList += ($VisitedModIds -split ',' | Where-Object { $_ }) }

$convertJarScript = Join-Path $ToolRoot 'Convert-OldJarToNeoForge262.ps1'
$resolvedDeps = Resolve-AndAcquireDependencies `
    -Records $depRecords `
    -Catalog $catalog `
    -LibsDir $libsDir `
    -CacheDir $cacheDir `
    -ConvertedDepsDir $convertedDir `
    -LocalJarDirs @($localDirs) `
    -ConvertJarScript $convertJarScript `
    -MinecraftVersion $MinecraftVersion `
    -NeoVersion $NeoVersion `
    -GeckoLibVersion $GeckoLibVersion `
    -DependencyDepth $DependencyDepth `
    -MaxDependencyDepth $MaxDependencyDepth `
    -VisitedModIds $visitedList `
    -SkipDownload:$SkipDependencyDownload `
    -SkipConvert:$SkipDependencyConvert `
    -ConvertOptional:$ConvertOptionalDependencies

$depPlan = New-DependencyGradlePlan -Resolved $resolvedDeps
Write-DependencyReport -Path (Join-Path $OutputPath 'DEPENDENCY_REPORT.md') -Records $depRecords -Resolved $resolvedDeps
Write-Ok 'Wrote DEPENDENCY_REPORT.md'

Write-Step 'Writing NeoForge 26.2 Gradle scaffold + resolved dependency map'
Write-GradleScaffold -Root $OutputPath -Meta $meta -LocalLibs $LocalLibDir -DepPlan $depPlan
Write-Ok 'build.gradle / settings.gradle / gradle.properties / neoforge.mods.toml'

Write-Step 'Mechanical Java rewrites (Forge -> NeoForge, Identifier, ticks, GeckoLib5)'
$j = if (Test-MigrationPass $sourceProfile 'mechanical-java') { Invoke-MechanicalJavaRewrites -Root $OutputPath } else { 0 }
Write-Ok "Touched $j Java file(s)"

Write-Step 'Exact primer migration path (detected source -> 26.2)'
$exactPrimer = Invoke-ExactPrimerMigrationRules -Root $OutputPath -Profile $sourceProfile -ModId $meta.mod_id
Write-Ok ("Applied {0} version-gated rule(s); touched {1} unit(s)" -f @($exactPrimer.Rules).Count, $exactPrimer.Touched)

Write-Step 'NeoForge/Minecraft 26.2 API pass (NBT, nav, teleport, weather, colors, permissions)'
$api = if (Test-MigrationPass $sourceProfile 'neoforge-26-api') { Invoke-NeoForge26ApiRewritePass -Root $OutputPath } else { 0 }
Write-Ok "API-touched $api Java file(s)"

Write-Step 'MCreator / NeoForge 1.21.x -> 26.2 pass (blocks GUI menus fluid overlay)'
$m121 = if (Test-MigrationPass $sourceProfile 'mcreator-1.21.x') { Invoke-Mcreator1218ToNeoForge262Pass -Root $OutputPath } else { 0 }
Write-Ok "1.21.x-touched $m121 Java file(s)"

Write-Step 'MCreator 1.20.1 residue pass (overlay, food, SavedData, effects; MCP-verified SRG)'
$m120 = if (Test-MigrationPass $sourceProfile 'mcreator-1.20.1') { Invoke-McreatorForge1201ResiduePass -Root $OutputPath } else { 0 }
Write-Ok "1.20.1-residue-touched $m120 Java file(s)"

Write-Step 'ModConfigSpec order pass (define-before-build; prevents world-join disconnect)'
$cfg = if (Test-MigrationPass $sourceProfile 'config-order') { Invoke-ModConfigSpecOrderPass -Root $OutputPath } else { 0 }
Write-Ok "Config-order-touched $cfg file(s)"

Write-Step 'Registry template pass (createEntities / Registries.SOUND_EVENT / items / blocks)'
$r = if (Test-MigrationPass $sourceProfile 'registry') { Invoke-RegistryTemplatePass -Root $OutputPath } else { 0 }
Write-Ok "Registry-touched $r file(s)"

Write-Step 'Block/Item Properties.setId pass (registerBlock/registerItem; 26.2 NPE Block/Item id not set)'
$ids = if (Test-MigrationPass $sourceProfile 'block-item-id') { Invoke-BlockItemIdPass -Root $OutputPath } else { 0 }
Write-Ok "Block/Item-id-touched $ids Java file(s)"

Write-Step 'GeckoLib 5.5 texture + AnimationController pass (TOWW/Friend 26.2)'
$geo = if (Test-MigrationPass $sourceProfile 'geckolib') { Invoke-GeckoLib26Pass -Root $OutputPath } else { 0 }
Write-Ok "GeckoLib-touched $geo Java file(s)"

Write-Step 'Mod entry template pass (IEventBus + ModContainer injection)'
$m = if (Test-MigrationPass $sourceProfile 'mod-entry') { Invoke-ModEntryTemplatePass -Root $OutputPath } else { 0 }
Write-Ok "Mod-entry-touched $m file(s)"

Write-Step 'EventBusSubscriber -> explicit addListener bootstrap'
$e = if (Test-MigrationPass $sourceProfile 'event-bus') { Invoke-EventBusSubscriberPass -Root $OutputPath -Meta $meta } else { 0 }
Write-Ok "Event-bus pass touched $e unit(s) (classes + LegacyEventBootstrap)"

Write-Step 'Restore assets/data (decompiled trees are often Java-only)'
$assetsRestored = Restore-ModAssets -Source $Source -Dest $OutputPath -ModId $meta.mod_id -OriginalJarPath $OriginalJarPath
Write-Ok "Asset restore units: $assetsRestored"

Write-Step 'Client item stubs (if models/item exist)'
$ci = Ensure-ClientItems -Root $OutputPath
Write-Ok "Created $ci client item file(s)"

Write-Step 'Gradle wrapper'
Install-WrapperFromTowwOrMdk -Root $OutputPath

$reportPath = Join-Path $OutputPath 'LEGACY_MIGRATION_REPORT.md'
$report = @"
# Legacy migration report: $($meta.mod_id)

- Source: ``$Source``
- Output: ``$OutputPath``
- Target: Minecraft $MinecraftVersion / NeoForge $NeoVersion
- Detected source: $($sourceProfile.SourceVersion) ($($sourceProfile.Loader), confidence $($sourceProfile.Confidence))
- Migration route: ``$($sourceProfile.Route)``
- Exact primer rules: ``$(@($exactPrimer.Rules) -join ', ')``
- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

## What was automated

1. Full project copy (original unchanged)
2. ModDevGradle 26.2 scaffold (Java 25)
3. Dependency pipeline (see ``DEPENDENCY_REPORT.md``):
   - Read ``mods.toml`` / Gradle / jar-in-jar / Java imports
   - Download official NeoForge 26.2 artifacts (GeckoLib, SmartBrainLib, Modrinth 26.2 jars)
   - Recursively convert required Forge 1.20.1 mods that have no 26.2 build
   - Wire Maven coordinates and ``libs/*.jar`` into the Gradle scaffold
4. Mechanical package renames Forge -> NeoForge
5. Safer TickEvent rewrite (ClientTickEvent.Post / ServerTickEvent.Post)
6. ``ResourceLocation`` -> ``Identifier`` (MC 26.x rename)
7. GeckoLib 4 packages -> GeckoLib 5 (``com.geckolib`` + AnimationController ctor)
8. **26.2 API pass** (Friend + The Knocker): NBT OrEmpty, isSolidRender, PathNavigation.moveTo vs Entity.snapTo,
   EntitySpawnReason create, server via level().getServer(), BreakBlockEvent, permissions, ColorCollection blocks,
   weather/clock stubs, cross-dim teleport signature, Camera.position, ClipContext CollisionContext,
   displayClientMessage->sendSystemMessage, RespawnConfig.respawnData, getSpawnPos, CommandSourceStack PermissionSet,
   FMLEnvironment.getDist(), registerItem/SpawnEggItem, client RenderTypes/SubmitNodeCollector/ArmorModelSet
9. **MCreator / NeoForge 1.21.x pass** (MOAdecor BATH): drop ``shouldDisplayFluidOverlay`` / ``BlockAndTintGetter``,
   ``noCollission``->``noCollision``, ``GuiGraphics``->``GuiGraphicsExtractor``, container ``renderBg``->``extractBackground``,
   final ``imageWidth``/``imageHeight`` via ``super(..., w, h)``, ``keyPressed(KeyEvent)``, ``isClientSide()``,
   remove ``Tuple`` work-queue, stub broken ``ItemHandler.ITEM/ENTITY`` capability binds
10. **ModConfigSpec order pass** (define-before-build) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â prevents world-join disconnect from decompiled MCreator configs
11. Registry templates (createEntities / Registries.SOUND_EVENT / createItems / createBlocks)
12. ``@Mod`` constructor injection template (IEventBus + ModContainer)
13. ``@Mod.EventBusSubscriber`` -> ``LegacyEventBootstrap`` + ``addListener`` registrations
14. Entity level accessors (safe ``this.level()`` only), getCenter, setMaxUpStep comment-out
15. pack.mcmeta format 107 + **templates/** neoforge.mods.toml (removes leftover resources META-INF toml that pins old MC versions)
16. Client item stubs where models/item existed

## Important

- Conversion success means a **scaffold** was written. It does **not** mean the mod is loadable yet.
- Only install jars produced by ``gradlew build`` from this output (``build/libs/*.jar``).
- Never rename the input 1.20.1 / 1.21.x jar and treat it as a 26.2 mod ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â NeoForge will reject old ``versionRange`` pins.

## What you must still fix manually

- GeckoLib 5 render/model method signatures (GeoRenderState) and remaining client ``submit`` layer bodies
- SmartBrainLib 1.x -> 2.x API if used
- Written books / dyed items (DataComponents) if used heavily
- Nested/multi-line teleportTo and complex expression rewrites
- Networking payload registrar typing, SavedDataType Identifier+Codec edge cases
- Capabilities transfer API (old ItemHandler registration is commented out)
- Mixins, worldgen datapacks
- SynchedEntityData.define builder APIs, entity tags, remaining vanilla package moves
- Full ``gradlew compileJava`` / ``build`` until clean

## Next commands

``````powershell
cd "$OutputPath"
.\gradlew.bat compileJava --stacktrace
.\gradlew.bat build
``````

Local jars (optional install into mods for runClient):
- ``$LocalLibDir\geckolib-neoforge-26.2-5.5.3.jar``
- ``$LocalLibDir\smartbrainlib-neoforge-26.2-2.0.0.jar``
"@
[System.IO.File]::WriteAllText($reportPath, $report)

Write-Ok "Wrote $reportPath"

$compileExit = 0
if ($Compile) {
    Write-Step 'Running Gradle build (compile + tests/resources + versioned JAR)'
    Push-Location $OutputPath
    try {
        # Use cmd so PowerShell does not treat Gradle stderr as a terminating error
        cmd /c "gradlew.bat build --no-daemon --stacktrace > compile-errors.log 2>&1"
        $compileExit = $LASTEXITCODE
        $null = Write-CompileDiagnosticSummary -LogPath (Join-Path $OutputPath 'compile-errors.log') -ExitCode $compileExit
        Write-Host "Gradle exit: $compileExit"
        if ($compileExit -ne 0) {
            Write-Warn2 "Gradle build failed (exit $compileExit). Scaffold is still written."
            Write-Warn2 "See compile-errors.log in the output folder for details."
            if (Test-Path (Join-Path $OutputPath 'compile-errors.log')) {
                Get-Content (Join-Path $OutputPath 'compile-errors.log') -Tail 40 | ForEach-Object { Write-Host "    $_" }
            }
        } else {
            $built = @(Get-ChildItem -LiteralPath (Join-Path $OutputPath 'build\libs') -Filter '*.jar' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'sources|javadoc' })
            if ($built.Count -gt 0) {
                Write-Ok "Gradle build succeeded: $($built[0].FullName)"
            } else {
                $compileExit = 3
                Write-Warn2 'Gradle reported success but no installable JAR was found under build\libs.'
            }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ''
Write-Host "Conversion scaffold complete: $OutputPath" -ForegroundColor Green
Write-Host 'Original unchanged.' -ForegroundColor Green
if ($Compile -and $compileExit -ne 0) {
    Write-Host "Note: requested build failed with exit $compileExit; the scaffold is available for repair." -ForegroundColor Yellow
}
# Always exit 0 after successful scaffold so GUI does not report hard failure for diagnostic compile
exit 0
