$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
# Mock only external installer and network boundaries; selection and verification are real.
function Get-ToolCatalog {@{Key='codex';Name='Codex';Type='CLI';Path='fake.exe';Source='test'}}
$script:exit=7; $script:after='1.0.0'; $script:calls=0
function Invoke-ToolProcess {param($FilePath,$Arguments,$TimeoutSeconds)
    if ($FilePath -ne 'fake.exe' -or ($Arguments -join ',') -ne 'update') {throw 'Wrong update command'}
    $script:calls++
    [pscustomobject]@{Success=($script:exit -eq 0);ExitCode=$script:exit;Output='fixture output';TimedOut=$false}
}
function Get-OneToolStatus {param($Tool) New-ToolStatus $Tool $script:after '2.0.0' '' ''}
$map=[ordered]@{codex=New-ToolStatus (Get-ToolCatalog) '1.0.0' '2.0.0' '' ''}
$r=Invoke-ManagedUpdate @('codex') $map
if ($r.Success -or $r.ExitCode -ne 7) {throw 'Failed installer reported as success'}
$script:exit=0
$r=Invoke-ManagedUpdate @('codex') $map
if ($r.Success) {throw 'Exit 0 without version change reported as success'}
$script:after='2.0.0'
$r=Invoke-ManagedUpdate @('codex') $map
if (-not $r.Success -or $r.After -ne '2.0.0' -or $r.Before -ne '1.0.0') {throw 'Verified update was not recognized'}
$rejected=$false
try {Invoke-ManagedUpdate @('unknown') $map} catch {$rejected=$true}
if (-not $rejected -or $script:calls -ne 3) {throw 'Unknown target executed'}
Write-Output 'PASS: nonzero exit, unchanged version, verified update, unknown target rejection'
