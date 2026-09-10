Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ManagerColor {
    param([string]$Hex)
    return [Drawing.ColorTranslator]::FromHtml($Hex)
}

function New-ManagerLabel {
    param([string]$Text, [float]$Size=10, [bool]$Bold=$false)
    $label=[Windows.Forms.Label]::new()
    $label.Text=$Text
    $label.Dock='Fill'
    $label.TextAlign='MiddleLeft'
    $label.AutoEllipsis=$true
    $style=if ($Bold) {[Drawing.FontStyle]::Bold} else {[Drawing.FontStyle]::Regular}
    $label.Font=[Drawing.Font]::new('Segoe UI',$Size,$style)
    $label.ForeColor=Get-ManagerColor '#DCE7F3'
    return $label
}

function New-ManagerButton {
    param([string]$Text, [bool]$Primary=$false)
    $button=[Windows.Forms.Button]::new()
    $button.Text=$Text
    $button.Size=[Drawing.Size]::new(136,34)
    $button.FlatStyle='Flat'
    $button.FlatAppearance.BorderSize=1
    $button.FlatAppearance.BorderColor=Get-ManagerColor $(if ($Primary) {'#6FE2C8'} else {'#3C5268'})
    $button.Cursor='Hand'
    $button.Margin=[Windows.Forms.Padding]::new(0,4,10,4)
    $button.BackColor=Get-ManagerColor $(if ($Primary) {'#65DCC2'} else {'#223246'})
    $button.ForeColor=Get-ManagerColor $(if ($Primary) {'#0B2923'} else {'#E8F0F8'})
    $button.Font=[Drawing.Font]::new('Segoe UI',9,[Drawing.FontStyle]::Bold)
    return $button
}

function New-ReleaseNotesPanel {
    param([string]$Heading, [string]$Accent, [string]$AccessibleBodyName)
    $container=[Windows.Forms.TableLayoutPanel]::new()
    $container.Dock='Fill'
    $container.RowCount=5
    $container.ColumnCount=1
    $container.Padding=[Windows.Forms.Padding]::new(18,14,18,16)
    $container.Margin=[Windows.Forms.Padding]::new(0,0,8,0)
    $container.BackColor=Get-ManagerColor '#172536'
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,30))
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,36))
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,62))
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$container.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,40))

    $headingLabel=New-ManagerLabel $Heading 9 $true
    $headingLabel.ForeColor=Get-ManagerColor $Accent
    $version=New-ManagerLabel '—' 19 $true
    $meta=[Windows.Forms.TextBox]::new()
    $meta.Dock='Fill'
    $meta.Multiline=$true
    $meta.ReadOnly=$true
    $meta.WordWrap=$true
    $meta.ScrollBars='Vertical'
    $meta.BorderStyle='None'
    $meta.BackColor=$container.BackColor
    $meta.ForeColor=Get-ManagerColor '#91A5BA'
    $meta.Font=[Drawing.Font]::new('Segoe UI',8)
    $meta.Text='Afventer valg af værktøj'
    $body=[Windows.Forms.RichTextBox]::new()
    $body.Dock='Fill'
    $body.ReadOnly=$true
    $body.BorderStyle='None'
    $body.ScrollBars='Vertical'
    $body.WordWrap=$true
    $body.DetectUrls=$false
    $body.BackColor=Get-ManagerColor '#101C29'
    $body.ForeColor=Get-ManagerColor '#D7E3EF'
    $body.Font=[Drawing.Font]::new('Segoe UI',9.5)
    $body.AccessibleName=$AccessibleBodyName
    $body.Text='Vælg Se nyheder på et værktøj for at hente ændringsnoter.'
    $source=New-ManagerButton 'Åbn kilde'
    $source.Width=122
    $source.Dock='Left'
    $source.Enabled=$false
    $source.AccessibleName="Åbn kilde til $Heading"
    $source.add_Click({param($sender,$eventArgs)
        if ($sender.Enabled -and $sender.Tag) {Open-ManagerReleaseSource -Url ([string]$sender.Tag)}
    })
    $container.Controls.Add($headingLabel,0,0)
    $container.Controls.Add($version,0,1)
    $container.Controls.Add($meta,0,2)
    $container.Controls.Add($body,0,3)
    $container.Controls.Add($source,0,4)
    return @{Container=$container; Heading=$headingLabel; Version=$version; Meta=$meta; Body=$body; Source=$source}
}

function Create-ToolCard {
    param([string]$Key, [string]$Name, [string]$Type)
    $card=[Windows.Forms.TableLayoutPanel]::new()
    $card.Height=92
    $card.Width=960
    $card.ColumnCount=5
    $card.RowCount=2
    $card.Padding=[Windows.Forms.Padding]::new(16,9,12,9)
    $card.Margin=[Windows.Forms.Padding]::new(0,0,0,8)
    $card.BackColor=Get-ManagerColor '#172536'
    foreach ($width in @(26,14,14,24,22)) {
        [void]$card.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,$width))
    }
    [void]$card.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,53))
    [void]$card.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,47))

    $nameLabel=New-ManagerLabel $Name 11 $true
    $typeText=if ($Type -eq 'CLI') {'KOMMANDOLINJE'} else {'DESKTOP-APP'}
    $typeLabel=New-ManagerLabel $typeText 8
    $typeLabel.ForeColor=Get-ManagerColor '#87A0B9'
    $card.Controls.Add($nameLabel,0,0)
    $card.Controls.Add($typeLabel,0,1)

    $installed=New-ManagerLabel '—' 10 $true
    $latest=New-ManagerLabel '—' 10 $true
    $installedCaption=New-ManagerLabel 'Installeret' 8
    $latestCaption=New-ManagerLabel 'Tilgængelig' 8
    $installedCaption.ForeColor=Get-ManagerColor '#8197AE'
    $latestCaption.ForeColor=Get-ManagerColor '#8197AE'
    $card.Controls.Add($installed,1,0)
    $card.Controls.Add($installedCaption,1,1)
    $card.Controls.Add($latest,2,0)
    $card.Controls.Add($latestCaption,2,1)

    $badge=New-ManagerLabel 'Afventer tjek' 9 $true
    $detail=New-ManagerLabel '' 8
    $detail.ForeColor=Get-ManagerColor '#91A5BA'
    $card.Controls.Add($badge,3,0)
    $card.Controls.Add($detail,3,1)

    $actions=[Windows.Forms.TableLayoutPanel]::new()
    $actions.Dock='Fill'
    $actions.RowCount=2
    $actions.ColumnCount=1
    $actions.Margin=[Windows.Forms.Padding]::new(8,0,0,0)
    [void]$actions.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,50))
    [void]$actions.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,50))
    $button=New-ManagerButton 'Opdatér' $true
    $button.Dock='Fill'
    $button.Margin=[Windows.Forms.Padding]::new(0,0,0,3)
    $button.Enabled=$false
    $button.Tag=$Key
    # The sender owns the target; no short-lived local variable is captured.
    $button.add_Click({param($sender,$eventArgs)
        if ($sender.Text -eq 'Tjek igen') {Start-AsyncCheck} else {Start-AsyncUpdate -Target ([string]$sender.Tag)}
    })
    $details=New-ManagerButton 'Se nyheder'
    $details.Dock='Fill'
    $details.Margin=[Windows.Forms.Padding]::new(0,3,0,0)
    $details.Tag=$Key
    $details.AccessibleName="Se nyheder for $Name"
    $details.add_Click({param($sender,$eventArgs)
        Show-ToolDetails -Key ([string]$sender.Tag)
    })
    $actions.Controls.Add($button,0,0)
    $actions.Controls.Add($details,0,1)
    $open=$null
    if ($Type -ne 'CLI') {
        $card.Height=124
        $actions.RowCount=3
        $actions.RowStyles.Clear()
        foreach($unused in 1..3){[void]$actions.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,33.333))}
        $open=New-ManagerButton 'Åbn app'
        $open.Dock='Fill'
        $open.Margin=[Windows.Forms.Padding]::new(0,3,0,0)
        $open.Enabled=$false
        $open.Tag=$Key
        $open.AccessibleName="Åbn $Name"
        $open.add_Click({param($sender,$eventArgs) Open-ManagerTool -Key ([string]$sender.Tag)})
        $actions.Controls.Add($open,0,2)
    }
    $card.Controls.Add($actions,4,0)
    $card.SetRowSpan($actions,2)
    return @{
        Card=$card
        LabelInstalled=$installed
        LabelLatest=$latest
        LabelBadge=$badge
        LabelDetail=$detail
        ButtonUpdate=$button
        ButtonDetails=$details
        ButtonOpen=$open
        NameLabel=$nameLabel
        TypeLabel=$typeLabel
        MatchesView=$true
    }
}

