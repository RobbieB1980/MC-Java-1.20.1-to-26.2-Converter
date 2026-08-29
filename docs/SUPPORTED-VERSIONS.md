# Supported source versions

The converter targets NeoForge 26.2 and selects its migration passes from detected metadata and Java API evidence.

| Source | Detection | Conversion route |
|---|---|---|
| Forge 1.20.1 | Supported | Forge/SRG, registry, event, MCreator and cumulative 26.2 migrations |
| NeoForge 1.21.x | Supported | 1.21-era, MCreator and cumulative 26.2 migrations |
| NeoForge 22.x–25.x | Supported | Feature-driven cumulative 26.2 migrations |
| NeoForge 26.0–26.1 | Supported | Direct 26.2 delta |
| NeoForge 26.2 | Detected | Conservative rebuild/resource checks |
| Fabric or Quilt | Detected, not converted | Decompile/resources only, followed by a clear unsupported result |

`SOURCE_PROFILE.json` records the selected route, confidence, evidence and migration passes. `PRIMER_CHANGE_INDEX.md` contains only the applicable ordered changes between the detected source and 26.2.

Supported means that the pipeline can intake and route the source version. It does not guarantee that every arbitrary mod compiles without a project-specific rule. Mixins, custom networking, capabilities/transfer systems, world generation and custom render geometry can require manual work.

## Completion criteria

A conversion is installable only when all of these are true:

1. `gradlew build` succeeds.
2. A newly compiled JAR exists under `build/libs`.
3. NeoForge starts with the converted JAR and its required 26.2 dependencies.
4. The mod's important content is tested in a world.

Never rename or copy the original input JAR into a 26.2 mods folder.
