[CmdletBinding()]
param(
    [ValidateSet('apk', 'appbundle')]
    [string] $Target = 'apk',

    [switch] $Clean,

    [switch] $AllowLocalBackend
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$SupabaseConfig = Join-Path $ProjectRoot 'config\supabase.prod.json'
$HadDebug = Test-Path Env:DEBUG
$PreviousDebug = $env:DEBUG

if (-not (Test-Path -LiteralPath $SupabaseConfig -PathType Leaf)) {
    throw "Missing config/supabase.prod.json. Copy config/supabase.prod.json.example, then add the production Supabase URL and anon key."
}

# VOICEOPS_API_URL in this file overrides the app's built-in production backend. A release
# build pointed at plain http or a LAN address can't reach Render: login (Supabase) still works,
# but voice never connects.
$Config = Get-Content -LiteralPath $SupabaseConfig -Raw | ConvertFrom-Json
$BackendUrl = $Config.VOICEOPS_API_URL
if ($BackendUrl) {
    $BackendHost = ([Uri] $BackendUrl).Host
    $LooksLocal = ($BackendUrl -notmatch '^https://') -or
        ($BackendHost -match '^(localhost$|voiceops-ll41\.onrender\.com$|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)')
    if ($LooksLocal -and -not $AllowLocalBackend) {
        throw "config/supabase.prod.json sets VOICEOPS_API_URL to $BackendUrl, which a release build on a phone can't reach. Use the production URL (https://kora-brd8.onrender.com), remove the key to use the app default, or pass -AllowLocalBackend."
    }
    Write-Host "Backend for this build: $BackendUrl"
} else {
    Write-Host 'Backend for this build: app default (see lib/core/config/backend_config.dart)'
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
