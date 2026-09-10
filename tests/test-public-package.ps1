$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$required = @(
    'README.md', 'LICENSE', 'CONTRIBUTING.md', '.gitignore',
    'docs/GUIDE.md', 'docs/GUIDE.da.md',
    'docs/images/dashboard.png', 'docs/images/release-notes.png', 'docs/images/history.png',
    '.github/workflows/synthetic-tests.yml',
    '.github/ISSUE_TEMPLATE/bug_report.yml', '.github/ISSUE_TEMPLATE/feature_request.yml',
    'ai-tray-updater.ps1', 'updater-core.ps1', 'updater-ui.ps1',
    'manage-startup.ps1', 'start-tray.cmd', 'start-tray.vbs', 'ai-updater.ico'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
        throw "Missing public package file: $relative"
    }
}

$forbidden = @(
    'AGENTS.md', 'AI_CONTEXT.md', 'docs/implementation.md', 'docs/verification.md',
    'tests/test-installed-ui.ps1', 'tests/test-notification-live.ps1',
    'tests/test-releases-live.ps1', 'tests/test-lifecycle.ps1',
    'tests/test-runtime-ui.ps1', 'artifacts', 'state'
)
foreach ($relative in $forbidden) {
    if (Test-Path -LiteralPath (Join-Path $root $relative)) {
        throw "Internal or live-only file leaked into public package: $relative"
    }
}

$aggregate=Get-Content -LiteralPath (Join-Path $root 'tests/test-all.ps1') -Raw
foreach ($liveName in @('test-installed-ui.ps1','test-notification-live.ps1','test-releases-live.ps1','test-lifecycle.ps1','test-runtime-ui.ps1')) {
    if ($aggregate -match [regex]::Escape($liveName)) {throw "Public aggregate test still references live test: $liveName"}
}

$textFiles = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension -in @('.md', '.ps1', '.cmd', '.vbs', '.cs', '.yml', '.yaml')
}
foreach ($file in $textFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if ($text -match '(?i)C:\\codex_projekts|SHARK\\brian|(?:192\.168|100\.\d+)\.\d+\.\d+') {
        throw "Private workspace or host value found in $($file.FullName)"
    }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'ai-tray-updater.ps1'),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count) {
    throw "PowerShell parser errors in ai-tray-updater.ps1: $($errors[0].Message)"
}

Write-Output "PASS: public inventory, privacy scan, live-test exclusions, and entry-point syntax"
