param([string]$BwExe = 'E:\FPGA\TD_6.2.1_SP1_178840_NL\bin\bw_commands_prompt.exe')
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $BwExe)) { throw 'BitWriter command-line tool was not found.' }
$expectedHashes = @{
    'competition_recovery_v19_flash.svf' = 'a647246b856acfb9710ffc59a1e8e8171b0a9d1813fe8e85b5964b8bd9def4a5'
    'competition_recovery_v19.bit' = '1d2f7c106b47173ef4f207660502291c135a1c864a79cce0eaf7a9057890e46e'
    'competition_recovery_v19.bin' = '14b13115d07963ac94ac0460ebe8ad7435b3bfdbe2078b86baaeb1e0a7d4ad0c'
    'backup\flash_before_v19.bin' = '76cdf2cea86903cbb0e452b7d878108ae83a9deccb7176dff485942369bda967'
}
foreach ($item in $expectedHashes.GetEnumerator()) {
    $assetPath = Join-Path $PSScriptRoot $item.Key
    if ((Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash -ne $item.Value) {
        throw "File differs from the released V19 image: $($item.Key)"
    }
}
$scriptPath = (Join-Path $PSScriptRoot 'program_flash.tcl').Replace('\', '/')
$logPath = Join-Path $PSScriptRoot ('flash_program_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
Push-Location $PSScriptRoot
try {
    Write-Output 'Writing the released V19 image to the connected HX4S20C configuration Flash. Keep power connected.'
    & $BwExe $scriptPath *> $logPath
    $toolExit = $LASTEXITCODE
    Get-Content -LiteralPath $logPath -Tail 30
    if ($toolExit -ne 0 -or (Select-String -LiteralPath $logPath -Pattern '\bERROR\s*:' -Quiet) -or
        !(Select-String -LiteralPath $logPath -Pattern '^FLASH_V19_BYTE_COMPARE_OK:' -Quiet)) {
        throw "Flash programming/readback did not complete successfully. See $logPath"
    }
    Write-Output 'Flash write and byte-for-byte readback completed. Power-cycle the board to confirm standalone boot.'
} finally { Pop-Location }
