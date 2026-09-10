param([string]$RenderDialogPath)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
. "$PSScriptRoot/../updater-ui.ps1"
[void][Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2)
[Windows.Forms.Application]::EnableVisualStyles()

$script:checks=0
$script:updates=[Collections.Generic.List[string]]::new()
$script:details=[Collections.Generic.List[string]]::new()
$script:opened=[Collections.Generic.List[string]]::new()
$script:sources=[Collections.Generic.List[string]]::new()
$script:manageClicks=0
function Start-AsyncCheck {$script:checks++}
function Start-AsyncUpdate {param($Target) $script:updates.Add([string]$Target)}
function Show-ToolDetails {param([string]$Key,[switch]$Force) $script:details.Add($Key)}
function Open-ManagerTool {param([string]$Key) $script:opened.Add($Key)}
function Open-ManagerReleaseSource {param([string]$Url) $script:sources.Add($Url)}
function Show-ManagerTools {$script:manageClicks++}
function Refresh-Dashboard {}
function Save-RuntimeState {}
function Invoke-ControlClick {
    param([Windows.Forms.Control]$Control)
    $method=[Windows.Forms.Control].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$method.Invoke($Control,@([EventArgs]::Empty))
}

$catalog=@(
    [pscustomobject]@{Key='zeta_cli';Name='Zeta CLI';Type='CLI';PackageId='Vendor.Zeta';PackageSource='winget';Source='Test';Path=''},
    [pscustomobject]@{Key='alpha_app';Name='Alpha App';Type='App';PackageId='Vendor.Alpha';PackageSource='winget';Source='Test';Path=''},
    [pscustomobject]@{Key='beta_cli';Name='Beta CLI';Type='CLI';PackageId='Vendor.Beta';PackageSource='winget';Source='Test';Path=''},
    [pscustomobject]@{Key='omega_app';Name='Omega App';Type='App';PackageId='Vendor.Omega';PackageSource='msstore';Source='Test';Path=''}
)
$status=[ordered]@{}
foreach($tool in $catalog){$status[$tool.Key]=New-ToolStatus $tool '2.0.0' '2.0.0' '' ''}
$status.omega_app=New-ToolStatus $catalog[3] '1.0.0' '2.0.0' '' ''
$status.omega_app.CanLaunch=$true
$status.alpha_app.CanLaunch=$true
$status.zeta_cli=New-ToolStatus $catalog[0] '1.0.0' '' '' 'Offline'

