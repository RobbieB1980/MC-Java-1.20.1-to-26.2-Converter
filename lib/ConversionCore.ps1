function ConvertTo-NormalizedMinecraftVersion {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $hits = [regex]::Matches($Value, '(?<!\d)(?:1\.(?:20|21)\.\d+|2[2-6](?:\.\d+){1,2})(?!\d)')
    if ($hits.Count -eq 0) { return '' }
    return $hits[0].Value
}

function ConvertTo-ExtendedPath([string]$Value) {
    if ($env:OS -ne 'Windows_NT') { return $Value }
    if ($Value.StartsWith('\\?\')) { return $Value }
    if ($Value.StartsWith('\\')) { return '\\?\UNC\' + $Value.TrimStart('\') }
    return '\\?\' + [IO.Path]::GetFullPath($Value)
}

function Copy-FileLongPath([string]$Source, [string]$Destination) {
    $src = ConvertTo-ExtendedPath $Source
    $dst = ConvertTo-ExtendedPath $Destination
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst)) | Out-Null
    [IO.File]::Copy($src, $dst, $true)
}

function Convert-LevelClientSideAccess([string]$Text) {
    # BlockEntity exposes getLevel(); Entity exposes level(). Keep both shapes
    # separate and make the conversion safe when a project is processed again.
    $thisAccessor = if ($Text -match '\bextends\s+(?:[\w.]+\.)?(?!BlockEntity\b)\w*Entity\b') { 'this.level().' } else { 'this.getLevel().' }
    $Text = $Text -replace '\bthis\.(?:level\(\)|getLevel\(\))\.', $thisAccessor
    $Text = $Text -replace '\bthis\.level\.isClientSide\s*\(\)', ($thisAccessor + 'isClientSide()')
    $Text = $Text -replace '\bthis\.level\.isClientSide\b(?!\s*\()', ($thisAccessor + 'isClientSide()')
    $Text = $Text -replace '\bthis\.level\.', $thisAccessor
    $Text = [regex]::Replace($Text, '(?<![\w.])(entity|friend|mob|living|player|target|owner|self)\.level\.isClientSide\s*\(\)', '$1.level().isClientSide()', 'IgnoreCase')
    $Text = [regex]::Replace($Text, '(?<![\w.])(entity|friend|mob|living|player|target|owner|self)\.level\.isClientSide\b(?!\s*\()', '$1.level().isClientSide()', 'IgnoreCase')
    $Text = [regex]::Replace($Text, '(?<![\w.])(entity|friend|mob|living|player|target|owner|self)\.level\.(?!isClientSide)', '$1.level().', 'IgnoreCase')
    return $Text
}

function Convert-NeoForge262ApiMoves([string]$Text) {
    # Mojang package reorganisations between the 1.21.x primer and 26.2.
    $Text = $Text.Replace(
        'net.minecraft.client.renderer.block.model.VariantMutator',
        'net.minecraft.client.renderer.block.dispatch.VariantMutator')
    $Text = $Text.Replace(
        'net.minecraft.client.renderer.block.model.BlockStateModel',
        'net.minecraft.client.renderer.block.dispatch.BlockStateModel')
    $Text = $Text.Replace(
        'net.minecraft.client.renderer.state.CameraRenderState',
        'net.minecraft.client.renderer.state.level.CameraRenderState')

    # StateHolder#getValues now returns Stream<Property.Value<?>>.
    $Text = [regex]::Replace($Text,
        'for\s*\(\s*Entry<Property<\?>,\s*Comparable<\?>>\s+(\w+)\s*:\s*([^\r\n]+?)\.getValues\(\)\.entrySet\(\)\s*\)',
        'for (Property.Value<?> $1 : $2.getValues().toList())')
    $Text = $Text.Replace('entry.getKey()', 'entry.property()')
    $Text = $Text.Replace('entry.getValue()', 'entry.value()')

    # 26.2 tag appenders accept registry keys instead of item instances.
    $Text = [regex]::Replace($Text,
        '\.add\(([^\r\n;]+?\.asItem\(\))\)',
        '.add($1.builtInRegistryHolder().key())')

    if ($Text -match 'implements\s+BlockEntityRenderer') {
        $Text = $Text.Replace('super.extractRenderState(', 'BlockEntityRenderer.super.extractRenderState(')
    }
    $Text = [regex]::Replace($Text,
        'LevelRenderer\.getLightColor\(([^,]+),\s*([^)]+)\)',
        'net.minecraft.util.LightCoordsUtil.getLightCoords($1, $2)')

    # Standalone model registration must be explicitly typed in 26.2; an
    # untyped lifecycle listener otherwise resolves to the base Event class.
    if ($Text -match 'SimpleUnbakedStandaloneModel\.blockStateModel') {
        $Text = [regex]::Replace($Text, 'modEventBus\.addListener\(\s*e\s*->', 'modEventBus.addListener((net.neoforged.neoforge.client.event.ModelEvent.RegisterStandalone e) ->', 1)
    }

    # Renderer submission now consumes model parts and tint arrays.
    $Text = [regex]::Replace($Text,
        'submitBlockModel\(\s*([^,]+),\s*([^,]+),\s*(.+?),\s*1\.0F,\s*1\.0F,\s*1\.0F,\s*([^,]+),\s*([^,]+),\s*([^\)]+)\)',
        'submitBlockModel($1, $2, rb.legacy.converter.compat.Legacy262Compat.modelParts($3), new int[0], $4, $5, $6)',
        'Singleline')
    $Text = $Text.Replace('_bs.setValue(_property, entry.value())', 'rb.legacy.converter.compat.Legacy262Compat.copyValue(_bs, entry)')
    return $Text
}

function Convert-ColorCollectionConstants([string]$Text) {
    $colors = [ordered]@{
        'WHITE'='white'; 'ORANGE'='orange'; 'MAGENTA'='magenta'; 'LIGHT_BLUE'='lightBlue'; 'YELLOW'='yellow'; 'LIME'='lime'
        'PINK'='pink'; 'GRAY'='gray'; 'LIGHT_GRAY'='lightGray'; 'CYAN'='cyan'; 'PURPLE'='purple'; 'BLUE'='blue'
        'BROWN'='brown'; 'GREEN'='green'; 'RED'='red'; 'BLACK'='black'
    }
    $groups = @(
        @{ Suffix='STAINED_GLASS_PANE'; Collection='STAINED_GLASS_PANE' }, @{ Suffix='CONCRETE_POWDER'; Collection='CONCRETE_POWDER' }
        @{ Suffix='GLAZED_TERRACOTTA'; Collection='GLAZED_TERRACOTTA' }, @{ Suffix='SHULKER_BOX'; Collection='DYED_SHULKER_BOX' }
        @{ Suffix='STAINED_GLASS'; Collection='STAINED_GLASS' }, @{ Suffix='TERRACOTTA'; Collection='DYED_TERRACOTTA' }
        @{ Suffix='CONCRETE'; Collection='CONCRETE' }, @{ Suffix='CARPET'; Collection='CARPET' }, @{ Suffix='BUNDLE'; Collection='DYED_BUNDLE' }
        @{ Suffix='HARNESS'; Collection='HARNESS' }, @{ Suffix='CANDLE'; Collection='DYED_CANDLE' }, @{ Suffix='BANNER'; Collection='BANNER' }
        @{ Suffix='WOOL'; Collection='WOOL' }, @{ Suffix='BED'; Collection='BED' }, @{ Suffix='DYE'; Collection='DYE' }
    ) | Sort-Object { $_.Suffix.Length } -Descending
    foreach ($group in $groups) {
        foreach ($color in $colors.Keys) {
            $Text = $Text.Replace("Items.${color}_$($group.Suffix)", "Items.$($group.Collection).$($colors[$color])()")
            $Text = $Text.Replace("Blocks.${color}_$($group.Suffix)", "Blocks.$($group.Collection).$($colors[$color])()")
        }
    }
    return $Text.Replace('Blocks.CHAIN', 'Blocks.IRON_CHAIN').Replace('Items.CHAIN', 'Items.IRON_CHAIN')
}

function Get-MigrationRoute {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$SourceVersion, [AllowEmptyString()][string]$Loader)
    $v = ConvertTo-NormalizedMinecraftVersion $SourceVersion
    if ($Loader -match 'fabric|quilt') { return 'unsupported-fabric-quilt' }
    if ($v -eq '1.20.1') { return 'forge-1.20.1' }
    if ($v -match '^1\.21\.') { return 'neoforge-1.21.x' }
    if ($v -match '^2[2-5]\.\d+') { return 'neoforge-22-to-25' }
    if ($v -match '^26\.[01](?:\.|$)') { return 'neoforge-26.0-26.1' }
    if ($v -eq '26.2' -or $v -match '^26\.2\.') { return 'already-26.2' }
    return 'generic-forge-neoforge'
}

