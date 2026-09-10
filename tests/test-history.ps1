$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
. "$PSScriptRoot/../updater-history.ps1"
$state=Join-Path $PSScriptRoot ('../artifacts/history-'+[guid]::NewGuid().ToString('N'))
$script:n=0
function Assert-History($Condition,[string]$Message) {if (-not $Condition) {throw $Message};$script:n++}
$map=[ordered]@{codex=@{Key='codex';Name='Codex CLI';Installed='1.0.0';Latest='1.2.0'}}
Assert-History (@(Get-ManagerHistory $state).Count -eq 0) 'Fresh history is not empty'
$attempts=Start-ManagerHistoryAttempts $state @('codex') $map
$pending=@(Get-ManagerHistory $state)
Assert-History ($pending.Count -eq 1 -and $pending[0].Outcome -eq 'Pending' -and -not $pending[0].Success) 'Attempt was not persisted before installation'
$result=@{Id=$attempts.codex;Key='codex';Name='Codex CLI';Success=$true;RequiresClose=$false;Before='1.0.0';After='1.2.0';Output='verified'}
Complete-ManagerHistoryAttempt $state $result
Complete-ManagerHistoryAttempt $state $result
$entries=@(Get-ManagerHistory $state)
Assert-History ($entries.Count -eq 1 -and $entries[0].Success -and $entries[0].Outcome -eq 'Success' -and $entries[0].CompletedAt) 'Result was not deduplicated and completed'
$attempts=Start-ManagerHistoryAttempts $state @('codex') $map
Repair-ManagerInterruptedHistory $state
$entries=@(Get-ManagerHistory $state)
Assert-History ($entries[0].Outcome -eq 'Interrupted' -and -not $entries[0].Success -and $entries.Count -eq 2) 'Unfinished attempt looked successful after restart'
$other=Join-Path $state 'external'
Update-ManagerObservedVersions $other $map
Assert-History (@(Get-ManagerHistory $other).Count -eq 0) 'First observation invented history'
$map.codex.Installed='1.1.0'
Update-ManagerObservedVersions $other $map
Update-ManagerObservedVersions $other $map
$entries=@(Get-ManagerHistory $other)
Assert-History ($entries.Count -eq 1 -and $entries[0].Outcome -eq 'Detected' -and $entries[0].Before -eq '1.0.0' -and $entries[0].After -eq '1.1.0' -and -not $entries[0].StartedAt) 'External version change was duplicated or given an invented installation time'
$map.codex.Installed='';Update-ManagerObservedVersions $other $map
Assert-History (@(Get-ManagerHistory $other).Count -eq 1) 'Missing/unknown version invented a change'
$map.codex.Installed='1.1.0.0';Update-ManagerObservedVersions $other $map
Assert-History (@(Get-ManagerHistory $other).Count -eq 1) 'Equivalent version formatting invented a change'
$recordedState=Join-Path $state 'recorded'
Save-ManagerJson (Join-Path $recordedState 'observed-versions.json') @{Schema=1;Tools=@{codex=@{Version='1.0.0';CheckedAt='2026-09-10T10:00:00+02:00'}}}
$attempts=Start-ManagerHistoryAttempts $recordedState @('codex') $map
Complete-ManagerHistoryAttempt $recordedState @{Id=$attempts.codex;Success=$true;After='1.1.0';Output='verified'}
$recorded=@(Get-ManagerHistory $recordedState);$recorded[0].CompletedAt='2026-09-10T08:01:00+00:00'
Save-ManagerHistory $recordedState $recorded
Update-ManagerObservedVersions $recordedState $map
Assert-History (@(Get-ManagerHistory $recordedState).Count -eq 1) 'Equivalent verified version or time-zone offset duplicated a completed update'
$map.codex.Installed='1.1.0';$attempts=Start-ManagerHistoryAttempts $other @('codex') $map
Complete-ManagerHistoryAttempt $other @{Id=$attempts.codex;Key='codex';Name='Codex CLI';Success=$false;RequiresClose=$true;Before='1.1.0';After='';Output=('x'*24000)}
$entries=@(Get-ManagerHistory $other)
Assert-History ($entries[0].Outcome -eq 'Blocked' -and $entries[0].Output.Length -le 16500) 'Blocked result or output limit lost'
$large=Join-Path $state 'large'
$many=@(1..200 | ForEach-Object {@{Id=[guid]::NewGuid().ToString('N');Outcome='Success';Success=$true;Output=('\'*16000)}})
Save-ManagerHistory $large $many
$retained=@(Get-ManagerHistory $large)
Assert-History ((Get-Item (Join-Path $large 'history.json')).Length -le 5MB -and $retained.Count -gt 0 -and $retained.Count -le 200 -and $retained[0].Id -eq $many[0].Id) 'Valid escaped output made history unreadable or evicted newest entries'
$retry=Join-Path $state 'retry'
$map.codex.Installed='1.0.0';Update-ManagerObservedVersions $retry $map
$script:actualSave=${function:Save-ManagerJson};$script:failObservation=$true
function Save-ManagerJson([string]$Path,$Value) {
    if ($Path.EndsWith('observed-versions.json') -and $script:failObservation) {$script:failObservation=$false;throw 'Injected observation-write failure'}
    & $script:actualSave $Path $Value
}
$map.codex.Installed='2.0.0';$failed=$false
try {Update-ManagerObservedVersions $retry $map} catch {$failed=$true}
Update-ManagerObservedVersions $retry $map
Assert-History ($failed -and @(Get-ManagerHistory $retry).Count -eq 1) 'Retry after failed observation save duplicated Detected history'
${function:Save-ManagerJson}=$script:actualSave
$path=Join-Path $other 'history.json';[IO.File]::WriteAllText($path,'corrupt')
$failed=$false;try {Start-ManagerHistoryAttempts $other @('codex') $map} catch {$failed=$true}
Assert-History ($failed -and [IO.File]::ReadAllText($path) -eq 'corrupt') 'Corrupt history was silently overwritten'
Write-Output "PASS: $script:n history assertions. Evidence: $state"
