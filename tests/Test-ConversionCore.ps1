[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
. (Join-Path $repo 'lib\ConversionCore.ps1')
. (Join-Path $repo 'lib\ModDependencyPipeline.ps1')

$failures = New-Object System.Collections.Generic.List[string]
function Assert-Equal([string]$Name, $Expected, $Actual) {
    if ($Expected -ne $Actual) { $failures.Add("$Name expected '$Expected' but got '$Actual'") | Out-Null }
    else { Write-Host "PASS $Name" -ForegroundColor Green }
}
function Assert-True([string]$Name, [bool]$Actual) {
    if (-not $Actual) { $failures.Add("$Name expected true") | Out-Null }
    else { Write-Host "PASS $Name" -ForegroundColor Green }
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('legacy-converter-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $forge = Join-Path $fixtureRoot 'forge1201'
    New-Item -ItemType Directory -Path (Join-Path $forge 'src\main\java\example') -Force | Out-Null
    Set-Content (Join-Path $forge 'gradle.properties') "minecraft_version=1.20.1`nforge_version=47.4.0"
    Set-Content (Join-Path $forge 'src\main\java\example\Mod.java') 'import net.minecraftforge.fml.common.Mod;'
    $profile = Get-SourceProfile $forge
    Assert-Equal 'Forge version' '1.20.1' $profile.SourceVersion
    Assert-Equal 'Forge loader' 'forge' $profile.Loader
    Assert-Equal 'Forge route' 'forge-1.20.1' $profile.Route
    Assert-True 'Forge residue pass' (Test-MigrationPass $profile 'mcreator-1.20.1')
    Assert-True 'Forge excludes 1.21 pass' (-not (Test-MigrationPass $profile 'mcreator-1.21.x'))

    $neo = Join-Path $fixtureRoot 'neo261'
    New-Item -ItemType Directory -Path (Join-Path $neo 'src\main\resources\META-INF') -Force | Out-Null
    Set-Content (Join-Path $neo 'src\main\resources\META-INF\neoforge.mods.toml') @'
modLoader="javafml"
[[dependencies.sample]]
modId="minecraft"
versionRange="[26.1,26.2)"
'@
    $profile = Get-SourceProfile $neo
    Assert-Equal 'Neo version range' '26.1' $profile.SourceVersion
    Assert-Equal 'Neo loader' 'neoforge' $profile.Loader
    Assert-Equal 'Neo route' 'neoforge-26.0-26.1' $profile.Route
    Assert-True 'Neo excludes old MCreator pass' (-not (Test-MigrationPass $profile 'mcreator-1.20.1'))

    $fabric = Join-Path $fixtureRoot 'fabric'
    New-Item -ItemType Directory -Path $fabric -Force | Out-Null
    Set-Content (Join-Path $fabric 'fabric.mod.json') '{"schemaVersion":1,"id":"sample"}'
    $profile = Get-SourceProfile $fabric -VersionOverride '1.21.8'
    Assert-Equal 'Fabric route' 'unsupported-fabric-quilt' $profile.Route

    Assert-Equal 'Normalize exact' '26.1' (ConvertTo-NormalizedMinecraftVersion '[26.1,26.2)')
    Assert-Equal 'Normalize old' '1.20.1' (ConvertTo-NormalizedMinecraftVersion '[1.20.1,1.21)')

    $compileLog = Join-Path $fixtureRoot 'compile-errors.log'
    Set-Content $compileLog @'
Example.java:12: error: cannot find symbol
Example.java:22: error: incompatible types: Foo cannot be converted to Bar
'@
    $compile = Write-CompileDiagnosticSummary -LogPath $compileLog -ExitCode 1
    Assert-Equal 'Compile error count' 2 $compile.ErrorLineCount
    Assert-Equal 'Missing symbol category' 1 $compile.Categories.'missing-symbol-or-package'
    Assert-True 'Compile JSON written' (Test-Path (Join-Path $fixtureRoot 'COMPILE_REPORT.json'))

    # TOML and import records do not carry MavenHint. ConversionCore must not
    # enable strict mode in its caller or these valid optional fields throw.
    $merged = @(Merge-DependencyRecords -Items @(
        [pscustomobject]@{ ModId='geckolib'; Required=$true; VersionRange='[4,)'; Source='toml' },
        [pscustomobject]@{ ModId='geckolib'; Required=$true; VersionRange=''; Source='import' }
    ))
    Assert-Equal 'Optional MavenHint merge count' 1 $merged.Count
    Assert-Equal 'Optional MavenHint defaults empty' '' $merged[0].MavenHint

    $depsPath = Join-Path $fixtureRoot 'detected-dependencies.json'
    Write-DetectedDependenciesJson -Path $depsPath -Records @(
        [pscustomobject]@{ ModId='neoforge'; Required=$true; VersionRange='[21.11,)'; Source='toml' },
        [pscustomobject]@{ ModId='fusion'; Required=$true; VersionRange='[1.2.11,)'; Source='toml' }
    )
    $depsJson = Get-Content $depsPath -Raw | ConvertFrom-Json
    Assert-Equal 'Dependency JSON record count' 2 @($depsJson).Count
    Assert-Equal 'Dependency JSON second mod' 'fusion' $depsJson[1].ModId

    Set-Content $depsPath '{"ModId":["neoforge","fusion"],"Required":[true,true],"VersionRange":["[21.11,)","[1.2.11,)"],"Source":["toml","toml"]}'
    $legacyDeps = @(Read-DetectedDependenciesJson -Root $fixtureRoot)
    Assert-Equal 'Legacy dependency JSON count' 2 $legacyDeps.Count
    Assert-Equal 'Legacy dependency JSON second mod' 'fusion' $legacyDeps[1].ModId

    $preserved = Join-Path $fixtureRoot 'preserved-profile'
    New-Item -ItemType Directory -Path (Join-Path $preserved 'src\main\java') -Force | Out-Null
    Set-Content (Join-Path $preserved 'gradle.properties') "source_minecraft_version=1.21.11`nminecraft_version=26.2"
    Set-Content (Join-Path $preserved 'SOURCE_PROFILE.json') '{"SourceVersion":"1.21.11","Loader":"neoforge","Framework":"unknown"}'
    $preservedResult = Get-SourceProfile $preserved
    Assert-Equal 'Preserved source beats target' '1.21.11' $preservedResult.SourceVersion
    Assert-Equal 'Preserved route' 'neoforge-1.21.x' $preservedResult.Route

    $stackLog = Join-Path $fixtureRoot 'stack-only.log'
    Set-Content $stackLog "FAILURE: Build failed with an exception.`nat org.gradle.internal.session.Foo.execute(Foo.java:46)"
    $stackSummary = Write-CompileDiagnosticSummary -LogPath $stackLog -ExitCode 1
    Assert-Equal 'Stack trace is not decompiler damage' 0 $stackSummary.Categories.'decompiler-artifact'

    $catalog = Get-DependencyCatalog -CatalogPath (Join-Path $repo 'lib\DependencyCatalog.json')
    $fusion = Get-CatalogEntry -Catalog $catalog -ModId 'fusion'
    Assert-Equal 'Fusion uses official dependency' 'official' $fusion.action
    Assert-Equal 'Fusion Modrinth slug' 'fusion-connected-textures' $fusion.modrinth

    $longSource = Join-Path $fixtureRoot 'long-source.txt'
    Set-Content $longSource 'long path copy works'
    $longDest = Join-Path $fixtureRoot ((@('segment12345678901234567890') * 9) -join '\')
    $longDest = Join-Path $longDest 'copied.txt'
    Copy-FileLongPath -Source $longSource -Destination $longDest
    Assert-True 'Long path copy' ([IO.File]::Exists((ConvertTo-ExtendedPath $longDest)))

    $primerIndex = Get-PrimerChangeIndex -Path (Join-Path $repo 'lib\PrimerChangeIndex.json')
    Assert-Equal 'Primer transition count' 16 @($primerIndex.transitions).Count
    $lateChain = @(Get-PrimerMigrationChain -SourceVersion '1.21.11' -Index $primerIndex)
    Assert-Equal '1.21.11 primer chain count' 2 $lateChain.Count
    Assert-Equal '1.21.11 chain ends at target' '26.2' $lateChain[-1].to
    $alreadyChain = @(Get-PrimerMigrationChain -SourceVersion '26.2' -Index $primerIndex)
    Assert-Equal '26.2 has no pending primers' 0 $alreadyChain.Count
    $primerReport = Join-Path $fixtureRoot 'PRIMER_CHANGE_INDEX.md'
    $primerCount = Write-PrimerQuickReference -Profile ([pscustomobject]@{ SourceVersion='1.21.11'; Route='neoforge-1.21.x' }) -Path $primerReport
    Assert-Equal 'Primer report step count' 2 $primerCount
    Assert-True 'Primer report written' (Test-Path $primerReport)

    Assert-Equal 'Block entity client-side field conversion' 'this.getLevel().isClientSide()' (Convert-LevelClientSideAccess 'this.level.isClientSide')
    Assert-Equal 'Block entity client-side call conversion' 'this.getLevel().isClientSide()' (Convert-LevelClientSideAccess 'this.level.isClientSide()')
    Assert-Equal 'Block entity client-side rewrite idempotent' 'this.getLevel().isClientSide()' (Convert-LevelClientSideAccess 'this.level().isClientSide()')
    Assert-Equal 'Entity client-side access' 'class Seat extends Entity { void x(){ this.level().isClientSide(); } }' (Convert-LevelClientSideAccess 'class Seat extends Entity { void x(){ this.level.isClientSide(); } }')
    Assert-Equal 'Variant mutator package move' 'import net.minecraft.client.renderer.block.dispatch.VariantMutator;' (Convert-NeoForge262ApiMoves 'import net.minecraft.client.renderer.block.model.VariantMutator;')
    Assert-Equal 'Camera render state package move' 'import net.minecraft.client.renderer.state.level.CameraRenderState;' (Convert-NeoForge262ApiMoves 'import net.minecraft.client.renderer.state.CameraRenderState;')
    Assert-Equal 'Item tag registry key' '.add(ModBlocks.TABLE.asItem().builtInRegistryHolder().key())' (Convert-NeoForge262ApiMoves '.add(ModBlocks.TABLE.asItem())')
    Assert-Equal '26.2 API moves idempotent' '.add(ModBlocks.TABLE.asItem().builtInRegistryHolder().key())' (Convert-NeoForge262ApiMoves '.add(ModBlocks.TABLE.asItem().builtInRegistryHolder().key())')
    Assert-Equal 'Block entity renderer default method' 'class R implements BlockEntityRenderer<A,B> { void x(){ BlockEntityRenderer.super.extractRenderState(a,b,c,d,e); } }' (Convert-NeoForge262ApiMoves 'class R implements BlockEntityRenderer<A,B> { void x(){ super.extractRenderState(a,b,c,d,e); } }')
    Assert-Equal 'Stained pane longest match' 'Blocks.STAINED_GLASS_PANE.black()' (Convert-ColorCollectionConstants 'Blocks.BLACK_STAINED_GLASS_PANE')
    Assert-Equal 'Concrete powder longest match' 'Blocks.CONCRETE_POWDER.white()' (Convert-ColorCollectionConstants 'Blocks.WHITE_CONCRETE_POWDER')
    Assert-Equal 'Color rewrite idempotent' 'Blocks.STAINED_GLASS_PANE.black()' (Convert-ColorCollectionConstants 'Blocks.STAINED_GLASS_PANE.black()')
}
finally {
    if (Test-Path $fixtureRoot) { [IO.Directory]::Delete((ConvertTo-ExtendedPath $fixtureRoot), $true) }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }
    exit 1
}
Write-Host "All conversion-core tests passed." -ForegroundColor Green
