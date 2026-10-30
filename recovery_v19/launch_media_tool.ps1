$ErrorActionPreference = 'Stop'
$candidates = @(
    (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\pythonw.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\pythonw.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\pythonw.exe')
)
$pythonExe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $pythonExe) { throw '需要 Python 3.11/3.12（含 Pillow、Tkinter）。请安装后用 python media_gui.py 启动。' }
$guiScript = Join-Path $PSScriptRoot 'media_gui.py'
Start-Process -FilePath $pythonExe -ArgumentList ('"' + $guiScript + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
