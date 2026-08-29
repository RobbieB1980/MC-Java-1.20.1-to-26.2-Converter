# Converter architecture

The converter uses two independent forms of evidence before changing Java code:

1. **Source metadata** — `gradle.properties`, Gradle dependencies, Forge/NeoForge TOML dependency ranges, loader files, and Java imports.
2. **API feature inventory** — scans Java sources for old package names and API families such as Forge imports, SRG names, legacy tick events, old NBT access, event subscribers, registries, capabilities, GUI rendering, and GeckoLib 4.

The result is written to `SOURCE_PROFILE.json`. It contains the detected source version, loader, confidence, route, evidence, matched API features, and planned migration passes.

`lib/PrimerChangeIndex.json` stores the ordered migration deltas and executable rule IDs. The final project receives `PRIMER_CHANGE_INDEX.md` containing only the transitions between its detected source and 26.2. Official primer transitions link to NeoForged; the unpublished 1.20.1–1.20.4 interval is explicitly labeled as a converter-maintained bridge.

The selected path is cumulative. For example, a detected 1.21.1 input receives the rules attached to every transition after 1.21.1, while a 1.21.11 input skips rules for APIs already changed in earlier releases. Shared mechanical rules remain general; narrowly semantic replacements live in version-and-mod-specific overlays and only run after both identities match.

## Cumulative routes

| Detected input | Route | Intended migration |
|---|---|---|
| Forge 1.20.1 | `forge-1.20.1` | Full SRG/Forge/API/MCreator chain to 26.2 |
| NeoForge 1.21.x | `neoforge-1.21.x` | 1.21-era API and MCreator passes, then 26.2 passes |
| NeoForge 22.x–25.x | `neoforge-22-to-25` | Common feature-driven 26.2 passes |
| NeoForge 26.0–26.1 | `neoforge-26.0-26.1` | Common 26.2 delta; skips old MCreator residue passes |
| NeoForge 26.2 | `already-26.2` | Conservative scaffold/registry/assets checks only |
| Fabric/Quilt | `unsupported-fabric-quilt` | Decompile is allowed; conversion stops clearly |
| Missing/mixed metadata | `generic-forge-neoforge` | Broad fallback supplemented by API feature evidence |

Routes control which rewrite functions run. Feature evidence can add a required pass when metadata is missing or decompiled sources mix APIs from multiple eras.

## Pipeline

1. JAR extraction and Vineflower decompilation (JAR mode)
2. Loader/version detection and API inventory
3. Source/resource layout and complete non-class resource copy
4. Dependency discovery and acquisition plan
5. NeoForge 26.2 ModDevGradle scaffold
6. Ordered, exact-version primer rules followed by route/feature-aware Java migration passes
7. Registry, mod entry point, event bus, assets, and client item repair
8. Optional `compileJava`
9. `COMPILE_REPORT.md`, `COMPILE_REPORT.json`, and full `compile-errors.log`

## Important boundary

This is a deterministic migration assistant, not a universal semantic Java translator. It can identify and rewrite known API patterns. Complex mixins, networking, custom render pipelines, capabilities/transfer code, world generation, and decompiler damage may still require targeted rules or manual work. A green `compileJava`, `build`, and `runClient` test remain the completion criteria for each converted mod.

When a new migration failure is fixed, add its detection pattern and regression fixture before broadening a rewrite. This keeps newer sources from receiving destructive old-version substitutions.
