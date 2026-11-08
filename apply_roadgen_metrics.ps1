param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
$changes = [ordered]@{}

function Replace-ExactlyOnce {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label
    )

    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "Patch anchor not found: $Label"
    }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) {
        throw "Patch anchor is ambiguous (appears more than once): $Label"
    }
    return $Text.Remove($first, $Old.Length).Insert($first, $New)
}

function Read-And-Patch {
    param([string]$RelativePath, [scriptblock]$Patch)
    $fullPath = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required source file not found: $RelativePath (extract this patch into the RoadWeaver project root)"
    }
    $original = [System.IO.File]::ReadAllText($fullPath)
    $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = $original.Replace("`r`n", "`n")
    $updated = & $Patch $content
    $updated = $updated.Replace("`n", $newline)
    if ($updated -ceq $content) {
        throw "No changes produced for $RelativePath; it may already be patched or differ from the expected 26.3 source."
    }
    $changes[$fullPath] = $updated
}

# 1) Queue service: a null RoadData result must not be marked COMPLETED.
Read-And-Patch 'common/src/main/java/net/shiroha233/roadweaver/generation/RoadGenerationService.java' {
    param($s)
    $s = Replace-ExactlyOnce $s 'import net.shiroha233.roadweaver.core.model.ConnectionStatus;' "import net.shiroha233.roadweaver.core.model.ConnectionStatus;`nimport net.shiroha233.roadweaver.core.model.RoadData;" 'RoadGenerationService RoadData import'
    $s = Replace-ExactlyOnce $s 'import java.util.ArrayList;' "import org.slf4j.Logger;`nimport org.slf4j.LoggerFactory;`n`nimport java.util.ArrayList;" 'RoadGenerationService logger imports'
    $s = Replace-ExactlyOnce $s "public final class RoadGenerationService {`n    private RoadGenerationService() {}" "public final class RoadGenerationService {`n    private static final Logger LOGGER = LoggerFactory.getLogger(`"roadweaver`");`n`n    private RoadGenerationService() {}" 'RoadGenerationService logger declaration'
    $old = @'
            new Road(level, conn, cfg, genCfg).generateRoad(modCfg.pathfindingCost().aStarMaxSteps());
            return true;
'@
    $new = @'
            long startedAtNanos = System.nanoTime();
            RoadData roadData = new Road(level, conn, cfg, genCfg)
                    .generateRoad(modCfg.pathfindingCost().aStarMaxSteps());
            long elapsedMs = (System.nanoTime() - startedAtNanos) / 1_000_000L;
            if (roadData == null) {
                LOGGER.warn("Path generation produced no road data for {} -> {} after {} ms",
                        conn.from(), conn.to(), elapsedMs);
                return false;
            }
            int segmentCount = roadData.roadSegmentList() == null ? 0 : roadData.roadSegmentList().size();
            int spanCount = roadData.spans() == null ? 0 : roadData.spans().size();
            LOGGER.info("Path generated {} -> {} in {} ms ({} segments, {} spans)",
                    conn.from(), conn.to(), elapsedMs, segmentCount, spanCount);
            return true;
'@
    $s = Replace-ExactlyOnce $s $old $new 'RoadGenerationService ordinary-road result handling'
    $oldCatch = @'
        } catch (Throwable t) {
            return false;
        }
    }

    public static boolean generateHighwayTask
'@
    $newCatch = @'
        } catch (Throwable t) {
            LOGGER.error("Unexpected error while generating path {} -> {}", conn.from(), conn.to(), t);
            return false;
        }
    }

    public static boolean generateHighwayTask
'@
    $s = Replace-ExactlyOnce $s $oldCatch $newCatch 'RoadGenerationService ordinary-road exception logging'
    $oldHighway = @'
            HighwayGenerationConfig genCfg = HighwayGenerationConfig.from(cfg);
            return new HighwayRoad(level, conn, genCfg).generateRoad(cfg.highway().aStarMaxSteps());
'@
    $newHighway = @'
            HighwayGenerationConfig genCfg = HighwayGenerationConfig.from(cfg);
            long startedAtNanos = System.nanoTime();
            boolean generated = new HighwayRoad(level, conn, genCfg).generateRoad(cfg.highway().aStarMaxSteps());
            long elapsedMs = (System.nanoTime() - startedAtNanos) / 1_000_000L;
            LOGGER.info("Highway generation {} -> {} finished in {} ms (success={})",
                    conn.from(), conn.to(), elapsedMs, generated);
            return generated;
'@
    $s = Replace-ExactlyOnce $s $oldHighway $newHighway 'RoadGenerationService highway timing'
    return $s
}

# 2) Ordinary-road pathfinding time (isolated from persistence and decoration precomputation).
Read-And-Patch 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/core/Road.java' {
    param($s)
    $s = Replace-ExactlyOnce $s 'import java.util.ArrayList;' "import org.slf4j.Logger;`nimport org.slf4j.LoggerFactory;`n`nimport java.util.ArrayList;" 'Road logger imports'
    $s = Replace-ExactlyOnce $s 'public final class Road {' "public final class Road {`n    private static final Logger LOGGER = LoggerFactory.getLogger(`"roadweaver`");" 'Road logger declaration'
    $old = @'
            PathCalculationResult pathResult = RoadPathCalculator.calculateAStarRoadPathDetailed(
                    rawStart,
                    rawEnd,
                    width,
                    level,
                    maxSteps,
                    cache,
                    generationConfig);
'@
    $new = @'
            long pathStartedAtNanos = System.nanoTime();
            PathCalculationResult pathResult = RoadPathCalculator.calculateAStarRoadPathDetailed(
                    rawStart,
                    rawEnd,
                    width,
                    level,
                    maxSteps,
                    cache,
                    generationConfig);
            long pathElapsedMs = (System.nanoTime() - pathStartedAtNanos) / 1_000_000L;
            int rawSegmentCount = pathResult.segments() == null ? 0 : pathResult.segments().size();
            LOGGER.info("Path search {} -> {} took {} ms ({} raw segments)",
                    rawStart, rawEnd, pathElapsedMs, rawSegmentCount);
'@
    $s = Replace-ExactlyOnce $s $old $new 'Road path calculation timer'
    return $s
}

# 3) Highway pathfinding time.
Read-And-Patch 'common/src/main/java/net/shiroha233/roadweaver/features/highway/generation/HighwayRoad.java' {
    param($s)
    $s = Replace-ExactlyOnce $s 'import java.util.ArrayList;' "import org.slf4j.Logger;`nimport org.slf4j.LoggerFactory;`n`nimport java.util.ArrayList;" 'HighwayRoad logger imports'
    $s = Replace-ExactlyOnce $s 'public final class HighwayRoad {' "public final class HighwayRoad {`n    private static final Logger LOGGER = LoggerFactory.getLogger(`"roadweaver`");" 'HighwayRoad logger declaration'
    $old = @'
            PathCalculationResult pathResult = HighwayPathCalculator.calculateHighwayPathDetailed(
                    rawStart,
                    rawEnd,
                    width,
                    level,
                    Math.max(1, maxSteps),
                    cache,
                    generationConfig);
'@
    $new = @'
            long pathStartedAtNanos = System.nanoTime();
            PathCalculationResult pathResult = HighwayPathCalculator.calculateHighwayPathDetailed(
                    rawStart,
                    rawEnd,
                    width,
                    level,
                    Math.max(1, maxSteps),
                    cache,
                    generationConfig);
            long pathElapsedMs = (System.nanoTime() - pathStartedAtNanos) / 1_000_000L;
            int rawSegmentCount = pathResult.segments() == null ? 0 : pathResult.segments().size();
            LOGGER.info("Highway path search {} -> {} took {} ms ({} raw segments)",
                    rawStart, rawEnd, pathElapsedMs, rawSegmentCount);
'@
    $s = Replace-ExactlyOnce $s $old $new 'HighwayRoad path calculation timer'
    return $s
}

# 4) Time actual chunk placement separately; expensive chunks are INFO, fast chunks are DEBUG.
Read-And-Patch 'common/src/main/java/net/shiroha233/roadweaver/features/path/PathFeature.java' {
    param($s)
    $s = Replace-ExactlyOnce $s 'import java.util.*;' "import org.slf4j.Logger;`nimport org.slf4j.LoggerFactory;`n`nimport java.util.*;" 'PathFeature logger imports'
    $s = Replace-ExactlyOnce $s 'public class PathFeature implements Feature {' "public class PathFeature implements Feature {`n    private static final Logger LOGGER = LoggerFactory.getLogger(`"roadweaver`");" 'PathFeature logger declaration'
    $s = Replace-ExactlyOnce $s '        List<RoadData> roadDataList = RoadShardStorage.queryRect(server, minX, minZ, maxX, maxZ);' "        long placementStartedAtNanos = System.nanoTime();`n        List<RoadData> roadDataList = RoadShardStorage.queryRect(server, minX, minZ, maxX, maxZ);" 'PathFeature placement timer start'
    $oldDecoration = @'
        DecorationExecutor.tryPlaceDecorations(decorations);
        return true;
'@
    $newDecoration = @'
        DecorationExecutor.tryPlaceDecorations(decorations);
        long placementElapsedMs = (System.nanoTime() - placementStartedAtNanos) / 1_000_000L;
        if (placementElapsedMs >= 25L) {
            LOGGER.info("Road chunk placement {} took {} ms ({} road data records)",
                    currentChunk, placementElapsedMs, roadDataList.size());
        } else {
            LOGGER.debug("Road chunk placement {} took {} ms ({} road data records)",
                    currentChunk, placementElapsedMs, roadDataList.size());
        }
        return true;
'@
    $s = Replace-ExactlyOnce $s $oldDecoration $newDecoration 'PathFeature placement timing log'
    return $s
}

