param([string]$GameRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$env:PSModulePath = [IO.Path]::Combine($PSHOME,'Modules') + ';' + $env:PSModulePath
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$compatibilityPath = Join-Path $PSScriptRoot 'compatibility.json'
if (Test-Path -LiteralPath $compatibilityPath) {
  $compatibility = [IO.File]::ReadAllText($compatibilityPath) | ConvertFrom-Json
  foreach ($property in $compatibility.PSObject.Properties) {
    $sourcePath = Join-Path $GameRoot ('resources\app\app\' + $property.Name)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine $property.Value) { throw ('游戏版本不匹配，未修改：' + $property.Name) }
  }
}
if (Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq (Join-Path $GameRoot 'DRAPLINE.exe') }) { throw '请先保存并正常退出游戏，再安装桥接。' }
$mainPath = Join-Path $GameRoot 'resources\app\electron\main.mjs'
$target = Join-Path $GameRoot 'resources\app\electron\drapline-ce'
$backupDir = Join-Path $PSScriptRoot 'backup'
$backupPath = Join-Path $backupDir 'main.mjs.original'
$manifestPath = Join-Path $backupDir 'manifest.json'
$marker = '// DRAPLINE CE bridge v1'
$text = [IO.File]::ReadAllText($mainPath)
if ($text.Contains($marker)) {
  if (-not (Test-Path -LiteralPath $manifestPath)) { throw '启动文件含有桥接标记，但备份清单缺失。请检查备份。' }
  $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ((Get-FileHash -LiteralPath $mainPath -Algorithm SHA256).Hash -ne $existing.installedHash) { throw '启动文件还包含其他修改；未覆盖。' }
  if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne $existing.originalHash) { throw '原始备份校验失败；未更新模块。' }
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bridge\main.mjs') -Destination (Join-Path $target 'main.mjs') -Force
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bridge\renderer.js') -Destination (Join-Path $target 'renderer.js') -Force
  $existing.gameRoot = $GameRoot
  [IO.File]::WriteAllText($manifestPath, ($existing | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  Write-Host '桥接模块已安装并更新。请重启游戏后打开 DRAPLINE.CT。'
  exit 0
}
if (Test-Path -LiteralPath $manifestPath) { throw '发现旧备份。请先检查或卸载旧版本，避免覆盖原始备份。' }
$anchor = '  await mainWindow.loadFile(join(APP_DIR_PATH, "index.html"));'
if (-not $text.Contains($anchor)) { throw '启动文件结构不匹配，未修改任何游戏文件。' }
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if (Test-Path -LiteralPath $backupPath) {
  if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $mainPath -Algorithm SHA256).Hash) { throw '已有原始备份属于其他启动文件；未覆盖。' }
} else { Copy-Item -LiteralPath $mainPath -Destination $backupPath }
$originalHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
$savePath = Join-Path $GameRoot 'save'
if ((Test-Path -LiteralPath $savePath) -and -not (Test-Path -LiteralPath (Join-Path $backupDir 'save-before-install'))) {
  Copy-Item -LiteralPath $savePath -Destination (Join-Path $backupDir 'save-before-install') -Recurse
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bridge\main.mjs') -Destination (Join-Path $target 'main.mjs')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bridge\renderer.js') -Destination (Join-Path $target 'renderer.js')
$insertion = @'
  // DRAPLINE CE bridge v1
  try {
    const { installDraplineCE } = await import("./drapline-ce/main.mjs");
    await installDraplineCE(mainWindow);
  } catch (error) { console.error("DRAPLINE CE bridge:", error); }

'@
$patched = $text.Replace($anchor, $insertion + $anchor)
[IO.File]::WriteAllText($mainPath, $patched, [Text.UTF8Encoding]::new($false))
$installedHash = (Get-FileHash -LiteralPath $mainPath -Algorithm SHA256).Hash
@{ version = 1; gameRoot = $GameRoot; originalHash = $originalHash; installedHash = $installedHash; installedAt = (Get-Date).ToString('o') } |
  ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host '桥接模块安装完成。原始启动文件和现有存档已备份到 CE-DRAPLINE\backup。'
Write-Host '请正常保存并关闭当前游戏，再重新启动。无需选择 CE 中的某个 DRAPLINE 子进程。'