function New-ManagerGroupHeader {
    param([string]$Text)
    $header=New-ManagerLabel $Text 10 $true
    $header.Height=34
    $header.Dock='Top'
    $header.Padding=[Windows.Forms.Padding]::new(4,7,0,3)
    $header.ForeColor=Get-ManagerColor '#91BFF0'
    $header.AccessibleName="$Text-gruppe"
    return $header
}

function New-ManagerDashboard {
    param($Catalog, [string]$IconPath)
    $form=[Windows.Forms.Form]::new()
    # Apply the initial DPI conversion once, after the complete control tree exists.
    # Otherwise only the form scales and controls added later retain 96-DPI bounds.
    $form.SuspendLayout()
    $form.Text='AI Manager 3.2'
    $form.ClientSize=[Drawing.Size]::new(1060,850)
    $form.MinimumSize=[Drawing.Size]::new(880,800)
    $form.StartPosition='CenterScreen'
    $form.AutoScaleMode='Dpi'
    $form.AutoScaleDimensions=[Drawing.SizeF]::new(96,96)
    $form.Font=[Drawing.Font]::new('Segoe UI',10)
    $form.BackColor=Get-ManagerColor '#0B1420'
    $form.ForeColor=Get-ManagerColor '#DCE7F3'
    if (Test-Path -LiteralPath $IconPath) {$form.Icon=[Drawing.Icon]::new($IconPath)}

    $root=[Windows.Forms.TableLayoutPanel]::new()
    $root.Dock='Fill'
    $root.ColumnCount=1
    $root.RowCount=7
    $root.Padding=[Windows.Forms.Padding]::new(22,12,22,10)
    foreach ($height in @(76,78,54)) {
        [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$height))
    }
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,0))
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    foreach ($height in @(48,28)) {
        [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$height))
    }
    $form.Controls.Add($root)

    $header=[Windows.Forms.TableLayoutPanel]::new()
    $header.Dock='Fill'
    $header.RowCount=2
    $header.ColumnCount=2
    [void]$header.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,65))
    [void]$header.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,35))
    [void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,92))
    $title=New-ManagerLabel 'AI Manager' 24 $true
    $subtitle=New-ManagerLabel "$($Catalog.Count) værktøjer · versioner, opdateringer og versionsnyt samlet ét sted" 10
    $subtitle.ForeColor=Get-ManagerColor '#91A8BF'
    $versionBadge=New-ManagerLabel 'VERSION 3.2' 9 $true
    $versionBadge.TextAlign='MiddleCenter'
    $versionBadge.ForeColor=Get-ManagerColor '#68DFC5'
    $header.Controls.Add($title,0,0)
    $header.Controls.Add($subtitle,0,1)
    $header.Controls.Add($versionBadge,1,0)
    $header.SetRowSpan($versionBadge,2)
    $root.Controls.Add($header,0,0)

    $summary=[Windows.Forms.TableLayoutPanel]::new()
    $summary.Dock='Fill'
    $summary.ColumnCount=3
    $summary.RowCount=1
    [void]$summary.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $metrics=@{}
    foreach ($pair in @(@('Updates','OPDATERINGER KLAR','#65DCC2'),@('Current','AJOUR / NYERE','#9DCDB0'),@('Attention','KRÆVER OPMÆRKSOMHED','#E8B978'))) {
        [void]$summary.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,33.333))
        $panel=[Windows.Forms.TableLayoutPanel]::new()
        $panel.Dock='Fill'
        $panel.RowCount=2
        [void]$panel.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,68))
        [void]$panel.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,32))
        $panel.BackColor=Get-ManagerColor '#152334'
        $panel.Padding=[Windows.Forms.Padding]::new(14,4,14,4)
        $panel.Margin=[Windows.Forms.Padding]::new(0,0,10,8)
        $count=New-ManagerLabel '—' 20 $true
        $count.ForeColor=Get-ManagerColor $pair[2]
        $caption=New-ManagerLabel $pair[1] 8 $true
        $caption.ForeColor=Get-ManagerColor '#8FA5BB'
        $panel.Controls.Add($count,0,0)
        $panel.Controls.Add($caption,0,1)
        [void]$summary.Controls.Add($panel)
        $metrics[$pair[0]]=$count
    }
    $root.Controls.Add($summary,0,1)
    foreach($metricName in @('Updates','Current','Attention')) {
        $metrics[$metricName].Cursor='Hand'
        $metrics[$metricName].AccessibleName="Filtrér på $metricName"
    }
    $metrics.Updates.add_Click({$script:ui.Search.Text='';$script:ui.TypeFilter.SelectedIndex=0;$script:ui.Filter.SelectedIndex=1;Refresh-Dashboard})
    $metrics.Current.add_Click({$script:ui.Search.Text='';$script:ui.TypeFilter.SelectedIndex=0;$script:ui.Filter.SelectedIndex=3;Refresh-Dashboard})
    $metrics.Attention.add_Click({$script:ui.Search.Text='';$script:ui.TypeFilter.SelectedIndex=0;$script:ui.Filter.SelectedIndex=2;Refresh-Dashboard})

    $toolbar=[Windows.Forms.FlowLayoutPanel]::new()
    $toolbar.Dock='Fill'
    $toolbar.WrapContents=$false
    $toolbar.AutoScroll=$false
    $check=New-ManagerButton 'Tjek nu'
    $check.Width=112
    $check.add_Click({Start-AsyncCheck})
    $update=New-ManagerButton 'Opdatér alle' $true
    $update.Width=126
    $update.Enabled=$false
    $update.add_Click({Start-AsyncUpdate -Target 'all'})
    $filter=[Windows.Forms.ComboBox]::new()
    $filter.DropDownStyle='DropDownList'
    $filter.Width=174
    $filter.Margin=[Windows.Forms.Padding]::new(4,7,10,0)
    [void]$filter.Items.AddRange([object[]]@('Alle værktøjer','Opdateringer klar','Kræver opmærksomhed','Ajour / nyere'))
    $filter.SelectedIndex=0
    $filter.add_SelectedIndexChanged({Refresh-Dashboard})
    $searchLabel=New-ManagerLabel 'Søg' 9 $true
    $searchLabel.Dock='None'
    $searchLabel.Width=36
    $searchLabel.Height=34
    $searchLabel.Margin=[Windows.Forms.Padding]::new(5,5,0,0)
    $search=[Windows.Forms.TextBox]::new()
    $search.Width=210
    $search.BorderStyle='FixedSingle'
    $search.BackColor=Get-ManagerColor '#152334'
    $search.ForeColor=Get-ManagerColor '#E5EDF6'
    $search.AccessibleName='Søg i værktøjer'
    $search.Margin=[Windows.Forms.Padding]::new(0,8,10,0)
    $search.add_TextChanged({Refresh-Dashboard})
    $progress=[Windows.Forms.ProgressBar]::new()
    $progress.Style='Marquee'
    $progress.MarqueeAnimationSpeed=30
    $progress.Width=82
    $progress.Height=7
    $progress.Margin=[Windows.Forms.Padding]::new(5,18,0,0)
    $progress.Visible=$false
    $toolbar.Controls.AddRange([Windows.Forms.Control[]]@($check,$update,$filter,$searchLabel,$search,$progress))
    $root.Controls.Add($toolbar,0,2)

    $operationPanel=[Windows.Forms.TableLayoutPanel]::new()
    $operationPanel.Dock='Fill';$operationPanel.ColumnCount=2;$operationPanel.RowCount=2
    $operationPanel.Padding=[Windows.Forms.Padding]::new(14,6,14,6);$operationPanel.BackColor=Get-ManagerColor '#152B3D';$operationPanel.Visible=$false
    [void]$operationPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,45))
    [void]$operationPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,55))
    [void]$operationPanel.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,30))
    [void]$operationPanel.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $operationTitle=New-ManagerLabel '' 11 $true;$operationMeta=New-ManagerLabel '' 9
    $operationOutput=[Windows.Forms.TextBox]::new();$operationOutput.Dock='Fill';$operationOutput.Multiline=$true;$operationOutput.ReadOnly=$true;$operationOutput.ScrollBars='Vertical';$operationOutput.WordWrap=$true
    $operationOutput.BackColor=Get-ManagerColor '#101C29';$operationOutput.ForeColor=Get-ManagerColor '#C5D4E4';$operationOutput.BorderStyle='None';$operationOutput.AccessibleName='Løbende output'
    $operationPanel.Controls.Add($operationTitle,0,0);$operationPanel.Controls.Add($operationMeta,0,1);$operationPanel.Controls.Add($operationOutput,1,0);$operationPanel.SetRowSpan($operationOutput,2)
    $root.Controls.Add($operationPanel,0,3)

    $tabs=[Windows.Forms.TabControl]::new()
    $tabs.Dock='Fill'
    $tabs.Padding=[Drawing.Point]::new(18,6)
    $overview=[Windows.Forms.TabPage]::new('Værktøjer')
    $detailsTab=[Windows.Forms.TabPage]::new('Versionsnyt')
    $historyTab=[Windows.Forms.TabPage]::new('Historik')
    $activity=[Windows.Forms.TabPage]::new('Aktivitet')
    foreach ($tab in @($overview,$detailsTab,$historyTab,$activity)) {
        $tab.BackColor=$form.BackColor
        $tab.Padding=[Windows.Forms.Padding]::new(8)
        [void]$tabs.TabPages.Add($tab)
    }
    $root.Controls.Add($tabs,0,4)

    $overviewRoot=[Windows.Forms.TableLayoutPanel]::new();$overviewRoot.Dock='Fill';$overviewRoot.RowCount=2;$overviewRoot.ColumnCount=1
    [void]$overviewRoot.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,54));[void]$overviewRoot.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $overviewTools=[Windows.Forms.FlowLayoutPanel]::new();$overviewTools.Dock='Fill';$overviewTools.WrapContents=$false
    $typeFilter=[Windows.Forms.ComboBox]::new();$typeFilter.DropDownStyle='DropDownList';$typeFilter.Width=118;$typeFilter.Margin=[Windows.Forms.Padding]::new(0,8,10,0)
    [void]$typeFilter.Items.AddRange([object[]]@('Alle typer','Apps','CLI'));$typeFilter.SelectedIndex=0;$typeFilter.AccessibleName='Filtrér på type';$typeFilter.add_SelectedIndexChanged({Refresh-Dashboard})
    $resultSummary=New-ManagerLabel 'Viser 0 af 0' 9;$resultSummary.Dock='None';$resultSummary.Width=280;$resultSummary.Height=38;$resultSummary.Margin=[Windows.Forms.Padding]::new(0,5,8,0)
    $showAll=New-ManagerButton 'Vis alle';$showAll.Width=96;$showAll.AccessibleName='Vis alle værktøjer';$showAll.add_Click({$script:ui.Search.Text='';$script:ui.TypeFilter.SelectedIndex=0;$script:ui.Filter.SelectedIndex=0;Refresh-Dashboard})
    $manage=New-ManagerButton 'Administrer';$manage.Width=112;$manage.AccessibleName='Administrer værktøjer';$manage.add_Click({Show-ManagerTools})
    $overviewTools.Controls.AddRange([Windows.Forms.Control[]]@($typeFilter,$resultSummary,$showAll,$manage));$overviewRoot.Controls.Add($overviewTools,0,0)
    $scroll=[Windows.Forms.Panel]::new()
    $scroll.Dock='Fill'
    $scroll.AutoScroll=$true
    $cards=[Windows.Forms.TableLayoutPanel]::new()
    $cards.Dock='Top'
    $cards.AutoSize=$true
    $cards.AutoSizeMode='GrowAndShrink'
    $cards.ColumnCount=1
    [void]$cards.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $scroll.Controls.Add($cards)
    $overviewRoot.Controls.Add($scroll,0,1);$overview.Controls.Add($overviewRoot)
    $cardMap=@{}
    foreach ($tool in $Catalog) {$cardMap[$tool.Key]=Create-ToolCard $tool.Key $tool.Name $tool.Type;$cardMap[$tool.Key].Card.Dock='Top';$cardMap[$tool.Key].Card.Tag=$tool.Key}
    $empty=New-ManagerLabel 'Ingen værktøjer matcher din søgning og dit filter.' 12
    $empty.Dock='Top'
    $empty.Height=64
    $empty.Visible=$false
    [void]$cards.Controls.Add($empty)

    $detailsRoot=[Windows.Forms.TableLayoutPanel]::new()
    $detailsRoot.Dock='Fill'
    $detailsRoot.RowCount=2
    $detailsRoot.ColumnCount=1
    [void]$detailsRoot.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,62))
    [void]$detailsRoot.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    $detailsHeader=[Windows.Forms.TableLayoutPanel]::new()
    $detailsHeader.Dock='Fill'
    $detailsHeader.RowCount=2
    $detailsHeader.ColumnCount=2
    [void]$detailsHeader.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,60))
    [void]$detailsHeader.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,40))
    [void]$detailsHeader.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$detailsHeader.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,142))
    $detailsTitle=New-ManagerLabel 'Versionsnyt' 17 $true
    $detailsStatus=New-ManagerLabel 'Vælg Se nyheder på et værktøj. Kildetekst vises på originalsproget.' 9
    $detailsStatus.ForeColor=Get-ManagerColor '#91A8BF'
    $detailsRefresh=New-ManagerButton 'Hent igen'
    $detailsRefresh.Dock='Fill'
    $detailsRefresh.Margin=[Windows.Forms.Padding]::new(10,10,0,10)
    $detailsRefresh.Enabled=$false
    $detailsRefresh.add_Click({param($sender,$eventArgs)
        if ($sender.Tag) {Show-ToolDetails -Key ([string]$sender.Tag) -Force}
    })
    $detailsHeader.Controls.Add($detailsTitle,0,0)
    $detailsHeader.Controls.Add($detailsStatus,0,1)
    $detailsHeader.Controls.Add($detailsRefresh,1,0)
    $detailsHeader.SetRowSpan($detailsRefresh,2)
    $detailsRoot.Controls.Add($detailsHeader,0,0)
    $releaseTabs=[Windows.Forms.TabControl]::new()
    $releaseTabs.Dock='Fill'
    $releaseTabs.Padding=[Drawing.Point]::new(16,5)
    $versionsPage=[Windows.Forms.TabPage]::new('Installeret og tilgængelig')
    $versionsPage.BackColor=$form.BackColor
    $versionsPage.Padding=[Windows.Forms.Padding]::new(6)
    $rangePage=[Windows.Forms.TabPage]::new('Nyt siden din version')
    $rangePage.BackColor=$form.BackColor
    $rangePage.Padding=[Windows.Forms.Padding]::new(6)
    [void]$releaseTabs.TabPages.Add($versionsPage)
    [void]$releaseTabs.TabPages.Add($rangePage)
    $releaseHost=[Windows.Forms.TableLayoutPanel]::new()
    $releaseHost.Dock='Fill'
    $releaseHost.ColumnCount=2
    $releaseHost.RowCount=1
    [void]$releaseHost.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100))
    [void]$releaseHost.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,50))
    [void]$releaseHost.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,50))
    $installedPanel=New-ReleaseNotesPanel 'INSTALLERET VERSION' '#91BFF0' 'Installerede ændringsnoter'
    $availablePanel=New-ReleaseNotesPanel 'TILGÆNGELIG VERSION' '#65DCC2' 'Tilgængelige ændringsnoter'
    $installedPanel.Container.Margin=[Windows.Forms.Padding]::new(0,0,6,0)
    $availablePanel.Container.Margin=[Windows.Forms.Padding]::new(6,0,0,0)
    $releaseHost.Controls.Add($installedPanel.Container,0,0)
    $releaseHost.Controls.Add($availablePanel.Container,1,0)
    $versionsPage.Controls.Add($releaseHost)
    $rangePanel=New-ReleaseNotesPanel 'NYT SIDEN DIN VERSION' '#D1A7F7' 'Ændringsnoter siden installeret version'
    $rangePanel.Container.Margin=[Windows.Forms.Padding]::new(0)
    $rangePage.Controls.Add($rangePanel.Container)
    $detailsRoot.Controls.Add($releaseTabs,0,1)
    $detailsTab.Controls.Add($detailsRoot)

    $historyRoot=[Windows.Forms.TableLayoutPanel]::new()
    $historyRoot.Dock='Fill';$historyRoot.RowCount=2;$historyRoot.ColumnCount=1
    [void]$historyRoot.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,60))
    [void]$historyRoot.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,40))
    $historyGrid=[Windows.Forms.DataGridView]::new()
    $historyGrid.Dock='Fill';$historyGrid.ReadOnly=$true;$historyGrid.AllowUserToAddRows=$false;$historyGrid.AllowUserToDeleteRows=$false
    $historyGrid.AllowUserToResizeRows=$false;$historyGrid.MultiSelect=$false;$historyGrid.SelectionMode='FullRowSelect';$historyGrid.RowHeadersVisible=$false
    $historyGrid.AutoGenerateColumns=$false;$historyGrid.AutoSizeColumnsMode='Fill';$historyGrid.BackgroundColor=Get-ManagerColor '#101C29';$historyGrid.BorderStyle='None'
    $historyGrid.EnableHeadersVisualStyles=$false;$historyGrid.ColumnHeadersDefaultCellStyle.BackColor=Get-ManagerColor '#223246';$historyGrid.ColumnHeadersDefaultCellStyle.ForeColor=Get-ManagerColor '#E8F0F8'
    $historyGrid.DefaultCellStyle.BackColor=Get-ManagerColor '#172536';$historyGrid.DefaultCellStyle.ForeColor=Get-ManagerColor '#D7E3EF';$historyGrid.DefaultCellStyle.SelectionBackColor=Get-ManagerColor '#2A5363';$historyGrid.DefaultCellStyle.SelectionForeColor=Get-ManagerColor '#FFFFFF'
    foreach($column in @(
        @('Time','Tidspunkt',24),@('Program','Program',24),@('Before','Fra',13),@('After','Til',13),@('Result','Resultat',26)
    )) {
        $gridColumn=[Windows.Forms.DataGridViewTextBoxColumn]::new();$gridColumn.Name=$column[0];$gridColumn.HeaderText=$column[1];$gridColumn.FillWeight=$column[2]
        [void]$historyGrid.Columns.Add($gridColumn)
    }
    $historyOutput=[Windows.Forms.TextBox]::new();$historyOutput.Dock='Fill';$historyOutput.Multiline=$true;$historyOutput.ReadOnly=$true;$historyOutput.ScrollBars='Vertical';$historyOutput.WordWrap=$true
    $historyOutput.BackColor=Get-ManagerColor '#101C29';$historyOutput.ForeColor=Get-ManagerColor '#C5D4E4';$historyOutput.BorderStyle='None';$historyOutput.AccessibleName='Detaljer for valgt historikpost'
    $historyGrid.Tag=$historyOutput
    $historyGrid.add_SelectionChanged({param($sender,$eventArgs)
        if ($sender.SelectedRows.Count) {
            $entry=$sender.SelectedRows[0].Tag
            $sender.Tag.Text=if ($entry -and $entry.Output) {[string]$entry.Output} else {'Ingen output registreret.'}
        }
    })
    $historyRoot.Controls.Add($historyGrid,0,0);$historyRoot.Controls.Add($historyOutput,0,1);$historyTab.Controls.Add($historyRoot)

    $log=[Windows.Forms.TextBox]::new()
    $log.Dock='Fill'
    $log.Multiline=$true
    $log.ReadOnly=$true
    $log.ScrollBars='Both'
    $log.WordWrap=$false
    $log.BackColor=Get-ManagerColor '#101C29'
    $log.ForeColor=Get-ManagerColor '#C5D4E4'
    $log.Font=[Drawing.Font]::new('Consolas',9)
    $log.BorderStyle='None'
    $activity.Controls.Add($log)

    $settings=[Windows.Forms.FlowLayoutPanel]::new()
    $settings.Dock='Fill'
    $settings.WrapContents=$false
    $startup=[Windows.Forms.CheckBox]::new()
    $startup.Text='Start med Windows'
    $startup.AutoSize=$true
    $startup.Margin=[Windows.Forms.Padding]::new(0,13,20,0)
    $notifications=[Windows.Forms.CheckBox]::new()
    $notifications.Text='Notifikationer'
    $notifications.AutoSize=$true
    $notifications.Margin=[Windows.Forms.Padding]::new(0,13,20,0)
    $intervalLabel=New-ManagerLabel 'Tjek hvert' 9
    $intervalLabel.Dock='None'
    $intervalLabel.Width=72
    $intervalLabel.Margin=[Windows.Forms.Padding]::new(0,12,0,0)
    $interval=[Windows.Forms.ComboBox]::new()
    $interval.DropDownStyle='DropDownList'
    $interval.Width=112
    $interval.Margin=[Windows.Forms.Padding]::new(0,10,16,0)
    [void]$interval.Items.AddRange([object[]]@('15 min.','30 min.','60 min.','120 min.','240 min.'))
    $hide=New-ManagerButton 'Skjul til bakken'
    $hide.Width=142
    $hide.add_Click({$script:ui.Form.Hide(); Save-RuntimeState})
    $settings.Controls.AddRange([Windows.Forms.Control[]]@($startup,$notifications,$intervalLabel,$interval,$hide))
    $root.Controls.Add($settings,0,5)
    $status=New-ManagerLabel 'Klar til versionskontrol' 9
    $status.ForeColor=Get-ManagerColor '#91A8BF'
    $root.Controls.Add($status,0,6)

    $tooltip=[Windows.Forms.ToolTip]::new()
    $tooltip.AutoPopDelay=20000
    $tooltip.SetToolTip($update,'Opdaterer kun installerede værktøjer med en bekræftet nyere version.')
    $tooltip.SetToolTip($search,'Søg på værktøjets navn eller type, fx CLI eller desktop.')
    $result=@{
        Form=$form
        Cards=$cardMap
        CardPanel=$scroll
        CardHost=$cards
        GroupHeaders=@{}
        Catalog=@($Catalog)
        Empty=$empty
        Metrics=$metrics
        Check=$check
        Update=$update
        Filter=$filter
        TypeFilter=$typeFilter
        ResultSummary=$resultSummary
        ShowAll=$showAll
        Manage=$manage
        Search=$search
        Progress=$progress
        Log=$log
        Tabs=$tabs
        DetailsTab=$detailsTab
        HistoryTab=$historyTab
        HistoryGrid=$historyGrid
        HistoryOutput=$historyOutput
        DetailsTitle=$detailsTitle
        DetailsStatus=$detailsStatus
        DetailsRefresh=$detailsRefresh
        ReleasePanels=@{Installed=$installedPanel; Available=$availablePanel}
        ReleaseTabs=$releaseTabs
        RangePanel=$rangePanel
        OperationPanel=$operationPanel
        OperationTitle=$operationTitle
        OperationMeta=$operationMeta
        OperationOutput=$operationOutput
        Startup=$startup
        Notifications=$notifications
        Interval=$interval
        Status=$status
        Tooltip=$tooltip
        Subtitle=$subtitle
        Root=$root
    }
    Update-ManagerCardLayout $result $null
    $form.ResumeLayout($true)
    return $result
}

