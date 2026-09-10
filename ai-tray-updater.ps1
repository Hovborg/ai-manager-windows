#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$CheckNowAndExit,
    [switch]$Json,
    [switch]$StartMinimized,
    [switch]$ExitExisting,
    [ValidateSet(15,30,60,120,240)][int]$CheckIntervalMinutes=60,
    [string]$StateDirectory=(Join-Path $env:LOCALAPPDATA 'Hovborg\AI-Manager')
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/updater-core.ps1"
. "$PSScriptRoot/updater-releases.ps1"
. "$PSScriptRoot/updater-history.ps1"
Set-ManagerDataDirectory $StateDirectory
if ($CheckNowAndExit) {
    $status=Get-AllToolStatus
    if ($Json) {$status.Values | ConvertTo-Json -Depth 5}
    else {$status.Values | Select-Object Name,Installed,Latest,State,Error | Format-Table -AutoSize -Wrap}
    if (@($status.Values | Where-Object State -in @('Unknown','Error')).Count) {exit 2}
    exit 0
}

$script:Root=$PSScriptRoot
$script:StateDirectory=$StateDirectory
$script:SettingsPath=Join-Path $StateDirectory 'settings.json'
$script:LogFile=Join-Path $StateDirectory 'updater.log'
$script:RuntimePath=Join-Path $StateDirectory 'runtime.json'
[void][IO.Directory]::CreateDirectory($StateDirectory)
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("$identity|$([IO.Path]::GetFullPath($StateDirectory).ToLowerInvariant())"))).Substring(0,16)
$script:Mutex=[Threading.Mutex]::new($false,"Local\Hovborg.AIManager.$hash")
$owned=$false
try {$owned=$script:Mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$owned=$true}
$script:ShowEvent=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,"Local\Hovborg.AIManager.Show.$hash")
$script:ExitEvent=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,"Local\Hovborg.AIManager.Exit.$hash")
if (-not $owned) {
    if ($ExitExisting) {[void]$script:ExitEvent.Set()} elseif (-not $StartMinimized) {[void]$script:ShowEvent.Set()}
    $script:ShowEvent.Dispose(); $script:ExitEvent.Dispose(); $script:Mutex.Dispose()
    Write-Output $(if ($ExitExisting) {'Afslutning anmodet; igangværende opdateringer beskyttes.'} else {'AI Manager kører allerede; eksisterende instans anvendes.'})
    exit 0
}
if ($ExitExisting) {
    $script:ShowEvent.Dispose(); $script:ExitEvent.Dispose(); $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose()
    Write-Output 'Ingen AI Manager-instans kører.'
    exit 0
}
$script:ui=$null; $script:work=$null; $script:notify=$null
$script:operation=$null;$script:history=@();$script:lastOperationSaved=$null
$script:releaseWork=$null; $script:releasePending=$null; $script:releaseSelection=''; $script:releaseBundle=$null; $script:releaseRequestId=''
$script:toastWork=$null; $script:toastQueue=[Collections.Generic.Queue[object]]::new(); $script:notificationIdentity=$null
$script:poll=$null; $script:timer=$null; $script:menu=$null; $script:appContext=$null
$script:status=[ordered]@{}; $script:realExit=$false; $script:lastCheck=$null; $script:nextCheck=Get-Date
$script:settings=Get-ManagerSettings $script:SettingsPath
if ($PSBoundParameters.ContainsKey('CheckIntervalMinutes')) {$script:settings.CheckIntervalMinutes=$CheckIntervalMinutes}

