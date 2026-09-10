# Windows-native app notifications. Only the fixed manager launcher can be activated.
function Get-ManagerNotificationRegistration {
    param([string]$Root, [string]$IconPath)
    [pscustomobject]@{
        AppId='Hovborg.AIManager'; DisplayName='AI Manager'; IconPath=$IconPath
        Protocol='hovborg-ai-manager'
        Command=('"{0}" "{1}"' -f (Join-Path $env:SystemRoot 'System32\wscript.exe'),(Join-Path $Root 'start-tray.vbs'))
        StubClsid='{A39F4A34-7B86-4C5C-B564-BD160C2DB19B}'
    }
}

function Register-ManagerNotificationIdentity {
    param([string]$Root, [string]$StateDirectory)
    $iconPath=Join-Path $StateDirectory 'notification-icon.png'
    $info=Get-ManagerNotificationRegistration $Root $iconPath
    $appKey="HKCU:\Software\Classes\AppUserModelId\$($info.AppId)"
    $protocolKey="HKCU:\Software\Classes\$($info.Protocol)"
    $shortcutPath=Join-Path ([Environment]::GetFolderPath('Programs')) 'AI Manager.lnk'
    $wsh=New-Object -ComObject WScript.Shell
    try {
        $shortcut=$wsh.CreateShortcut($shortcutPath)
        $launcher=Join-Path $Root 'start-tray.vbs'
        $target=Join-Path $env:SystemRoot 'System32\wscript.exe'
        if ((Test-Path -LiteralPath $shortcutPath) -and ($shortcut.TargetPath -ne $target -or $shortcut.Arguments -ne ('"'+$launcher+'"'))) {throw 'Startmenugenvejen AI Manager findes med et andet mål og er ikke ændret.'}
    } finally {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)}
    foreach ($key in @($appKey,$protocolKey)) {
        if (Test-Path -LiteralPath $key) {
            $existing=Get-ItemProperty -LiteralPath $key
            if ($existing.ManagedBy -ne 'Hovborg.AIManager') {throw "Registreringen '$key' findes allerede og er ikke ejet af AI Manager."}
        }
    }
    [void][IO.Directory]::CreateDirectory($StateDirectory)
    if (-not (Test-Path -LiteralPath $iconPath)) {
        Add-Type -AssemblyName System.Drawing
        $icon=[Drawing.Icon]::new((Join-Path $Root 'ai-updater.ico'),64,64)
        $bitmap=$icon.ToBitmap()
        try {$bitmap.Save($iconPath,[Drawing.Imaging.ImageFormat]::Png)} finally {$bitmap.Dispose(); $icon.Dispose()}
    }
    [void](New-Item -Path $appKey -Force)
    foreach ($pair in @(@('ManagedBy','Hovborg.AIManager'),@('DisplayName',$info.DisplayName),@('IconUri',$info.IconPath),@('IconBackgroundColor','FF101923'),@('CustomActivator',$info.StubClsid))) {
        [void](New-ItemProperty -LiteralPath $appKey -Name $pair[0] -Value $pair[1] -PropertyType String -Force)
    }
    # Protocol activation is sufficient; no COM server, elevation or arbitrary URL arguments.
    [void](New-Item -Path "$protocolKey\shell\open\command" -Force)
    Set-Item -LiteralPath $protocolKey -Value 'URL:AI Manager'
    [void](New-ItemProperty -LiteralPath $protocolKey -Name 'URL Protocol' -Value '' -PropertyType String -Force)
    [void](New-ItemProperty -LiteralPath $protocolKey -Name 'ManagedBy' -Value 'Hovborg.AIManager' -PropertyType String -Force)
    Set-Item -LiteralPath "$protocolKey\shell\open\command" -Value $info.Command
    $wsh=New-Object -ComObject WScript.Shell
    try {
        $shortcut=$wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath=$target; $shortcut.Arguments='"'+$launcher+'"'; $shortcut.WorkingDirectory=$Root
        $shortcut.Description='AI Manager'; $shortcut.IconLocation=Join-Path $Root 'ai-updater.ico'; $shortcut.Save()
    } finally {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)}
    if (-not ('Hovborg.AIManager.NotificationShortcut' -as [type])) {Add-Type -Path (Join-Path $Root 'notification-shortcut.cs')}
    [Hovborg.AIManager.NotificationShortcut]::SetIdentity($shortcutPath,$info.AppId,[guid]$info.StubClsid)
    if ([Hovborg.AIManager.NotificationShortcut]::ReadAppId($shortcutPath) -ne $info.AppId) {throw 'Startmenugenvejens notifikationsidentitet kunne ikke verificeres.'}
    $actual=Get-ItemProperty -LiteralPath $appKey
    $command=(Get-Item -LiteralPath "$protocolKey\shell\open\command").GetValue('')
    if ($actual.DisplayName -ne 'AI Manager' -or $actual.IconUri -ne $iconPath -or $command -ne $info.Command) {throw 'Windows-notifikationsidentiteten kunne ikke verificeres.'}
    return $info
}

function New-ManagerToastXml {
    param([string]$Title, [string]$Message, [string]$IconPath)
    $document=[xml]'<toast activationType="protocol" launch="hovborg-ai-manager:open" duration="short"><visual><binding template="ToastGeneric"><text/><text hint-maxLines="3"/><image placement="appLogoOverride" hint-crop="circle"/></binding></visual><actions><action activationType="protocol" arguments="hovborg-ai-manager:open"/><action activationType="system" arguments="dismiss" content="Luk"/></actions><audio silent="true"/></toast>'
    $textNodes=$document.SelectNodes('/toast/visual/binding/text')
    $textNodes[0].InnerText=$Title; $textNodes[1].InnerText=$Message
    $document.SelectSingleNode('/toast/visual/binding/image').SetAttribute('src',([uri]$IconPath).AbsoluteUri)
    $document.SelectSingleNode('/toast/actions/action').SetAttribute('content','Åbn AI Manager')
    return $document.OuterXml
}

function Send-ManagerToast {
    param([string]$Root,[string]$Xml,[ValidateSet('updates','result','preview')][string]$Tag='updates')
    $helper=Join-Path $Root 'windows-toast.ps1'
    $hostPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Xml))
    $result=Invoke-ToolProcess $hostPath @('-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',$helper,'-Action','Show','-XmlBase64',$encoded,'-Tag',$Tag) 15
    if (-not $result.Success) {throw "Windows-notifikation fejlede: $($result.Output)"}
    return ($result.Output | ConvertFrom-Json -ErrorAction Stop)
}