function Get-RecommendedMigrationPasses {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Route)
    $common = @('mechanical-java', 'neoforge-26-api', 'config-order', 'registry', 'block-item-id', 'geckolib', 'mod-entry', 'event-bus', 'assets')
    switch ($Route) {
        'forge-1.20.1'       { return @('srg-1.20.1') + $common + @('mcreator-1.20.1') }
        'neoforge-1.21.x'    { return $common + @('mcreator-1.21.x') }
        'neoforge-22-to-25'  { return $common }
        'neoforge-26.0-26.1' { return $common }
        'already-26.2'       { return @('config-order', 'registry', 'block-item-id', 'assets') }
        'unsupported-fabric-quilt' { return @('assets') }
        default              { return $common + @('mcreator-1.20.1', 'mcreator-1.21.x') }
    }
}

function Test-MigrationPass {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$Name)
    return @($Profile.RecommendedPasses) -contains $Name
}

function Get-ApiFeatureInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $rules = @(
        [pscustomobject]@{ Id='forge-packages'; Pass='mechanical-java'; Pattern='net\.minecraftforge\.'; Description='Forge package imports' }
        [pscustomobject]@{ Id='resource-location'; Pass='mechanical-java'; Pattern='\bResourceLocation\b'; Description='ResourceLocation API renamed for 26.x' }
        [pscustomobject]@{ Id='legacy-tick-events'; Pass='mechanical-java'; Pattern='TickEvent\.(?:ClientTickEvent|ServerTickEvent)'; Description='Legacy tick event shape' }
        [pscustomobject]@{ Id='legacy-nbt-access'; Pass='neoforge-26-api'; Pattern='getCompound\s*\('; Description='Legacy compound NBT access' }
        [pscustomobject]@{ Id='display-client-message'; Pass='neoforge-26-api'; Pattern='displayClientMessage\s*\('; Description='Legacy player message call' }
        [pscustomobject]@{ Id='event-bus-subscriber'; Pass='event-bus'; Pattern='@Mod\.EventBusSubscriber'; Description='Annotation event-bus bootstrap' }
        [pscustomobject]@{ Id='deferred-register'; Pass='registry'; Pattern='\bDeferredRegister\b'; Description='Deferred registry API' }
        [pscustomobject]@{ Id='legacy-geckolib'; Pass='geckolib'; Pattern='software\.bernie\.geckolib|AnimationController\s*<[^>]+>\s*\('; Description='GeckoLib 4 API' }
        [pscustomobject]@{ Id='mcreator-source'; Pass='mcreator-1.21.x'; Pattern='net\.mcreator\.'; Description='MCreator-generated source' }
        [pscustomobject]@{ Id='legacy-gui-graphics'; Pass='mcreator-1.21.x'; Pattern='\bGuiGraphics\b|renderBg\s*\('; Description='Pre-26.2 GUI rendering API' }
        [pscustomobject]@{ Id='legacy-srg-name'; Pass='mcreator-1.20.1'; Pattern='\b(?:m_\d+_|f_\d+_)\b'; Description='Forge 1.20.1 SRG names' }
        [pscustomobject]@{ Id='legacy-capability'; Pass='neoforge-26-api'; Pattern='ForgeCapabilities|IItemHandler|registerBlockEntity\s*\('; Description='Legacy capability/item handler API' }
    )
    $hits = New-Object System.Collections.Generic.List[object]
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { $javaRoot = $Root }
    foreach ($file in @(Get-ChildItem -LiteralPath $javaRoot -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $text) { continue }
        foreach ($rule in $rules) {
            if ($text -notmatch $rule.Pattern) { continue }
            if (-not ($hits | Where-Object Id -eq $rule.Id)) {
                $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
                $hits.Add([pscustomobject]@{ Id=$rule.Id; Pass=$rule.Pass; Description=$rule.Description; ExampleFile=$relative }) | Out-Null
            }
        }
    }
    return $hits.ToArray()
}

