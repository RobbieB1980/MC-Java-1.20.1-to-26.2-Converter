# Dependency pipeline

The converter cannot magically make **every** Forge 1.20.1 mod a loadable 26.2 jar. Mixins, coremods, and huge APIs still need hand work. It **does** now:

1. Read what the mod actually depends on
2. Download an official NeoForge 26.2 build when one exists
3. Decompile + convert required mods that still need a 26.2 port

## Where dependencies are read

| Source | Example |
|--------|---------|
| `META-INF/mods.toml` / `neoforge.mods.toml` | `[[dependencies.mymod]] modId="geckolib"` |
| `build.gradle` | `implementation fg.deobf("software.bernie.geckolib:...")` |
| `META-INF/jarjar/metadata.json` | Forge jar-in-jar |
| Java imports | `software.bernie.geckolib`, `mezz.jei`, … |
| `detected-dependencies.json` | Written by the jar decompiler |

`minecraft`, `forge`, and `neoforge` are skipped.

## Resolution order (per mod id)

1. **Catalog Maven** — GeckoLib 5.5.3, SmartBrainLib 2.0.0, …
2. **Modrinth** — NeoForge 26.2 jar, then Forge 26.2 jar
3. **Convert** — only if the dep is **required** (or `-ConvertOptionalDependencies`)
   - Local jar from `-DependencyJarDir`, source `libs/`, or `run/mods/`
   - Else download the Forge **1.20.1** jar from Modrinth and run the same pipeline
4. **Gap** — recorded in `DEPENDENCY_REPORT.md`

Never auto-converted (need official 26.2 ports): Architectury, Kotlin for Forge, Flywheel, Create, MixinExtras.

## Output layout

```
mymod-26.2/
  libs/                  official or converted jars used at compile time
  converted-deps/        recursive 26.2 scaffolds for required mods
  DEPENDENCY_REPORT.md
  detected-dependencies.json
```

Jars are cached in `tools/lib/dep-cache/` so re-runs do not re-download.

## Limits

- Recursive convert uses the same first-pass rewrites. A converted dependency may not compile.
- Default depth is **2**. Raise `-MaxDependencyDepth` only if you accept a long run.
- Optional toml deps are listed but not converted unless `-ConvertOptionalDependencies`.
- Put 1.20.1 companion jars next to the input (or pass `-DependencyJarDir`) when Modrinth has no matching slug.
