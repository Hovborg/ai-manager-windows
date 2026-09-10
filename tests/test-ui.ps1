param(
    [string]$RenderPath=(Join-Path $PSScriptRoot '../artifacts/dashboard.png'),
    [string]$RenderDetailsPath,
    [string]$RenderRangePath,
    [string]$RenderHistoryPath,
    [string]$RenderOperationPath,
    [string]$RenderNarrowPath,
    [string]$RenderStatePath
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
. "$PSScriptRoot/../updater-ui.ps1"
[void][Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2)
[Windows.Forms.Application]::EnableVisualStyles()
$script:targets=[Collections.Generic.List[string]]::new()
function Start-AsyncUpdate {param($Target) $script:targets.Add($Target)}
$script:checks=0
function Start-AsyncCheck {$script:checks++}
function Refresh-Dashboard {}
function Show-ManagerTools {}
function Open-ManagerTool {param([string]$Key)}
$script:details=[Collections.Generic.List[string]]::new()
function Show-ToolDetails {param([string]$Key,[switch]$Force) $script:details.Add("$Key`:$([bool]$Force)")}
$script:sources=[Collections.Generic.List[string]]::new()
function Open-ManagerReleaseSource {param([string]$Url) $script:sources.Add($Url)}
function Save-RuntimeState {}
function Save-TestDashboardImage {
    param($Form,[string]$Path)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($Path))))
    $bitmap=[Drawing.Bitmap]::new($Form.Width,$Form.Height)
    $Form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height))
    $bitmap.Save([IO.Path]::GetFullPath($Path),[Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}
function Assert-DashboardTextFits {
    param($UI)
    $root=$UI.Form.Controls[0]
    $header=$root.GetControlFromPosition(0,0)
    $controls=@($header.GetControlFromPosition(0,0),$header.GetControlFromPosition(1,0),$UI.Metrics.Updates,$UI.Metrics.Current,$UI.Metrics.Attention,$UI.Check,$UI.Update,$UI.Filter,$UI.Search,$UI.Startup,$UI.Notifications,$UI.Interval,$UI.ShowAll,$UI.Manage)
    foreach ($metric in $UI.Metrics.Values) {$controls+=@($metric.Parent.Controls[1])}
    foreach ($control in $controls) {
        if (-not $control -or -not $control.Visible -or -not $control.Text) {continue}
        $textSize=[Windows.Forms.TextRenderer]::MeasureText($control.Text,$control.Font,[Drawing.Size]::new(10000,10000),[Windows.Forms.TextFormatFlags]::SingleLine)
        if ($textSize.Height -gt $control.ClientSize.Height -or $textSize.Width -gt $control.ClientSize.Width) {
            throw "Clipped text '$($control.Text)': needs $textSize, has $($control.ClientSize), DPI $($UI.Form.DeviceDpi)"
        }
        $visibleBounds=$control.RectangleToScreen($control.ClientRectangle)
        $ancestor=$control.Parent
        while ($ancestor) {
            $visibleBounds=[Drawing.Rectangle]::Intersect($visibleBounds,$ancestor.RectangleToScreen($ancestor.ClientRectangle))
            $ancestor=$ancestor.Parent
        }
        if ($textSize.Height -gt $visibleBounds.Height -or $textSize.Width -gt $visibleBounds.Width) {
            throw "Parent clips '$($control.Text)' at DPI $($UI.Form.DeviceDpi): needed=$textSize, visible=$visibleBounds, control=$($control.Bounds), form=$($UI.Form.Size)"
        }
    }
}
$catalog=@(Get-ToolCatalog)
$codexCli=$catalog | Where-Object Key -eq 'codex'
if ($codexCli) {$codexCli.Name='Codex CLI'}
if (-not ($catalog | Where-Object Key -eq 'codex_app')) {
    $catalog+=@([pscustomobject]@{Key='codex_app';Name='ChatGPT / Codex';Type='App';Source='Syntetisk Windows-app';Path='';PackageId='OpenAI.ChatGPT';Url='';Format=''})
}
$expectedKeys=@($catalog | ForEach-Object {[string]$_.Key})
$expectedAppKeys=@($catalog | Where-Object {$_.Type -ne 'CLI'} | ForEach-Object {[string]$_.Key} | Sort-Object)
$script:ui=New-ManagerDashboard $catalog (Join-Path $PSScriptRoot '../ai-updater.ico')
$map=[ordered]@{}
foreach ($tool in $catalog) {$map[$tool.Key]=New-ToolStatus $tool '1.0.0' '2.0.0' '' ''}
$script:ui.Form.Show()
$dpiFactor=$script:ui.Form.DeviceDpi/96.0
try {
    Set-DashboardStatus $script:ui $map $false
    [Windows.Forms.Application]::DoEvents()
    Assert-DashboardTextFits $script:ui
    foreach ($tool in $catalog) {$script:ui.Cards[$tool.Key].ButtonUpdate.PerformClick()}
    $actual=$script:targets -join ','
    if ($actual -ne ($expectedKeys -join ',')) {throw "Buttons lost targets: $actual"}
    foreach ($tool in $catalog) {$script:ui.Cards[$tool.Key].ButtonDetails.PerformClick()}
    $detailTargets=$script:details -join ','
    if ($detailTargets -ne (@($expectedKeys | ForEach-Object {"$_`:False"}) -join ',')) {throw "Details buttons lost targets: $detailTargets"}
    if ($script:ui.Cards.Values.Where({$_.ButtonDetails.Tag}).Count -ne $catalog.Count) {throw 'All details buttons must carry a target in Tag'}
    foreach ($tool in $catalog) {
        if ($script:ui.Cards[$tool.Key].ButtonDetails.AccessibleName -ne "Se nyheder for $($tool.Name)") {throw "Details action lacks accessible identity for $($tool.Key)"}
    }
    if ($script:ui.Search.AccessibleName -ne 'Søg i værktøjer') {throw 'Search field lacks accessible identity'}
    if ($script:ui.Form.Text -notmatch '3\.2') {throw 'Window does not identify AI Manager 3.2'}
    $subtitle=$script:ui.Form.Controls[0].Controls[0].Controls[1]
    if ($subtitle.Text -notmatch "^$($catalog.Count) værktøjer") {throw "Subtitle is not catalog-driven: $($subtitle.Text)"}
    if ($catalog.Count -ne 7 -or $script:ui.Cards.Count -ne $catalog.Count -or -not $script:ui.Cards.ContainsKey('codex_app')) {throw 'Synthetic ChatGPT / Codex card is missing'}
    if ($script:ui.Tabs.TabPages.Count -ne 4 -or $script:ui.DetailsTab.Text -ne 'Versionsnyt' -or $script:ui.HistoryTab.Text -ne 'Historik') {throw 'Versionsnyt or history tab is missing'}
    if (-not $script:ui.ReleasePanels.Installed -or -not $script:ui.ReleasePanels.Available) {throw 'Release panels are not exposed for automation'}
    if ($script:ui.ReleasePanels.Installed.Body.AccessibleName -ne 'Installerede ændringsnoter' -or $script:ui.ReleasePanels.Available.Body.AccessibleName -ne 'Tilgængelige ændringsnoter') {throw 'Release note fields lack accessible identities'}

    $script:ui.Search.Text='desktop'
    Set-DashboardStatus $script:ui $map $false
    [Windows.Forms.Application]::DoEvents()
    $visibleKeys=@($script:ui.Cards.Keys | Where-Object {$script:ui.Cards[$_].Card.Visible} | Sort-Object)
    if (($visibleKeys -join ',') -ne ($expectedAppKeys -join ',')) {throw "Search did not match name/type: $($visibleKeys -join ',')"}
    $script:ui.Filter.SelectedIndex=1
    Set-DashboardStatus $script:ui $map $false
    $visibleKeys=@($script:ui.Cards.Keys | Where-Object {$script:ui.Cards[$_].Card.Visible} | Sort-Object)
    if (($visibleKeys -join ',') -ne ($expectedAppKeys -join ',')) {throw 'Search and update filter do not combine'}
    $script:ui.Search.Text=''
    $script:ui.Filter.SelectedIndex=0

    Set-ReleaseNotesView $script:ui $map.codex $null $true
    if ($script:ui.DetailsTitle.Text -notmatch [regex]::Escape([string]$map.codex.Name)) {throw 'Details title does not identify selected tool'}
    if ($script:ui.DetailsStatus.Text -notmatch 'Henter versionsnyt') {throw 'Loading state is not understandable'}
    if ($script:ui.DetailsRefresh.Enabled) {throw 'Details refresh is enabled while loading'}
    if ($script:ui.DetailsRefresh.Tag -ne 'codex') {throw 'Details refresh lost selected target'}

    $bundle=[pscustomobject]@{
        Installed=[pscustomobject]@{Version='1.0.0';Body="Installed changes`r`nSecond line";State='Ready';Message='';SourceUrl='https://example.test/installed';PublishedAt='2026-09-01T10:00:00Z';RetrievedAt='2026-09-10T09:00:00Z';IsStale=$false;ExactVersion=$true}
        Available=[pscustomobject]@{Version='2.0.0';Body="Available changes`r`nMore details";State='Ready';Message='Generelle noter for denne udgivelseskanal.';SourceUrl='https://example.test/available';PublishedAt='2026-09-09T10:00:00Z';RetrievedAt='2026-09-10T09:00:00Z';IsStale=$true;ExactVersion=$false}
        Range=[pscustomobject]@{Version='1.0.0 → 2.0.0';FromVersion='1.0.0';ToVersion='2.0.0';ReleaseCount=4;Complete=$true;Body="Version 1.4`r`n- Faster checks`r`n`r`nVersion 1.7`r`n- Clearer status`r`n`r`nVersion 2.0`r`n- New dashboard";State='Ready';Message='Samlet fra fire udgivelser.';SourceUrl='https://example.test/range';PublishedAt='2026-09-09T10:00:00Z';RetrievedAt='2026-09-10T09:00:00Z';IsStale=$false;ExactVersion=$true}
    }
    Set-ReleaseNotesView $script:ui $map.codex $bundle $false
    if ($script:ui.ReleasePanels.Installed.Version.Text -ne '1.0.0' -or $script:ui.ReleasePanels.Available.Version.Text -ne '2.0.0') {throw 'Release versions were not rendered'}
    if ($script:ui.ReleasePanels.Installed.Body.Text -notmatch 'Installed changes' -or $script:ui.ReleasePanels.Available.Body.Text -notmatch 'Available changes') {throw 'Release notes were not rendered'}
    if ($script:ui.ReleasePanels.Available.Body.Text -notmatch 'Generelle noter for denne udgivelseskanal') {throw 'Ready-state message was hidden'}
    if ($script:ui.ReleasePanels.Available.Meta.Text -notmatch 'Ældre cache') {throw 'Stale release data is not marked'}
    if ($script:ui.ReleasePanels.Installed.Meta.Text -notmatch 'Udgivet' -or $script:ui.ReleasePanels.Installed.Meta.Text -notmatch 'Hentet') {throw 'Published and retrieved freshness timestamps are not both visible'}
    if ($script:ui.ReleasePanels.Available.Meta.Text -notmatch 'Ikke eksakt versionsmatch' -or $script:ui.ReleasePanels.Available.Meta.Text -notmatch 'Generelle noter') {throw 'Inexact/general metadata is missing'}
    if (-not $script:ui.ReleasePanels.Available.Meta.ReadOnly -or -not $script:ui.ReleasePanels.Available.Meta.WordWrap -or $script:ui.ReleasePanels.Available.Meta.ScrollBars -ne 'Vertical') {throw 'Release metadata can be clipped without a readable scroll path'}
    if (-not $script:ui.ReleasePanels.Installed.Source.Enabled -or $script:ui.ReleasePanels.Installed.Source.Tag -ne 'https://example.test/installed') {throw 'Installed source action is not wired'}
    if (-not $script:ui.ReleasePanels.Available.Source.Enabled -or $script:ui.ReleasePanels.Available.Source.Tag -ne 'https://example.test/available') {throw 'Available source action is not wired'}
    $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab
    [Windows.Forms.Application]::DoEvents()
    $script:ui.ReleasePanels.Installed.Source.PerformClick(); $script:ui.ReleasePanels.Available.Source.PerformClick()
    if (($script:sources -join ',') -ne 'https://example.test/installed,https://example.test/available') {throw 'Source buttons lost URL targets'}
    $script:ui.DetailsRefresh.PerformClick()
    if ($script:details[$script:details.Count-1] -ne 'codex:True') {throw 'Details refresh did not force selected target'}

    $offlineBundle=[pscustomobject]@{
        Installed=[pscustomobject]@{Version='1.0.0';Body='Cached installed note';State='Ready';Message='';SourceUrl='';PublishedAt='';RetrievedAt='2026-09-01T09:00:00Z';IsStale=$true;ExactVersion=$true}
        Available=[pscustomobject]@{Version='2.0.0';Body='';State='Error';Message='Offline test';SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$false}
    }
    Set-ReleaseNotesView $script:ui $map.codex $offlineBundle $false
    if ($script:ui.DetailsStatus.Text -notmatch 'Offline test') {throw 'Release error is not summarized'}
    if ($script:ui.ReleasePanels.Installed.Meta.Text -notmatch 'Ældre cache') {throw 'Installed stale state disappeared'}
    if ($script:ui.ReleasePanels.Available.Body.Text -notmatch 'Offline test') {throw 'Available error is not readable in its panel'}
    if ($script:ui.ReleasePanels.Available.Source.Enabled) {throw 'Source action enabled without URL'}
    $script:ui.Tabs.SelectedIndex=0
    [Windows.Forms.Application]::DoEvents()
    Set-DashboardStatus $script:ui $map $true
    if (@($script:ui.Cards.Values | Where-Object {$_.ButtonUpdate.Enabled}).Count) {throw 'Update buttons enabled while busy'}
    if ($script:ui.Check.Enabled -or $script:ui.Update.Enabled) {throw 'Bulk/check enabled while busy'}
    $map.codex=New-ToolStatus ($catalog | Where-Object Key -eq 'codex') '1.0.0' '' '' 'Offline test'
    $map.gh=New-ToolStatus ($catalog | Where-Object Key -eq 'gh') '2.0.0' '2.0.0' '' ''
    Set-DashboardStatus $script:ui $map $false
    if ($script:ui.Cards.codex.ButtonUpdate.Enabled) {throw 'Offline tool update enabled'}
    if ($script:ui.Metrics.Attention.Text -ne '1') {throw 'Unknown status not counted'}
    $script:ui.Filter.SelectedIndex=1
    Set-DashboardStatus $script:ui $map $false
    if ($script:ui.Cards.codex.Card.Visible -or $script:ui.Cards.gh.Card.Visible) {throw 'Update filter includes unavailable tools'}
    $script:ui.Filter.SelectedIndex=2
    Set-DashboardStatus $script:ui $map $false
    if (-not $script:ui.Cards.codex.Card.Visible -or $script:ui.Cards.agy.Card.Visible) {throw 'Attention filter incorrect'}
    $codexAppError='ChatGPT / Codex kører stadig. Luk appen helt, og prøv igen.'
    $map.codex_app.State='NeedsClose'; $map.codex_app.HasUpdate=$true; $map.codex_app.Error=$codexAppError
    $script:ui.Filter.SelectedIndex=0
    Set-DashboardStatus $script:ui $map $false
    if ($script:ui.Cards.codex_app.LabelBadge.Text -ne 'Opdatering klar' -or $script:ui.Cards.codex_app.LabelDetail.Text -ne 'Luk appen først') {throw 'Generic blocked app does not explain its confirmed update'}
    if ($script:ui.Cards.codex_app.ButtonUpdate.Text -ne 'Tjek igen' -or -not $script:ui.Cards.codex_app.ButtonUpdate.Enabled) {throw 'Generic blocked app does not offer recheck'}
    if ($script:ui.Tooltip.GetToolTip($script:ui.Cards.codex_app.ButtonUpdate) -ne $codexAppError) {throw 'Generic blocked app tooltip lost the full error'}
    $targetsBeforeRecheck=$script:targets.Count; $checksBeforeRecheck=$script:checks
    $script:ui.Cards.codex_app.ButtonUpdate.PerformClick()
    if ($script:targets.Count -ne $targetsBeforeRecheck -or $script:checks -ne ($checksBeforeRecheck+1)) {throw 'Generic blocked app attempted installation instead of rechecking'}
    $expectedUpdateCount=@($map.Values | Where-Object {$_.HasUpdate}).Count
    $expectedAttentionCount=@($map.Values | Where-Object {$_.State -in @('Missing','Error','Unknown','NeedsClose')}).Count
    if ($script:ui.Metrics.Updates.Text -ne [string]$expectedUpdateCount -or $script:ui.Metrics.Attention.Text -ne [string]$expectedAttentionCount) {throw 'Blocked confirmed update is not counted in both update and attention totals'}
    $script:ui.Filter.SelectedIndex=1
    Set-DashboardStatus $script:ui $map $false
    if (-not $script:ui.Cards.codex_app.Card.Visible) {throw 'Blocked confirmed update is missing from update filter'}
    foreach ($key in $map.Keys) {
        if ($key -ne 'codex_app') {$map[$key].State='Current'; $map[$key].HasUpdate=$false; $map[$key].Error=''}
    }
    Set-DashboardStatus $script:ui $map $false
    if ($script:ui.Update.Enabled) {throw 'Bulk update enabled with only a blocked update'}
    $map.agy.State='Update'; $map.agy.HasUpdate=$true
    Set-DashboardStatus $script:ui $map $false
    if (-not $script:ui.Update.Enabled) {throw 'Bulk update disabled despite an unblocked update'}

    foreach ($tool in $catalog) {$map[$tool.Key]=New-ToolStatus $tool '1.0.0' '2.0.0' '' ''}
    $script:ui.Filter.SelectedIndex=2
    $map.claude_app.State='NeedsClose'; $map.claude_app.Error='Luk Claude helt først'
    Set-DashboardStatus $script:ui $map $false
    if (-not $script:ui.Cards.claude_app.Card.Visible -or $script:ui.Cards.claude_app.LabelBadge.Text -ne 'Luk Claude helt først') {throw 'Blocked app not explained in attention filter'}
    $script:ui.Cards.claude_app.ButtonUpdate.PerformClick()
    if ($script:checks -ne ($checksBeforeRecheck+2) -or $script:targets.Count -ne $targetsBeforeRecheck) {throw 'Blocked Claude button installed instead of rechecking'}
    $map.claude_app.Error='Cowork-tjenesten holder Claude åben'
    Set-DashboardStatus $script:ui $map $false
    if ($script:ui.Cards.claude_app.LabelBadge.Text -ne 'Cowork blokerer') {throw 'Cowork service was presented as a normal tray app'}
    Set-DashboardStatus $script:ui $map $true
    if ($script:ui.Cards.claude_app.ButtonUpdate.Enabled) {throw 'Blocked app recheck enabled while busy'}
    $map.claude_app.State='Update'; $map.claude_app.Error=''
    $script:ui.Filter.SelectedIndex=0
    $script:ui.Search.Text=''
    Set-DashboardStatus $script:ui $map $false
    foreach ($width in @(880,1060,1320)) {
        $script:ui.Form.Width=[int]($width*$dpiFactor)
        [Windows.Forms.Application]::DoEvents()
        Assert-DashboardTextFits $script:ui
        if ($script:ui.CardPanel.HorizontalScroll.Visible) {throw "Horizontal scrolling at width $width"}
        foreach ($card in $script:ui.Cards.Values) {
            if ($card.ButtonUpdate.Right -gt $card.Card.ClientSize.Width) {throw "Button outside card at width $width"}
            if ($card.ButtonDetails.Right -gt $card.Card.ClientSize.Width) {throw "Details button outside card at width $width"}
        }
        $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab
        [Windows.Forms.Application]::DoEvents()
        if ($script:ui.ReleasePanels.Installed.Container.Right -gt $script:ui.DetailsTab.ClientSize.Width -or $script:ui.ReleasePanels.Available.Container.Right -gt $script:ui.DetailsTab.ClientSize.Width) {throw "Release panel outside details tab at width $width"}
        $script:ui.Tabs.SelectedIndex=0
    }
    $script:ui.Form.Size=$script:ui.Form.MinimumSize
    $script:ui.Tabs.SelectedIndex=0
    [Windows.Forms.Application]::DoEvents()
    $lastCard=@($script:ui.Cards.Values | Sort-Object {$_.Card.Bottom} -Descending)[0].Card
    $script:ui.CardPanel.ScrollControlIntoView($lastCard)
    [Windows.Forms.Application]::DoEvents()
    $lastBounds=$lastCard.RectangleToScreen($lastCard.ClientRectangle)
    $viewport=$script:ui.CardPanel.RectangleToScreen($script:ui.CardPanel.ClientRectangle)
    if ($script:ui.CardPanel.VerticalScroll.Value -le 0 -or -not $lastBounds.IntersectsWith($viewport)) {throw 'Last of seven cards cannot be reached by scrolling'}
    $script:ui.CardPanel.AutoScrollPosition=[Drawing.Point]::Empty
    $script:ui.Form.ClientSize=[Drawing.Size]::new([int](1060*$dpiFactor),[int](850*$dpiFactor))
    $script:ui.Startup.Checked=$true; $script:ui.Notifications.Checked=$true; $script:ui.Interval.SelectedIndex=2
    $script:ui.Status.Text='Testvisning · kontrollerede testdata til layout og knapper'
    if ($RenderStatePath) {
        $snapshot=Get-Content -LiteralPath $RenderStatePath -Raw | ConvertFrom-Json
        $live=[ordered]@{}; foreach ($item in $snapshot.Tools) {$live[$item.Key]=$item}
        if ($live.Count -ne $catalog.Count) {throw "Render snapshot does not contain $($catalog.Count) tools"}
        Set-DashboardStatus $script:ui $live $false
        $script:ui.Status.Text="Forhåndsvisning fra versionskontrol $(([datetime]$snapshot.LastCheck).ToString('HH:mm:ss')) · Opdateringer starter kun ved dit klik"
    }
    [Windows.Forms.Application]::DoEvents()
    Save-TestDashboardImage $script:ui.Form $RenderPath
    if ($RenderNarrowPath) {
        $script:ui.Form.Width=[int](880*$dpiFactor)
        [Windows.Forms.Application]::DoEvents()
        Save-TestDashboardImage $script:ui.Form $RenderNarrowPath
        $script:ui.Form.ClientSize=[Drawing.Size]::new([int](1060*$dpiFactor),[int](850*$dpiFactor))
    }
    if ($RenderDetailsPath) {
        Set-ReleaseNotesView $script:ui $map.codex $bundle $false
        $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab
        $script:ui.ReleaseTabs.SelectedIndex=0
        [Windows.Forms.Application]::DoEvents()
        Save-TestDashboardImage $script:ui.Form $RenderDetailsPath
    }
    if ($RenderRangePath) {
        Set-ReleaseNotesView $script:ui $map.codex $bundle $false
        $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab;$script:ui.ReleaseTabs.SelectedIndex=1
        [Windows.Forms.Application]::DoEvents();Save-TestDashboardImage $script:ui.Form $RenderRangePath
    }
    if ($RenderHistoryPath) {
        Set-ManagerHistoryView $script:ui @(
            [pscustomobject]@{Id='new';Key='codex';Name='Codex CLI';StartedAt='2026-09-10T11:42:00Z';CompletedAt='2026-09-10T11:42:24Z';Before='1.2.0';After='1.3.0';TargetVersion='1.3.0';Success=$true;Outcome='Success';Output="Opdatering fuldført.`r`nVersion 1.3.0 bekræftet."},
            [pscustomobject]@{Id='detected';Key='claude_app';Name='Claude Desktop';StartedAt='';CompletedAt='2026-09-10T12:15:00Z';Before='1.1.0';After='1.2.0';TargetVersion='';Success=$false;Outcome='Detected';Output='Ekstern versionsændring registreret.'},
            [pscustomobject]@{Id='pending';Key='codex_app';Name='ChatGPT / Codex';StartedAt='2026-09-10T09:30:00Z';CompletedAt='';Before='1.0.0';After='';TargetVersion='1.1.0';Success=$false;Outcome='Pending';Output='Afventer at appen lukkes.'}
        )
        $script:ui.Tabs.SelectedTab=$script:ui.HistoryTab;[Windows.Forms.Application]::DoEvents();Save-TestDashboardImage $script:ui.Form $RenderHistoryPath
    }
    if ($RenderOperationPath) {
        $script:ui.Tabs.SelectedIndex=0
        Set-ManagerOperationView $script:ui ([pscustomobject]@{Name='ChatGPT / Codex';Phase='Kontrollerer';Message='Bekræfter installeret version';ElapsedSeconds=67;Index=2;Total=4;Output="WinGet-resultat modtaget.`r`nKontrollerer version 2 af 4 …"})
        [Windows.Forms.Application]::DoEvents();Save-TestDashboardImage $script:ui.Form $RenderOperationPath;Set-ManagerOperationView $script:ui $null
    }
    $script:ui.Tabs.SelectedTab=$script:ui.DetailsTab
    $script:ui.Form.Size=$script:ui.Form.MinimumSize
    [Windows.Forms.Application]::DoEvents()
    foreach ($panel in $script:ui.ReleasePanels.Values) {
        if ($panel.Body.ClientSize.Height -lt [int](70*$dpiFactor)) {
            throw "Release notes reading area too small: actual=$($panel.Body.ClientSize.Height), required=$([int](70*$dpiFactor)), DPI=$($script:ui.Form.DeviceDpi), form=$($script:ui.Form.Size), client=$($script:ui.Form.ClientSize), root rows=$($script:ui.Root.GetRowHeights() -join ','), panel rows=$($panel.Container.GetRowHeights() -join ',')"
        }
    }
    # Reproduce a short working area like the Windows CI desktop, which can
    # constrain the actual form below its requested 800-pixel minimum.
    $savedMinimum=$script:ui.Form.MinimumSize
    try {
        $script:ui.Form.MinimumSize=[Drawing.Size]::new([int](880*$dpiFactor),[int](650*$dpiFactor))
        $script:ui.Form.Height=[int](718*$dpiFactor)
        foreach ($tabIndex in @(0,1)) {
            $script:ui.ReleaseTabs.SelectedIndex=$tabIndex
            [Windows.Forms.Application]::DoEvents()
            $panels=if ($tabIndex -eq 0) {@($script:ui.ReleasePanels.Values)} else {@($script:ui.RangePanel)}
            foreach ($panel in $panels) {
                if ($panel.Body.ClientSize.Height -lt [int](70*$dpiFactor)) {throw 'Short desktop collapsed the release notes reading field'}
                $panel.Container.ScrollControlIntoView($panel.Source)
                [Windows.Forms.Application]::DoEvents()
                $sourceBounds=$panel.Source.RectangleToScreen($panel.Source.ClientRectangle)
                $viewport=$panel.Container.RectangleToScreen($panel.Container.ClientRectangle)
                if (-not $viewport.Contains($sourceBounds)) {throw 'Release source button cannot be reached on a short desktop'}
            }
        }
    } finally {$script:ui.Form.MinimumSize=$savedMinimum}
    $dpiUI=New-ManagerDashboard $catalog (Join-Path $PSScriptRoot '../ai-updater.ico')
    try {
        # Test the requested 880-logical-pixel layout independently of the
        # runner's physical monitor size. Default Windows tracking limits
        # can otherwise clamp this synthetic 175% form to only 1044 pixels.
        $dpiUI.Form.MaximumSize=[Drawing.Size]::new(4096,4096)
        $dpiUI.Form.Show()
        Set-DashboardStatus $dpiUI $map $false
        $currentDpiFactor=$dpiUI.Form.DeviceDpi/96.0
        if ([Math]::Abs($currentDpiFactor-1.75) -gt 0.01) {
            $supplementalScale=1.75/$currentDpiFactor
            $dpiUI.Form.Scale([Drawing.SizeF]::new($supplementalScale,$supplementalScale))
        }
        $dpiUI.Form.Width=[int](880*1.75)
        [Windows.Forms.Application]::DoEvents()
        if ($dpiUI.Form.Width -ne [int](880*1.75)) {throw 'The synthetic 175 percent viewport was clamped by the test desktop'}
        Assert-DashboardTextFits $dpiUI
        if ($dpiUI.Form.AutoScaleMode -ne 'Dpi' -or $dpiUI.CardPanel.HorizontalScroll.Visible) {throw 'Dashboard does not remain DPI-aware at 175 percent'}
        foreach ($card in $dpiUI.Cards.Values) {
            if ($card.ButtonUpdate.Right -gt $card.Card.ClientSize.Width -or $card.ButtonDetails.Right -gt $card.Card.ClientSize.Width) {throw 'Card actions overflow at 175 percent DPI scaling'}
        }
    } finally {
        $dpiUI.Tooltip.Dispose()
        $dpiUI.Form.Dispose()
    }
    Write-Output "PASS: AI Manager 3.2 dashboard, search plus filters, $($catalog.Count) update/detail targets, generic/Claude blocked updates, release states/sources, busy guards, scrolling, 3 logical widths, text fits at $($script:ui.Form.DeviceDpi) DPI and 175 percent scaling, dashboard render"
} finally {$script:ui.Tooltip.Dispose(); $script:ui.Form.Dispose()}