function Get-SourceProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [AllowEmptyString()][string]$VersionOverride = '')

    $evidence = New-Object System.Collections.Generic.List[object]
    $candidates = New-Object System.Collections.Generic.List[object]
    $loader = 'unknown'
    $framework = 'unknown'
    function Add-Candidate([string]$Version, [int]$Weight, [string]$Source, [string]$Detail) {
        $normalized = ConvertTo-NormalizedMinecraftVersion $Version
        if (-not $normalized) { return }
        $candidates.Add([pscustomobject]@{ Version = $normalized; Weight = $Weight; Source = $Source }) | Out-Null
        $evidence.Add([pscustomobject]@{ Source = $Source; Value = $normalized; Detail = $Detail }) | Out-Null
    }

    if ($VersionOverride) { Add-Candidate $VersionOverride 100 'override' 'Explicit -SourceVersion value' }
    $preservedProfile = Join-Path $Root 'SOURCE_PROFILE.json'
    if (Test-Path -LiteralPath $preservedProfile) {
        try {
            $prior = Get-Content -LiteralPath $preservedProfile -Raw | ConvertFrom-Json
            if ($prior.SourceVersion) { Add-Candidate ([string]$prior.SourceVersion) 95 'preserved source profile' 'SOURCE_PROFILE.json' }
            if ($prior.Loader) { $loader = [string]$prior.Loader }
            if ($prior.Framework) { $framework = [string]$prior.Framework }
        } catch { }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'gradle.properties' -ErrorAction SilentlyContinue | Select-Object -First 3)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in @('(?m)^\s*source_minecraft_version\s*=\s*([^\r\n#]+)', '(?m)^\s*minecraft_version\s*=\s*([^\r\n#]+)', '(?m)^\s*minecraftVersion\s*=\s*([^\r\n#]+)')) {
            $m = [regex]::Match($text, $pattern)
            if ($m.Success) {
                $weight = if ($pattern -match 'source_minecraft') { 95 } else { 90 }
                Add-Candidate $m.Groups[1].Value $weight 'gradle.properties' $file.Name
                break
            }
        }
        if ($text -match '(?im)^\s*(?:neo_version|neoforge_version)\s*=') { $loader = 'neoforge' }
        elseif ($text -match '(?im)^\s*forge_version\s*=') { $loader = 'forge' }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('mods.toml', 'neoforge.mods.toml') } | Select-Object -First 8)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($file.Name -eq 'neoforge.mods.toml') { $loader = 'neoforge' } elseif ($loader -eq 'unknown') { $loader = 'forge' }
        foreach ($block in [regex]::Matches($text, '(?is)\[\[dependencies\.[^\]]+\]\](.*?)(?=\[\[|\z)')) {
            if ($block.Value -notmatch '(?im)^\s*modId\s*=\s*["'']minecraft["'']') { continue }
            $range = [regex]::Match($block.Value, '(?im)^\s*versionRange\s*=\s*["'']([^"'']+)["'']')
            if ($range.Success) { Add-Candidate $range.Groups[1].Value 85 'mod metadata' $file.Name }
        }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('build.gradle', 'build.gradle.kts') } | Select-Object -First 5)) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        foreach ($m in [regex]::Matches($text, '(?:net\.neoforged:neoforge:|minecraft_version\s*[=:]\s*["'']?)(1\.20\.1|1\.21\.\d+|2[2-6]\.\d+(?:\.\d+)?)')) { Add-Candidate $m.Groups[1].Value 70 'build script' $file.Name }
        if ($text -match 'net\.neoforged|moddevgradle|neoForge') { $loader = 'neoforge' } elseif ($text -match 'net\.minecraftforge|ForgeGradle') { $loader = 'forge' }
    }

    if (Test-Path (Join-Path $Root 'fabric.mod.json')) { $loader = 'fabric' }
    if (Test-Path (Join-Path $Root 'quilt.mod.json')) { $loader = 'quilt' }
    $javaRoot = Join-Path $Root 'src\main\java'
    if (Test-Path $javaRoot) {
        foreach ($file in @(Get-ChildItem -LiteralPath $javaRoot -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue | Select-Object -First 300)) {
            $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($text -match 'net\.mcreator\.') { $framework = 'mcreator' }
            if ($loader -eq 'unknown' -and $text -match 'net\.neoforged\.') { $loader = 'neoforge' }
            if ($loader -eq 'unknown' -and $text -match 'net\.minecraftforge\.') { $loader = 'forge' }
        }
    }

    $selected = $candidates | Sort-Object Weight -Descending | Select-Object -First 1
    $sourceVersion = if ($selected) { $selected.Version } else { 'unknown' }
    $confidence = if (-not $selected) { 'low' } elseif ($selected.Weight -ge 85) { 'high' } else { 'medium' }
    $route = Get-MigrationRoute -SourceVersion $sourceVersion -Loader $loader
    $recommended = @(Get-RecommendedMigrationPasses -Route $route)
    $features = @(Get-ApiFeatureInventory -Root $Root)
    # Feature evidence supplements metadata. This is especially important for
    # decompiled or mixed-version projects whose manifest range is missing.
    foreach ($feature in $features) {
        if ($recommended -notcontains $feature.Pass -and $route -notin @('already-26.2', 'unsupported-fabric-quilt')) {
            $recommended += $feature.Pass
        }
    }
    [pscustomobject]@{
        SchemaVersion = 1; SourceVersion = $sourceVersion; Loader = $loader; Framework = $framework
        Confidence = $confidence; Route = $route
        RecommendedPasses = @($recommended); ApiFeatures = @($features)
        Evidence = $evidence.ToArray()
    }
}

