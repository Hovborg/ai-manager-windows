# Only the manager UI thread writes history. Worker messages carry attempt IDs.
function Get-ManagerHistory {
    param([string]$StateDirectory)
    $path=Join-Path $StateDirectory 'history.json'
    if (-not (Test-Path -LiteralPath $path)) {return}
    if ((Get-Item -LiteralPath $path).Length -gt 5MB) {throw 'Historikfilen er for stor; den bevares uden ændring.'}
    $data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($data.Schema -ne 1 -or $data.Entries -isnot [array] -or $data.Entries.Count -gt 200) {throw 'Historikkens format kan ikke læses; filen bevares.'}
    foreach ($entry in $data.Entries) {
        if ($entry.Id -cnotmatch '^[a-f0-9]{32}$' -or $entry.Outcome -notin @('Pending','Success','Failed','Blocked','Interrupted','Detected') -or
            $entry.Success -isnot [bool] -or $entry.Output -isnot [string] -or $entry.Output.Length -gt 16500) {throw 'En historikpost har ugyldigt format; filen bevares.'}
        $entry
    }
}

function Save-ManagerHistory {
    param([string]$StateDirectory,[object[]]$Entries)
    $retained=@($Entries | Select-Object -First 200)
    do {
        $payload=@{Schema=1;Entries=$retained}
        $bytes=[Text.Encoding]::UTF8.GetByteCount(($payload | ConvertTo-Json -Depth 8))
        if ($bytes -le 5MB) {break}
        # JSON escaping and UTF-8 can expand an otherwise bounded output field.
        # Retain the newest prefix, reducing it before the same serializer writes.
        $keep=[Math]::Max(0,[Math]::Min($retained.Count-1,[int][Math]::Floor($retained.Count * 5MB / $bytes)-1))
        $retained=@($retained | Select-Object -First $keep)
    } while ($true)
    Save-ManagerJson (Join-Path $StateDirectory 'history.json') $payload
}

function Start-ManagerHistoryAttempts {
    param([string]$StateDirectory,[string[]]$Keys,$StatusMap)
    $entries=@(Get-ManagerHistory $StateDirectory);$attempts=@{};$now=[datetimeoffset]::Now.ToString('o')
    foreach ($key in $Keys) {
        $item=$StatusMap[$key];$id=[guid]::NewGuid().ToString('N');$attempts[$key]=$id
        $entries=@(@{Id=$id;Key=$key;Name=$item.Name;StartedAt=$now;CompletedAt='';Before=$item.Installed;After='';TargetVersion=$item.Latest;Success=$false;Outcome='Pending';Output='Afventer gennemførelse.'})+$entries
    }
    Save-ManagerHistory $StateDirectory $entries
    return $attempts
}

function Complete-ManagerHistoryAttempt {
    param([string]$StateDirectory,$Result)
    $entries=@(Get-ManagerHistory $StateDirectory)
    $match=@($entries | Where-Object Id -eq $Result.Id)
    if ($match.Count -ne 1) {throw 'Opdateringsresultatet matcher ikke et gemt forsøg.'}
    $entry=$match[0]
    if ($entry.Outcome -ne 'Pending') {return}
    $entry.CompletedAt=[datetimeoffset]::Now.ToString('o');$entry.After=[string]$Result.After
    $entry.Success=[bool]$Result.Success
    $entry.Outcome=if ($Result.Success) {'Success'} elseif ($Result.RequiresClose) {'Blocked'} else {'Failed'}
    $output=[string]$Result.Output
    $entry.Output=if ($output.Length -gt 16000) {'[Tidligere output forkortet]'+"`n"+$output.Substring($output.Length-16000)} else {$output}
    Save-ManagerHistory $StateDirectory $entries
}

function Repair-ManagerInterruptedHistory {
    param([string]$StateDirectory,[string[]]$Ids)
    $entries=@(Get-ManagerHistory $StateDirectory);$changed=$false
    foreach ($entry in $entries) {
        if ($entry.Outcome -eq 'Pending' -and (-not $Ids -or $entry.Id -in $Ids)) {
            $entry.Outcome='Interrupted';$entry.Success=$false;$entry.CompletedAt=[datetimeoffset]::Now.ToString('o')
            $entry.Output='Manageren modtog ikke et afsluttet installationsresultat. Versionskontrollen må afgøre den aktuelle installation.';$changed=$true
        }
    }
    if ($changed) {Save-ManagerHistory $StateDirectory $entries}
}

function Update-ManagerObservedVersions {
    param([string]$StateDirectory,$StatusMap)
    $path=Join-Path $StateDirectory 'observed-versions.json';$previous=@{}
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).Length -gt 256KB) {throw 'Versionshistorikkens observationsfil er for stor.'}
        $saved=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($saved.Schema -ne 1 -or $saved.Tools -isnot [Collections.IDictionary]) {throw 'Versionshistorikkens observationer kunne ikke læses.'}
        $previous=$saved.Tools
    }
    $entries=@(Get-ManagerHistory $StateDirectory);$now=[datetimeoffset]::Now.ToString('o');$changed=$false
    foreach ($item in $StatusMap.Values) {
        if (-not $item.Installed) {continue}
        $old=$previous[$item.Key]
        $different=$old -and -not (Test-ManagerSameVersion $old.Version $item.Installed)
        if ($different) {
            $recorded=@($entries | Where-Object {
                $_.Key -eq $item.Key -and
                ($_.Outcome -eq 'Success' -or ($_.Outcome -eq 'Detected' -and (Test-ManagerSameVersion $_.Before $old.Version))) -and
                (Test-ManagerSameVersion $_.After $item.Installed) -and
                [datetimeoffset]::Parse($_.CompletedAt) -ge [datetimeoffset]::Parse($old.CheckedAt)
            }).Count -gt 0
            if (-not $recorded) {
                $entries=@(@{Id=[guid]::NewGuid().ToString('N');Key=$item.Key;Name=$item.Name;StartedAt='';CompletedAt=$now;Before=$old.Version;After=$item.Installed;TargetVersion=$item.Installed;Success=$false;Outcome='Detected';Output='Versionsændringen blev opdaget ved kontrol. Det præcise installationstidspunkt og installationsprogram er ikke kendt.'})+$entries
                $changed=$true
            }
        }
        $previous[$item.Key]=@{Version=$item.Installed;CheckedAt=$now}
    }
    if ($changed) {Save-ManagerHistory $StateDirectory $entries}
    Save-ManagerJson $path @{Schema=1;Tools=$previous}
}

function Test-ManagerSameVersion {
    param([string]$Left,[string]$Right)
    try {return (Compare-ToolVersion $Left $Right) -eq 0}
    catch {return $Left -ceq $Right}
}
