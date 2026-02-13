[CmdletBinding()]
param(
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$flutterRoot = Join-Path $repoRoot "apps/lazynote_flutter"

if (-not (Test-Path $flutterRoot)) {
    throw "Flutter app directory not found: $flutterRoot"
}

Push-Location $flutterRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    dart format --output=none --set-exit-if-changed .
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    flutter test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (-not $SkipBuild) {
        flutter build windows --debug
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
finally {
    Pop-Location
}
