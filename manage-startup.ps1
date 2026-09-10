#requires -Version 7.0
[CmdletBinding()]
param([ValidateSet('status','enable','disable')][string]$Action='status', [switch]$PassThru)
$ErrorActionPreference='Stop'
$taskName='AI-CLI-Updater'
$description='Hovborg AI Manager: start i systembakken ved brugerens Windows-login.'
$scriptPath=Join-Path $PSScriptRoot 'ai-tray-updater.ps1'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$userSid=$identity.User.Value
function Resolve-StartupIdentitySid {
    param([string]$Account)
    if (-not $Account) {return ''}
    try {return ([Security.Principal.SecurityIdentifier]::new($Account)).Value} catch {}
    try {return ([Security.Principal.NTAccount]::new($Account)).Translate([Security.Principal.SecurityIdentifier]).Value} catch {return ''}
}
$pwsh=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
if (-not (Test-Path -LiteralPath $pwsh)) {$pwsh=Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'}
$arguments="-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -StartMinimized"
$legacy=Join-Path ([Environment]::GetFolderPath('Startup')) 'AI-CLI-Updater.lnk'
$task=Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
if ($Action -ne 'status' -and $task -and $task.Description -ne $description) {throw "Den planlagte opgave '$taskName' tilhører en anden opsætning. Den er ikke ændret."}
if ($Action -ne 'status' -and $task) {
    $ownerSid=Resolve-StartupIdentitySid ([string]$task.Principal.UserId)
    $triggerOwners=@($task.Triggers | ForEach-Object {Resolve-StartupIdentitySid ([string]$_.UserId)})
    if ($ownerSid -ne $userSid -or $triggerOwners.Count -ne 1 -or $triggerOwners[0] -ne $userSid) {
        throw "Den planlagte opgave '$taskName' har ukendt ejerskab eller tilhører en anden bruger. Den er ikke ændret."
    }
}
if ($Action -eq 'enable') {
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) {throw 'PowerShell 7 blev ikke fundet. Installér PowerShell 7 før autostart aktiveres.'}
    $taskAction=New-ScheduledTaskAction -Execute $pwsh -Argument $arguments -WorkingDirectory $PSScriptRoot
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $userSid
    $trigger.Delay='PT15S'
    $principal=New-ScheduledTaskPrincipal -UserId $userSid -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    $definition=New-ScheduledTask -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description $description
    [void](Register-ScheduledTask -TaskName $taskName -TaskPath '\' -InputObject $definition -Force)
} elseif ($Action -eq 'disable' -and $task) {[void](Disable-ScheduledTask -TaskName $taskName -TaskPath '\')}
$task=Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
$valid=$false
if ($task -and $task.Actions -and $task.Triggers -and $task.Actions.Count -eq 1 -and $task.Triggers.Count -eq 1) {
    $actualUser=Resolve-StartupIdentitySid ([string]$task.Principal.UserId)
    $triggerUser=Resolve-StartupIdentitySid ([string]$task.Triggers[0].UserId)
    $valid=$task.Description -eq $description -and $task.Actions.Count -eq 1 -and $task.Actions[0].Execute -eq $pwsh -and $task.Actions[0].Arguments -eq $arguments -and $task.Actions[0].WorkingDirectory -eq $PSScriptRoot -and $actualUser -eq $userSid -and [string]$task.Principal.LogonType -eq 'Interactive' -and [string]$task.Principal.RunLevel -eq 'Limited' -and $task.Triggers.Count -eq 1 -and $task.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and $task.Triggers[0].Enabled -and $triggerUser -eq $userSid -and (Test-Path -LiteralPath $pwsh)
}
$settingsValid=$valid -and $task.Settings.ExecutionTimeLimit -eq 'PT0S' -and [string]$task.Settings.MultipleInstances -eq 'IgnoreNew' -and $task.Settings.RestartCount -eq 3 -and $task.Settings.RestartInterval -eq 'PT1M' -and -not $task.Settings.DisallowStartIfOnBatteries -and -not $task.Settings.StopIfGoingOnBatteries -and $task.Settings.StartWhenAvailable -and $task.Triggers[0].Delay -eq 'PT15S'
$valid=[bool]($valid -and $settingsValid)
$enabled=[bool]($valid -and $task.Settings.Enabled -and [string]$task.State -ne 'Disabled')
if ($Action -eq 'enable' -and -not $enabled) {throw 'Opgaven blev registreret, men kontrol af autostart mislykkedes. Gammel genvej er bevaret.'}
# Move only this app's exact legacy shortcut to a backup after verification.
if (($Action -eq 'enable' -and $enabled) -or $Action -eq 'disable') {
    if (Test-Path -LiteralPath $legacy) {
        $shell=New-Object -ComObject WScript.Shell
        try {
            $shortcut=$shell.CreateShortcut($legacy)
            $expected='"' + (Join-Path $PSScriptRoot 'start-tray.vbs') + '" minimized'
            if ([IO.Path]::GetFileName($shortcut.TargetPath) -ieq 'wscript.exe' -and $shortcut.Arguments -ieq $expected) {
                $backup=Join-Path $env:LOCALAPPDATA 'Hovborg\AI-Manager\startup-backup'
                [void][IO.Directory]::CreateDirectory($backup)
                $backupPath=Join-Path $backup ("AI-CLI-Updater-{0}.lnk" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
                Move-Item -LiteralPath $legacy -Destination $backupPath
            } else {Write-Warning 'Den gamle startgenvej har et andet mål og er bevaret. Kontrollér eventuel dobbeltstart.'}
        } finally {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    }
}
$info=if ($task) {Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\'} else {$null}
$result=[pscustomobject]@{
    Enabled=$enabled; ConfigurationValid=[bool]$valid; TaskName=$taskName
    State=$(if ($task) {[string]$task.State} else {'NotRegistered'})
    Execute=$(if ($task -and $task.Actions) {$task.Actions[0].Execute} else {$null})
    Arguments=$(if ($task -and $task.Actions) {$task.Actions[0].Arguments} else {$null})
    User=$identity.Name; LastRunTime=$info.LastRunTime; LastTaskResult=$info.LastTaskResult
    LegacyShortcutPresent=(Test-Path -LiteralPath $legacy)
    Detail=$(if ($enabled) {'Starter minimeret 15 sekunder efter dit login. Interaktiv bruger; ingen administratorrettigheder.'} else {'Autostart er slået fra, mangler eller stemmer ikke med den forventede konfiguration.'})
}
if ($PassThru) {$result} else {$result | Format-List}
