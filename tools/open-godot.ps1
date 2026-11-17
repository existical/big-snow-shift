$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionLock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'godot-version.json') -Raw | ConvertFrom-Json
$editorPath = Join-Path $projectRoot ".tools\godot\$($versionLock.version)\Godot_v$($versionLock.release)_win64.exe"
if (-not (Test-Path -LiteralPath $editorPath)) {
    throw 'Godot is missing. Run: python tools/setup_godot.py'
}
if (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot')) {
    & $editorPath --editor --path $projectRoot
} else {
    & $editorPath --project-manager
}
