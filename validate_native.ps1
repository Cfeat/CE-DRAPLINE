param(
  [Parameter(Mandatory=$true)][string]$Fixture,
  [Parameter(Mandatory=$true)][string]$CeDirectory
)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = [IO.Path]::Combine($PSHOME,'Modules') + ';' + $env:PSModulePath
$Fixture = (Resolve-Path -LiteralPath $Fixture).Path
$CeDirectory = (Resolve-Path -LiteralPath $CeDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $Fixture 'fixture-path.txt'))) { throw 'Run validate_single_file.py first and use its fixture directory.' }
$executable = Join-Path $CeDirectory 'cheatengine-x86_64-SSE4-AVX2.exe'
if (-not (Test-Path -LiteralPath $executable)) { $executable = Join-Path $CeDirectory 'cheatengine-x86_64.exe' }
if (-not (Test-Path -LiteralPath $executable)) { throw '64-bit Cheat Engine executable not found.' }
$autorun = Join-Path $CeDirectory 'autorun\drapline_single_native_verify.lua'
if (Test-Path -LiteralPath $autorun) { throw 'Test autorun already exists; it was not overwritten.' }
$result = Join-Path $Fixture 'native-result.txt'
$table = Join-Path $Fixture 'native-table.CT'
New-Item -ItemType Directory -Path (Join-Path $Fixture 'Unicode 临时 scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'DRAPLINE_SingleFile.CT') -Destination $table -Force
if (Test-Path -LiteralPath $result) { Remove-Item -LiteralPath $result }
$oldFixture = $env:DRAPLINE_CE_NATIVE_FIXTURE
$oldTable = $env:DRAPLINE_CE_NATIVE_TABLE
$child = $null
try {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'validate_native.lua') -Destination $autorun
  $driverHash = (Get-FileHash -LiteralPath $autorun).Hash
  $env:DRAPLINE_CE_NATIVE_FIXTURE = $Fixture
  $env:DRAPLINE_CE_NATIVE_TABLE = $table
  $child = Start-Process -FilePath $executable -WindowStyle Hidden -PassThru
  $started = $child.StartTime.ToUniversalTime().Ticks
  $deadline = (Get-Date).AddSeconds(150)
  $previous = ''
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $result) {
      try { $message = [IO.File]::ReadAllText($result) } catch { $message = '' }
      if ($message -ne $previous) { Write-Host $message; $previous = $message }
      if ($message.StartsWith('PASS ')) { return }
      if ($message.StartsWith('FAIL ')) { throw $message }
    }
    if ($child.HasExited) { throw 'Verification CE exited before completing the test.' }
    Start-Sleep -Milliseconds 500
  }
  throw ('Native CE verification timed out. Last result: ' + $previous)
} finally {
  $env:DRAPLINE_CE_NATIVE_FIXTURE = $oldFixture
  $env:DRAPLINE_CE_NATIVE_TABLE = $oldTable
  if ($child) {
    $current = Get-Process -Id $child.Id -ErrorAction SilentlyContinue
    if ($current -and $current.StartTime.ToUniversalTime().Ticks -eq $started -and $current.Path -ieq $executable) {
      Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $current.Id -and $_.Name -eq 'powershell.exe' } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
      Stop-Process -Id $current.Id -ErrorAction SilentlyContinue
    }
  }
  if ((Test-Path -LiteralPath $autorun) -and (Get-FileHash -LiteralPath $autorun).Hash -eq $driverHash) { Remove-Item -LiteralPath $autorun }
}
