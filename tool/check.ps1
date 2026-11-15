param([string]$FlutterRoot)
$ErrorActionPreference = 'Stop'
$flutterCommand = if ($FlutterRoot) { Join-Path $FlutterRoot 'bin/flutter.bat' } else { 'flutter' }
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & $flutterCommand --version
    if ($LASTEXITCODE -ne 0) { throw 'Flutter SDK is unavailable' }
    & $flutterCommand analyze
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed' }
    & $flutterCommand test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    foreach ($source in @('assets/web/app.js', 'assets/web/room.js', 'assets/web/theme.js', 'tool/web_preview.cjs')) {
        & node --check $source
        if ($LASTEXITCODE -ne 0) { throw "JavaScript syntax failed: $source" }
    }
    & node --test test/web/client.test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Browser unit tests failed' }
    Write-Output 'All checks passed. No release artifact was built.'
} finally { Pop-Location }