function Update-ManagerCardLayout {
    param($UI, $StatusMap)
    if (-not $UI.CardHost) {return}
    $UI.CardHost.SuspendLayout()
    try {
        $UI.CardHost.Controls.Clear()
        $UI.GroupHeaders=@{}
        foreach($group in @(@('Apps','App'),@('CLI','CLI'))) {
            $groupName=[string]$group[0]
            $kind=[string]$group[1]
            $entries=@(
                foreach($key in $UI.Cards.Keys) {
                    $controls=$UI.Cards[$key]
                    if (-not [bool]$controls.MatchesView) {continue}
                    $item=if ($StatusMap -and $StatusMap.Contains($key)) {$StatusMap[$key]} else {$null}
                    $type=if ($item -and $item.Type) {[string]$item.Type} elseif ($controls.TypeLabel.Text -eq 'KOMMANDOLINJE') {'CLI'} else {'App'}
                    if (($kind -eq 'CLI') -ne ($type -eq 'CLI')) {continue}
                    [pscustomobject]@{Key=[string]$key;Controls=$controls;UpdateRank=$(if ($item -and [bool]$item.HasUpdate) {0} else {1});Name=[string]$controls.NameLabel.Text}
                }
            ) | Sort-Object UpdateRank,Name
            if (-not $entries.Count) {continue}
            $header=New-ManagerGroupHeader $groupName
            $UI.GroupHeaders[$groupName]=$header
            [void]$UI.CardHost.Controls.Add($header)
            foreach($entry in $entries) {[void]$UI.CardHost.Controls.Add($entry.Controls.Card)}
        }
        $visibleCount=@($UI.Cards.Values | Where-Object {[bool]$_.MatchesView}).Count
        $UI.Empty.Text=if ($UI.Cards.Count -eq 0) {'Ingen værktøjer overvåges. Vælg Administrer for at vise eller tilføje værktøjer.'} else {'Ingen værktøjer matcher din søgning og dit filter.'}
        $UI.Empty.Visible=($visibleCount -eq 0)
        if ($UI.Empty.Visible) {[void]$UI.CardHost.Controls.Add($UI.Empty)}
    } finally {$UI.CardHost.ResumeLayout($true)}
}