function Write-ManagerLog {
    param([string]$Message)
    $entry="[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message"
    try {
        if ((Test-Path -LiteralPath $script:LogFile) -and (Get-Item -LiteralPath $script:LogFile).Length -gt 2MB) {
            [IO.File]::Move($script:LogFile,"$script:LogFile.1",$true)
        }
        Add-Content -LiteralPath $script:LogFile -Value $entry -Encoding utf8
    } catch {$entry+=" · Logfilen kunne ikke gemmes: $($_.Exception.Message)"}
    if ($script:ui -and -not $script:ui.Log.IsDisposed) {
        if ($script:ui.Log.TextLength -gt 150000) {$script:ui.Log.Text=$script:ui.Log.Text.Substring($script:ui.Log.TextLength-100000)}
        $script:ui.Log.AppendText("$entry`r`n")
    }
}
function Save-RuntimeState {
    Save-ManagerJson $script:RuntimePath @{
        Version='3.2.0'; PID=$PID; StartedAt=$script:startedAt; UpdatedAt=(Get-Date).ToString('o')
        Visible=($script:ui -and $script:ui.Form.Visible); Busy=[bool]$script:work
        LastCheck=$script:lastCheck; NextCheck=$script:nextCheck.ToString('o'); Tools=@($script:status.Values)
        ReleaseNotes=@{Key=$script:releaseSelection;Busy=[bool]($script:releaseWork -or $script:releasePending);Bundle=$script:releaseBundle}
        Operation=$script:operation;HistoryCount=$script:history.Count
    }
}
function Queue-ManagerNotification {
    param([string]$Title,[string]$Message,[ValidateSet('updates','result','preview')][string]$Tag='updates',[string]$Signature='')
    if (-not $script:settings.Notifications) {return}
    if ($Signature -and ($Signature -eq $script:settings.LastNotification -or ($script:toastWork -and $script:toastWork.Signature -eq $Signature) -or @($script:toastQueue | Where-Object Signature -eq $Signature).Count -gt 0)) {return}
    try {
        if (-not $script:notificationIdentity) {$script:notificationIdentity=Register-ManagerNotificationIdentity $script:Root $script:StateDirectory}
        $xml=New-ManagerToastXml $Title $Message $script:notificationIdentity.IconPath
        $script:toastQueue.Enqueue(@{Xml=$xml;Tag=$Tag;Signature=$Signature})
    } catch {Write-ManagerLog "Notifikation kunne ikke oprettes: $($_.Exception.Message)"}
}
function Complete-ManagerNotification {
    if ($script:toastWork -and $script:toastWork.Handle.IsCompleted) {
        $finished=$script:toastWork
        try {
            $result=$finished.PowerShell.EndInvoke($finished.Handle)
            if ($finished.PowerShell.HadErrors -or $result.Count -ne 1) {throw ($finished.PowerShell.Streams.Error | Out-String)}
            if ($result[0].Success) {
                Write-ManagerLog "Windows-notifikation accepteret som AI Manager [$($finished.Tag)]."
                if ($finished.Signature) {$script:settings.LastNotification=$finished.Signature; Save-ManagerJson $script:SettingsPath $script:settings}
            } else {Write-ManagerLog "Windows viser ikke notifikationen: $($result[0].Setting)."}
        } catch {Write-ManagerLog "Notifikation fejlede: $($_.Exception.Message)"}
        finally {$finished.PowerShell.Dispose(); $script:toastWork=$null}
    }
    if (-not $script:toastWork -and $script:toastQueue.Count -gt 0) {
        $next=$script:toastQueue.Dequeue()
        if (-not $script:settings.Notifications) {return}
        if ($next.Signature -and $next.Signature -eq $script:settings.LastNotification) {return}
        $ps=[powershell]::Create()
        try {
            [void]$ps.AddScript('param($Root,$Xml,$Tag) $ErrorActionPreference="Stop"; . (Join-Path $Root "updater-core.ps1"); . (Join-Path $Root "updater-notifications.ps1"); Send-ManagerToast $Root $Xml $Tag').AddArgument($script:Root).AddArgument($next.Xml).AddArgument($next.Tag)
            $script:toastWork=@{PowerShell=$ps;Handle=$ps.BeginInvoke();Signature=$next.Signature;Tag=$next.Tag}
        } catch {$ps.Dispose(); Write-ManagerLog "Notifikation kunne ikke starte: $($_.Exception.Message)"}
    }
}
function Refresh-Dashboard {
    if (-not $script:ui) {return}
    Set-DashboardStatus $script:ui $script:status ([bool]$script:work)
    if (-not $script:work) {
        $checked=if ($script:lastCheck) {([datetime]$script:lastCheck).ToString('HH:mm:ss')} else {'afventer'}
        $script:ui.Status.Text="Sidste tjek: $checked   ·   Næste tjek: $($script:nextCheck.ToString('HH:mm'))   ·   X skjuler til bakken"
    }
    if ($script:menu) {
        foreach ($item in $script:menu.Items) {
            if ($item.Tag -eq 'check') {$item.Enabled=-not [bool]$script:work}
            elseif ($item.Tag -in @('all','all_clis','all_apps')) {$item.Enabled=(-not $script:work -and @(Get-UpdateTargets $item.Tag $script:status).Count -gt 0)}
        }
    }
}
function Show-Dashboard {
    $script:ui.Form.Show(); $script:ui.Form.WindowState='Normal'; $script:ui.Form.Activate()
    Save-RuntimeState
}
function Start-ManagerWork {
    param([ValidateSet('check','update')][string]$Kind, [string[]]$Keys=@())
    if ($script:work) {return}
    $ps=[powershell]::Create()
    $events=[Collections.Concurrent.ConcurrentQueue[object]]::new();$attempts=@{}
    try {
        if ($Kind -eq 'update') {$attempts=Start-ManagerHistoryAttempts $script:StateDirectory $Keys $script:status;Refresh-ManagerHistory}
        [void]$ps.AddScript('param($Root,$Kind,$Keys,$Map,$StateDirectory,$Events,$Attempts) $ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; . (Join-Path $Root "updater-core.ps1"); Set-ManagerDataDirectory $StateDirectory; Set-ManagerEventQueue $Events; if ($Kind -eq "check") {Get-AllToolStatus} else {Invoke-ManagedUpdate $Keys $Map $Attempts}')
        [void]$ps.AddArgument($script:Root).AddArgument($Kind).AddArgument($Keys).AddArgument($script:status).AddArgument($script:StateDirectory).AddArgument($events).AddArgument($attempts)
        $script:work=@{PowerShell=$ps; Handle=$ps.BeginInvoke(); Kind=$Kind; Started=Get-Date;Events=$events;Attempts=$attempts}
        $script:ui.Status.Text=if ($Kind -eq 'check') {'Kontrollerer installerede og tilgængelige versioner …'} else {'Opdaterer valgte værktøjer … Følg program, status og output i visningen.'}
        $script:notify.Text=if ($Kind -eq 'check') {'AI Manager · kontrollerer versioner'} else {'AI Manager · opdaterer'}
        Write-ManagerLog $(if ($Kind -eq 'check') {'Starter versionskontrol.'} else {"Starter opdatering: $($Keys -join ', ')."})
        Refresh-Dashboard; Save-RuntimeState
    } catch {
        $ps.Dispose(); $script:work=$null
        if ($attempts.Count) {
            try {Repair-ManagerInterruptedHistory $script:StateDirectory @($attempts.Values);Refresh-ManagerHistory}
            catch {Write-ManagerLog "Historik kunne ikke afsluttes: $($_.Exception.Message)"}
        }
        throw
    }
}
function Start-AsyncCheck {Start-ManagerWork 'check'}
function Start-AsyncUpdate {
    param([string]$Target)
    if ($script:work) {return}
    try {
        $keys=@(Get-UpdateTargets $Target $script:status)
        if ($keys.Count -eq 0) {Write-ManagerLog 'Ingen bekræftede opdateringer i det valgte udvalg.'; return}
        Start-ManagerWork 'update' $keys
    } catch {Write-ManagerLog "Opdatering kunne ikke starte: $($_.Exception.Message)"}
}
function Complete-ManagerWork {
    if (-not $script:work -or -not $script:work.Handle.IsCompleted) {return}
    $finished=$script:work; $followup=$finished.Kind -eq 'update'
    try {
        Read-ManagerWorkEvents
        $result=$finished.PowerShell.EndInvoke($finished.Handle)
        if ($finished.PowerShell.HadErrors) {throw ($finished.PowerShell.Streams.Error | Out-String)}
        if ($finished.Kind -eq 'check') {
            $expectedKeys=@(Get-ToolCatalog | ForEach-Object {$_.Key})
            if ($result.Count -ne 1 -or -not ($result[0] -is [Collections.IDictionary]) -or $result[0].Count -ne $expectedKeys.Count -or @($expectedKeys | Where-Object {-not $result[0].Contains($_)}).Count) {throw 'Versionskontrollen returnerede et ufuldstændigt resultat.'}
            $script:status=$result[0]; $script:lastCheck=(Get-Date).ToString('o')
            try {Update-ManagerObservedVersions $script:StateDirectory $script:status;Refresh-ManagerHistory} catch {Write-ManagerLog "Versionshistorik kunne ikke gemmes: $($_.Exception.Message)"}
            $updates=@($script:status.Values | Where-Object HasUpdate)
            $uncertain=@($script:status.Values | Where-Object State -in @('Error','Unknown','Missing','NeedsClose'))
            Write-ManagerLog "Kontrol afsluttet: $($updates.Count) opdateringer, $($uncertain.Count) kræver opmærksomhed."
            foreach ($item in $script:status.Values) {
                Write-ManagerLog "$($item.Name): $($item.Installed) -> $($item.Latest) [$($item.State)] $($item.Error)"
            }
            $script:notify.Text="AI Manager · $($updates.Count) opdateringer · $($uncertain.Count) kræver opmærksomhed"
            $signature=(@($updates | Sort-Object Key | ForEach-Object {"$($_.Key):$($_.Latest)"}) -join '|')
            if ($signature -and $signature -ne $script:settings.LastNotification -and $script:settings.Notifications) {
                $names=($updates | ForEach-Object {"$($_.Name) $($_.Latest)"}) -join ' · '
                Queue-ManagerNotification 'Opdateringer klar' $names 'updates' $signature
            }
        } else {
            foreach ($updateResult in $result) {Complete-ManagerHistoryAttempt $script:StateDirectory $updateResult}
            Refresh-ManagerHistory
            foreach ($item in $result) {Write-ManagerLog "$($item.Name): $(if ($item.Success) {'VERIFICERET'} elseif ($item.RequiresClose) {'LUK APPEN FØRST'} else {'FEJL'}) · $($item.Before) -> $($item.After) · exit $($item.ExitCode)`r`n$($item.Output)"}
            $failures=@($result | Where-Object {-not $_.Success}).Count
            if ($script:settings.Notifications) {
                $title=if ($failures) {'Opdatering kræver opmærksomhed'} else {'Opdatering verificeret'}
                $message=if ($failures) {"$failures opdateringer kunne ikke bekræftes. Se Aktivitet."} else {"$($result.Count) opdateringer bekræftet med versionskontrol."}
                if (@($result | Where-Object RequiresClose).Count) {$message='Luk '+(($result | Where-Object RequiresClose).Name -join ', ')+' helt. Gem arbejdet, og tryk derefter Tjek igen i AI Manager.'}
                if (@($result | Where-Object {$_.RequiresClose -and $_.Output -like '*Cowork-tjenesten*'}).Count) {$message='Cowork-tjenesten blokerer Claude-opdateringen. Afslut Cowork-arbejde, og se vejledningen i AI Manager.'}
                Queue-ManagerNotification $title $message 'result'
            }
        }
    } catch {
        Write-ManagerLog "Operation fejlede: $($_.Exception.Message)"
        $script:notify.Text='AI Manager · kontrol fejlede'
        if ($finished.Kind -eq 'check') {
            foreach ($item in $script:status.Values) {$item.State='Unknown'; $item.HasUpdate=$false; $item.Error='Seneste kontrol mislykkedes.'}
        }
    } finally {
        try {
            if ($finished.Kind -eq 'update') {
                try {Repair-ManagerInterruptedHistory $script:StateDirectory @($finished.Attempts.Values);Refresh-ManagerHistory}
                catch {Write-ManagerLog "Historik kunne ikke afsluttes: $($_.Exception.Message)"}
            }
        } finally {
            try {$finished.PowerShell.Dispose()}
            finally {$script:work=$null;$script:operation=$null}
        }
        Set-ManagerOperationView $script:ui $null
        $script:nextCheck=(Get-Date).AddMinutes($script:settings.CheckIntervalMinutes)
        Refresh-Dashboard; Save-RuntimeState
    }
    Refresh-SelectedReleaseNotes
    if ($followup) {Start-AsyncCheck}
}
function Request-ManagerExit {
    param([string]$Reason='Bakkemenu')
    if ($script:work -and $script:work.Kind -eq 'update') {
        [void][Windows.Forms.MessageBox]::Show('Vent til opdateringen er afsluttet. Du kan skjule vinduet imens.','Opdatering i gang')
        return
    }
    Write-ManagerLog "Afslutning anmodet: $Reason."
    $script:realExit=$true; $script:appContext.ExitThread()
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2)
    [Windows.Forms.Application]::EnableVisualStyles()
    . "$PSScriptRoot/updater-ui.ps1"
    . "$PSScriptRoot/updater-release-work.ps1"
    . "$PSScriptRoot/updater-notifications.ps1"
    . "$PSScriptRoot/updater-features.ps1"
    Add-Type -Path (Join-Path $PSScriptRoot 'notification-shortcut.cs')
    [Hovborg.AIManager.NotificationShortcut]::SetProcessIdentity('Hovborg.AIManager')
    $script:ui=New-ManagerDashboard (Get-ToolCatalog) (Join-Path $PSScriptRoot 'ai-updater.ico')
    try {Repair-ManagerInterruptedHistory $script:StateDirectory;Refresh-ManagerHistory} catch {Write-ManagerLog "Historik kræver opmærksomhed: $($_.Exception.Message)"}
    $script:ui.Notifications.Checked=$script:settings.Notifications
    $script:ui.Interval.SelectedIndex=[array]::IndexOf(@(15,30,60,120,240),$script:settings.CheckIntervalMinutes)
    $startup=& "$PSScriptRoot/manage-startup.ps1" -Action status -PassThru
    $script:ui.Startup.Checked=$startup.Enabled
    $script:ui.Startup.add_Click({
        try {
            $action=if ($script:ui.Startup.Checked) {'enable'} else {'disable'}
            $state=& "$script:Root/manage-startup.ps1" -Action $action -PassThru
            $script:ui.Startup.Checked=$state.Enabled
            Write-ManagerLog "Autostart: $($state.Enabled). $($state.Detail)"
        } catch {
            $script:ui.Startup.Checked=-not $script:ui.Startup.Checked
            Write-ManagerLog "Autostart kunne ikke ændres: $($_.Exception.Message)"
            [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Autostart')
        }
    })
    $script:ui.Notifications.add_CheckedChanged({$script:settings.Notifications=$script:ui.Notifications.Checked; Save-ManagerJson $script:SettingsPath $script:settings})
    $script:ui.Interval.add_SelectedIndexChanged({
        $script:settings.CheckIntervalMinutes=@(15,30,60,120,240)[$script:ui.Interval.SelectedIndex]
        $script:nextCheck=(Get-Date).AddMinutes($script:settings.CheckIntervalMinutes)
        Save-ManagerJson $script:SettingsPath $script:settings; Refresh-Dashboard; Save-RuntimeState
    })
    $script:ui.Form.add_FormClosing({param($sender,$eventArgs)
        if (-not $script:realExit -and $eventArgs.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing) {$eventArgs.Cancel=$true; $sender.Hide(); Save-RuntimeState}
        else {Write-ManagerLog "Vindue afsluttes: $($eventArgs.CloseReason)."; $script:realExit=$true; $script:appContext.ExitThread()}
    })
    $script:notify=[Windows.Forms.NotifyIcon]::new(); $script:notify.Icon=$script:ui.Form.Icon; $script:notify.Text='AI Manager'; $script:notify.Visible=$true
    $script:notify.add_MouseClick({param($sender,$eventArgs) if ($eventArgs.Button -eq 'Left') {Show-Dashboard}})
    $script:menu=[Windows.Forms.ContextMenuStrip]::new()
    $open=[Windows.Forms.ToolStripMenuItem]::new('Åbn AI Manager'); $open.add_Click({Show-Dashboard}); [void]$script:menu.Items.Add($open)
    [void]$script:menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    foreach ($pair in @(@('check','Tjek nu'),@('all','Opdatér alle'),@('all_clis',"Opdatér CLI'er"),@('all_apps','Opdatér desktop-apps'))) {
        $item=[Windows.Forms.ToolStripMenuItem]::new($pair[1]); $item.Tag=$pair[0]
        $item.add_Click({param($sender,$eventArgs) if ($sender.Tag -eq 'check') {Start-AsyncCheck} else {Start-AsyncUpdate $sender.Tag}})
        [void]$script:menu.Items.Add($item)
    }
    [void]$script:menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
    $preview=[Windows.Forms.ToolStripMenuItem]::new('Test notifikation')
    $preview.add_Click({Queue-ManagerNotification 'AI Manager' 'Notifikationer med eget navn og ikon. Åbn oversigten med knappen nedenfor.' 'preview'})
    [void]$script:menu.Items.Add($preview)
    $exit=[Windows.Forms.ToolStripMenuItem]::new('Afslut AI Manager'); $exit.add_Click({Request-ManagerExit}); [void]$script:menu.Items.Add($exit)
    $script:notify.ContextMenuStrip=$script:menu
    if (Test-Path -LiteralPath $script:LogFile) {$script:ui.Log.Text=(Get-Content -LiteralPath $script:LogFile -Tail 120) -join "`r`n"; $script:ui.Log.AppendText("`r`n")}
    $script:startedAt=(Get-Date).ToString('o')
    $script:poll=[Windows.Forms.Timer]::new(); $script:poll.Interval=250
    $script:poll.add_Tick({
        try {
            if ($script:ShowEvent.WaitOne(0)) {Show-Dashboard}
            if ($script:ExitEvent.WaitOne(0)) {Request-ManagerExit -Reason 'Kommandolinje'; if ($script:realExit) {return}}
            Complete-ManagerWork
            Read-ManagerWorkEvents
            Complete-ReleaseNotesWork
            Complete-ManagerNotification
            if (-not $script:work -and (Get-Date) -ge $script:nextCheck) {Start-AsyncCheck}
        } catch {Write-ManagerLog "Programfejl: $($_.Exception.Message)"}
    })
    $script:appContext=[Windows.Forms.ApplicationContext]::new()
    # Creating a handle keeps UI callbacks available while starting in the tray.
    [void]$script:ui.Form.Handle
    $script:nextCheck=(Get-Date).AddSeconds(2)
    if (-not $StartMinimized) {Show-Dashboard}
    $script:poll.Start(); Refresh-Dashboard; Save-RuntimeState
    Write-ManagerLog "AI Manager 3.2.0 startet · PID $PID · minimeret=$StartMinimized · interval=$($script:settings.CheckIntervalMinutes) min."
    [Windows.Forms.Application]::Run($script:appContext)
} catch {
    Write-ManagerLog "FATAL: $($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
    throw
} finally {
    if ($script:poll) {$script:poll.Stop(); $script:poll.Dispose()}
    if ($script:work) {$script:work.PowerShell.Stop(); $script:work.PowerShell.Dispose()}
    if ($script:releaseWork) {$script:releaseWork.PowerShell.Stop(); $script:releaseWork.PowerShell.Dispose()}
    if ($script:toastWork) {$script:toastWork.PowerShell.Stop(); $script:toastWork.PowerShell.Dispose()}
    if ($script:notify) {$script:notify.Visible=$false; $script:notify.Dispose()}
    if ($script:menu) {$script:menu.Dispose()}
    if ($script:ui) {$script:ui.Tooltip.Dispose(); $script:ui.Form.Dispose()}
    if ($script:appContext) {$script:appContext.Dispose()}
    Save-ManagerJson $script:RuntimePath @{Version='3.2.0';PID=$PID;StoppedAt=(Get-Date).ToString('o');Visible=$false;Busy=$false}
    $script:ShowEvent.Dispose(); $script:ExitEvent.Dispose(); $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose()
}