function Write-SourceProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path $Path -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-PrimerChangeIndex {
    [CmdletBinding()]
    param([string]$Path = (Join-Path $PSScriptRoot 'PrimerChangeIndex.json'))
    if (-not (Test-Path -LiteralPath $Path)) { throw "Primer change index missing: $Path" }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-PrimerMigrationChain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceVersion, $Index = (Get-PrimerChangeIndex))
    $aliases = @{
        '1.20.2'='1.20.1'; '1.20.3'='1.20.1'; '1.20.4'='1.20.4'; '1.21.2'='1.21.2/3'; '1.21.3'='1.21.2/3'
        '26.1.1'='26.1'; '26.1.2'='26.1'
    }
    $start = if ($aliases.ContainsKey($SourceVersion)) { $aliases[$SourceVersion] } else { $SourceVersion }
    $all = @($Index.transitions)
    $position = -1
    for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].from -eq $start) { $position = $i; break } }
    if ($SourceVersion -eq '26.2') { return @() }
    if ($position -lt 0) { return @($all) }
    return @($all[$position..($all.Count - 1)])
}

function Get-PrimerMigrationRules {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceVersion, $Index = (Get-PrimerChangeIndex))
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result = New-Object Collections.Generic.List[string]
    foreach ($transition in @(Get-PrimerMigrationChain -SourceVersion $SourceVersion -Index $Index)) {
        $ruleProperty = $transition.PSObject.Properties['rules']
        $transitionRules = if ($null -ne $ruleProperty) { @($ruleProperty.Value) } else { @() }
        foreach ($rule in $transitionRules) {
            if ($rule -and $seen.Add([string]$rule)) { $result.Add([string]$rule) | Out-Null }
        }
    }
    return $result.ToArray()
}

