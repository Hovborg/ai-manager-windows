# UI-thread coordination. Network and cache work run in a separate PowerShell runspace.
function Test-ReleaseRequestCurrent {
    param($Request)
    return $Request -and $Request.Id -eq $script:releaseRequestId -and
        $Request.Key -eq $script:releaseSelection -and $script:status.Contains($Request.Key) -and
        $Request.Installed -ceq $script:status[$Request.Key].Installed -and
        $Request.Latest -ceq $script:status[$Request.Key].Latest
}

function Show-ToolDetails {
    param([string]$Key,[switch]$Force)
    if (-not $script:status.Contains($Key)) {return}
    $script:releaseSelection=$Key
    $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab
    $item=$script:status[$Key]
    $script:releaseRequestId=[guid]::NewGuid().ToString('N')
    $script:releasePending=@{Id=$script:releaseRequestId;Key=$Key;Installed=$item.Installed;Latest=$item.Latest;Force=[bool]$Force}
    Set-ReleaseNotesView $script:ui $item $null $true
    Start-PendingReleaseWork
    Save-RuntimeState
}

function Start-PendingReleaseWork {
    if ($script:releaseWork -or -not $script:releasePending) {return}
    $request=$script:releasePending; $script:releasePending=$null
    $ps=[powershell]::Create()
    try {
        [void]$ps.AddScript('param($Root,$Request,$StateDirectory) $ErrorActionPreference="Stop"; . (Join-Path $Root "updater-core.ps1"); . (Join-Path $Root "updater-releases.ps1"); Get-ToolReleaseBundle $Request $StateDirectory -Force:$Request.Force').AddArgument($script:Root).AddArgument($request).AddArgument($script:StateDirectory)
        $script:releaseWork=@{PowerShell=$ps;Handle=$ps.BeginInvoke();Request=$request}
    } catch {
        $ps.Dispose(); $script:releaseWork=$null
        Set-ReleaseWorkError $request $_.Exception.Message
    }
}

function Set-ReleaseWorkError {
    param($Request,[string]$Message)
    if (-not (Test-ReleaseRequestCurrent $Request)) {return}
    $bundle=[pscustomobject]@{Key=$Request.Key;Installed=$null;Available=$null;Range=$null}
    foreach ($side in @('Installed','Available')) {
        $version=if ($side -eq 'Installed') {$Request.Installed} else {$Request.Latest}
        $bundle.$side=[pscustomobject]@{Version=$version;Body='';State='Error';Message="Versionsnyt kunne ikke hentes: $Message";SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$false}
    }
    $bundle.Range=[pscustomobject]@{Version="$($Request.Installed) → $($Request.Latest)";FromVersion=$Request.Installed;ToVersion=$Request.Latest;Body='';State='Error';Message="Versionsnyt kunne ikke hentes: $Message";SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$false;ReleaseCount=0;Complete=$false}
    $script:releaseBundle=$bundle
    Set-ReleaseNotesView $script:ui $script:status[$Request.Key] $bundle $false
    Write-ManagerLog "Versionsnyt for $($Request.Key) fejlede: $Message"
}

function Complete-ReleaseNotesWork {
    if ($script:releaseWork -and $script:releaseWork.Handle.IsCompleted) {
        $finished=$script:releaseWork
        try {
            $result=$finished.PowerShell.EndInvoke($finished.Handle)
            if ($finished.PowerShell.HadErrors -or $result.Count -ne 1 -or -not $result[0].Installed -or -not $result[0].Available -or -not $result[0].Range) {
                throw 'Versionsnyt returnerede et ufuldstændigt resultat.'
            }
            if (Test-ReleaseRequestCurrent $finished.Request) {
                $script:releaseBundle=$result[0]
                Set-ReleaseNotesView $script:ui $script:status[$finished.Request.Key] $script:releaseBundle $false
                Write-ManagerLog "Versionsnyt: $($finished.Request.Key) · installeret=$($result[0].Installed.State) · tilgængelig=$($result[0].Available.State)."
            }
        } catch {Set-ReleaseWorkError $finished.Request $_.Exception.Message}
        finally {$finished.PowerShell.Dispose(); $script:releaseWork=$null}
        Start-PendingReleaseWork
        Save-RuntimeState
    }
}

function Refresh-SelectedReleaseNotes {
    if (-not $script:releaseSelection -or -not $script:status.Contains($script:releaseSelection)) {return}
    $item=$script:status[$script:releaseSelection]
    if (($script:releasePending -and (Test-ReleaseRequestCurrent $script:releasePending)) -or
        ($script:releaseWork -and (Test-ReleaseRequestCurrent $script:releaseWork.Request))) {return}
    if ($script:releaseBundle -and $script:releaseBundle.Key -eq $item.Key -and
        $script:releaseBundle.Installed.Version -ceq $item.Installed -and $script:releaseBundle.Available.Version -ceq $item.Latest) {
        Set-ReleaseNotesView $script:ui $item $script:releaseBundle $false
    } else {
        # Updating status must not unexpectedly change the user's current tab.
        $tab=$script:ui.Tabs.SelectedTab
        Show-ToolDetails $item.Key
        $script:ui.Tabs.SelectedTab=$tab
    }
}

function Open-ManagerReleaseSource {
    param([string]$Url)
    try {
        if (-not (Test-ManagerReleaseUrl $Url)) {throw 'Kildelinket er ikke en godkendt officiel versionskilde.'}
        $start=[Diagnostics.ProcessStartInfo]::new(); $start.FileName=$Url; $start.UseShellExecute=$true
        $process=[Diagnostics.Process]::Start($start)
        if ($process) {$process.Dispose()}
    } catch {Write-ManagerLog "Kunne ikke åbne versionskilden: $($_.Exception.Message)"}
}