function Set-ManagerDashboardCatalog {
    param($UI, $Catalog)
    foreach($old in @($UI.Cards.Values)) {if ($old.Card) {$old.Card.Dispose()}}
    $cardMap=@{}
    foreach($tool in @($Catalog)) {
        $cardMap[[string]$tool.Key]=Create-ToolCard ([string]$tool.Key) ([string]$tool.Name) ([string]$tool.Type)
        $factor=$UI.Form.DeviceDpi/96.0
        if ([Math]::Abs($factor-1) -gt 0.01) {$cardMap[[string]$tool.Key].Card.Scale([Drawing.SizeF]::new($factor,$factor))}
        $cardMap[[string]$tool.Key].Card.Dock='Top'
        $cardMap[[string]$tool.Key].Card.Tag=[string]$tool.Key
        $cardMap[[string]$tool.Key].Card.Visible=$true
        $cardMap[[string]$tool.Key].MatchesView=$true
    }
    $UI.Cards=$cardMap
    $UI.Catalog=@($Catalog)
    if ($UI.Subtitle) {$UI.Subtitle.Text="$(@($Catalog).Count) værktøjer · versioner, opdateringer og versionsnyt samlet ét sted"}
    Update-ManagerCardLayout $UI $null
}

function Set-DashboardStatus {
    param($UI, $StatusMap, [bool]$Busy)
    $counts=@{Updates=0;Current=0;Attention=0}
    $bulkUpdates=0
    $visible=0
    $query=if ($UI.Search) {$UI.Search.Text.Trim().ToLowerInvariant()} else {''}
    foreach ($key in $UI.Cards.Keys) {
        $controls=$UI.Cards[$key]
        $item=if ($StatusMap -and $StatusMap.Contains($key)) {$StatusMap[$key]} else {$null}
        if (-not $item) {
            $controls.ButtonUpdate.Enabled=$false
            if ($controls.ButtonOpen) {$controls.ButtonOpen.Enabled=$false}
            $controls.MatchesView=$false
            $controls.Card.Visible=$false
            continue
        }
        $controls.LabelInstalled.Text=if ($item.Installed) {$item.Installed} else {'—'}
        $controls.LabelLatest.Text=if ($item.Latest) {$item.Latest} else {'Ukendt'}
        $color='#E8B978';$detail=''
        switch ($item.State) {
            'Update' {$text='Opdatering klar';$color='#65DCC2';$counts.Updates++;if ($item.HasUpdate) {$bulkUpdates++}}
            'NeedsClose' {
                if ($item.HasUpdate) {$counts.Updates++}
                if ($key -eq 'claude_app') {
                    $text='Luk Claude helt først';$detail='Ved uret > Quit/Afslut'
                    if ($item.Error -like 'Cowork*') {$text='Cowork blokerer';$detail='Baggrundstjeneste kører'}
                } elseif ($item.HasUpdate) {$text='Opdatering klar';$detail='Luk appen først';$color='#65DCC2'}
                else {$text='Luk appen først';$detail='Tjek igen efter lukning'}
                $counts.Attention++
            }
            'Current' {$text='Opdateret';$color='#9DCDB0';$counts.Current++}
            'Ahead' {$text='Nyere end kilden';$color='#91BFF0';$counts.Current++}
            'Missing' {$text='Ikke installeret';$detail='Installer separat';$counts.Attention++}
            'Error' {$text='Kontrol fejlede';$detail='Se Aktivitet for detaljer';$counts.Attention++}
            default {$text='Ikke bekræftet';$detail='Se Aktivitet for detaljer';$counts.Attention++}
        }
        $controls.LabelBadge.Text=$text;$controls.LabelBadge.ForeColor=Get-ManagerColor $color;$controls.LabelDetail.Text=$detail
        $UI.Tooltip.SetToolTip($controls.LabelBadge, "$($item.Source)`n$($item.Error)")
        $UI.Tooltip.SetToolTip($controls.LabelDetail, [string]$item.Error)
        $UI.Tooltip.SetToolTip($controls.ButtonUpdate, [string]$item.Error)
        $UI.Tooltip.SetToolTip($controls.NameLabel, "$($item.Source)`n$($item.Path)")
        $controls.ButtonUpdate.Enabled=([bool]$item.HasUpdate -and -not $Busy)
        $controls.ButtonUpdate.BackColor=Get-ManagerColor $(if ($controls.ButtonUpdate.Enabled) {'#65DCC2'} else {'#91A5BA'})
        $controls.ButtonUpdate.ForeColor=Get-ManagerColor $(if ($controls.ButtonUpdate.Enabled) {'#0B2923'} else {'#93A6BA'})
        $controls.ButtonUpdate.Text=if ($item.State -eq 'NeedsClose') {'Tjek igen'} elseif ($item.HasUpdate) {'Opdatér'} elseif ($item.State -in @('Current','Ahead')) {'Ajour'} else {'—'}
        if ($controls.ButtonOpen) {
            $controls.ButtonOpen.Enabled=([bool](Get-ReleaseNotesValue $item 'CanLaunch' $false) -and -not $Busy)
            $controls.ButtonOpen.BackColor=Get-ManagerColor $(if ($controls.ButtonOpen.Enabled) {'#223246'} else {'#91A5BA'})
            $controls.ButtonOpen.ForeColor=Get-ManagerColor $(if ($controls.ButtonOpen.Enabled) {'#E8F0F8'} else {'#1B2D3F'})
            $UI.Tooltip.SetToolTip($controls.ButtonOpen, $(if ($controls.ButtonOpen.Enabled) {'Åbn den installerede app.'} else {'Appen kan ikke åbnes fra denne status.'}))
        }
        $matchesFilter=$UI.Filter.SelectedIndex -eq 0 -or
            ($UI.Filter.SelectedIndex -eq 1 -and [bool]$item.HasUpdate) -or
            ($UI.Filter.SelectedIndex -eq 2 -and $item.State -in @('Missing','Error','Unknown','NeedsClose')) -or
            ($UI.Filter.SelectedIndex -eq 3 -and $item.State -in @('Current','Ahead'))
        $matchesType=$UI.TypeFilter.SelectedIndex -eq 0 -or
            ($UI.TypeFilter.SelectedIndex -eq 1 -and $item.Type -ne 'CLI') -or
            ($UI.TypeFilter.SelectedIndex -eq 2 -and $item.Type -eq 'CLI')
        $searchText=("$($controls.NameLabel.Text) $($item.Type) $($controls.TypeLabel.Text)").ToLowerInvariant()
        $matchesSearch=(-not $query -or $searchText.Contains($query))
        $show=$matchesFilter -and $matchesType -and $matchesSearch
        $controls.MatchesView=$show
        $controls.Card.Visible=$show
        if ($show) {$visible++}
    }
    foreach ($key in $counts.Keys) {$UI.Metrics[$key].Text=[string]$counts[$key]}
    $total=$UI.Cards.Count
    $UI.ResultSummary.Text="Viser $visible af $total" + $(if ($visible -lt $total) {" · $($total-$visible) skjult af søgning eller filter"} else {''})
    $UI.Update.Enabled=($bulkUpdates -gt 0 -and -not $Busy)
    $UI.Check.Enabled=-not $Busy
    $UI.Progress.Visible=$Busy
    Update-ManagerCardLayout $UI $StatusMap
}

