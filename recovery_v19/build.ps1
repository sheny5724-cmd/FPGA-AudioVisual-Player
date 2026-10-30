param([string]$TdExe = 'E:\FPGA\TD_6.2.1_SP1_178840_NL\bin\td_commands_prompt.exe')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $TdExe)) { throw '找不到 TD 编译程序，请用 -TdExe 指定其路径。' }
$buildScript = (Join-Path $PSScriptRoot 'build.tcl').Replace('\', '/')
$buildLog = Join-Path $PSScriptRoot 'build_console.log'
$buildStart = Get-Date
Push-Location $PSScriptRoot
try {
    & $TdExe $buildScript *> $buildLog
    if ($LASTEXITCODE -ne 0) { throw "TD 退出码 $LASTEXITCODE，请查看 build_console.log。" }
    if (Select-String -LiteralPath $buildLog -Pattern '\bERROR\s*:' -Quiet) { throw '编译有错误，请查看日志。' }
    $newBit = Get-Item -LiteralPath (Join-Path $PSScriptRoot 'competition_recovery_v19.bit')
    if ($newBit.LastWriteTime -lt $buildStart) { throw '没有生成新的位流文件。' }
    Write-Output "已生成 $($newBit.FullName)。下载前请查看 competition_pr.timing。"
} finally { Pop-Location }