function Convert-CustomBlockRegistrationText {
    param([Parameter(Mandatory)][string]$Text)
    if ($Text -notmatch 'DeferredRegister\.createBlocks\(' -or
        $Text -notmatch 'registerBlock\(String name, Supplier<T> block\)') { return $Text }
    $Text = $Text.Replace('import java.util.function.Supplier;', 'import java.util.function.Function;')
    $Text = $Text.Replace('registerBlock(String name, Supplier<T> block)', 'registerBlock(String name, Function<Properties, T> block)')
    $Text = $Text.Replace('BLOCKS.register(name, block)', 'BLOCKS.registerBlock(name, block)')
    $Text = [regex]::Replace($Text, '(registerBlock\(\s*"[^"]+"\s*,\s*)\(\)\s*->\s*new ', '$1properties -> new ')
    $Text = $Text.Replace('Properties.of()', 'properties')
    $Text = [regex]::Replace($Text,
        'ModItems\.ITEMS\.register\(name,\s*\(\)\s*->\s*new BlockItem\(\(Block\)block\.get\(\),\s*new net\.minecraft\.world\.item\.Item\.Properties\(\)\)\)',
        'ModItems.ITEMS.registerItem(name, properties -> new BlockItem((Block)block.get(), properties))')
    return $Text
}

