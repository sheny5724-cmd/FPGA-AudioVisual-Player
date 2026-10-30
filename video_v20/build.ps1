param([string]$TdExe = 'E:\FPGA\TD_6.2.1_SP1_178840_NL\bin\td_commands_prompt.exe')
$ErrorActionPreference = 'Stop'
$buildScript = (Join-Path $PSScriptRoot 'build.tcl').Replace('\','/')
$buildLog = Join-Path $PSScriptRoot 'build_console.log'
$buildStart = Get-Date
Push-Location $PSScriptRoot
try {
    & $TdExe $buildScript *> $buildLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $buildLog -Pattern '\bERROR\s*:' -Quiet)) { throw 'TD build failed; see build_console.log.' }
    $newBit = Get-Item -LiteralPath (Join-Path $PSScriptRoot 'competition_video_v20.bit')
    if ($newBit.LastWriteTime -lt $buildStart) { throw 'No new bitstream was generated.' }
    Write-Output "Generated $($newBit.FullName). Read competition_pr.timing before downloading."
} finally { Pop-Location }
