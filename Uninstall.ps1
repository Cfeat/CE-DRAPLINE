$ErrorActionPreference = 'Stop'
$backupDir = Join-Path $PSScriptRoot 'backup'
$manifestPath = Join-Path $backupDir 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$gameRoot = (Resolve-Path -LiteralPath $manifest.gameRoot).Path
$mainPath = Join-Path $gameRoot 'resources\app\electron\main.mjs'
$original = Join-Path $backupDir 'main.mjs.original'
if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $manifest.originalHash) { throw '原始备份校验失败，未修改游戏。' }
$hash = (Get-FileHash -LiteralPath $mainPath -Algorithm SHA256).Hash
if ($hash -eq $manifest.originalHash) { Write-Host '游戏启动文件已恢复。'; exit 0 }
if ($hash -ne $manifest.installedHash) { throw '安装后启动文件发生过其他修改；为保护其他修改，未自动覆盖。请对照 backup\main.mjs.original 手动移除 CE 桥接段。' }
Copy-Item -LiteralPath $original -Destination $mainPath -Force
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Move-Item -LiteralPath $manifestPath -Destination (Join-Path $backupDir "manifest.uninstalled-$stamp.json")
Write-Host '已恢复原始启动文件。重启游戏后桥接模块不再加载。'
Write-Host '备份和模块源码保留；不会恢复或覆盖当前存档。'
