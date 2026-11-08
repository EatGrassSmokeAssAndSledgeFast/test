param(
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$relativePath = 'common/src/main/java/net/shiroha233/roadweaver/features/path/pathlogic/core/VillagePathConnector.java'
$root = (Get-Location).Path
$target = Join-Path $root $relativePath

if (!(Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "Could not find $relativePath. Run this script from the RoadWeaver project root (the folder containing gradlew.bat)."
}

$original = [System.IO.File]::ReadAllText($target)
$old = 'if ((x >> 4) != chunk.x || (z >> 4) != chunk.z) return;'
$new = 'if ((x >> 4) != chunk.x() || (z >> 4) != chunk.z()) return;'
$oldCount = ([regex]::Matches($original, [regex]::Escape($old))).Count
$newCount = ([regex]::Matches($original, [regex]::Escape($new))).Count

if ($oldCount -eq 0 -and $newCount -eq 1) {
    Write-Host 'PASS: VillagePathConnector already uses the ChunkPos record accessors.'
    exit 0
}
if ($oldCount -ne 1 -or $newCount -ne 0) {
    throw "Unexpected source state (old line count=$oldCount, fixed line count=$newCount). No files were changed. Inspect $relativePath manually."
}

if ($CheckOnly) {
    Write-Host 'PASS: found the exact two-field-accessor compile error. No files were changed.'
    exit 0
}

$backupDir = Join-Path $root ('.roadweaver-backups\chunkpos-accessor-fix-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $target -Destination (Join-Path $backupDir 'VillagePathConnector.java.bak')
$updated = $original.Replace($old, $new)
$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($target, $updated, $encoding)
Write-Host 'Fixed ChunkPos accessors in VillagePathConnector.java.'
Write-Host "Backup: $backupDir\VillagePathConnector.java.bak"
Write-Host 'Next: .\gradlew.bat clean :fabric:build'
