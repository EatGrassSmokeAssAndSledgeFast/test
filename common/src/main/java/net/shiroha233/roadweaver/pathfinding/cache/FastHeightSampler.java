package net.shiroha233.roadweaver.pathfinding.cache;

import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.RandomState;

import java.util.concurrent.ConcurrentHashMap;

/**
 * Cached coarse-grained terrain sampler. 26.3 no longer exposes the old
 * DensityFunction/NoiseRouter interpolation path, so use the generator's
 * supported base-height query and retain a small spatial cache for bulk work.
 */
public final class FastHeightSampler {
    private static final int SAMPLE_GRID = 4;

    private final ChunkGenerator generator;
    private final ServerLevel level;
    private final RandomState randomState;
    private final ConcurrentHashMap<Long, Integer> surfaceHeightCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Long, Integer> oceanFloorCache = new ConcurrentHashMap<>();

    private FastHeightSampler(ServerLevel level, ChunkGenerator generator, RandomState randomState) {
        this.level = level;
        this.generator = generator;
        this.randomState = randomState;
    }

    public static FastHeightSampler create(ServerLevel level) {
        var chunkSource = level.getChunkSource();
        return new FastHeightSampler(level, chunkSource.getGenerator(),
                chunkSource.getGeneratorState().randomState());
    }

    public int sampleHeight(int x, int z) {
        int sampleX = alignToSampleGrid(x);
        int sampleZ = alignToSampleGrid(z);
        return surfaceHeightCache.computeIfAbsent(packXZ(sampleX, sampleZ), ignored ->
                generator.getBaseHeight(sampleX, sampleZ, Heightmap.Types.WORLD_SURFACE_WG, level, randomState));
    }

    public int sampleOceanFloor(int x, int z) {
        int sampleX = alignToSampleGrid(x);
        int sampleZ = alignToSampleGrid(z);
        return oceanFloorCache.computeIfAbsent(packXZ(sampleX, sampleZ), ignored ->
                generator.getBaseHeight(sampleX, sampleZ, Heightmap.Types.OCEAN_FLOOR_WG, level, randomState));
    }

    public void prewarmRegion(int minX, int minZ, int maxX, int maxZ, int step) {
        int safeStep = Math.max(1, step);
        for (int x = minX; x <= maxX; x += safeStep) {
            for (int z = minZ; z <= maxZ; z += safeStep) {
                sampleHeight(x, z);
                sampleOceanFloor(x, z);
            }
        }
    }

    public void clearCache() {
        surfaceHeightCache.clear();
        oceanFloorCache.clear();
    }

    public int getCacheSize() {
        return surfaceHeightCache.size();
    }

    private static int alignToSampleGrid(int value) {
        return Math.floorDiv(value, SAMPLE_GRID) * SAMPLE_GRID;
    }

    private static long packXZ(int x, int z) {
        return ((long) x << 32) | (z & 0xFFFFFFFFL);
    }
}
