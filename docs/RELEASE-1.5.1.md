# Release 1.5.1

Version 1.5.1 makes the primer index executable. Detection no longer only writes a reference report: it selects the ordered rule IDs required from the exact input version through NeoForge 26.2.

## Verified 1.21.1 conversion

Input: the original decompiled NextGen Furniture NeoForge 1.21.1 JAR.

Result: the normal converter selected 11 applicable transitions, applied the gated migration rules and semantic overlay, and completed `gradlew build` with exit code 0. The installable output is:

`nextgen_furniture-0.0.9-beta+mc26.2-neoforge.jar`

The original JAR remained unchanged.

## Scope

The migration graph supports exact source-version routing across the indexed releases. General rules are reusable across mods. The included 1.21.1 semantic overlay is intentionally restricted to NextGen Furniture because custom renderer behavior cannot safely be inferred by blind text replacement. Other mods can still produce targeted compile findings that should become new tested general rules or narrowly identified overlays.
