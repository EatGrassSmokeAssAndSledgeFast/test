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
            if ((x >> 4) != chunk.x() || (z >> 4) != chunk.z()) return;

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