function Get-ReleaseNotesValue {
    param($Item, [string]$Name, $Default=$null)
    if (-not $Item) {return $Default}
    $property=$Item.PSObject.Properties[$Name]
    if (-not $property) {return $Default}
    return $property.Value
}

function Format-ReleaseNotesTime {
    param($Value)
    if (-not $Value) {return ''}
    try {return ([datetime]$Value).ToLocalTime().ToString('dd. MMM yyyy HH:mm')} catch {return [string]$Value}
}

function Set-OneReleaseNotesPanel {
    param($Panel, $Release, [bool]$Loading)
    $Panel.Source.Tag=$null
    $Panel.Source.Enabled=$false
    if ($Loading) {
        $Panel.Version.Text='—'
        $Panel.Meta.Text='Henter fra kilden …'
        $Panel.Meta.ForeColor=Get-ManagerColor '#91A8BF'
        $Panel.Body.Text='Henter ændringsnoter …'
        return
    }
    $state=[string](Get-ReleaseNotesValue $Release 'State' 'Unavailable')
    $message=[string](Get-ReleaseNotesValue $Release 'Message' '')
    $version=[string](Get-ReleaseNotesValue $Release 'Version' '')
    $body=[string](Get-ReleaseNotesValue $Release 'Body' '')
    $sourceUrl=[string](Get-ReleaseNotesValue $Release 'SourceUrl' '')
    $published=Format-ReleaseNotesTime (Get-ReleaseNotesValue $Release 'PublishedAt' '')
    $retrieved=Format-ReleaseNotesTime (Get-ReleaseNotesValue $Release 'RetrievedAt' '')
    $isStale=[bool](Get-ReleaseNotesValue $Release 'IsStale' $false)
    $exact=[bool](Get-ReleaseNotesValue $Release 'ExactVersion' $false)
    $Panel.Version.Text=if ($version) {$version} else {'Ikke oplyst'}
    $metaParts=[Collections.Generic.List[string]]::new()
    if ($published) {$metaParts.Add("Udgivet $published")}
    if ($retrieved) {$metaParts.Add("Hentet $retrieved")}
    if ($isStale) {$metaParts.Add('Ældre cache')}
    if ($state -eq 'Ready' -and -not $exact) {$metaParts.Add('Ikke eksakt versionsmatch')}
    if ($message) {$metaParts.Add($message)}
    if (-not $metaParts.Count) {$metaParts.Add($(if ($state -eq 'Ready') {'Aktuel kilde'} else {'Ingen friskhedsdata'}))}
    $Panel.Meta.Text=$metaParts -join "`r`n"
    $Panel.Meta.ForeColor=Get-ManagerColor $(if ($isStale -or $state -ne 'Ready') {'#E8B978'} else {'#91A8BF'})
    switch ($state) {
        'Ready' {
            $notes=if ($body) {$body} else {'Kilden indeholder ingen ændringsnoter for denne version.'}
            $Panel.Body.Text=if ($message) {"Bemærkning:`r`n$message`r`n`r`n$notes"} else {$notes}
        }
        'Error' {$Panel.Body.Text="Versionsnyt kunne ikke hentes.`r`n`r`n$(if ($message) {$message} else {'Ukendt fejl.'})"}
        default {$Panel.Body.Text="Versionsnyt er ikke tilgængeligt.`r`n`r`n$(if ($message) {$message} else {'Kilden har ingen noter for denne version.'})"}
    }
    if ($sourceUrl) {
        $Panel.Source.Tag=$sourceUrl
        $Panel.Source.Enabled=$true
    }
}

