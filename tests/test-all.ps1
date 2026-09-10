$ErrorActionPreference='Stop'
$exe=(Get-Process -Id $PID).Path
$tests=@('test-core.ps1','test-catalog.ps1','test-update.ps1','test-claude-update.ps1','test-codex-app.ps1','test-cancellation.ps1','test-progress.ps1','test-history.ps1','test-manager-work.ps1','test-startup.ps1','test-notifications.ps1','test-releases.ps1','test-release-http.ps1','test-release-work.ps1','test-ui.ps1','test-ui-tools.ps1')
$tests+='test-feature-runtime.ps1'
foreach ($test in $tests) {
    & $exe -NoProfile -NonInteractive -STA -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) {throw "$test failed with exit code $LASTEXITCODE"}
}
Write-Output "PASS: all $($tests.Count) test scripts"
