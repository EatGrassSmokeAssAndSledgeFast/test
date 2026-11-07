package net.shiroha233.roadweaver.mixin.fabric;

import net.minecraft.core.BlockPos;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.feature.Feature;
import net.minecraft.world.level.levelgen.placement.FeaturePlacer;
import net.shiroha233.roadweaver.persistence.RoadPositionQuery;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

import java.util.Locale;

/**
 * Blocks tree-like features at their final, placement-modified origin. In 26.3,
 * FeaturePlacer is the common entry point for executing PlacedFeatures.
 */
@Mixin(FeaturePlacer.class)
public abstract class GenericVegetationFeatureMixin {
    @Redirect(
            method = "place(Lnet/minecraft/world/level/levelgen/placement/PlacedFeature;Lnet/minecraft/util/RandomSource;Lnet/minecraft/core/BlockPos;Z)Z",
            at = @At(
                    value = "INVOKE",
                    target = "Lnet/minecraft/world/level/levelgen/feature/Feature;place(Lnet/minecraft/world/level/WorldGenLevel;Lnet/minecraft/world/level/chunk/ChunkGenerator;Lnet/minecraft/util/RandomSource;Lnet/minecraft/core/BlockPos;)Z"
            )
    )
    private boolean roadweaver$blockTreesOnRoad(Feature feature, WorldGenLevel level,
                                                 ChunkGenerator generator, RandomSource random, BlockPos pos) {
        try {
            if (roadweaver$isTreeLikeFeature(feature) && RoadPositionQuery.isOnRoad(level, pos)) {
                return false;
            }
        } catch (Throwable ignored) {
            // Fail open: an unexpected road-query issue must not disable world generation.
        }
        return feature.place(level, generator, random, pos);
    }

    @Unique
    private static boolean roadweaver$isTreeLikeFeature(Feature feature) {
        if (feature == null) return false;
        String name = feature.getClass().getName().toLowerCase(Locale.ROOT);
        return name.contains("tree") || name.contains("fungus") || name.contains("mushroom")
                || name.contains("bamboo") || name.contains("cactus") || name.contains("chorus")
                || name.contains("nbt") || name.contains("structure") || name.contains("template")
                || name.contains("bush");
    }
}