function Set-ReleaseNotesView {
    param($UI, $ToolStatus, $Bundle, [bool]$Loading)
    if (-not $Loading -and -not $ToolStatus -and -not $Bundle) {
        $UI.DetailsTitle.Text='Versionsnyt'
        $UI.DetailsStatus.Text='Vælg Se nyheder på et værktøj. Kildetekst vises på originalsproget.'
        $UI.DetailsRefresh.Tag=$null;$UI.DetailsRefresh.Enabled=$false
        foreach($panel in @($UI.ReleasePanels.Installed,$UI.ReleasePanels.Available,$UI.RangePanel)) {
            $panel.Version.Text='—';$panel.Meta.Text='Afventer valg af værktøj';$panel.Meta.ForeColor=Get-ManagerColor '#91A8BF'
            $panel.Body.Text='Vælg Se nyheder på et værktøj for at hente ændringsnoter.';$panel.Source.Tag=$null;$panel.Source.Enabled=$false
        }
        return
    }
    $toolName=if ($ToolStatus -and $ToolStatus.Name) {$ToolStatus.Name} elseif ($ToolStatus -and $ToolStatus.Key) {$ToolStatus.Key} else {'Valgt værktøj'}
    $toolKey=if ($ToolStatus -and $ToolStatus.Key) {[string]$ToolStatus.Key} else {''}
    $UI.DetailsTitle.Text="Versionsnyt · $toolName"
    $UI.DetailsRefresh.Tag=$toolKey
    $UI.DetailsRefresh.Enabled=(-not $Loading -and [bool]$toolKey)
    if ($Loading) {
        $UI.DetailsStatus.Text='Henter versionsnyt … vinduet kan fortsat bruges.'
        Set-OneReleaseNotesPanel $UI.ReleasePanels.Installed $null $true
        Set-OneReleaseNotesPanel $UI.ReleasePanels.Available $null $true
        Set-OneReleaseNotesPanel $UI.RangePanel $null $true
        return
    }
    $installed=if ($Bundle) {$Bundle.Installed} else {$null}
    $available=if ($Bundle) {$Bundle.Available} else {$null}
    $range=if ($Bundle) {$Bundle.Range} else {$null}
    Set-OneReleaseNotesPanel $UI.ReleasePanels.Installed $installed $false
    Set-OneReleaseNotesPanel $UI.ReleasePanels.Available $available $false
    if (-not $range) {
        Set-OneReleaseNotesPanel $UI.RangePanel $null $false
        $UI.RangePanel.Version.Text='Afventer'
        $UI.RangePanel.Meta.Text='Versionsinterval er endnu ikke tilgængeligt.'
        $UI.RangePanel.Body.Text='Nyt siden din version vises, når intervallet er beregnet.'
    } else {
        Set-OneReleaseNotesPanel $UI.RangePanel $range $false
        $from=[string](Get-ReleaseNotesValue $range 'FromVersion' '')
        $to=[string](Get-ReleaseNotesValue $range 'ToVersion' '')
        if ($from -or $to) {$UI.RangePanel.Version.Text="Fra $from  →  Til $to"}
        $releaseCount=Get-ReleaseNotesValue $range 'ReleaseCount' $null
        $complete=[bool](Get-ReleaseNotesValue $range 'Complete' $false)
        $rangeMeta=[Collections.Generic.List[string]]::new()
        if ($null -ne $releaseCount) {$rangeMeta.Add("$releaseCount udgivelser")}
        if (-not $complete) {$rangeMeta.Add('Ufuldstændig dækning')}
        if ($UI.RangePanel.Meta.Text) {$rangeMeta.Add($UI.RangePanel.Meta.Text)}
        $UI.RangePanel.Meta.Text=$rangeMeta -join "`r`n"
        if (-not $complete) {$UI.RangePanel.Meta.ForeColor=Get-ManagerColor '#E8B978'}
    }
    $issues=[Collections.Generic.List[string]]::new()
    foreach ($release in @($installed,$available,$range)) {
        $state=[string](Get-ReleaseNotesValue $release 'State' 'Unavailable')
        if ($state -ne 'Ready') {
            if ($release -eq $range -and $state -eq 'Unavailable') {
                try {if ((Compare-ToolVersion $range.FromVersion $range.ToVersion) -ge 0) {continue}} catch {}
            }
            $message=[string](Get-ReleaseNotesValue $release 'Message' '')
            if ($message -and -not $issues.Contains($message)) {$issues.Add($message)}
        }
    }
    if ($issues.Count) {
        $UI.DetailsStatus.Text="Nogle oplysninger kunne ikke hentes: $($issues -join ' · ') · Kildetekst vises på originalsproget."
    } elseif ([bool](Get-ReleaseNotesValue $installed 'IsStale' $false) -or [bool](Get-ReleaseNotesValue $available 'IsStale' $false) -or [bool](Get-ReleaseNotesValue $range 'IsStale' $false)) {
        $UI.DetailsStatus.Text='Mindst ét panel viser en ældre cache · Kildetekst vises på originalsproget.'
    } else {
        $UI.DetailsStatus.Text='Kildetekst vises på originalsproget · Brug Åbn kilde for den oprindelige udgivelse.'
    }
}

