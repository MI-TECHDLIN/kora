[CmdletBinding()]
param(
    [ValidateSet('apk', 'appbundle')]
    [string] $Target = 'apk',

    [switch] $Clean
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$SupabaseConfig = Join-Path $ProjectRoot 'config\supabase.prod.json'
$HadDebug = Test-Path Env:DEBUG
$PreviousDebug = $env:DEBUG

if (-not (Test-Path -LiteralPath $SupabaseConfig -PathType Leaf)) {
    throw "Missing config/supabase.prod.json. Copy config/supabase.prod.json.example, then add the production Supabase URL and anon key."
}

Push-Location $ProjectRoot
try {
    Remove-Item Env:DEBUG -ErrorAction SilentlyContinue

    if ($Clean) {
        flutter clean
    }

    $PackageConfig = Join-Path $ProjectRoot '.dart_tool\package_config.json'
    if (-not (Test-Path -LiteralPath $PackageConfig -PathType Leaf)) {
        flutter pub get
    }

    $BuildTarget = if ($Target -eq 'appbundle') { 'appbundle' } else { 'apk' }
    $BuildArgs = @('build', $BuildTarget, '--release', "--dart-define-from-file=$SupabaseConfig")
    if (Test-Path -LiteralPath $PackageConfig -PathType Leaf) {
        $BuildArgs += '--no-pub'
    }
    flutter @BuildArgs
} finally {
    if ($HadDebug) {
        $env:DEBUG = $PreviousDebug
    } else {
        Remove-Item Env:DEBUG -ErrorAction SilentlyContinue
    }
    Pop-Location
}
