# Changelog

## 1.5.3 — 2026-08-29

- Fixed the NeoForge 26.2 runtime crash `Block id not set` for custom `Supplier`-based block registration helpers.
- Custom block and block-item factories now receive registry-keyed properties; added idempotent regression coverage.

## 1.5.2 — 2026-08-29

- Fixed the self-contained installer preferring an older portable ZIP beside the setup EXE over its embedded payload.
- Setup now verifies the installed application version and exact-primer migration stage before reporting success.

## 1.5.1 — 2026-08-29

- Primer transitions now carry executable rule IDs, so the detected source version selects only the cumulative migration path required to reach 26.2.
- Added 1.21.1 render-state, standalone-model, block-entity value I/O, entity registration/damage, direction-property and legacy-datagen migrations.
- Added a verified semantic overlay for NextGen Furniture 1.21.1.
- Proved the untouched 1.21.1 decompile through the normal converter pipeline: full `gradlew build` and an installable `nextgen_furniture-0.0.9-beta+mc26.2-neoforge.jar`.

## 1.5.0 — 2026-08-29

Complete staged conversion and verification release.

### Detection and reference index
- Evidence-based Forge/NeoForge source detection from 1.20.1 through 26.2.
- Route-specific migration passes and `SOURCE_PROFILE.json`.
- Ordered `PrimerChangeIndex.json` and generated source-specific `PRIMER_CHANGE_INDEX.md`.

### Build and reports
- `-Compile` now runs the complete Gradle build and only reports success when `build/libs` contains an installable JAR.
- Structured compile reports, dependency report, migration report and preserved decompile report.
- Version-prefixed installable JAR handling; the original input JAR is never copied or renamed as a result.

### NeoForge 26.2 migrations
- Package moves for block-state models, variant mutators and camera render state.
- Entity `level()` versus block-entity `getLevel()` detection.
- Removed `ItemBlockRenderTypes` calls migrated to model `render_type` metadata.
- 26.2 block-model submission compatibility, packed-light lookup and standalone-model event registration.
- Stream-based block-state property copying and registry-key item tags.
- Fixed idempotency defects in client-side and color-collection rewrites.

### Dependencies and verification
- Dependency JSON compatibility and optional `MavenHint` handling.
- Official Fusion 26.2 dependency resolution.
- Verified NextGen Furniture 1.21.11 conversion with `gradlew build` and an installable NeoForge 26.2 JAR.

## 1.4.0 — 2026-08-23

Final 26.2 converter from the Knocker + The One Who Watches (TOWW) campaign.

### Jar extract
- Copy **every non-class file** from the original jar (textures, geo, animations, sounds, data, logo, mixins).
- Decompile report lists PNG/ogg/geo/animation/nbt counts and writes `original-jar.txt`.
- 26.2 convert restores assets from the source tree, sibling jar, or `-OriginalJarPath` if the decompile was Java-only.

### Mappings
- Official SRG map from workstation `Minecraft_Mappings/1.20.1` flat TSV (64,225 unique, 0 conflicts) → `lib/Srg1201Official.json`.
- `Srg1201Common.json` only holds SRGs missing from that flat map (guessed overlays were renaming `playLocalSound` → `setBlock`).

### NeoForge 26.2 load
- `DeferredRegister.Blocks.registerBlock` / `Items.registerItem` + `Properties` constructors (`Block/Item id not set`).
- `ForgeSpawnEggItem(entity,…)` → `properties.spawnEgg(entity.get())`.
- `queueServerWork` only on the server thread (C2ME `playLocalSound` crash).
- `Animal.createAnimalAttributes()` so `TemptGoal` has `minecraft:tempt_range`.
- Skip MCreator `OnInitialEntitySpawn` discard for `SPAWN_ITEM_USE` / `COMMAND` / `DISPENSER` / `MOB_SUMMONED`.
- Do not double-register `EntityAttributeCreationEvent`.

### GeckoLib 5
- Bare geo IDs (`toww_geckolib` → `assets/<mod>/geckolib/models|animations/`).
- Real texture PNG (never `unknown.png`); `AnimationController<>` not array wrap.
- Procedure controller `STOP` when clip empty; do not flatten every form to pose1.
- TOWW live stack can use completed-port `TowwGeoModel` / `TowwGeoRenderer` / `AbstractTOWWMonster`.
- Do not store MCreator `WorldVariables` under the same SavedData id as `TowwWorldData` (`worldvars`).

### Proven
- **The Knocker** — 26.2 jar, in-game spawn.
- **The One Who Watches** — 26.2 jar loads; GeckoLib geo/anim/textures packed; spawn-egg / summon; world-data crash fixed.

## 1.2.6 — 2026-08-01

### Networking rewrite actually applies (MOAdecor BATH retest)
- **Critical fix:** v1.2.5 `MESSAGES.forEach → playBidirectional` rewrite regex never matched
  real MCreator output (`playBidirectional(...));` vs broken `...;);` pattern).
- Now matches the single-line forEach lambda, injects typed `registerOne`, and when
  `network/MenuStateUpdateMessage.java` exists:
  - registers `MenuStateUpdateMessage` directly on `RegisterPayloadHandlersEvent` (4-arg)
  - strips late `@EventBusSubscriber` / `FMLCommonSetupEvent` registration
- Proven: reconverted **MOAdecor BATH** builds a loadable jar; problems report is deprecation
  warnings only (0 ERROR).

### Packaging
- GUI / Setup / portable package **1.2.6**

## 1.2.5 — 2026-08-01