function Set-ManagerHistoryView {
    param($UI, $Entries)
    $UI.HistoryGrid.Rows.Clear()
    $ordered=@($Entries | Sort-Object @{Expression={
        $timeValue=if ($_.CompletedAt) {$_.CompletedAt} else {$_.StartedAt}
        try {[datetime]$timeValue} catch {[datetime]::MinValue}
    };Descending=$true})
    foreach($entry in $ordered) {
        $outcome=[string]$entry.Outcome
        $resultText=switch($outcome) {
            'Success' {'Gennemført'}
            'Failed' {'Mislykkedes'}
            'Blocked' {'Blokeret'}
            'Interrupted' {'Afbrudt'}
            'Detected' {'Registreret ændring'}
            'Pending' {'Afventer'}
            default {$outcome}
        }
        if ($outcome -eq 'Detected') {
            $timeValue=if ($entry.CompletedAt) {$entry.CompletedAt} else {$entry.StartedAt}
            $timeText="Registreret $(Format-ReleaseNotesTime $timeValue)"
        } else {
            $timeValue=if ($entry.CompletedAt) {$entry.CompletedAt} else {$entry.StartedAt}
            $timeText=Format-ReleaseNotesTime $timeValue
        }
        $index=$UI.HistoryGrid.Rows.Add($timeText,[string]$entry.Name,[string]$entry.Before,[string]$entry.After,$resultText)
        $UI.HistoryGrid.Rows[$index].Tag=$entry
    }
    if ($UI.HistoryGrid.Rows.Count) {
        $UI.HistoryGrid.Rows[0].Selected=$true
        $UI.HistoryOutput.Text=if ($UI.HistoryGrid.Rows[0].Tag.Output) {[string]$UI.HistoryGrid.Rows[0].Tag.Output} else {'Ingen output registreret.'}
    } else {$UI.HistoryOutput.Text='Ingen historik registreret.'}
}

function Set-ManagerOperationView {
    param($UI, $Operation)
    $rowStyle=$UI.Root.RowStyles[3]
    if (-not $Operation) {
        $UI.OperationPanel.Visible=$false
        $rowStyle.Height=0
        $UI.OperationTitle.Text='';$UI.OperationMeta.Text='';$UI.OperationOutput.Text=''
        return
    }
    $rowStyle.Height=[single](96 * $UI.Form.DeviceDpi / 96.0)
    $UI.OperationTitle.Text="$($Operation.Name) · $($Operation.Phase)".Trim(' ','·')
    $elapsed=[TimeSpan]::FromSeconds([Math]::Max(0,[double]$Operation.ElapsedSeconds))
    $elapsedText=if ($elapsed.TotalHours -ge 1) {$elapsed.ToString('hh\:mm\:ss')} else {$elapsed.ToString('mm\:ss')}
    $parts=[Collections.Generic.List[string]]::new()
    if ($Operation.Message) {$parts.Add([string]$Operation.Message)}
    $parts.Add("Tid $elapsedText")
    if ([int]$Operation.Total -gt 0) {$parts.Add("$([int]$Operation.Index) af $([int]$Operation.Total)")}
    $UI.OperationMeta.Text=$parts -join ' · '
    $output=[string]$Operation.Output
    if ($output.Length -gt 12000) {$output=$output.Substring($output.Length-12000)}
    $UI.OperationOutput.Text=$output
    $UI.OperationPanel.Visible=$true
}

