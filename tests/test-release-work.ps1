$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
$module=Join-Path $PSScriptRoot '../updater-release-work.ps1'
if (-not (Test-Path -LiteralPath $module)) {throw 'Async release selection is not implemented'}
. $module
$script:ui=@{DetailsTab='notes';Tabs=@{SelectedTab=''};Form=@{}}
$script:releaseSelection='';$script:releaseWork=$null;$script:releasePending=$null;$script:releaseBundle=$null
$script:status=[ordered]@{codex=[pscustomobject]@{Key='codex';Installed='1.0.0';Latest='2.0.0'};gh=[pscustomobject]@{Key='gh';Installed='3.0.0';Latest='4.0.0'}}
$script:rendered=[Collections.Generic.List[object]]::new()
function Set-ReleaseNotesView($UI,$ToolStatus,$Bundle,[bool]$Loading) {$script:rendered.Add(@{Key=$ToolStatus.Key;Bundle=$Bundle;Loading=$Loading})}
function Save-RuntimeState {}
function Write-ManagerLog([string]$Message) {}
# Hold the external worker boundary while exercising actual selection and stale-response protection.
function Start-PendingReleaseWork {}
Show-ToolDetails -Key 'codex'
if ($script:releasePending.Key -ne 'codex' -or -not $script:rendered[-1].Loading) {throw 'First selection did not queue or render loading'}
$oldRequest=$script:releasePending
Show-ToolDetails -Key 'gh'
if ($script:releasePending.Key -ne 'gh' -or $script:releaseSelection -ne 'gh') {throw 'New selection failed to replace queued request'}
if (Test-ReleaseRequestCurrent $oldRequest) {throw 'Old tool request can overwrite newer selection'}
$current=$script:releasePending
if (-not (Test-ReleaseRequestCurrent $current)) {throw 'Current request was discarded'}
$script:status.gh.Latest='5.0.0'
if (Test-ReleaseRequestCurrent $current) {throw 'Old version response can overwrite newer version status'}
$script:releaseBundle=[pscustomobject]@{Key='gh';Installed=[pscustomobject]@{Version='3.0.0'};Available=[pscustomobject]@{Version='4.0.0'}}
Refresh-SelectedReleaseNotes
if ($script:releasePending.Latest -ne '5.0.0') {throw 'Versions changed without refreshing notes'}
$script:releaseBundle=[pscustomobject]@{Key='gh';Installed=[pscustomobject]@{Version='3.0.0'};Available=[pscustomobject]@{Version='5.0.0'}}
$script:releasePending=$null
Refresh-SelectedReleaseNotes
if ($script:releasePending) {throw 'Unchanged versions unnecessarily fetched again'}
Show-ToolDetails -Key 'gh' -Force
if (-not $script:releasePending.Force) {throw 'Manual refresh did not bypass cache'}
Write-Output 'PASS: async selection, rapid switching, stale-result guard, version changes and forced refresh'
