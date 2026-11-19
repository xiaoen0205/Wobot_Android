param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'
$appDirectory = Split-Path -Parent $PSScriptRoot
$localConfiguration = Join-Path (Split-Path -Parent $appDirectory) '.local/android.json'
if (-not (Test-Path -LiteralPath $localConfiguration)) {
    throw 'Create the ignored .local/android.json before running live tests.'
}

Push-Location -LiteralPath $appDirectory
try {
    # Retain the installed app and Firebase session even when an assertion fails.
    & flutter test integration_test/live_chat_test.dart -d $DeviceId `
        --no-uninstall --no-pub `
        "--dart-define-from-file=$localConfiguration" `
        --dart-define=RUN_LIVE_CHAT_TESTS=true --reporter expanded
    $liveTestExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $liveTestExitCode