$script:ui=New-ManagerDashboard $catalog (Join-Path $PSScriptRoot '../ai-updater.ico')
$script:ui.Form.Show()
try {
    if ($script:ui.Form.Text -notmatch '3\.2') {throw 'Dashboard is not version 3.2'}
    foreach($name in @('TypeFilter','ResultSummary','ShowAll','Manage','CardHost','GroupHeaders','HistoryTab','HistoryGrid','HistoryOutput','OperationPanel','OperationTitle','OperationMeta','OperationOutput','RangePanel')) {
        if (-not $script:ui.ContainsKey($name)) {throw "Missing UI return field: $name"}
    }
    if (($script:ui.TypeFilter.Items -join ',') -ne 'Alle typer,Apps,CLI') {throw 'Type filter choices are wrong'}
    $script:ui.Manage.PerformClick(); if($script:manageClicks -ne 1){throw 'Manage callback is not wired'}

    Set-DashboardStatus $script:ui $status $false
    [Windows.Forms.Application]::DoEvents()
    if ($script:ui.ResultSummary.Text -notmatch '^Viser 4 af 4') {throw 'Initial result count is wrong'}
    if (($script:ui.GroupHeaders.Keys|Sort-Object)-join ',' -ne 'Apps,CLI') {throw 'Apps/CLI groups are missing'}
    $order=@($script:ui.CardHost.Controls | Where-Object {$_.Tag -and $script:ui.Cards.ContainsKey([string]$_.Tag)} | ForEach-Object {[string]$_.Tag})
    if (($order -join ',') -ne 'omega_app,alpha_app,beta_cli,zeta_cli') {throw "Grouping/update-first/name order is wrong: $($order -join ',')"}

    $script:ui.Search.Text='omega'; $script:ui.TypeFilter.SelectedIndex=1; $script:ui.Filter.SelectedIndex=1
    Set-DashboardStatus $script:ui $status $false
    if ($script:ui.ResultSummary.Text -notmatch '^Viser 1 af 4' -or $script:ui.ResultSummary.Text -notmatch 'skjult') {throw 'Filtered result explanation is missing'}
    $script:ui.ShowAll.PerformClick()
    if ($script:ui.Search.Text -or $script:ui.TypeFilter.SelectedIndex -ne 0 -or $script:ui.Filter.SelectedIndex -ne 0) {throw 'Show all did not reset all navigation filters'}
    Invoke-ControlClick $script:ui.Metrics.Current
    if ($script:ui.Filter.SelectedIndex -ne 3 -or $script:ui.Search.Text -or $script:ui.TypeFilter.SelectedIndex -ne 0) {throw 'Current metric click does not match its count'}
    Invoke-ControlClick $script:ui.Metrics.Updates; if($script:ui.Filter.SelectedIndex -ne 1){throw 'Update metric is not clickable'}
    Invoke-ControlClick $script:ui.Metrics.Attention; if($script:ui.Filter.SelectedIndex -ne 2){throw 'Attention metric is not clickable'}

    $status.omega_app.State='NeedsClose'; $status.omega_app.HasUpdate=$true
    Set-DashboardStatus $script:ui $status $false
    if ($script:ui.Metrics.Updates.Text -ne '1' -or $script:ui.Metrics.Attention.Text -ne '2' -or $script:ui.Update.Enabled) {throw 'NeedsClose counts or bulk guard regressed'}

    if ($script:ui.Cards.alpha_app.ButtonOpen.AccessibleName -ne 'Åbn Alpha App') {throw 'Open app accessibility name is wrong'}
    if ($script:ui.Cards.beta_cli.ButtonOpen) {throw 'CLI received an Open app action'}
    $script:ui.Filter.SelectedIndex=0; Set-DashboardStatus $script:ui $status $false
    if (-not $script:ui.Cards.alpha_app.ButtonOpen.Enabled) {throw 'Launchable app action is disabled'}
    $script:ui.Cards.alpha_app.ButtonOpen.PerformClick()
    if ($script:opened[$script:opened.Count-1] -ne 'alpha_app') {throw 'Open app action lost sender.Tag'}
    Set-DashboardStatus $script:ui $status $true;if($script:ui.Cards.alpha_app.ButtonOpen.Enabled){throw 'Open app action ignores busy guard'};Set-DashboardStatus $script:ui $status $false

    $script:ui.Filter.SelectedIndex=2
    $reduced=@($catalog | Where-Object Key -ne 'zeta_cli')
    $initialHeight=$script:ui.Cards.omega_app.Card.Height
    Set-ManagerDashboardCatalog $script:ui $reduced
    if ([Math]::Abs($script:ui.Cards.omega_app.Card.Height-$initialHeight) -gt 2) {throw 'Catalog rebuild changed the DPI-scaled card height'}
    if ($script:ui.Cards.Count -ne 3 -or $script:ui.Cards.ContainsKey('zeta_cli') -or $script:ui.Filter.SelectedIndex -ne 2) {throw 'Catalog rebuild did not replace cards or preserve navigation state'}
    Set-ManagerDashboardCatalog $script:ui @()
    if ($script:ui.Cards.Count -ne 0 -or -not $script:ui.Empty.Visible -or $script:ui.Empty.Text -notmatch 'Administrer' -or -not $script:ui.Manage.Enabled) {throw 'Empty catalog has no usable recovery path'}
    Set-ManagerDashboardCatalog $script:ui $catalog

    $bundle=[pscustomobject]@{
        Installed=[pscustomobject]@{Version='1.0';Body='Installed';State='Ready';Message='';SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$true}
        Available=[pscustomobject]@{Version='2.0';Body='Available';State='Ready';Message='';SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$true}
        Range=[pscustomobject]@{Version='1.0 → 2.0';FromVersion='1.0';ToVersion='2.0';ReleaseCount=4;Complete=$false;Body='Four releases';State='Ready';Message='Kun delvist dækket';SourceUrl='https://example.test/range';PublishedAt='';RetrievedAt='2026-09-10T09:00:00Z';IsStale=$true;ExactVersion=$true}
    }
    Set-ReleaseNotesView $script:ui $status.omega_app $bundle $false
    if ($script:ui.RangePanel.Version.Text -notmatch '1\.0.*2\.0' -or $script:ui.RangePanel.Body.Text -notmatch 'Four releases' -or $script:ui.RangePanel.Source.AccessibleName -notmatch 'NYT SIDEN') {throw 'Range notes or source accessibility are missing'}
    if ($script:ui.RangePanel.Meta.Text -notmatch '4 udgivelser' -or $script:ui.RangePanel.Meta.Text -notmatch 'Ufuldstændig' -or $script:ui.RangePanel.Meta.Text -notmatch 'Ældre cache') {throw 'Range completeness/freshness is unclear'}
    $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab;$script:ui.ReleaseTabs.SelectedIndex=1;[Windows.Forms.Application]::DoEvents()
    $script:ui.RangePanel.Source.PerformClick(); if($script:sources[$script:sources.Count-1] -ne 'https://example.test/range'){throw 'Range source callback lost URL'}
    $currentRange=[pscustomobject]@{FromVersion='2.0';ToVersion='2.0';State='Unavailable';Message='Den installerede version er den nyeste kendte.';Body='';ReleaseCount=0;Complete=$false}
    Set-ReleaseNotesView $script:ui $status.omega_app ([pscustomobject]@{Installed=$bundle.Installed;Available=$bundle.Available;Range=$currentRange}) $false
    if ($script:ui.DetailsStatus.Text -match 'kunne ikke hentes') {throw 'A current version was described as a failed source lookup'}
    Set-ReleaseNotesView $script:ui $status.omega_app ([pscustomobject]@{Installed=$bundle.Installed;Available=$bundle.Available;Range=$null}) $false
    if ($script:ui.RangePanel.Version.Text -ne 'Afventer' -or $script:ui.RangePanel.Body.Text -notmatch 'når intervallet er beregnet') {throw 'Temporary missing range is presented as a hard failure'}
    Set-ReleaseNotesView $script:ui $null $null $false
    $resetPanels=@($script:ui.ReleasePanels.Installed,$script:ui.ReleasePanels.Available,$script:ui.RangePanel)
    if ($script:ui.DetailsTitle.Text -ne 'Versionsnyt' -or $script:ui.DetailsRefresh.Enabled -or $script:ui.DetailsRefresh.Tag -or @($resetPanels|Where-Object {$_.Version.Text-ne'—'-or$_.Body.Text-notmatch'^Vælg Se nyheder'}).Count) {throw 'Removed selected tool leaves stale release-note state'}

    $entries=@(
        [pscustomobject]@{Id='old';Key='beta_cli';Name='Beta CLI';StartedAt='2026-09-10T10:00:00Z';CompletedAt='2026-09-10T10:00:30Z';Before='1';After='1';TargetVersion='2';Success=$false;Outcome='Failed';Output='Synthetic failure'},
        [pscustomobject]@{Id='detected';Key='alpha_app';Name='Alpha App';StartedAt='';CompletedAt='2026-09-10T12:00:00Z';Before='1';After='2';TargetVersion='';Success=$false;Outcome='Detected';Output='External change detected'},
        [pscustomobject]@{Id='success';Key='omega_app';Name='Omega App';StartedAt='2026-09-10T11:00:00Z';CompletedAt='2026-09-10T11:01:00Z';Before='1';After='2';TargetVersion='2';Success=$true;Outcome='Success';Output='Updated'},
        [pscustomobject]@{Id='pending';Key='zeta_cli';Name='Zeta CLI';StartedAt='2026-09-10T09:00:00Z';CompletedAt='';Before='1';After='';TargetVersion='2';Success=$false;Outcome='Pending';Output='Waiting'}
    )
    Set-ManagerHistoryView $script:ui $entries
    if ($script:ui.HistoryGrid.Rows.Count -ne 4 -or $script:ui.HistoryGrid.Rows[0].Cells['Program'].Value -ne 'Alpha App' -or $script:ui.HistoryGrid.Rows[3].Cells['Result'].Value -ne 'Afventer') {throw 'History order or pending state is wrong'}
    if ($script:ui.HistoryGrid.Rows[0].Cells['Time'].Value -notmatch 'Registreret' -or $script:ui.HistoryGrid.Rows[0].Cells['Result'].Value -ne 'Registreret ændring') {throw 'Detected history invents update semantics'}
    if ($script:ui.HistoryOutput.Text -ne 'External change detected') {throw 'Newest detected entry output is not selected'}
    $script:ui.HistoryGrid.ClearSelection(); $script:ui.HistoryGrid.Rows[2].Selected=$true
    [Windows.Forms.Application]::DoEvents()
    if ($script:ui.HistoryOutput.Text -ne 'Synthetic failure') {throw 'History output is not separate/selectable'}

    Set-ManagerOperationView $script:ui ([pscustomobject]@{Name='Omega App';Phase='Installerer';Message='Kontrollerer version';ElapsedSeconds=67;Index=2;Total=4;Output=('x'*13000)})
    if (-not $script:ui.OperationPanel.Visible -or $script:ui.OperationTitle.Text -notmatch 'Omega App' -or $script:ui.OperationMeta.Text -notmatch '01:07' -or $script:ui.OperationMeta.Text -notmatch '2 af 4') {throw 'Live operation summary is incomplete'}
    if (-not $script:ui.OperationOutput.ReadOnly -or $script:ui.OperationOutput.Text.Length -gt 12000 -or $script:ui.OperationMeta.Text -match '%') {throw 'Live operation output/percentage contract failed'}
    Set-ManagerOperationView $script:ui $null; if($script:ui.OperationPanel.Visible){throw 'Null operation did not hide status box'}

    $dpiFactor=$script:ui.Form.DeviceDpi/96.0
    foreach($width in @(880,1060,1320)){
        $script:ui.Form.Width=[int]($width*$dpiFactor); [Windows.Forms.Application]::DoEvents()
        if($script:ui.CardPanel.HorizontalScroll.Visible){throw "Horizontal overview scroll at $width"}
    }
} finally {$script:ui.Tooltip.Dispose();$script:ui.Form.Dispose()}

