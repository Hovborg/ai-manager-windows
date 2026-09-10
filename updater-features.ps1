# UI-thread feature coordination; all process/network work remains in a worker.
function Refresh-ManagerHistory {
    try {
        $script:history=@(Get-ManagerHistory $script:StateDirectory)
        Set-ManagerHistoryView $script:ui $script:history
    } catch {Write-ManagerLog "Historik kunne ikke læses: $($_.Exception.Message)"}
}

function Open-ManagerTool {
    param([string]$Key)
    if ($script:work) {return}
    try {
        $tool=Get-ToolCatalog | Where-Object Key -eq $Key | Select-Object -First 1
        if (-not $tool -or -not $script:status.Contains($Key) -or -not $script:status[$Key].Installed) {throw 'Programmet er ikke et installeret, aktivt katalogværktøj.'}
        Start-ManagerApp $tool
        Write-ManagerLog "Åbn app anmodet: $($tool.Name)."
    } catch {Write-ManagerLog "Kunne ikke åbne programmet: $($_.Exception.Message)"}
}

function Apply-ManagerToolConfiguration {
    param($Configuration)
    if ($script:work) {throw 'Vent til den aktuelle kontrol eller opdatering er afsluttet.'}
    Save-ManagerToolConfiguration $Configuration
    $catalog=@(Get-ToolCatalog)
    $next=[ordered]@{}
    foreach ($tool in $catalog) {
        $next[$tool.Key]=if ($script:status.Contains($tool.Key)) {$script:status[$tool.Key]} else {New-ToolStatus $tool '' '' '' 'Afventer versionskontrol.'}
    }
    $script:status=$next
    if ($script:releaseSelection -and -not $next.Contains($script:releaseSelection)) {
        $script:releaseSelection='';$script:releasePending=$null;$script:releaseRequestId='';$script:releaseBundle=$null
        Set-ReleaseNotesView $script:ui $null $null $false
    }
    Set-ManagerDashboardCatalog $script:ui $catalog
    Refresh-Dashboard
    Write-ManagerLog "Programliste gemt: $($catalog.Count) overvåges."
    Start-AsyncCheck
}

function Show-ManagerTools {
    if ($script:work) {return}
    try {
        $configuration=Get-ManagerToolConfiguration
        $result=Show-ToolManagerDialog $script:ui.Form @(Get-ToolCatalog -IncludeHidden) $configuration
        if ($null -ne $result) {Apply-ManagerToolConfiguration $result}
    } catch {
        Write-ManagerLog "Programlisten kunne ikke gemmes: $($_.Exception.Message)"
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Programliste')
    }
}

function Read-ManagerWorkEvents {
    if (-not $script:work) {return}
    $event=$null;$historyChanged=$false;$changed=$false
    while ($script:work.Events.TryDequeue([ref]$event)) {
        $changed=$true
        if ($event.Type -eq 'Stage') {
            $same=$script:operation -and $script:operation.Key -eq $event.Key
            $oldOutput=if ($same) {$script:operation.Output} else {''}
            $began=if ($same) {$script:operation.StartedAt} else {$event.At}
            $script:operation=@{Key=$event.Key;Name=$event.Name;Phase=$event.Phase;Message=$event.Text;StartedAt=$began;ElapsedSeconds=0;Index=$event.Index;Total=$event.Total;Output=$oldOutput}
        } elseif ($event.Type -eq 'Output' -and $script:operation) {
            $script:operation.Output+=$event.Text
            if ($script:operation.Output.Length -gt 12000) {$script:operation.Output=$script:operation.Output.Substring($script:operation.Output.Length-12000)}
        } elseif ($event.Type -eq 'Result') {
            try {Complete-ManagerHistoryAttempt $script:StateDirectory $event.Data;$historyChanged=$true}
            catch {Write-ManagerLog "Resultat kunne ikke gemmes i historikken: $($_.Exception.Message)"}
        }
    }
    if ($script:operation) {
        $script:operation.ElapsedSeconds=[int]([datetimeoffset]::Now-[datetimeoffset]::Parse($script:operation.StartedAt)).TotalSeconds
        Set-ManagerOperationView $script:ui $script:operation
    }
    if ($historyChanged) {Refresh-ManagerHistory}
    if ($changed -or -not $script:lastOperationSaved -or ((Get-Date)-$script:lastOperationSaved).TotalSeconds -ge 1) {
        Save-RuntimeState;$script:lastOperationSaved=Get-Date
    }
}
