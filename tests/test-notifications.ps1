$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-notifications.ps1"
$title='Codex & Claude <klar>'
$message='Æ, ø og å bevares. "C:\Program Files\App" er kun tekst.'
[xml]$xml=New-ManagerToastXml $title $message 'C:\Icons\ai icon.png'
$nodes=$xml.SelectNodes('/toast/visual/binding/text')
if ($nodes[0].InnerText -cne $title -or $nodes[1].InnerText -cne $message) {throw 'Notification text was not preserved/escaped'}
if ($xml.toast.activationType -ne 'protocol' -or $xml.toast.launch -ne 'hovborg-ai-manager:open') {throw 'Body activation must only open manager'}
if ($xml.toast.actions.action[0].arguments -ne 'hovborg-ai-manager:open' -or $xml.toast.actions.action[0].activationType -ne 'protocol') {throw 'Button can launch wrong target'}
if ($xml.toast.actions.action[1].activationType -ne 'system' -or $xml.toast.actions.action[1].arguments -ne 'dismiss') {throw 'Dismiss action incorrect'}
if ($xml.toast.visual.binding.image.src -ne 'file:///C:/Icons/ai%20icon.png') {throw 'Local icon URI not encoded'}
if ($xml.toast.audio.silent -ne 'true') {throw 'Notification ignores quiet behavior'}
$root='C:\AI Manager\project'
$registration=Get-ManagerNotificationRegistration $root 'C:\Icons\ai.png'
if ($registration.DisplayName -ne 'AI Manager' -or $registration.AppId -ne 'Hovborg.AIManager') {throw 'PowerShell is still the notification identity'}
if ($registration.Command.Contains('%1') -or $registration.Command -notlike '*"C:\AI Manager\project\start-tray.vbs"') {throw 'Protocol must use only a quoted fixed launcher, no URL input'}
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../ai-tray-updater.ps1'),[ref]$null,[ref]$null)
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Queue-ManagerNotification'},$true)
Invoke-Expression $definition.Extent.Text
$script:settings=@{Notifications=$true;LastNotification=''}
$script:notificationIdentity=@{IconPath='C:\Icons\ai.png'}
$script:toastQueue=[Collections.Generic.Queue[object]]::new(); $script:toastWork=$null
function Write-ManagerLog {param($Message) throw $Message}
Queue-ManagerNotification 'Update' 'Version 2' 'updates' 'codex:2.0.0'
Queue-ManagerNotification 'Update' 'Version 2' 'updates' 'codex:2.0.0'
if ($script:toastQueue.Count -ne 1) {throw 'Repeated check enqueued duplicate notification'}
$script:toastWork=$script:toastQueue.Dequeue()
Queue-ManagerNotification 'Update' 'Version 2' 'updates' 'codex:2.0.0'
if ($script:toastQueue.Count -ne 0) {throw 'Active notification enqueued again'}
$script:toastWork=$null
Queue-ManagerNotification 'Update' 'Version 2' 'updates' 'codex:2.0.0'
if ($script:toastQueue.Count -ne 1) {throw 'Failed delivery cannot be retried'}
$script:settings.LastNotification='codex:3.0.0'
Queue-ManagerNotification 'Update' 'Version 3' 'updates' 'codex:3.0.0'
if ($script:toastQueue.Count -ne 1) {throw 'Delivered notification enqueued again'}
$script:settings.Notifications=$false
Queue-ManagerNotification 'Update' 'Version 4' 'updates' 'codex:4.0.0'
if ($script:toastQueue.Count -ne 1) {throw 'Disabled notifications still queued'}
Write-Output 'PASS: branded identity, escaped Danish XML, local icon, fixed activation, dismiss, quiet audio'
Write-Output 'PASS: queued/active/delivered deduplication, retry after failure, disabled notifications'
