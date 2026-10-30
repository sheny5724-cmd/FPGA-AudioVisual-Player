param([string]$BwExe = 'E:\FPGA\TD_6.2.1_SP1_178840_NL\bin\bw_commands_prompt.exe')
$ErrorActionPreference = 'Stop'
$bitFile = Join-Path $PSScriptRoot 'competition_video_v20.bit'
if (-not (Test-Path -LiteralPath $bitFile)) { throw 'Missing competition_video_v20.bit.' }
$tclFile = (Join-Path $PSScriptRoot 'download_sram.tcl').Replace('\','/')
$logFile = Join-Path $PSScriptRoot 'download_sram.log'
Push-Location $PSScriptRoot
try {
    & $BwExe $tclFile *> $logFile
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $logFile -Pattern '\bERROR\s*:' -Quiet)) { throw 'Download failed; see download_sram.log.' }
    if (-not (Select-String -LiteralPath $logFile -SimpleMatch 'V20_SRAM_DOWNLOAD_FINISHED_FLASH_NOT_WRITTEN' -Quiet)) { throw 'Download did not finish.' }
    Write-Output 'V20 SRAM download finished. Flash remains V19. Power-cycle to restore V19.'
} finally { Pop-Location }