$dialogCatalog=@(
    [pscustomobject]@{Key='codex';Name='Codex CLI';Type='CLI';PackageId='OpenAI.Codex';PackageSource='winget'},
    [pscustomobject]@{Key='codex_app';Name='ChatGPT / Codex';Type='App';PackageId='9NT1R1C2HH7J';PackageSource='msstore'}
)
$configuration=[pscustomobject]@{HiddenKeys=@('codex');CustomTools=@([pscustomobject]@{Key='custom_existing';Name='Existing custom';Type='App';PackageId='Vendor.Existing';PackageSource='winget';LaunchName='Existing'})}
$timer=[Windows.Forms.Timer]::new();$timer.Interval=100
$timer.add_Tick({
    $dialog=[Windows.Forms.Application]::OpenForms|Where-Object AccessibleName -eq 'Administrer værktøjer'|Select-Object -First 1
    if(-not $dialog){return};$timer.Stop()
    if($RenderDialogPath){$scale=1.75/($dialog.DeviceDpi/96.0);if([Math]::Abs($scale-1)-gt0.01){$dialog.Scale([Drawing.SizeF]::new($scale,$scale));[Windows.Forms.Application]::DoEvents()};[void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($RenderDialogPath))));$bitmap=[Drawing.Bitmap]::new($dialog.Width,$dialog.Height);$dialog.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save([IO.Path]::GetFullPath($RenderDialogPath),[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose()}
    $list=$dialog.Controls.Find('CatalogList',$true)[0];if($list.Items.Count-ne 2-or $list.GetItemChecked(0)){throw 'Hidden catalog state is wrong'};$list.SetItemChecked(0,$true)
    $dialog.Controls.Find('CustomName',$true)[0].Text='My Tool';$dialog.Controls.Find('CustomType',$true)[0].SelectedItem='App';$dialog.Controls.Find('CustomPackageId',$true)[0].Text='Vendor.MyTool';$dialog.Controls.Find('CustomPackageSource',$true)[0].SelectedItem='msstore';$dialog.Controls.Find('CustomLaunchName',$true)[0].Text='My * App'
    $dialog.Controls.Find('AddCustomTool',$true)[0].PerformClick();if($dialog.Controls.Find('CustomList',$true)[0].Items.Count-ne1){throw 'Wildcard LaunchName was accepted'};$dialog.Controls.Find('CustomLaunchName',$true)[0].Text='My Tool App'
    $dialog.Controls.Find('AddCustomTool',$true)[0].PerformClick();$dialog.Controls.Find('ManagerToolsOk',$true)[0].PerformClick()
})
$timer.Start();$result=Show-ToolManagerDialog $null $dialogCatalog $configuration;$timer.Dispose()
if(-not $result-or $result.HiddenKeys.Count-ne 0){throw 'Tool manager visibility result is wrong'}
$added=@($result.CustomTools|Where-Object Name -eq 'My Tool')
if($added.Count-ne 1-or $added[0].Key-notmatch '^custom_[0-9a-f]{32}$'-or $added[0].PackageSource-ne 'msstore'-or $added[0].LaunchName-ne 'My Tool App'){throw 'Tool manager custom data is wrong'}
if(@($result.CustomTools|Where-Object Key -eq 'custom_existing').Count-ne 1){throw 'Existing custom tool was lost'}
$cancelTimer=[Windows.Forms.Timer]::new();$cancelTimer.Interval=100
$cancelTimer.add_Tick({$dialog=[Windows.Forms.Application]::OpenForms|Where-Object AccessibleName -eq 'Administrer værktøjer'|Select-Object -First 1;if($dialog){$cancelTimer.Stop();$dialog.Controls.Find('ManagerToolsCancel',$true)[0].PerformClick()}})
$cancelTimer.Start();$cancelled=Show-ToolManagerDialog $null $dialogCatalog $configuration;$cancelTimer.Dispose();if($null-ne$cancelled){throw 'Cancel returned data'}
$deleteCatalog=@($dialogCatalog)+@($configuration.CustomTools)
$configuration.HiddenKeys=@('codex','custom_existing')
$deleteTimer=[Windows.Forms.Timer]::new();$deleteTimer.Interval=100
$deleteTimer.add_Tick({
    $dialog=[Windows.Forms.Application]::OpenForms|Where-Object AccessibleName -eq 'Administrer værktøjer'|Select-Object -First 1
    if($dialog){$deleteTimer.Stop();$dialog.Controls.Find('CustomList',$true)[0].SelectedIndex=0;$dialog.Controls.Find('DeleteCustomTool',$true)[0].PerformClick();$dialog.Controls.Find('ManagerToolsOk',$true)[0].PerformClick()}
})
try {$deleteTimer.Start();$deleted=Show-ToolManagerDialog $null $deleteCatalog $configuration} finally {$deleteTimer.Stop();$deleteTimer.Dispose()}
$validated=ConvertTo-ManagerToolConfiguration $deleted
if ($validated.CustomTools.Count -ne 0 -or 'custom_existing' -in $validated.HiddenKeys -or 'codex' -notin $validated.HiddenKeys) {throw 'Deleted hidden custom tool left an invalid visibility entry'}
Write-Output 'PASS: AI Manager 3.2 groups, filters, metrics, range, history, operation, catalog rebuild, app launch and tool manager data'
