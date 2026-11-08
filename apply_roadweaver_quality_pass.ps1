param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$patches = New-Object System.Collections.Generic.List[object]
function AddPatch([string]$File, [string]$Old, [string]$New, [int]$Expected = 1) {
    $script:patches.Add([pscustomobject]@{ File=$File; Old=$Old; New=$New; Expected=$Expected })
}

# 1) Terrain-level ocean barrier. Sample between coarse A* nodes, not only at endpoints.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/terrain/PathTerrainField.java' @'
    default int waterDepth(int x, int z) {
'@ @'
    default boolean isOceanBiome(int x, int z) {
        if (!contains(x, z)) return false;
        var holder = biome(x, z);
        return holder != null && (holder.is(BiomeTags.IS_OCEAN) || holder.is(BiomeTags.IS_DEEP_OCEAN));
    }

    default boolean crossesOcean(int fromX, int fromZ, int toX, int toZ) {
        int dx = toX - fromX;
        int dz = toZ - fromZ;
        int distance = Math.max(Math.abs(dx), Math.abs(dz));
        int samples = Math.max(1, (distance + 3) / 4);
        for (int i = 0; i <= samples; i++) {
            double t = (double) i / samples;
            int x = (int) Math.round(fromX + dx * t);
            int z = (int) Math.round(fromZ + dz * t);
            if (isOceanBiome(x, z)) return true;
        }
        return false;
    }

    default int waterDepth(int x, int z) {
'@

# 2) Apply ocean rejection to every supported ordinary-road pathfinder.
$searchPaths = @(
 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/BasicAStarPathfinder.java',
 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/GradientDescentPathfinder.java',
 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/PotentialFieldPathfinder.java'
)
foreach ($file in $searchPaths) {
    AddPatch $file @'
                    if (!terrain.contains(nxz.getX(), nxz.getZ())) continue;
'@ @'
                    if (!terrain.contains(nxz.getX(), nxz.getZ())) continue;
                    if (terrain.crossesOcean(current.pos.getX(), current.pos.getZ(), nxz.getX(), nxz.getZ())) continue;
'@
}
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/BidirectionalAStarPathfinder.java' @'
            if (!terrain.contains(nxz.getX(), nxz.getZ())) continue;
'@ @'
            if (!terrain.contains(nxz.getX(), nxz.getZ())) continue;
            if (terrain.crossesOcean(current.pos.getX(), current.pos.getZ(), nxz.getX(), nxz.getZ())) continue;
'@

# Exact endpoint completion prevents Gradient/Potential/Basic from accepting a route several blocks short.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/BasicAStarPathfinder.java' @'
                if (manhattan2d(current.pos, end) < d * 2) {
'@ @'
                if (current.pos.getX() == end.getX() && current.pos.getZ() == end.getZ()) {
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/GradientDescentPathfinder.java' @'
                if (manhattan2d(current.pos, end) < (int) (d * RoadConstants.GRADIENT_DESCENT_SUCCESS_DISTANCE_FACTOR)) {
'@ @'
                if (current.pos.getX() == end.getX() && current.pos.getZ() == end.getZ()) {
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/PotentialFieldPathfinder.java' @'
                if (manhattan2d(current.pos, end) < (int) (d * RoadConstants.POTENTIAL_FIELD_SUCCESS_DISTANCE_FACTOR)) {
'@ @'
                if (current.pos.getX() == end.getX() && current.pos.getZ() == end.getZ()) {
'@

# Reduce lateral wandering in the default gradient-based algorithm.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/GradientDescentPathfinder.java' @'
                    double gCost = current.gCost + computeMoveCost(current.pos, np, nxz, off, d,
                            terrain, cfg);
'@ @'
                    double gCost = current.gCost + computeMoveCost(current.pos, np, nxz, off, d,
                            start, end, terrain, cfg);
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/GradientDescentPathfinder.java' @'
    private double computeMoveCost(BlockPos current, BlockPos np, BlockPos nxz, int[] off, int d,
                                   PathTerrainField terrain,
                                   PathfindingCostConfig cfg) {
'@ @'
    private double computeMoveCost(BlockPos current, BlockPos np, BlockPos nxz, int[] off, int d,
                                   BlockPos start, BlockPos end,
                                   PathTerrainField terrain,
                                   PathfindingCostConfig cfg) {
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/GradientDescentPathfinder.java' @'
        double nearWaterPenalty = nearWater ? (cfg.nearWaterCost() * NEAR_WATER_COST_MULTIPLIER) : 0.0;

        double elevationCost = elevation * elevation * cfg.elevationWeight();
'@ @'
        double nearWaterPenalty = nearWater ? (cfg.nearWaterCost() * NEAR_WATER_COST_MULTIPLIER) : 0.0;
        double deviationCost = deviationFromDirectLine(np, start, end)
                * cfg.deviationWeight() / Math.max(1, d);

        double elevationCost = elevation * elevation * cfg.elevationWeight();
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/GradientDescentPathfinder.java' @'
                + waterDepthPenalty
                + nearWaterPenalty;
    }

    private List<RoadSegmentPlacement> reconstructPath(List<BlockPos> rawPath, int width,
'@ @'
                + waterDepthPenalty
                + nearWaterPenalty
                + deviationCost;
    }

    private static double deviationFromDirectLine(BlockPos point, BlockPos start, BlockPos end) {
        double ax = start.getX(), az = start.getZ();
        double bx = end.getX(), bz = end.getZ();
        double dx = bx - ax, dz = bz - az;
        double length = Math.hypot(dx, dz);
        if (length < 1.0e-6) return 0.0;
        return Math.abs(dz * point.getX() - dx * point.getZ() + bx * az - bz * ax) / length;
    }

    private List<RoadSegmentPlacement> reconstructPath(List<BlockPos> rawPath, int width,
'@

# Apply the same route-stability penalty to Potential Field mode.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/PotentialFieldPathfinder.java' @'
                    double moveCost = computeMoveCost(
                            current.pos, np, nxz, off, d,
                            grad, gradMag, contour,
                            terrain, cfg);
'@ @'
                    double moveCost = computeMoveCost(
                            current.pos, np, nxz, off, d,
                            start, end, grad, gradMag, contour,
                            terrain, cfg);
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/PotentialFieldPathfinder.java' @'
    private double computeMoveCost(BlockPos current, BlockPos np, BlockPos nxz,
                                   int[] off, int d,
                                   double[] grad, double gradMag, double[] contour,
'@ @'
    private double computeMoveCost(BlockPos current, BlockPos np, BlockPos nxz,
                                   int[] off, int d,
                                   BlockPos start, BlockPos end,
                                   double[] grad, double gradMag, double[] contour,
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/PotentialFieldPathfinder.java' @'
        double nearWaterPenalty = nearWater ? (cfg.nearWaterCost() * 3.0) : 0.0;

        return adjustedBase
'@ @'
        double nearWaterPenalty = nearWater ? (cfg.nearWaterCost() * 3.0) : 0.0;
        double deviationCost = deviationFromDirectLine(np, start, end)
                * cfg.deviationWeight() / Math.max(1, d);

        return adjustedBase
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/impl/PotentialFieldPathfinder.java' @'
                + waterPenalty
                + nearWaterPenalty;
    }

    private List<RoadSegmentPlacement> reconstructPath(List<BlockPos> rawPath, int width,
'@ @'
                + waterPenalty
                + nearWaterPenalty
                + deviationCost;
    }

    private static double deviationFromDirectLine(BlockPos point, BlockPos start, BlockPos end) {
        double ax = start.getX(), az = start.getZ();
        double bx = end.getX(), bz = end.getZ();
        double dx = bx - ax, dz = bz - az;
        double length = Math.hypot(dx, dz);
        if (length < 1.0e-6) return 0.0;
        return Math.abs(dz * point.getX() - dx * point.getZ() + bx * az - bz * ax) / length;
    }

    private List<RoadSegmentPlacement> reconstructPath(List<BlockPos> rawPath, int width,
'@

# A quantized water sample must not hide a real river under the final path.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/pathfinding/PathSpanExtractor.java' @'
        if (terrain != null && terrain.contains(pos.getX(), pos.getZ())) {
            return terrain.isBridgeWater(pos.getX(), pos.getZ(), minWaterDepth);
        }
'@ @'
        if (terrain != null && terrain.contains(pos.getX(), pos.getZ())
                && terrain.isBridgeWater(pos.getX(), pos.getZ(), minWaterDepth)) {
            return true;
        }
'@

# 3) Reject ocean points introduced by spline smoothing / road-width rasterization.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/pathfinding/RoadPathCalculator.java' @'
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
'@ @'
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.tags.BiomeTags;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/pathfinding/RoadPathCalculator.java' @'
        return segments == null ? PathCalculationResult.failure() : new PathCalculationResult(segments, terrain);
    }

    static int heightSampler(TerrainSamplingCache cache, int x, int z, ServerLevel level) {
'@ @'
        if (segments == null || segments.isEmpty() || touchesOceanBiome(segments, level, cache)) {
            return PathCalculationResult.failure();
        }
        return new PathCalculationResult(segments, terrain);
    }

    private static boolean touchesOceanBiome(List<RoadSegmentPlacement> segments,
                                             ServerLevel level,
                                             TerrainSamplingCache cache) {
        for (RoadSegmentPlacement segment : segments) {
            BlockPos center = segment.middlePos();
            if (isOcean(cache.getBiome(level, center.getX(), center.getZ()))) return true;
            for (BlockPos pos : segment.positions()) {
                if (isOcean(cache.getBiome(level, pos.getX(), pos.getZ()))) return true;
            }
        }
        return false;
    }

    private static boolean isOcean(net.minecraft.core.Holder<net.minecraft.world.level.biome.Biome> biome) {
        return biome != null && (biome.is(BiomeTags.IS_OCEAN) || biome.is(BiomeTags.IS_DEEP_OCEAN));
    }

    static int heightSampler(TerrainSamplingCache cache, int x, int z, ServerLevel level) {
'@

# 4) Reject water-filled road-width cells unless the corresponding segment is a planned bridge.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/core/Road.java' @'
            List<RoadSpan> spans = PathSpanExtractor.extractSpans(
                    segments,
                    level,
                    cache,
                    terrain,
                    generationConfig.bridgeMinWaterDepth());
            List<Integer> targetY = computeTargetY(segments, spans);
'@ @'
            List<RoadSpan> spans = PathSpanExtractor.extractSpans(
                    segments,
                    level,
                    cache,
                    terrain,
                    generationConfig.bridgeMinWaterDepth());
            if (containsUnbridgedWater(segments, spans, level, cache)) {
                return null;
            }
            List<Integer> targetY = computeTargetY(segments, spans);
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/core/Road.java' @'
    private static int getRandomWidth(RandomSource random, PathFeatureConfig config) {
'@ @'
    private static boolean containsUnbridgedWater(List<RoadSegmentPlacement> segments,
                                                  List<RoadSpan> spans,
                                                  ServerLevel level,
                                                  TerrainSamplingCache cache) {
        Map<Long, Integer> indexByCenter = new HashMap<>();
        for (int i = 0; i < segments.size(); i++) {
            indexByCenter.put(segments.get(i).middlePos().asLong(), i);
        }
        boolean[] bridgeMask = new boolean[segments.size()];
        if (spans != null) {
            for (RoadSpan span : spans) {
                if (span.type() != SpanType.BRIDGE) continue;
                Integer a = indexByCenter.get(span.start().asLong());
                Integer b = indexByCenter.get(span.end().asLong());
                if (a == null || b == null) continue;
                int first = Math.max(0, Math.min(a, b));
                int last = Math.min(segments.size() - 1, Math.max(a, b));
                for (int i = first; i <= last; i++) bridgeMask[i] = true;
            }
        }
        for (int i = 0; i < segments.size(); i++) {
            if (bridgeMask[i]) continue;
            for (BlockPos pos : segments.get(i).positions()) {
                if (cache.isColumnWater(level, pos.getX(), pos.getZ())) return true;
            }
        }
        return false;
    }

    private static int getRandomWidth(RandomSource random, PathFeatureConfig config) {
'@

# 5) Let ordinary river bridges reach 256 blocks even if the old default (100) was retained in config.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/bridge/BridgeRangeCalculator.java' @'
        int maxLenBlocks = useBuoysInstead ? 0 : Math.max(0, cfg.bridgeMaxLengthBlocks());
'@ @'
        int configuredMaxLength = cfg.bridgeMaxLengthBlocks();
        int maxLenBlocks = useBuoysInstead || configuredMaxLength <= 0
                ? 0
                : Math.max(256, configuredMaxLength);
'@

# 6) The sea-question sign is only appropriate beside ocean biomes, never ordinary rivers.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/decoration/system/SkippedBridgeBankSignPlanner.java' @'
import net.minecraft.core.Vec3i;
import net.minecraft.world.level.WorldGenLevel;
'@ @'
import net.minecraft.core.Vec3i;
import net.minecraft.tags.BiomeTags;
import net.minecraft.world.level.WorldGenLevel;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/decoration/system/SkippedBridgeBankSignPlanner.java' @'
        if (!beforeSkip && !afterSkip) return;

        int dx = nextPos.getX() - prevPos.getX();
'@ @'
        if (!beforeSkip && !afterSkip) return;
        if (!isOcean(world, placePos) && !isOcean(world, nextPos) && !isOcean(world, prevPos)) return;

        int dx = nextPos.getX() - prevPos.getX();
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/decoration/system/SkippedBridgeBankSignPlanner.java' @'
    }
}
'@ @'
    }

    private static boolean isOcean(WorldGenLevel world, BlockPos pos) {
        var biome = world.getBiome(pos);
        return biome.is(BiomeTags.IS_OCEAN) || biome.is(BiomeTags.IS_DEEP_OCEAN);
    }
}
'@

# 7) Remove the old arbitrary seven-segment end suppression; it disagreed with the map polyline.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/PathFeature.java' @'
            segmentIndex++;
            if (segmentIndex < 8 || segmentIndex > segments.size() - 8)
                continue;
            ChunkPos middleChunk = ChunkPos.containing(middle);
'@ @'
            segmentIndex++;
            ChunkPos middleChunk = ChunkPos.containing(middle);
'@

# 8) Cap village endpoint trimming so roads can reach the village's actual path network.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/core/StructureRoadOffsetService.java' @'
            case VILLAGE -> cfg.villageRoadOffset();
'@ @'
            case VILLAGE -> Math.min(cfg.villageRoadOffset(), 16);
'@

# 9) A bounded dirt-path connector runs only when a route endpoint and a real village path are in the same generated chunk.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/PathFeature.java' @'
import net.shiroha233.roadweaver.features.path.pathlogic.core.SegmentPaver;
'@ @'
import net.shiroha233.roadweaver.features.path.pathlogic.core.SegmentPaver;
import net.shiroha233.roadweaver.features.path.pathlogic.core.VillagePathConnector;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/features/path/PathFeature.java' @'
            }
        }
    }
}
'@ @'
            }
        }
        VillagePathConnector.connectInChunk(world, currentChunk, middlePositions);
    }
}
'@

# 10) Map snapshot viewport coverage: zooming inside already-fetched bounds does not launch another full scan.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/RoadMapScreen.java' @'
    private MapSnapshot snapshot = MapSnapshot.empty();
    private Identifier currentDimensionId;
'@ @'
    private MapSnapshot snapshot = MapSnapshot.empty();
    private Identifier currentDimensionId;
    private Identifier snapshotCoverageDimensionId;
    private Identifier requestedSnapshotDimensionId;
    private boolean snapshotCoverageValid;
    private int snapshotCoverageMinX, snapshotCoverageMinZ, snapshotCoverageMaxX, snapshotCoverageMaxZ;
    private int requestedSnapshotMinX, requestedSnapshotMinZ, requestedSnapshotMaxX, requestedSnapshotMaxZ;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/RoadMapScreen.java' @'
        if (dimensionId != null && (currentDimensionId == null || !dimensionId.equals(currentDimensionId))) {
            currentDimensionId = dimensionId;
            MapSnapshot cached = MapSnapshotCache.peek(currentDimensionId);
            if (cached != null) {
                this.snapshot = cached;
            }
        }
        
        MinecraftServer server = mc.getSingleplayerServer();
'@ @'
        if (dimensionId != null && (currentDimensionId == null || !dimensionId.equals(currentDimensionId))) {
            currentDimensionId = dimensionId;
            snapshotCoverageValid = false;
            snapshotCoverageDimensionId = dimensionId;
            MapSnapshot cached = MapSnapshotCache.peek(currentDimensionId);
            if (cached != null) {
                this.snapshot = cached;
            }
        }
        if (dimensionId != null && snapshotCoverageValid
                && dimensionId.equals(snapshotCoverageDimensionId)
                && minX >= snapshotCoverageMinX && minZ >= snapshotCoverageMinZ
                && maxX <= snapshotCoverageMaxX && maxZ <= snapshotCoverageMaxZ) {
            return;
        }
        requestedSnapshotMinX = minX;
        requestedSnapshotMinZ = minZ;
        requestedSnapshotMaxX = maxX;
        requestedSnapshotMaxZ = maxZ;
        requestedSnapshotDimensionId = dimensionId;

        MinecraftServer server = mc.getSingleplayerServer();
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/RoadMapScreen.java' @'
            Identifier did = (mc.level != null) ? mc.level.dimension().identifier() : Identifier.fromNamespaceAndPath("minecraft", "overworld");
            ClientNetBridge.requestSnapshot(requestSeq, did, minX, minZ, maxX, maxZ);
'@ @'
            Identifier did = (mc.level != null) ? mc.level.dimension().identifier() : Identifier.fromNamespaceAndPath("minecraft", "overworld");
            requestedSnapshotDimensionId = did;
            ClientNetBridge.requestSnapshot(requestSeq, did, minX, minZ, maxX, maxZ);
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/RoadMapScreen.java' @'
        this.snapshot = snapshot;
        MapSnapshotCache.put(dimensionId, snapshot);
        if (shouldRefitView) {
'@ @'
        this.snapshot = snapshot;
        MapSnapshotCache.put(dimensionId, snapshot);
        if (dimensionId.equals(requestedSnapshotDimensionId)) {
            snapshotCoverageDimensionId = dimensionId;
            snapshotCoverageMinX = requestedSnapshotMinX;
            snapshotCoverageMinZ = requestedSnapshotMinZ;
            snapshotCoverageMaxX = requestedSnapshotMaxX;
            snapshotCoverageMaxZ = requestedSnapshotMaxZ;
            snapshotCoverageValid = true;
        }
        if (shouldRefitView) {
'@

# 11) Frame-time safety cap for road line drawing at high zoom.
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/render/MapRenderers.java' @'
public final class MapRenderers {
    private MapRenderers() {}
'@ @'
public final class MapRenderers {
    private MapRenderers() {}
    private static final int MAX_ROAD_SEGMENTS_PER_FRAME = 4096;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/render/MapRenderers.java' @'
                                           int lodStepBlocks) {
        for (List<BlockPos> pl : polylines) {
'@ @'
                                           int lodStepBlocks) {
        int renderedSegments = 0;
        for (List<BlockPos> pl : polylines) {
            if (renderedSegments >= MAX_ROAD_SEGMENTS_PER_FRAME) return;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/render/MapRenderers.java' @'
            for (int i = 1; i < pl.size(); i++) {
'@ @'
            for (int i = 1; i < pl.size(); i++) {
                if (renderedSegments >= MAX_ROAD_SEGMENTS_PER_FRAME) return;
'@
AddPatch 'common/src/main/java/net/shiroha233/roadweaver/client/map/render/MapRenderers.java' @'
                    RenderUtils.drawThickLine(g, x1, y1, x2, y2, color, thickness, left, top, right, bottom);
'@ @'
                    RenderUtils.drawThickLine(g, x1, y1, x2, y2, color, thickness, left, top, right, bottom);
                    if (++renderedSegments >= MAX_ROAD_SEGMENTS_PER_FRAME) return;
'@ 2

# New helper class is installed as part of this patch.
$connectorPath = 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/core/VillagePathConnector.java'
$connectorSource = @'
package net.shiroha233.roadweaver.features.path.pathlogic.core;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.levelgen.Heightmap;

import java.util.List;

/**
 * Joins a generated road endpoint to an already-generated village dirt path.
 * It deliberately searches and edits only the current chunk: it never force-loads
 * neighbouring chunks during world generation.
 */
public final class VillagePathConnector {
    private static final int SEARCH_RADIUS = 18;
    private static final int MAX_CONNECTOR_LENGTH = 18;
    private static final int MAX_SURFACE_SCAN_DEPTH = 5;

    private VillagePathConnector() {}

    public static void connectInChunk(WorldGenLevel world, ChunkPos chunk, List<BlockPos> centers) {
        if (world == null || chunk == null || centers == null || centers.size() < 2) return;
        tryConnectEndpoint(world, chunk, centers.get(0));
        tryConnectEndpoint(world, chunk, centers.get(centers.size() - 1));
    }

    private static void tryConnectEndpoint(WorldGenLevel world, ChunkPos chunk, BlockPos endpoint) {
        if (endpoint == null || !ChunkPos.containing(endpoint).equals(chunk)) return;
        BlockPos target = findNearestVillagePath(world, chunk, endpoint);
        if (target == null) return;

        int dx = target.getX() - endpoint.getX();
        int dz = target.getZ() - endpoint.getZ();
        int steps = Math.max(Math.abs(dx), Math.abs(dz));
        if (steps < 2 || steps > MAX_CONNECTOR_LENGTH) return;

        BlockPos[] connector = new BlockPos[steps - 1];
        int previousY = endpoint.getY();
        for (int i = 1; i < steps; i++) {
            double t = (double) i / steps;
            int x = (int) Math.round(endpoint.getX() + dx * t);
            int z = (int) Math.round(endpoint.getZ() + dz * t);
            if ((x >> 4) != chunk.x || (z >> 4) != chunk.z) return;

            int y = world.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z) - 1;
            if (Math.abs(y - previousY) > 2) return;
            BlockPos pos = new BlockPos(x, y, z);
            var state = world.getBlockState(pos);
            if (state.is(Blocks.WATER) || state.is(Blocks.LAVA)) return;
            if (!world.getBlockState(pos.above()).isAir()) return;
            connector[i - 1] = pos;
            previousY = y;
        }

        for (BlockPos pos : connector) {
            world.setBlock(pos, Blocks.DIRT_PATH.defaultBlockState(), 3);
        }
    }

    private static BlockPos findNearestVillagePath(WorldGenLevel world, ChunkPos chunk, BlockPos endpoint) {
        int minX = chunk.getMinBlockX();
        int minZ = chunk.getMinBlockZ();
        int maxX = chunk.getMaxBlockX();
        int maxZ = chunk.getMaxBlockZ();
        int radiusSq = SEARCH_RADIUS * SEARCH_RADIUS;
        BlockPos best = null;
        int bestDistanceSq = Integer.MAX_VALUE;

        int fromX = Math.max(minX, endpoint.getX() - SEARCH_RADIUS);
        int toX = Math.min(maxX, endpoint.getX() + SEARCH_RADIUS);
        int fromZ = Math.max(minZ, endpoint.getZ() - SEARCH_RADIUS);
        int toZ = Math.min(maxZ, endpoint.getZ() + SEARCH_RADIUS);
        for (int x = fromX; x <= toX; x++) {
            for (int z = fromZ; z <= toZ; z++) {
                int dx = x - endpoint.getX();
                int dz = z - endpoint.getZ();
                int distanceSq = dx * dx + dz * dz;
                if (distanceSq == 0 || distanceSq > radiusSq || distanceSq >= bestDistanceSq) continue;

                int surfaceY = world.getHeight(Heightmap.Types.WORLD_SURFACE_WG, x, z) - 1;
                for (int depth = 0; depth <= MAX_SURFACE_SCAN_DEPTH; depth++) {
                    BlockPos candidate = new BlockPos(x, surfaceY - depth, z);
                    if (world.getBlockState(candidate).is(Blocks.DIRT_PATH)) {
                        best = candidate;
                        bestDistanceSq = distanceSq;
                        break;
                    }
                }
            }
        }
        return best;
    }
}
'@

# Verify every patch anchor before changing any files.
$grouped = $patches | Group-Object File
$prepared = @{}
foreach ($group in $grouped) {
    $relative = $group.Name
    $path = Join-Path $root $relative
    if (!(Test-Path -LiteralPath $path)) { throw "Missing target file: $relative" }
    $original = [System.IO.File]::ReadAllText($path)
    $normalized = $original.Replace("`r`n", "`n")
    $updated = $normalized
    foreach ($patch in $group.Group) {
        $count = ([regex]::Matches($updated, [regex]::Escape($patch.Old))).Count
        if ($count -ne $patch.Expected) {
            throw "Anchor count mismatch in $relative (expected $($patch.Expected), found $count). No files have been changed."
        }
        $updated = $updated.Replace($patch.Old, $patch.New)
    }
    $prepared[$relative] = [pscustomobject]@{ Path=$path; Original=$original; Updated=$updated }
}
$newConnectorPath = Join-Path $root $connectorPath
if ((Test-Path -LiteralPath $newConnectorPath) -and ([System.IO.File]::ReadAllText($newConnectorPath) -ne $connectorSource)) {
    throw "A different VillagePathConnector.java already exists. No files have been changed."
}

if ($CheckOnly) {
    Write-Host "PASS: $($patches.Count) exact source edits and the village connector file are compatible with this checkout."
    Write-Host "No files were changed."
    exit 0
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $root ".roadweaver-backups\quality-pass-$timestamp"
foreach ($item in $prepared.GetEnumerator()) {
    $relative = $item.Key
    $entry = $item.Value
    $backup = Join-Path $backupRoot ($relative + '.bak')
    $backupDir = Split-Path -Parent $backup
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $entry.Path -Destination $backup
    $content = $entry.Updated
    if ($entry.Original.Contains("`r`n")) { $content = $content.Replace("`n", "`r`n") }
    [System.IO.File]::WriteAllText($entry.Path, $content, ([System.Text.UTF8Encoding]::new($false)))
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $newConnectorPath) | Out-Null
[System.IO.File]::WriteAllText($newConnectorPath, $connectorSource, ([System.Text.UTF8Encoding]::new($false)))
Write-Host "Applied RoadWeaver quality pass. Backups: $backupRoot"
Write-Host "Next: .\gradlew.bat clean :fabric:build"
