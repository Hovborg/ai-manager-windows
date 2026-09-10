# ASCII source: Windows PowerShell 5.1 supplies built-in WinRT support.
# Message/XML is UTF-8 data, passed as Base64, never evaluated as code.
param(
    [ValidateSet('Show','History')][string]$Action='Show',
    [string]$XmlBase64,
    [ValidateSet('updates','result','preview')][string]$Tag='updates'
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$appId='Hovborg.AIManager'
[void][Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom.XmlDocument,ContentType=WindowsRuntime]
if ($Action -eq 'History') {
    $entries=@([Windows.UI.Notifications.ToastNotificationManager]::History.GetHistory($appId) | ForEach-Object {
        [pscustomobject]@{Tag=$_.Tag;Group=$_.Group;Xml=$_.Content.GetXml()}
    })
    ConvertTo-Json -InputObject $entries -Depth 4 -Compress
    exit 0
}
if (-not $XmlBase64) {throw 'Notification XML is required.'}
$xmlText=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($XmlBase64))
$xml=[Windows.Data.Xml.Dom.XmlDocument]::new()
$xml.LoadXml($xmlText)
$notifier=[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
$toast=[Windows.UI.Notifications.ToastNotification]::new($xml)
$toast.Tag=$Tag; $toast.Group='manager'; $toast.ExpirationTime=[DateTimeOffset]::Now.AddDays(1)
$notifier.Show($toast)
# For a new unpackaged app, Setting is unavailable until its first Show call.
# Show itself respects Windows notification preferences; no setting is overridden.
$setting=[string]$notifier.get_Setting()
[pscustomobject]@{Success=($setting -eq 'Enabled');AppId=$appId;Setting=$setting;Tag=$Tag} | ConvertTo-Json -Compress