# 5) Initial pass summary: elapsed time and final completed/failed counts.
Read-And-Patch 'common/src/main/java/net/shiroha233/roadweaver/generation/InitialGenManager.java' {
    param($s)
    $s = Replace-ExactlyOnce $s 'import java.util.concurrent.atomic.AtomicInteger;' "import org.slf4j.Logger;`nimport org.slf4j.LoggerFactory;`n`nimport java.util.concurrent.atomic.AtomicInteger;" 'InitialGenManager logger imports'
    $s = Replace-ExactlyOnce $s 'public final class InitialGenManager {' "public final class InitialGenManager {`n    private static final Logger LOGGER = LoggerFactory.getLogger(`"roadweaver`");" 'InitialGenManager logger declaration'
    $s = Replace-ExactlyOnce $s '    private static volatile boolean active;' "    private static volatile boolean active;`n    private static volatile long initialStartedAtNanos;" 'InitialGenManager start-time field'
    $s = Replace-ExactlyOnce $s '        active = true;' "        active = true;`n        initialStartedAtNanos = System.nanoTime();" 'InitialGenManager start-time capture'
    $newCompletion = @'
            active = false;
            long elapsedMs = (System.nanoTime() - initialStartedAtNanos) / 1_000_000L;
            LOGGER.info("Initial network pass finished in {} ms: planned={}, completed={}, failed={}",
                    elapsedMs, totalCount, doneCount, failedCount);
'@
    $s = Replace-ExactlyOnce $s '            active = false;' $newCompletion 'InitialGenManager completion summary'
    return $s
}

if ($CheckOnly) {
    Write-Host "PASS: all five source files and patch anchors match. No files were changed."
    exit 0
}

foreach ($path in $changes.Keys) {
    $backup = "${path}.pre-roadgen-metrics.bak"
    if (Test-Path -LiteralPath $backup) {
        throw "Backup already exists; refusing to overwrite it: $backup"
    }
}

foreach ($path in $changes.Keys) {
    Copy-Item -LiteralPath $path -Destination "${path}.pre-roadgen-metrics.bak"
    [System.IO.File]::WriteAllText($path, $changes[$path], $utf8NoBom)
    Write-Host "Patched: $($path.Substring($root.Length).TrimStart([char[]]@('\', '/')))"
}

Write-Host "RoadWeaver generation telemetry patch applied. Original files are saved as *.pre-roadgen-metrics.bak."