function Show-ToolManagerDialog {
    param($Owner, $Catalog, $Configuration)
    $form=[Windows.Forms.Form]::new()
    $form.Text='Administrer værktøjer';$form.AccessibleName='Administrer værktøjer';$form.ClientSize=[Drawing.Size]::new(760,650);$form.MinimumSize=[Drawing.Size]::new(720,610)
    $form.StartPosition='CenterParent';$form.AutoScaleMode='Dpi';$form.AutoScaleDimensions=[Drawing.SizeF]::new(96,96);$form.BackColor=Get-ManagerColor '#0B1420';$form.ForeColor=Get-ManagerColor '#DCE7F3';$form.Font=[Drawing.Font]::new('Segoe UI',10)
    $state=@{CatalogKeys=[Collections.Generic.List[string]]::new();CustomTools=[Collections.ArrayList]::new();Result=$null};$form.Tag=$state
    foreach($tool in @($Configuration.CustomTools)) {[void]$state.CustomTools.Add($tool)}

    $root=[Windows.Forms.TableLayoutPanel]::new();$root.Dock='Fill';$root.Padding=[Windows.Forms.Padding]::new(18);$root.RowCount=7;$root.ColumnCount=1
    foreach($height in @(52,180,38,162,44,48)) {[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,$height))}
    # An owned dialog may be created in an already scaled UI thread. Let the
    # input controls determine their row heights instead of dividing 162 pixels.
    $root.RowStyles[3].SizeType=[Windows.Forms.SizeType]::AutoSize
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100));$form.Controls.Add($root)
    $intro=New-ManagerLabel 'Markér katalogværktøjer, der skal overvåges. Skjulte værktøjer kan altid vises igen.' 9 $true;$intro.AutoEllipsis=$false;$root.Controls.Add($intro,0,0)
    $catalogList=[Windows.Forms.CheckedListBox]::new();$catalogList.Name='CatalogList';$catalogList.Dock='Fill';$catalogList.CheckOnClick=$true;$catalogList.BackColor=Get-ManagerColor '#172536';$catalogList.ForeColor=Get-ManagerColor '#DCE7F3';$catalogList.BorderStyle='FixedSingle';$catalogList.AccessibleName='Katalogværktøjer der overvåges'
    $hidden=@($Configuration.HiddenKeys)
    foreach($tool in @($Catalog)) {$state.CatalogKeys.Add([string]$tool.Key);[void]$catalogList.Items.Add("$($tool.Name) · $($tool.Type)", -not ($hidden -contains [string]$tool.Key))}
    $root.Controls.Add($catalogList,0,1)
    $customHeading=New-ManagerLabel 'Egne værktøjer' 10 $true;$root.Controls.Add($customHeading,0,2)
    $customArea=[Windows.Forms.TableLayoutPanel]::new();$customArea.Dock='Fill';$customArea.AutoSize=$true;$customArea.AutoSizeMode='GrowAndShrink';$customArea.ColumnCount=2;$customArea.RowCount=1
    [void]$customArea.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,40));[void]$customArea.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,60))
    $customList=[Windows.Forms.ListBox]::new();$customList.Name='CustomList';$customList.Dock='Fill';$customList.BackColor=$catalogList.BackColor;$customList.ForeColor=$catalogList.ForeColor
    foreach($tool in @($state.CustomTools)) {[void]$customList.Items.Add("$($tool.Name) · $($tool.Type)")}
    $fields=[Windows.Forms.TableLayoutPanel]::new();$fields.Dock='Fill';$fields.AutoSize=$true;$fields.AutoSizeMode='GrowAndShrink';$fields.ColumnCount=2;$fields.RowCount=5
    [void]$fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,175));[void]$fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
    foreach($unused in 1..5){[void]$fields.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))}
    $fieldSpecs=@(@('Navn','CustomName','Text'),@('Type','CustomType','Type'),@('Pakke-id','CustomPackageId','Text'),@('Kilde','CustomPackageSource','Source'),@('Startmenu-navn','CustomLaunchName','Text'))
    $fieldControls=@{}
    for($i=0;$i-lt$fieldSpecs.Count;$i++) {
        $label=New-ManagerLabel $fieldSpecs[$i][0] 9;$control=if($fieldSpecs[$i][2] -eq 'Text'){[Windows.Forms.TextBox]::new()}else{[Windows.Forms.ComboBox]::new()}
        $control.Name=$fieldSpecs[$i][1];$control.Dock='Fill';$control.Margin=[Windows.Forms.Padding]::new(4,2,4,2)
        $control.BackColor=Get-ManagerColor '#172536';$control.ForeColor=Get-ManagerColor '#E8F0F8'
        if($control -is [Windows.Forms.ComboBox]){$control.DropDownStyle='DropDownList';if($fieldSpecs[$i][2]-eq'Type'){[void]$control.Items.AddRange([object[]]@('App','CLI'))}else{[void]$control.Items.AddRange([object[]]@('winget','msstore'))};$control.SelectedIndex=0}
        elseif($fieldSpecs[$i][1]-eq'CustomName'){$control.MaxLength=64}
        elseif($fieldSpecs[$i][1]-eq'CustomPackageId'){$control.MaxLength=120}
        $fields.Controls.Add($label,0,$i);$fields.Controls.Add($control,1,$i);$fieldControls[$fieldSpecs[$i][1]]=$control
    }
    $customArea.Controls.Add($customList,0,0);$customArea.Controls.Add($fields,1,0);$root.Controls.Add($customArea,0,3)
    $customButtons=[Windows.Forms.FlowLayoutPanel]::new();$customButtons.Dock='Fill';$customButtons.FlowDirection='RightToLeft';$customButtons.WrapContents=$false
    $add=New-ManagerButton 'Tilføj';$add.Name='AddCustomTool';$add.AccessibleName='Tilføj eget værktøj'
    $delete=New-ManagerButton 'Slet valgt';$delete.Name='DeleteCustomTool';$delete.AccessibleName='Slet valgt eget værktøj'
    $customButtons.Controls.AddRange([Windows.Forms.Control[]]@($add,$delete));$root.Controls.Add($customButtons,0,4)
    $explanation=New-ManagerLabel 'Pakke-id skal findes i WinGet eller Microsoft Store. Kun installerede programmer opdateres. Dialogen søger eller installerer ikke.' 8
    $explanation.AutoEllipsis=$false;$explanation.ForeColor=Get-ManagerColor '#91A8BF';$root.Controls.Add($explanation,0,5)
    $actions=[Windows.Forms.FlowLayoutPanel]::new();$actions.Dock='Fill';$actions.FlowDirection='RightToLeft';$actions.WrapContents=$false
    $ok=New-ManagerButton 'Gem' $true;$ok.Name='ManagerToolsOk';$ok.AccessibleName='Gem værktøjsvalg'
    $cancel=New-ManagerButton 'Annuller';$cancel.Name='ManagerToolsCancel';$cancel.AccessibleName='Annuller værktøjsvalg'
    $actions.Controls.AddRange([Windows.Forms.Control[]]@($ok,$cancel));$root.Controls.Add($actions,0,6)
    $add.add_Click({
        $name=[string]$fieldControls.CustomName.Text;$packageId=[string]$fieldControls.CustomPackageId.Text
        $launchName=[string]$fieldControls.CustomLaunchName.Text
        if ($state.CustomTools.Count -ge 50 -or -not $name.Trim() -or $name.Trim().Length -gt 64 -or $packageId.Trim() -notmatch '^[A-Za-z0-9][A-Za-z0-9._+\-]{0,119}$' -or $launchName -match '[*?]') {return}
        $tool=[pscustomobject]@{Key=('custom_'+[guid]::NewGuid().ToString('N'));Name=$name.Trim();Type=[string]$fieldControls.CustomType.SelectedItem;PackageId=$packageId.Trim();PackageSource=[string]$fieldControls.CustomPackageSource.SelectedItem;LaunchName=$launchName.Trim()}
        [void]$state.CustomTools.Add($tool);[void]$customList.Items.Add("$($tool.Name) · $($tool.Type)")
        $fieldControls.CustomName.Text='';$fieldControls.CustomPackageId.Text='';$fieldControls.CustomLaunchName.Text=''
    })
    $delete.add_Click({
        if($customList.SelectedIndex -ge 0) {
            $index=$customList.SelectedIndex;$key=[string]$state.CustomTools[$index].Key
            $catalogIndex=$state.CatalogKeys.IndexOf($key)
            if ($catalogIndex -ge 0) {$state.CatalogKeys.RemoveAt($catalogIndex);$catalogList.Items.RemoveAt($catalogIndex)}
            $state.CustomTools.RemoveAt($index);$customList.Items.RemoveAt($index)
        }
    })
    $ok.add_Click({
        $hiddenKeys=[Collections.Generic.List[string]]::new();for($i=0;$i-lt$state.CatalogKeys.Count;$i++){if(-not$catalogList.GetItemChecked($i)){$hiddenKeys.Add($state.CatalogKeys[$i])}}
        $state.Result=[pscustomobject]@{HiddenKeys=[string[]]$hiddenKeys.ToArray();CustomTools=[object[]]@($state.CustomTools)}
        $form.DialogResult=[Windows.Forms.DialogResult]::OK;$form.Close()
    })
    $cancel.add_Click({$form.DialogResult=[Windows.Forms.DialogResult]::Cancel;$form.Close()})
    $dialogResult=if($Owner){$form.ShowDialog($Owner)}else{$form.ShowDialog()}
    $result=if($dialogResult-eq[Windows.Forms.DialogResult]::OK){$state.Result}else{$null}
    $form.Dispose()
    return $result
}
