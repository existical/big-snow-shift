param([switch]$SkipTests, [switch]$WindowsOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot 'builds'
$logRoot = Join-Path $buildRoot 'logs'
$windowsRoot = Join-Path $buildRoot 'windows'
$androidRoot = Join-Path $buildRoot 'android'
New-Item -ItemType Directory -Force $logRoot, $windowsRoot, $androidRoot | Out-Null
# Keep generated screenshots, fixtures and packages out of Godot imports on a fresh checkout.
[System.IO.File]::WriteAllText((Join-Path $buildRoot '.gdignore'), '')
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'godot-version.json') -Raw | ConvertFrom-Json
$engine = Join-Path $projectRoot ".tools/godot/$($lock.version)/Godot_v$($lock.release)_win64_console.exe"
function Invoke-GodotCheck([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $logRoot "$Name.log"
    # Windows PowerShell 5 turns redirected native stderr into error records.
    # Capture the two native streams directly so warnings and failures retain their meaning.
    $errors = Join-Path $logRoot "$Name-errors.log"
    $quoted = $Arguments | ForEach-Object { '"' + $_ + '"' }
    $process = Start-Process -FilePath $engine -ArgumentList $quoted -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $errors -Wait -PassThru
    $diagnostics = (Get-Content -LiteralPath $log -Raw) + (Get-Content -LiteralPath $errors -Raw)
    if ($process.ExitCode -ne 0 -or $diagnostics -match '(?m)^(SCRIPT ERROR:|ERROR:|FAIL:)') {
        throw "$Name failed. See $log"
    }
    Write-Output "$Name passed"
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination (Join-Path $projectRoot 'assets/licenses/GAME_LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'ASSET_LICENSES.md') -Destination (Join-Path $projectRoot 'assets/licenses/ASSET_LICENSES.txt') -Force
& python -X utf8 (Join-Path $PSScriptRoot 'prepare_privacy.py')
if ($LASTEXITCODE -ne 0) { throw 'Privacy text preparation failed.' }
& python -X utf8 (Join-Path $PSScriptRoot 'check_localization.py')
if ($LASTEXITCODE -ne 0) { throw 'Localization catalogs failed validation.' }
Invoke-GodotCheck 'import' @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
if (-not $SkipTests) {
    & python -X utf8 (Join-Path $PSScriptRoot 'test_localization_tools.py')
    if ($LASTEXITCODE -ne 0) { throw 'Localization tooling checks failed.' }
    Invoke-GodotCheck 'rules' @('--headless', '--path', $projectRoot, '--script', 'tests/test_game.gd')
    Invoke-GodotCheck 'difficulty' @('--headless', '--path', $projectRoot, '--script', 'tests/test_difficulty.gd')
    Invoke-GodotCheck 'custom-game' @('--headless', '--path', $projectRoot, '--script', 'tests/test_custom_game.gd')
    Invoke-GodotCheck 'round-count' @('--headless', '--path', $projectRoot, '--script', 'tests/test_round_count.gd')
    Invoke-GodotCheck 'landing-warnings' @('--headless', '--path', $projectRoot, '--script', 'tests/test_landing_warnings.gd')
    Invoke-GodotCheck 'difficulty-playthroughs' @('--headless', '--path', $projectRoot, '--script', 'tests/test_difficulty_playthroughs.gd')
    Invoke-GodotCheck 'piles' @('--headless', '--path', $projectRoot, '--script', 'tests/test_piles.gd')
    Invoke-GodotCheck 'icicles' @('--headless', '--path', $projectRoot, '--script', 'tests/test_icicles.gd')
    Invoke-GodotCheck 'depth' @('--headless', '--path', $projectRoot, '--script', 'tests/test_depth.gd')
    Invoke-GodotCheck 'endings' @('--headless', '--path', $projectRoot, '--script', 'tests/test_endings.gd')
    Invoke-GodotCheck 'timeout' @('--headless', '--path', $projectRoot, '--script', 'tests/test_timeout.gd')
    Invoke-GodotCheck 'doors' @('--headless', '--path', $projectRoot, '--script', 'tests/test_doors.gd')
    Invoke-GodotCheck 'santa-depth' @('--headless', '--path', $projectRoot, '--script', 'tests/test_santa_depth.gd')
    Invoke-GodotCheck 'hits' @('--headless', '--path', $projectRoot, '--script', 'tests/test_hits.gd')
    Invoke-GodotCheck 'tuning' @('--headless', '--path', $projectRoot, '--script', 'tests/test_tuning.gd')
	Invoke-GodotCheck 'controls' @('--headless', '--path', $projectRoot, '--script', 'tests/test_controls.gd')
	Invoke-GodotCheck 'audio' @('--headless', '--path', $projectRoot, '--script', 'tests/test_audio.gd')
    Invoke-GodotCheck 'windows-display' @('--headless', '--path', $projectRoot, '--script', 'tests/test_windows_display.gd')
    Invoke-GodotCheck 'ui' @('--headless', '--path', $projectRoot, '--script', 'tests/test_ui.gd')
    Invoke-GodotCheck 'review-recovery' @('--headless', '--path', $projectRoot, '--script', 'tests/test_review_recovery.gd')
    Invoke-GodotCheck 'rule-lock' @('--headless', '--path', $projectRoot, '--script', 'tests/test_rule_lock.gd')
    Invoke-GodotCheck 'localization' @('--headless', '--path', $projectRoot, '--script', 'tests/test_localization.gd')
    Invoke-GodotCheck 'performance' @('--headless', '--path', $projectRoot, '--script', 'tests/test_performance.gd')
    foreach ($nativeCase in @(@('touch-ui', 'res://tests/test_touch_ui.gd'), @('snow-cache', 'res://tests/test_snow_cache.gd'), @('landing-warning-render', 'res://tests/test_landing_warning_render.gd'), @('door-snow-depth', 'res://tests/test_door_snow_depth.gd'), @('windows-display-native', 'res://tests/test_windows_display.gd'))) {
        $nativeLog = Join-Path $logRoot ($nativeCase[0] + '.log')
        $nativeErrors = Join-Path $logRoot ($nativeCase[0] + '-errors.log')
        # These UI/rendering checks do not need a host audio endpoint.
        $nativeArgs = @('--path', ('"' + $projectRoot + '"'), '--script', $nativeCase[1], '--resolution', '1280x720', '--audio-driver', 'Dummy')
        if ($nativeCase[0] -eq 'windows-display-native') { $nativeArgs += @('--', '--native') }
        $native = Start-Process -FilePath $engine -ArgumentList $nativeArgs -WindowStyle Hidden -RedirectStandardOutput $nativeLog -RedirectStandardError $nativeErrors -PassThru
        $nativeHandle = $native.Handle
        if (-not $native.WaitForExit(30000)) {
            Stop-Process -Id $native.Id
            throw ('Native checks timed out: ' + $nativeCase[0])
        }
        $nativeText = (Get-Content -LiteralPath $nativeLog -Raw) + (Get-Content -LiteralPath $nativeErrors -Raw)
        if ($native.ExitCode -ne 0 -or $nativeText -match '(?m)^(SCRIPT ERROR:|ERROR:|FAIL:)') { throw "Native checks failed. See $nativeLog" }
        Write-Output ('native ' + $nativeCase[0] + ' passed')
    }
}
Invoke-GodotCheck 'export-windows' @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop', (Join-Path $windowsRoot 'BigSnowShift.exe'))
Invoke-GodotCheck 'package-localization' @('--headless', '--path', (Join-Path $PSScriptRoot 'smoke-project'), '--script', (Join-Path $PSScriptRoot 'check_package.gd'), '--', (Join-Path $windowsRoot 'BigSnowShift.pck'), (Join-Path $buildRoot 'localization-package.json'))
# Remove the obsolete sidecar from reused build directories.
$obsoleteTuning = Join-Path $windowsRoot 'game_settings.cfg'
if (Test-Path -LiteralPath $obsoleteTuning) { Remove-Item -LiteralPath $obsoleteTuning -Force }
$windowsLog = Join-Path $logRoot 'windows-startup.log'
$windowsProcess = Start-Process -FilePath (Join-Path $windowsRoot 'BigSnowShift.exe') -ArgumentList @('--headless', '--quit-after', '120', '--log-file', ('"' + $windowsLog + '"')) -WindowStyle Hidden -PassThru
$windowsHandle = $windowsProcess.Handle
if (-not $windowsProcess.WaitForExit(30000)) {
    Stop-Process -Id $windowsProcess.Id
    throw 'Exported Windows startup timed out.'
}
$startupText = Get-Content -LiteralPath $windowsLog -Raw
if ($windowsProcess.ExitCode -ne 0 -or -not $startupText.Contains('BIG_SNOW_SHIFT_GAME_READY') -or $startupText -match '(?m)^(SCRIPT ERROR:|ERROR:)') { throw "Exported Windows startup failed. See $windowsLog" }
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\PLAYER_README.md') -Destination (Join-Path $windowsRoot 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\Nunito-LICENSE.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\fonts\MPLUSRounded1c-LICENSE.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\THIRD_PARTY_NOTICES.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\licenses\MUSIC_CREDITS.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\licenses\CC-BY-4.0.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\licenses\PRIVACY_POLICY.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE'), (Join-Path $projectRoot 'ASSET_LICENSES.md') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/licenses/SOUND_CREDITS.txt'), (Join-Path $projectRoot 'assets/licenses/CC0-1.0.txt') -Destination $windowsRoot -Force
$zipPath = Join-Path $buildRoot 'BigSnowShift-0.30.5-Windows.zip'
Compress-Archive -LiteralPath @((Join-Path $windowsRoot 'BigSnowShift.exe'), (Join-Path $windowsRoot 'BigSnowShift.pck'), (Join-Path $windowsRoot 'README.md'), (Join-Path $windowsRoot 'Nunito-LICENSE.txt'), (Join-Path $windowsRoot 'MPLUSRounded1c-LICENSE.txt'), (Join-Path $windowsRoot 'THIRD_PARTY_NOTICES.txt'), (Join-Path $windowsRoot 'MUSIC_CREDITS.txt'), (Join-Path $windowsRoot 'SOUND_CREDITS.txt'), (Join-Path $windowsRoot 'CC0-1.0.txt'), (Join-Path $windowsRoot 'CC-BY-4.0.txt'), (Join-Path $windowsRoot 'PRIVACY_POLICY.txt'), (Join-Path $windowsRoot 'LICENSE'), (Join-Path $windowsRoot 'ASSET_LICENSES.md')) -DestinationPath $zipPath -Force
& python -X utf8 (Join-Path $PSScriptRoot 'verify_windows_package.py')
if ($LASTEXITCODE -ne 0) { throw 'Windows ZIP verification failed.' }
# Finish the verified Windows package before Android so PC testing can begin.
Write-Output "Windows build ready: $zipPath"
if ($WindowsOnly) { return }
Invoke-GodotCheck 'export-android' @('--headless', '--path', $projectRoot, '--export-debug', 'Android', (Join-Path $androidRoot 'BigSnowShift-0.30.5-arm64-debug.apk'))
Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath, (Join-Path $androidRoot 'BigSnowShift-0.30.5-arm64-debug.apk') | Select-Object Path, Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $buildRoot 'checksums.json') -Encoding utf8
Write-Output "Builds ready: $zipPath and $androidRoot"
