# Real UI-thread coordinator + BeginInvoke/EndInvoke + subprocess; only external tool boundaries are fixtures.
$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. "$testRoot/updater-core.ps1"
. "$testRoot/updater-history.ps1"
. "$testRoot/updater-features.ps1"
$script:StateDirectory=Join-Path $testRoot ('artifacts/manager-work-'+[guid]::NewGuid().ToString('N'))
$script:Root=Join-Path $script:StateDirectory 'worker'
[void][IO.Directory]::CreateDirectory($script:Root)
$fixture=@'
. '__CORE__'
$script:actualProcess=${function:Invoke-ToolProcess}
function Get-ToolCatalog {@{Key='codex';Name='Synthetic tool';Type='CLI';Path='fixture';Source='synthetic'}}
function Invoke-ToolProcess {
    param($FilePath,$Arguments,$TimeoutSeconds)
    if ($FilePath -ne 'fixture' -or ($Arguments -join ',') -ne 'update') {throw 'Unexpected external operation'}
    & $script:actualProcess (Get-Process -Id $PID).Path @('-NoProfile','-Command','[Console]::Write("working-before-exit"); Start-Sleep -Milliseconds 1100; [Console]::Write(" complete"); exit 0') 10
}
function Get-OneToolStatus {param($Tool) New-ToolStatus $Tool '2.0.0' '2.0.0' 'fixture' ''}
'@
[IO.File]::WriteAllText((Join-Path $script:Root 'updater-core.ps1'),$fixture.Replace('__CORE__',(Join-Path $testRoot 'updater-core.ps1').Replace("'","''")))
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $testRoot 'ai-tray-updater.ps1'),[ref]$null,[ref]$null)
foreach ($name in @('Start-ManagerWork','Complete-ManagerWork')) {
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$script:ui=@{Status=@{Text=''}};$script:notify=@{Text=''};$script:settings=@{CheckIntervalMinutes=60;Notifications=$false}
$script:work=$null;$script:operation=$null;$script:history=@();$script:followups=0;$script:rendered=@();$script:messages=@();$script:nextCheck=Get-Date
function Get-ToolCatalog {@{Key='codex';Name='Synthetic tool';Type='CLI';Path='fixture';Source='synthetic'}}
function Refresh-Dashboard {}
function Save-RuntimeState {}
function Refresh-SelectedReleaseNotes {}
function Start-AsyncCheck {$script:followups++}
function Set-ManagerHistoryView($UI,$Entries) {}
function Set-ManagerOperationView($UI,$Operation) {if ($Operation) {$script:rendered+=@{Output=$Operation.Output;Phase=$Operation.Phase;Elapsed=$Operation.ElapsedSeconds}}}
function Write-ManagerLog([string]$Message) {$script:messages+=$Message}
$script:status=[ordered]@{codex=New-ToolStatus (Get-ToolCatalog) '1.0.0' '2.0.0' 'fixture' ''}
Start-ManagerWork 'update' @('codex')
if (@(Get-ManagerHistory $script:StateDirectory)[0].Outcome -ne 'Pending') {throw 'Attempt was not durable when worker started'}
$deadline=(Get-Date).AddSeconds(12);$early=$false
while ($script:work -and -not $script:work.Handle.IsCompleted -and (Get-Date) -lt $deadline) {
    Read-ManagerWorkEvents
    if ($script:operation.Output -match 'working-before-exit') {$early=$true}
    Start-Sleep -Milliseconds 40
}
if (-not $script:work.Handle.IsCompleted) {throw 'Worker did not finish'}
$ownedPowerShell=$script:work.PowerShell
Complete-ManagerWork
$entries=@(Get-ManagerHistory $script:StateDirectory)
if (-not $early -or $script:work -or $script:operation -or $script:followups -ne 1 -or $entries.Count -ne 1 -or $entries[0].Outcome -ne 'Success' -or $entries[0].After -ne '2.0.0' -or $entries[0].Output -notmatch 'complete') {throw 'Actual coordinator failed progress, history deduplication, verified result or follow-up'}
$disposed=$false;try {$null=$ownedPowerShell.AddScript('1')} catch [ObjectDisposedException] {$disposed=$true}
if (-not $disposed) {throw 'Completed runspace was not disposed'}
# A storage failure must not strand Busy=true or leak the completed worker.
Start-ManagerWork 'update' @('codex')
$deadline=(Get-Date).AddSeconds(12)
while (-not $script:work.Handle.IsCompleted -and (Get-Date) -lt $deadline) {Start-Sleep -Milliseconds 40}
if (-not $script:work.Handle.IsCompleted) {throw 'Second worker did not finish'}
$ownedPowerShell=$script:work.PowerShell
[IO.File]::WriteAllText((Join-Path $script:StateDirectory 'history.json'),'corrupt')
Complete-ManagerWork
if ($script:work -or $script:operation -or $script:followups -ne 2 -or -not @($script:messages | Where-Object {$_ -like 'Historik kunne ikke afsluttes:*'}).Count) {throw 'History failure stranded manager or went unreported'}
$disposed=$false;try {$null=$ownedPowerShell.AddScript('1')} catch [ObjectDisposedException] {$disposed=$true}
if (-not $disposed) {throw 'Storage failure leaked runspace'}
$ownedPowerShell=[powershell]::Create();[void]$ownedPowerShell.AddScript('[pscustomobject]@{Id="missing"}')
$handle=$ownedPowerShell.BeginInvoke();while (-not $handle.IsCompleted) {Start-Sleep -Milliseconds 20}
$script:work=@{PowerShell=$ownedPowerShell;Handle=$handle;Kind='update';Events=[Collections.Concurrent.ConcurrentQueue[object]]::new();Attempts=@{}}
function Write-ManagerLog([string]$Message) {throw 'Synthetic log write failure'}
try {Complete-ManagerWork} catch {}
$disposed=$false;try {$null=$ownedPowerShell.AddScript('1')} catch [ObjectDisposedException] {$disposed=$true}
if ($script:work -or -not $disposed) {$ownedPowerShell.Dispose();throw 'Simultaneous history and log failure leaked runspace or stranded Busy'}
Write-Output "PASS: actual coordinator, early progress, persistent attempt, verified result, idempotent history, follow-up and cleanup on storage failure. Evidence: $script:StateDirectory"
