# Release 1.5.0

Version 1.5.0 is the first release in the `MC-Java-1.20.1-to-26.2-Converter` repository.

## Included

- Windows self-contained GUI installer and portable distribution
- Project-folder and finished-JAR conversion modes
- Vineflower decompile intake with complete non-class resource copying
- Source loader/version detection from Forge 1.20.1 through NeoForge 26.2
- Ordered primer-change reference and route-specific migration passes
- Dependency detection, official 26.2 resolution and required-dependency conversion
- NeoForge 26.2 ModDevGradle scaffold generation
- Java, registry, event, render, model, resource and asset migrations
- Full Gradle build option and structured reports
- PowerShell regression test suite

## Verified build

NextGen Furniture `1.21.11 / 0.0.9-beta` was decompiled and converted to NeoForge 26.2. Its full `gradlew build` completed successfully and produced an installable JAR. This verifies the 26.2 model metadata, standalone models, block entity renderer state, packed lighting, state-property copying, item tags and official Fusion dependency path used by that project.

Compilation is not the same as an in-game certification. Converted mods should still be launched in a dedicated test instance before distribution.

## Release artifacts

- `RB-Legacy-Java-Converter-Setup.exe`
- `RB-Legacy-Java-Converter-Portable.zip`

The repository contains complete source and build scripts; generated binaries are distributed through GitHub Releases.
