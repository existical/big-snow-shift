# Pass engine switches directly, for example:
#   .\tools\godot.ps1 --headless --version
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionLock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'godot-version.json') -Raw | ConvertFrom-Json
$editorName = "Godot_v$($versionLock.release)_win64_console.exe"
$editorPath = Join-Path $projectRoot ".tools\godot\$($versionLock.version)\$editorName"
if (-not (Test-Path -LiteralPath $editorPath)) {
    throw 'Godot is missing. Run: python tools/setup_godot.py'
}
& $editorPath @args
exit $LASTEXITCODE
