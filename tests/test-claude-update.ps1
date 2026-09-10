$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
$script:processes=@([pscustomobject]@{Path="$env:ProgramFiles\WindowsApps\Claude_1.40609.1.0_x64__pzs8sxrjxfjjc\app\Claude.exe"})
function Get-Process {param($Name,$ErrorAction) $script:processes}
$script:coworkService=$null
function Get-CimInstance {param($ClassName,$Filter,$OperationTimeoutSec,$ErrorAction) $script:coworkService}
function Find-ToolExecutable {'fixture.exe'}
$script:installerCalls=0
function Invoke-ToolProcess {param($FilePath,$Arguments,$TimeoutSeconds)
    if ($Arguments[0] -eq 'upgrade') {$script:installerCalls++; return [pscustomobject]@{Success=$true;ExitCode=0;Output='installer diagnostic retained';TimedOut=$false}}
    [pscustomobject]@{Success=$true;ExitCode=0;Output='Claude Anthropic.Claude 1.40609.1.0 1.44121.2'}
}
$tool=Get-ToolCatalog | Where-Object Key -eq 'claude_app'
$status=Get-OneToolStatus $tool
if ($status.State -ne 'NeedsClose' -or -not $status.HasUpdate -or $status.Error -notlike '*Luk Claude helt*') {throw 'Running Claude does not explain that it must close'}
$map=[ordered]@{claude_app=$status}
if (@(Get-UpdateTargets 'all' $map).Count) {throw 'Bulk update includes blocked Claude'}
# A process can start after the status check. Recheck at the installation boundary.
$map.claude_app=New-ToolStatus $tool '1.40609.1.0' '1.44121.2' '' ''
$r=Invoke-ManagedUpdate @('claude_app') $map
if ($script:installerCalls -ne 0 -or $r.Success -or -not $r.RequiresClose) {throw 'Running app reached installer'}
$script:processes=@([pscustomobject]@{Path="$env:USERPROFILE\.local\bin\claude.exe"},[pscustomobject]@{Path="$env:APPDATA\Claude\claude-code\2.1.255\claude.exe"})
$status=Get-OneToolStatus $tool
if ($status.State -ne 'Update') {throw 'Claude Code was confused with Desktop'}
$r=Invoke-ManagedUpdate @('claude_app') $map
if ($script:installerCalls -ne 1 -or $r.Success -or $r.Output -notlike '*installer diagnostic retained*') {throw 'Unverified exit zero lost installer evidence'}
Write-Output 'PASS: running Desktop blocked, bulk skip, install-time recheck, CLI isolation, installer diagnostics retained'
$script:processes=@()
$script:coworkService=[pscustomobject]@{State='Running';PathName='"'+$env:ProgramFiles+'\WindowsApps\Claude_1.40609.1.0_x64__pzs8sxrjxfjjc\app\resources\cowork-svc.exe"'}
$status=Get-OneToolStatus $tool
if ($status.State -ne 'NeedsClose' -or $status.Error -notlike 'Cowork*') {throw 'System Cowork service was missed when Claude.exe was closed'}
$r=Invoke-ManagedUpdate @('claude_app') $map
if ($script:installerCalls -ne 1 -or -not $r.RequiresClose) {throw 'Running Cowork service reached installer'}
$script:coworkService.State='Stopped'
if ((Get-OneToolStatus $tool).State -ne 'Update') {throw 'Stopped service still blocks update'}
$script:coworkService.State='Running'; $script:coworkService.PathName='C:\Unrelated\cowork-svc.exe'
if ((Get-OneToolStatus $tool).State -ne 'Update') {throw 'Unrelated service was classified as Claude'}
Write-Output 'PASS: packaged Cowork service blocked, stopped service allowed, unrelated path ignored'