function Write-PrimerQuickReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$Path)
    $chain = @(Get-PrimerMigrationChain -SourceVersion ([string]$Profile.SourceVersion))
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Primer change quick reference') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add("Detected source: **$($Profile.SourceVersion)**; target: **26.2**; route: ``$($Profile.Route)``.") | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('This is a condensed change index, not a replacement for the linked official primers. Only transitions after the detected source are included.') | Out-Null
    foreach ($step in $chain) {
        $lines.Add('') | Out-Null
        $lines.Add("## $($step.from) → $($step.to)") | Out-Null
        $lines.Add('') | Out-Null
        $sourceLabel = if ($step.sourceType -eq 'official-primer') { "[Official primer]($($step.officialPrimer))" } else { 'Converter-maintained bridge (no official primer published for this interval)' }
        $lines.Add("Source: $sourceLabel") | Out-Null
        foreach ($change in @($step.changes)) { $lines.Add("- $change") | Out-Null }
        if (@($step.passes).Count -gt 0) { $lines.Add("- Converter passes: ``$(@($step.passes) -join '`, `')``") | Out-Null }
    }
    [IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"))
    return $chain.Count
}

function Write-CompileDiagnosticSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][int]$ExitCode)
    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }
    $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
    $errorLines = @($lines | Where-Object { $_ -match '(?i)(?:\.java:\d+:\s+error:|^\s*error:)' })
    $families = [ordered]@{
        'missing-symbol-or-package' = @($lines | Where-Object { $_ -match '(?i)cannot find symbol|package .+ does not exist' }).Count
        'signature-or-type-change' = @($lines | Where-Object { $_ -match '(?i)cannot be applied to given types|incompatible types|does not override' }).Count
        'access-or-removed-api' = @($lines | Where-Object { $_ -match '(?i)has private access|has protected access|cannot be accessed|deprecated and marked for removal' }).Count
        'decompiler-artifact' = @($lines | Where-Object { $_ -match "(?i)illegal start|not a statement|';' expected|reached end of file" }).Count
    }
    $summary = [pscustomobject]@{
        SchemaVersion = 1; ExitCode = $ExitCode; Succeeded = ($ExitCode -eq 0)
        ErrorLineCount = $errorLines.Count; Categories = $families
        NextAction = if ($ExitCode -eq 0) { 'Install the versioned build/libs JAR and runClient-test it.' } else { 'Fix the first error family, rerun gradlew build, and repeat.' }
    }
    $dir = Split-Path $LogPath -Parent
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'COMPILE_REPORT.json') -Encoding UTF8
    $rows = @($families.GetEnumerator() | ForEach-Object { "| $($_.Key) | $($_.Value) |" })
    @(
        '# Compile diagnostic report', '', "- Exit code: $ExitCode", "- Error lines: $($errorLines.Count)",
        "- Result: $(if ($ExitCode -eq 0) { 'compileJava succeeded' } else { 'compileJava needs follow-up' })", '',
        '## Error families', '', '| Family | Matches |', '|---|---:|'
    ) + $rows + @('', 'See `compile-errors.log` for the full Gradle output.') |
        Set-Content -LiteralPath (Join-Path $dir 'COMPILE_REPORT.md') -Encoding UTF8
    return $summary
}
