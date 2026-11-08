package net.shiroha233.roadweaver.generation;

import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.shiroha233.roadweaver.config.ConfigService;
import net.shiroha233.roadweaver.config.ModConfig;
import net.shiroha233.roadweaver.core.model.ConnectionStatus;
import net.shiroha233.roadweaver.core.model.StructureConnection;
import net.shiroha233.roadweaver.features.highway.planning.HighwayPlanningService;
import net.shiroha233.roadweaver.persistence.RoadPositionQuery;
import net.shiroha233.roadweaver.persistence.WorldDataProvider;
import net.shiroha233.roadweaver.persistence.sharded.RoadShardStorage;
import net.shiroha233.roadweaver.postprocess.RoadSnapService;
import net.shiroha233.roadweaver.structures.placement.SpawnCabinPlacer;

import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.atomic.AtomicInteger;

/**
 * Coordinates initial road planning and tracks its progress.
 * Actual road generation is dispatched by RoadGenerationService from server ticks;
 * the integrated server must never wait synchronously for generation workers here.
 */
public final class InitialGenManager {
    private static final Logger LOGGER = LoggerFactory.getLogger("roadweaver");
    private static volatile boolean active;
    private static volatile long initialStartedAtNanos;
    private static final AtomicInteger total = new AtomicInteger(0);
    private static final AtomicInteger done = new AtomicInteger(0);
    private static final AtomicInteger generating = new AtomicInteger(0);
    private static final AtomicInteger failed = new AtomicInteger(0);

    private InitialGenManager() {
    }

    public static boolean isActive() {
        return active;
    }

    public static int getTotal() {
        return total.get();
    }

    public static int getDone() {
        return done.get();
    }

    public static int getGenerating() {
        return generating.get();
    }

    public static int getFailed() {
        return failed.get();
    }

    public static void begin(ServerLevel level) {
        if (level == null) {
            return;
        }

        active = true;
        initialStartedAtNanos = System.nanoTime();
        total.set(0);
        done.set(0);
        generating.set(0);
        failed.set(0);

        net.shiroha233.roadweaver.pathfinding.cache.TerrainSamplingStats.reset();
        net.shiroha233.roadweaver.pathfinding.cache.AccurateSamplingStats.reset();

        ModConfig config = ConfigService.get();
        if (config.roadAppearance().spawnCabinEnabled()) {
            SpawnCabinPlacer.ensurePlaced(level);
        }

        if (config.highway().enabled()) {
            HighwayPlanningService.initialPlan(level);
        } else {
            net.shiroha233.roadweaver.planning.RoadPlanningService.initialPlan(level);
        }

        if (config.longDrive().enabled()) {
            net.shiroha233.roadweaver.features.longdrive.planning.LongDrivePlanningService.initialPlan(level);
        }

        // Refresh once after planning so the UI sees the initial PLANNED edges.
        // Generation itself starts on the next END_SERVER_TICK via RoadGenerationService.tick().
        update(level);
    }

    /**
     * Kept for source compatibility with older call sites. This method intentionally
     * does not wait: waiting here deadlocks integrated-server startup because terrain
     * sampling workers can be waiting for chunk futures serviced by the server thread.
     */
    @Deprecated
    public static void blockUntilDone(ServerLevel level) {
        update(level);
    }

    public static void update(ServerLevel level) {
        if (level == null) {
            return;
        }

        WorldDataProvider provider = WorldDataProvider.getInstance();
        List<StructureConnection> connections = provider.getStructureConnections(level);
        List<StructureConnection> highways = provider.getHighwayConnections(level);

        int totalCount = 0;
        int plannedCount = 0;
        int generatingCount = 0;
        int doneCount = 0;
        int failedCount = 0;

        if (connections != null) {
            totalCount += connections.size();
            for (StructureConnection connection : connections) {
                switch (connection.status()) {
                    case PLANNED -> plannedCount++;
                    case GENERATING -> generatingCount++;
                    case COMPLETED -> doneCount++;
                    case FAILED -> failedCount++;
                    default -> {
                    }
                }
            }
        }

        if (highways != null) {
            totalCount += highways.size();
            for (StructureConnection connection : highways) {
                switch (connection.status()) {
                    case PLANNED -> plannedCount++;
                    case GENERATING -> generatingCount++;
                    case COMPLETED -> doneCount++;
                    case FAILED -> failedCount++;
                    default -> {
                    }
                }
            }
        }

        total.set(totalCount);
        generating.set(generatingCount);
        done.set(doneCount);
        failed.set(failedCount);

        // Finish the initial pass only after the normal tick-driven queue has drained.
        if (active && plannedCount == 0 && generatingCount == 0) {
            List<StructureConnection> combined = new ArrayList<>(totalCount);
            if (connections != null) {
                combined.addAll(connections);
            }
            if (highways != null) {
                combined.addAll(highways);
            }
            snapInitialRoads(level, combined);
            RoadShardStorage.flushAll(level);
            RoadPositionQuery.clearCache(level);
            active = false;
            long elapsedMs = (System.nanoTime() - initialStartedAtNanos) / 1_000_000L;
            LOGGER.info("Initial network pass finished in {} ms: planned={}, completed={}, failed={}",
                    elapsedMs, totalCount, doneCount, failedCount);
        }
    }

    private static void snapInitialRoads(ServerLevel level, List<StructureConnection> connections) {
        if (connections == null || connections.isEmpty()) {
            return;
        }

        int minX = Integer.MAX_VALUE;
        int minZ = Integer.MAX_VALUE;
        int maxX = Integer.MIN_VALUE;
        int maxZ = Integer.MIN_VALUE;
        for (StructureConnection connection : connections) {
            minX = Math.min(minX, Math.min(connection.from().getX(), connection.to().getX()));
            minZ = Math.min(minZ, Math.min(connection.from().getZ(), connection.to().getZ()));
            maxX = Math.max(maxX, Math.max(connection.from().getX(), connection.to().getX()));
            maxZ = Math.max(maxZ, Math.max(connection.from().getZ(), connection.to().getZ()));
        }
        RoadSnapService.snapAllRoads(level, minX, minZ, maxX, maxZ);
    }
}