### Networking forEach type-inference fix (MOAdecor GARDEN)
- **Fix:** MCreator main class pattern  
  `MESSAGES.forEach((id, msg) -> registrar.playBidirectional(...))`  
  fails to compile under Java generics wildcards  
  (`no suitable method found for playBidirectional` / CAP# constraints).
- Converter rewrites that form to a typed `registerOne` helper loop.
- Prefer registering `MenuStateUpdateMessage` on `RegisterPayloadHandlersEvent`  
  with 4-arg handlers (not `FMLCommonSetupEvent`).

Proven: **MOAdecor GARDEN 1.21.8.A** → `gradlew build`.

### Packaging
- GUI / Setup / portable package **1.2.5**

## 1.2.4 — 2026-08-01

### Converter rewrite safety (MOAdecor ELECTRONICS)
- **Fix:** naive `playBidirectional` 3→4-arg expansion could mangle
  `networkMessage.handler()` into invalid Java  
  `handler(, handler(), handler())` (compile failure).
- Now only rewrites the exact MCreator form  
  `playBidirectional(id, msg.reader(), msg.handler())`  
  and can repair the previously corrupted form.
- **Fix:** `registerItem` rewrite no longer treats nested  
  `new BlockItem(..., prop)` as the third argument; repairs  
  `BlockItem(..., () -> prop)` and wraps only the final  
  `properties` variable as `() -> properties`.

Proven: **MOAdecor ELECTRONICS 1.21.8.A** → `gradlew build` after re-apply.

### Packaging
- GUI / Setup / portable package **1.2.4**

## 1.2.3 — 2026-08-01

### MCreator / NeoForge 1.21.x → 26.2 pass (MOAdecor BATH)
New rewrite pass for decompiled **1.21.8 NeoForge / MCreator** jars (in addition to Forge 1.20.1). Not a separate converter product — same Legacy pipeline + extra pass:
- Remove `shouldDisplayFluidOverlay` + old `BlockAndTintGetter` import (method gone from Block)
- `.noCollission()` → `.noCollision()`
- `GuiGraphics` → `GuiGraphicsExtractor`; `renderBg` → `extractBackground`; tooltip/label extract renames
- Final `imageWidth`/`imageHeight` → `super(menu, inv, title, w, h)` (including delayed field assigns)
- `keyPressed(int,int,int)` → `keyPressed(KeyEvent)` (ESC close pattern)
- `.isClientSide` field → `.isClientSide()`
- `net.minecraft.util.Tuple` delayed work queue → `Object[]` holders
- Stub MCreator `ItemHandler.ITEM` / `ItemHandler.ENTITY` capability binds (transfer API is manual)
- `Minecraft.getInstance().screen` → `gui.screen()`
- `registerItem(name, fn, Properties)` → supplier form `() -> properties`
- Payload `StreamCodec<? extends FriendlyByteBuf` → `? super RegistryFriendlyByteBuf`
- **Critical networking:** use 4-arg `playBidirectional(type, codec, handler, handler)` — 3-arg leaves client handler null and crashes with `missing client-side handlers`

Proven: **MOAdecor BATH 1.21.8.A** → compile, `gradlew build`, and **client load on NeoForge 26.2.0.32-beta**.

### Packaging
- GUI / Setup / portable package **1.2.3**

## 1.2.2 — 2026-08-01

### 26.2 API rewrite expansions (BuildPaste / decompile lessons)
- `EntityType.VANILLA_FIELD` → `EntityTypes.VANILLA_FIELD` (+ import)
- Full **ColorCollection** grid for `Items`/`Blocks` (`WHITE_WOOL` → `WOOL.white()`, glazed terracotta, beds, carpets, …)
- `getMainCamera()` → `mainCamera()`
- `Minecraft.getInstance().renderBuffers()` → `gameRenderer.renderBuffers()`
- Note: `MultiBufferSource` / `.bufferSource()` world drawing still needs manual `SubmitCustomGeometryEvent` + `submitShapeOutline` (naive renames are not enough)

### Packaging
- Bump GUI / portable package when releasing **1.2.2**

## 1.2.1 — 2026-07-25

### Critical fix (The Knocker world-join disconnect)
- **ModConfigSpec define-before-build pass:** decompiled MCreator configs that call `BUILDER.build()` before `.define(...)` caused  
  `Cannot get config value before spec is built` on player spawn → **Connection lost / Disconnected**.
- Converter now reorders SPEC construction after config value definitions.

### Packaging
- GUI + Setup version **1.2.1**
- Rebuild installer / portable package

## 1.2.0 — 2026-07-25

Proven on **Friend** (runtime) and **The Knocker** (NeoForge 1.21.8 jar → 26.2 compile/build).

### Critical fixes
- **Strip leftover `src/main/resources/META-INF/neoforge.mods.toml`** (and `mods.toml` / `MANIFEST.MF`) so generated templates control Minecraft/NeoForge `versionRange`.
  - Fixes loader rejection still asking for old versions such as **1.21.8**.
- Clearer docs: conversion success ≠ loadable mod; only install `gradlew build` output jars; never rename the input jar as 26.2.

### API rewrite expansions (26.2)
- `displayClientMessage` → `sendSystemMessage`
- `getLevelData().getSpawnPos()` → `getRespawnData().pos()`
- `getRespawnConfig().pos()/dimension()` → `respawnData()...`
- Broader `entity.getServer()` → `level().getServer()` receivers
- `CommandSourceStack` permission int → `LevelBasedPermissionSet`

## 1.1.x and earlier
See git history for initial GUI, jar pipeline, and Forge 1.20.1 scaffold support.
