$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$global:StartupAliasPresent=$true
$global:StartupDisableCalls=0
function Disable-ScheduledTask {[CmdletBinding()]param($TaskName,$TaskPath) $global:StartupDisableCalls++}
$aliasPath=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
$fallbackPath=Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
# Model executable discovery independently of the test runner's installation.
function Test-Path {
    [CmdletBinding()]param([string]$LiteralPath,[string]$PathType)
    if ($LiteralPath -eq (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')) {return $global:StartupAliasPresent}
    if ($LiteralPath -eq (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')) {return $true}
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
$global:StartupTestFixture=[pscustomobject]@{
    Description='Hovborg AI Manager: start i systembakken ved brugerens Windows-login.';State='Ready'
    Actions=@([pscustomobject]@{Execute=(Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe');Arguments="-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$root\ai-tray-updater.ps1`" -StartMinimized";WorkingDirectory=$root})
    Principal=[pscustomobject]@{UserId=$sid;LogonType='Interactive';RunLevel='Limited'}
    Triggers=@([pscustomobject]@{CimClass=[pscustomobject]@{CimClassName='MSFT_TaskLogonTrigger'};UserId=$sid;Enabled=$true;Delay='PT15S'})
    Settings=[pscustomobject]@{Enabled=$true;ExecutionTimeLimit='PT0S';MultipleInstances='IgnoreNew';RestartCount=3;RestartInterval='PT1M';DisallowStartIfOnBatteries=$false;StopIfGoingOnBatteries=$false;StartWhenAvailable=$true}
}
function Get-ScheduledTask {[CmdletBinding()]param($TaskName,$TaskPath) $global:StartupTestFixture}
function Get-ScheduledTaskInfo {[CmdletBinding()]param($TaskName,$TaskPath) [pscustomobject]@{LastRunTime=$null;LastTaskResult=0}}
$good=& "$root/manage-startup.ps1" -Action status -PassThru
if (-not $good.ConfigurationValid -or -not $good.Enabled) {throw 'Valid task rejected'}
# Mutations must reject another user's task before invoking Task Scheduler.
foreach ($ownerField in @('Principal','Trigger')) {
    if ($ownerField -eq 'Principal') {$global:StartupTestFixture.Principal.UserId='S-1-5-21-1-2-3-9999'}
    else {$global:StartupTestFixture.Triggers[0].UserId='S-1-5-21-1-2-3-9999'}
    $rejected=$false
    try {& "$root/manage-startup.ps1" -Action disable -PassThru | Out-Null}
    catch {if ($_.Exception.Message -match 'anden bruger|ejerskab') {$rejected=$true} else {throw}}
    if (-not $rejected -or $global:StartupDisableCalls) {throw "Foreign $ownerField owner reached a task mutation"}
    $global:StartupTestFixture.Principal.UserId=$sid
    $global:StartupTestFixture.Triggers[0].UserId=$sid
}
$global:StartupAliasPresent=$false
$global:StartupTestFixture.Actions[0].Execute=$fallbackPath
$fallback=& "$root/manage-startup.ps1" -Action status -PassThru
if (-not $fallback.ConfigurationValid -or -not $fallback.Enabled) {throw 'Valid MSI fallback task rejected'}
$global:StartupTestFixture.Actions[0].Execute=$aliasPath
if ((& "$root/manage-startup.ps1" -Action status -PassThru).ConfigurationValid) {throw 'Unavailable alias accepted instead of MSI fallback'}
$global:StartupAliasPresent=$true
$global:StartupTestFixture.Triggers[0].UserId=[Security.Principal.WindowsIdentity]::GetCurrent().Name
if (-not (& "$root/manage-startup.ps1" -Action status -PassThru).Enabled) {throw 'Windows account name normalization rejected'}
$cases=@{ExecutionTimeLimit='PT1M';MultipleInstances='Parallel';RestartCount=0;RestartInterval='PT2M';DisallowStartIfOnBatteries=$true;StopIfGoingOnBatteries=$true;StartWhenAvailable=$false}
foreach ($key in $cases.Keys) {
    $previous=$global:StartupTestFixture.Settings.$key; $global:StartupTestFixture.Settings.$key=$cases[$key]
    $result=& "$root/manage-startup.ps1" -Action status -PassThru
    if ($result.ConfigurationValid -or $result.Enabled) {throw "Invalid $key accepted as enabled"}
    $global:StartupTestFixture.Settings.$key=$previous
}
$global:StartupTestFixture.Triggers[0].Delay='PT0S'
if ((& "$root/manage-startup.ps1" -Action status -PassThru).ConfigurationValid) {throw 'Wrong login delay accepted'}
$global:StartupTestFixture.Triggers=$null
if ((& "$root/manage-startup.ps1" -Action status -PassThru).ConfigurationValid) {throw 'Absent trigger accepted'}
$global:StartupTestFixture.Actions=$null
if ((& "$root/manage-startup.ps1" -Action status -PassThru).ConfigurationValid) {throw 'Absent action accepted'}
Write-Output 'PASS: startup contract covers alias and MSI discovery and rejects time limit, parallel instances, wrong restart/battery/delay settings'
