param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference = 'Stop'
# Prefer the native Windows PowerShell modules even when launched by PowerShell 7.
$env:PSModulePath = [IO.Path]::Combine($PSHOME,'Modules') + ';' + $env:PSModulePath
$utf8 = New-Object System.Text.UTF8Encoding($false)
$task = [IO.File]::ReadAllText($Request, $utf8) | ConvertFrom-Json
$payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$transportTemp = if ($task.tempRoot) { [string]$task.tempRoot } elseif ($env:TEMP) { $env:TEMP } elseif ($env:TMP) { $env:TMP } else { [IO.Path]::GetTempPath() }
function Publish($values) {
  $lines = foreach ($key in $values.Keys) { $key + "`t" + ([string]$values[$key] -replace '[\r\n\t]', ' ') }
  $temporary = [string]$task.result + '.tmp'
  [IO.File]::WriteAllText($temporary, (($lines -join "`n") + "`n"), $utf8)
  Move-Item -LiteralPath $temporary -Destination ([string]$task.result) -Force
}
function RuntimeFor([string]$root) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.TrimEnd('\','/').ToLowerInvariant())) }
  finally { $sha.Dispose() }
  $tag = ([BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant().Substring(0,12)
  return Join-Path $transportTemp ('DRAPLINE-CE-' + $tag)
}
function ReadStatus([string]$directory) {
  try {
    $path = Join-Path $directory 'status.tsv'
    $info = Get-Item -LiteralPath $path
    if ($info.Length -gt 262144 -or ((Get-Date).ToUniversalTime() - $info.LastWriteTimeUtc).TotalSeconds -gt 5) { return }
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($path,$utf8)) {
      $parts = $line.Split([char]9,2)
      if ($parts.Length -eq 2) { $state[$parts[0]] = $parts[1] }
    }
    if ($state.protocol -ne '1' -or [int]$state.bridge_version -lt 2) { return }
    $millis = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ([math]::Abs($millis - [double]$state.time) -gt 5000) { return }
    if (-not (Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue)) { return }
    return @{ status='connected'; runtime=$directory; exe= $(if ($state.game_root) { Join-Path $state.game_root 'DRAPLINE.exe' } else { [string]$task.exe }); message='已发现运行中的游戏桥接。' }
  } catch { return }
}
function ResolveGame {
  $exe = (Resolve-Path -LiteralPath ([string]$task.exe)).Path
  if ([IO.Path]::GetFileName($exe) -ine 'DRAPLINE.exe' -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw '请选择本游戏的 DRAPLINE.exe。' }
  $root = Split-Path -Parent $exe
  foreach ($property in $payload.compatibility.PSObject.Properties) {
    $file = Join-Path $root ('resources\app\app\' + $property.Name)
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $property.Value) {
      throw ('游戏版本不匹配，未修改游戏文件：' + $property.Name)
    }
  }
  return @{ exe=$exe; root=$root; runtime=(RuntimeFor $root) }
}
function RequireClosed($game) {
  $running = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $game.exe }
  if ($running) { throw '请先在游戏里保存进度并正常退出，再点击“一键连接 / 首次安装”。不会自动关闭你的游戏。' }
}
function InstallBridge($game) {
  RequireClosed $game
  $main = Join-Path $game.root 'resources\app\electron\main.mjs'
  $module = Join-Path $game.root 'resources\app\electron\drapline-ce'
  $backup = Join-Path $game.root 'CE-DRAPLINE\backup'
  $original = Join-Path $backup 'main.mjs.original'
  $manifestPath = Join-Path $backup 'manifest.json'
  $text = [IO.File]::ReadAllText($main,$utf8)
  $marker = '// DRAPLINE CE bridge v1'
  $anchor = '  await mainWindow.loadFile(join(APP_DIR_PATH, "index.html"));'
  $currentHash = (Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
  if ($text.Contains($marker)) {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw '游戏已修改，但原始备份清单缺失。未覆盖启动文件。' }
    $manifest = [IO.File]::ReadAllText($manifestPath,$utf8) | ConvertFrom-Json
    if ($currentHash -ine $manifest.installedHash) { throw '启动文件安装后被其他工具修改。未覆盖这些修改。' }
    if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ine $manifest.originalHash) { throw '原始启动备份校验失败。' }
    $patched = $text
    $originalHash = $manifest.originalHash
  } else {
    if (-not $text.Contains($anchor)) { throw '游戏启动文件结构不匹配，未修改游戏。' }
    if (Test-Path -LiteralPath $manifestPath) {
      $manifest = [IO.File]::ReadAllText($manifestPath,$utf8) | ConvertFrom-Json
      if ($currentHash -ine $manifest.originalHash) { throw '发现不匹配的旧备份，未覆盖。' }
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if (Test-Path -LiteralPath $original) {
      if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ine $currentHash) { throw '已有原始备份属于其他启动文件，未覆盖。' }
    } else { Copy-Item -LiteralPath $main -Destination $original }
    $originalHash = $currentHash
    $save = Join-Path $game.root 'save'
    $saveBackup = Join-Path $backup 'save-before-install'
    if ((Test-Path -LiteralPath $save) -and -not (Test-Path -LiteralPath $saveBackup)) { Copy-Item -LiteralPath $save -Destination $saveBackup -Recurse }
    $loader = @'
  // DRAPLINE CE bridge v1
  try {
    const { installDraplineCE } = await import("./drapline-ce/main.mjs");
    await installDraplineCE(mainWindow);
  } catch (error) { console.error("DRAPLINE CE bridge:", error); }

'@
    $patched = $text.Replace($anchor,$loader + $anchor)
  }
  New-Item -ItemType Directory -Path $module -Force | Out-Null
  foreach ($name in @('main.mjs','renderer.js')) {
    $destination = Join-Path $module $name
    [IO.File]::WriteAllBytes(($destination+'.single.tmp'),[Convert]::FromBase64String($payload.$name))
    Move-Item -LiteralPath ($destination+'.single.tmp') -Destination $destination -Force
  }
  $patchedBytes = $utf8.GetBytes($patched)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $installedHash = ([BitConverter]::ToString($sha.ComputeHash($patchedBytes)) -replace '-','') } finally { $sha.Dispose() }
  $manifest = @{ version=1; gameRoot=$game.root; originalHash=$originalHash; installedHash=$installedHash; installedAt=[DateTimeOffset]::Now.ToString('o') }
  [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json),$utf8)
  [IO.File]::WriteAllBytes(($main+'.single.tmp'),$patchedBytes)
  Move-Item -LiteralPath ($main+'.single.tmp') -Destination $main -Force
}
try {
  if ($task.mode -eq 'probe' -or $task.mode -eq 'wait') {
    $attempts = if ($task.mode -eq 'wait') { 30 } else { 1 }
    for ($attempt=0; $attempt -lt $attempts; $attempt++) {
      if ($task.exe -and (Test-Path -LiteralPath ([string]$task.exe))) {
        $directory = RuntimeFor (Split-Path -Parent ([string]$task.exe))
        $found = ReadStatus $directory
        if ($found) { Publish $found; exit }
      } else {
        $found = @(Get-ChildItem -LiteralPath $transportTemp -Directory -Filter 'DRAPLINE-CE-*' | ForEach-Object { ReadStatus $_.FullName })
        if ($found.Count -eq 1) { Publish $found[0]; exit }
        if ($found.Count -gt 1) { Publish @{status='select';message='存在多个游戏实例，请选择要连接的 DRAPLINE.exe。'}; exit }
      }
      if ($attempts -gt 1) { Start-Sleep -Milliseconds 1000 }
    }
    Publish @{status='select';message='尚未发现可连接的游戏。请选择 DRAPLINE.exe。'}
  } elseif ($task.mode -eq 'install') {
    $game = ResolveGame
    $found = ReadStatus $game.runtime
    if ($found) { Publish $found; exit }
    InstallBridge $game
    Publish @{ status='installed'; exe=$game.exe; runtime=$game.runtime; message='桥接已安装并备份，将启动游戏并连接。' }
  } elseif ($task.mode -eq 'uninstall') {
    $game = ResolveGame
    RequireClosed $game
    $main = Join-Path $game.root 'resources\app\electron\main.mjs'
    $backup = Join-Path $game.root 'CE-DRAPLINE\backup'
    $manifestPath = Join-Path $backup 'manifest.json'
    $original = Join-Path $backup 'main.mjs.original'
    $manifest = [IO.File]::ReadAllText($manifestPath,$utf8) | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ine $manifest.originalHash) { throw '原始备份校验失败，未修改游戏。' }
    $hash = (Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
    if ($hash -ine $manifest.originalHash -and $hash -ine $manifest.installedHash) { throw '启动文件有其他修改，未覆盖。' }
    Copy-Item -LiteralPath $original -Destination $main -Force
    Move-Item -LiteralPath $manifestPath -Destination (Join-Path $backup ('manifest.uninstalled-' + [DateTimeOffset]::Now.ToUnixTimeMilliseconds() + '.json'))
    Publish @{status='uninstalled';message='已恢复原始启动文件，存档和备份保留。'}
  } else { throw 'Unknown setup operation.' }
} catch { Publish @{ status='error'; message=$_.Exception.Message } }
