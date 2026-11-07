# RoadWeaver 26.3 migration notes

This source tree has been ported from Minecraft 1.21.11 to Minecraft 26.3 for the Fabric Architectury target only.

## Build requirements

- Java 25 (JDK, not just a JRE)
- Gradle 9.6.1 (the Gradle Wrapper downloads the configured distribution)
- Fabric Loader 0.19.5+ and Fabric API 0.165.2+26.3 for the Fabric build

Run `./gradlew build` on Linux/macOS or `gradlew.bat build` on Windows.

## Main porting changes

- Switched to Architectury Loom's `loom-no-remap` plugin for the unobfuscated 26.3 Minecraft runtime.
- Updated Shadow to 9.6.1 and changed the final artifact pipeline: Shadow creates a shaded intermediate, then Loom's ordinary `jar` task overlays it so its Jar-in-Jar metadata and `include(...)` libraries are retained.
- Updated both loader targets, Architectury API, Cloth Config, optional Mod Menu, the Java toolchain, and Gradle Wrapper (Gradle 9.6.1).
- Migrated RoadWeaver's custom world-generation features to the 26.3 `Feature`/`MapCodec` model and `FEATURE_TYPE` registry.
- Moved custom feature definitions from `worldgen/configured_feature` to `worldgen/feature`; the old `config` object is no longer present.
- Replaced the old `ConfiguredFeature` interception mixins with a `FeaturePlacer` hook that filters tree-like placements on roads.
- Replaced GLFW key constants with Minecraft's `InputConstants` key and mouse constants for the SDL3 input backend.
- Replaced legacy `NoiseChunk`/`DensityFunction` column sampling with `ChunkGenerator#getBaseHeight`, retaining cached coarse sampling and exact per-column sampling modes.
- Updated structure reference lookup and injection for the 26.3 `StructureManager`/`StructureAccess` API, and updated `ChunkPos` record accessors and packing helpers.
- Migrated Beardifier road-density injection from the removed `compute` method to `DensitySampler#sampleValue` with `SamplerContext`.
- Updated sign text mutation to `SignText.Mutable`/`SignTextSlot`, and player overlays to the 26.3 `sendOverlayMessage` API.
- Updated mixin compatibility to Java 25 and bundled resource-pack metadata to format 97.1.

## Compatibility scope

The previous version-specific TYG, RTF, and DynamicTrees mixins were removed because they targeted the old feature-placement API. The new generic `FeaturePlacer` interception is intended to cover tree-like features through the common placement path, but integrations with those mods have not been runtime-verified on 26.3.

## Validation status

Source and resource migration checks have been performed. The uploaded Windows build logs confirmed that common and Fabric Java compilation pass after the reported source fixes. The last all-platform build stopped while Architectury transformed the NeoForge production jar; that loader is intentionally removed in this Fabric-only distribution. A clean Fabric-only Gradle build and runtime test should still be completed on JDK 25 with access to the required Maven repositories; this workspace only has Java 21 and no Gradle distribution cache, so this archive is not represented as a compiled or runtime-tested JAR.

## Follow-up compile fixes (2026-11-07)

The next Windows build reported five remaining common-source API mismatches. These have been corrected:

- Overlay denial messages now call `Minecraft.gui.hud.setOverlayMessage(...)` (the overlay API belongs to `Hud`, exposed as `Gui.hud`).
- Structure verification now supplies `MinecraftServer.getStructureTemplateManager()` to `StructureCheck`.
- Structure injection and bridge-template lookup now use `ServerLevel.getStructureTemplateManager()`.

These are source-level fixes; a complete Gradle build still needs to be run on a machine with JDK 25 and working dependency access.

### Follow-up compile fixes (revision 3)

- Fabric DataGen now uses `FabricPackOutput` (26.3 API) instead of `FabricDataOutput`.
- Fabric key registration now uses `KeyMappingHelper.registerKeyMapping`.
- Fabric play payload registries now use `serverboundPlay` / `clientboundPlay`.

## Fabric-only distribution

This distribution intentionally contains only the Fabric loader module. The NeoForge module, platform dependencies, production transform, and release artifact have been removed. The common module is configured for Fabric only, and the release workflow now builds and publishes only the Fabric artifact.
