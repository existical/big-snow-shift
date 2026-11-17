$projectRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'godot-version.json') -Raw | ConvertFrom-Json).version
$engine = Join-Path $projectRoot ".tools\godot\$version\Godot_v$version-stable_win64.exe"
Start-Process -FilePath $engine -ArgumentList @('--path', ('"' + $projectRoot + '"')) -WorkingDirectory $projectRoot
