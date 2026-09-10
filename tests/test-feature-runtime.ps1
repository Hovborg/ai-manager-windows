# Runs the real entry point and WinForms message loop with controlled installer/source boundaries.
# No real program is installed, updated or closed; all data belongs to this test directory.
param([string]$StateDirectory=(Join-Path $PSScriptRoot ('../artifacts/features-runtime-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$testRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$StateDirectory=[IO.Path]::GetFullPath($StateDirectory)
. "$testRoot/updater-core.ps1"
Save-ManagerJson (Join-Path $StateDirectory 'settings.json') @{Notifications=$false;CheckIntervalMinutes=60}
$script:fixtureRoot=Join-Path $StateDirectory 'worker';[void][IO.Directory]::CreateDirectory($script:fixtureRoot)
$coreFixture=@'
. '__CORE__'
$script:realProcess=${function:Invoke-ToolProcess}
function Get-OneToolStatus {
    param($Tool)
    $version=if ($Tool.Key -eq 'codex' -and (Test-Path (Join-Path $script:ManagerDataDirectory 'synthetic-updated'))) {'2.0.0'} else {'1.0.0'}
    $latest=if ($Tool.Key -eq 'codex') {'2.0.0'} else {'1.0.0'}
    $status=New-ToolStatus $Tool $version $latest 'synthetic' ''
    $status.CanLaunch=$Tool.Type -eq 'App';$status
}
function Invoke-ToolProcess {
    param($FilePath,$Arguments,$TimeoutSeconds)
    if (($Arguments -join ',') -ne 'update') {throw 'Synthetic fixture rejected an external operation'}
    $result=& $script:realProcess (Get-Process -Id $PID).Path @('-NoProfile','-Command','[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::WriteLine("Syntetisk installationsoutput: trin 1"); Start-Sleep -Milliseconds 2800; [Console]::WriteLine("Syntetisk installationsoutput: færdig")') 10
    [IO.File]::WriteAllText((Join-Path $script:ManagerDataDirectory 'synthetic-updated'),'2.0.0')
    $result
}
'@
[IO.File]::WriteAllText((Join-Path $script:fixtureRoot 'updater-core.ps1'),$coreFixture.Replace('__CORE__',(Join-Path $testRoot 'updater-core.ps1').Replace("'","''")))
$releaseFixture=@'
. '__RELEASES__'
function Invoke-ReleaseRequest([string]$Url) {
    if ($Url -like 'https://api.github.com/repos/openai/codex/releases/tags/*') {
        $tag=($Url -split '/')[-1]
        return (@{tag_name=$tag;body="Syntetiske noter for $tag";published_at='2026-09-10T10:00:00Z'} | ConvertTo-Json)
    }
    if ($Url -eq 'https://api.github.com/repos/openai/codex/releases?per_page=100&page=1') {
        return (ConvertTo-Json -InputObject @(foreach($v in @('2.0.0','1.5.0','1.0.0')) {@{tag_name="rust-v$v";body="Syntetiske noter for $v";draft=$false;prerelease=$false;published_at='2026-09-10T10:00:00Z'}}))
    }
    throw "Fixture rejected network: $Url"
}
'@
[IO.File]::WriteAllText((Join-Path $script:fixtureRoot 'updater-releases.ps1'),$releaseFixture.Replace('__RELEASES__',(Join-Path $testRoot 'updater-releases.ps1').Replace("'","''")))
Add-Type -AssemblyName System.Windows.Forms
$script:featurePhase='boot';$script:featureFailure='';$script:featureTicks=0;$script:featureEarly=$false;$script:openedKey=''
$script:featureDeadline=(Get-Date).AddSeconds(45)
function Save-FeatureImage([string]$Name) {
    $bitmap=[Drawing.Bitmap]::new($script:ui.Form.Width,$script:ui.Form.Height)
    try {$script:ui.Form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save((Join-Path $StateDirectory "$Name.png"))} finally {$bitmap.Dispose()}
}
function Start-ManagerApp($Tool) {$script:openedKey=$Tool.Key}
function Test-FeatureToolDialog {
    # Exercise the owned modal from the real message loop: its DPI context differs
    # from a standalone ShowDialog call made before Application.Run.
    $script:dialogFailure='';$script:featureDialogSeen=$false
    $dialogTimer=[Windows.Forms.Timer]::new();$dialogTimer.Interval=100
    $dialogTimer.add_Tick({
        $dialog=[Windows.Forms.Application]::OpenForms | Where-Object AccessibleName -eq 'Administrer værktøjer' | Select-Object -First 1
        if (-not $dialog) {return};$dialogTimer.Stop();$script:featureDialogSeen=$true
        try {
            $inputs=@('CustomName','CustomType','CustomPackageId','CustomPackageSource','CustomLaunchName' | ForEach-Object {$dialog.Controls.Find($_,$true)[0]})
            Save-ManagerJson (Join-Path $StateDirectory 'owned-dialog-layout.json') @(foreach ($field in $inputs) {@{Name=$field.Name;Top=$field.Top;Bottom=$field.Bottom;Height=$field.Height;PreferredHeight=$field.PreferredSize.Height;ParentHeight=$field.Parent.ClientSize.Height;Dpi=$dialog.DeviceDpi}})
            $bitmap=[Drawing.Bitmap]::new($dialog.Width,$dialog.Height)
            try {$dialog.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$bitmap.Width,$bitmap.Height));$bitmap.Save((Join-Path $StateDirectory 'owned-tool-dialog.png'))} finally {$bitmap.Dispose()}
            $previousBottom=0
            foreach ($field in $inputs) {
                $textHeight=[Windows.Forms.TextRenderer]::MeasureText('Ægj',$field.Font).Height
                if ($field.Top -lt $previousBottom -or $field.Bottom -gt $field.Parent.ClientSize.Height -or $field.ClientSize.Height -lt $textHeight) {throw "Owned tool dialog clips or overlaps $($field.Name) at $($dialog.DeviceDpi) DPI"}
                $previousBottom=$field.Bottom
            }
        } catch {$script:dialogFailure=$_.Exception.Message}
        finally {$dialog.Controls.Find('ManagerToolsCancel',$true)[0].PerformClick()}
    })
    try {$dialogTimer.Start();$script:ui.Manage.PerformClick()} finally {$dialogTimer.Stop();$dialogTimer.Dispose()}
    if (-not $script:featureDialogSeen) {throw 'The real Manage button did not open its dialog'}
    if ($script:dialogFailure) {throw $script:dialogFailure}
}
$script:featureTimer=[Windows.Forms.Timer]::new();$script:featureTimer.Interval=100
$script:featureTimer.add_Tick({
    try {
        $script:featureTicks++
        if ((Get-Date) -gt $script:featureDeadline) {throw "Feature runtime timeout: $script:featurePhase"}
        if (-not $script:ui) {return}
        switch ($script:featurePhase) {
            'boot' {
                # Swap only the worker's external boundaries before the initial two-second timer.
                $script:Root=$script:fixtureRoot
                function script:Start-ManagerApp($Tool) {$script:openedKey=$Tool.Key}
                $script:featurePhase='overview'
            }
            'overview' {
                if (-not $script:lastCheck -or $script:work) {return}
                if ($script:status.Count -ne 7 -or $script:ui.ResultSummary.Text -notmatch '7 af 7') {throw 'Real overview lost original tools'}
                $script:ui.TypeFilter.SelectedIndex=1;$script:ui.Search.Text='ChatGPT'
                if ($script:ui.ResultSummary.Text -notmatch '1 af 7') {throw 'Real search/type filtering failed'}
                $script:ui.ShowAll.PerformClick()
                if ($script:ui.ResultSummary.Text -notmatch '7 af 7' -or $script:ui.TypeFilter.SelectedIndex -ne 0 -or $script:ui.Search.Text) {throw 'Real Vis alle did not reset the view'}
                Save-FeatureImage 'overview'
                $script:featureTimer.Stop()
                Test-FeatureToolDialog
                $script:featureTimer.Start()
                $script:ui.Cards.codex.ButtonDetails.PerformClick();$script:featurePhase='range'
            }
            'range' {
                if ($script:releaseWork -or $script:releasePending) {return}
                $script:ui.ReleaseTabs.SelectedIndex=1
                if ($script:releaseBundle.Range.ReleaseCount -ne 2 -or -not $script:releaseBundle.Range.Complete -or $script:ui.RangePanel.Body.Text -notmatch '1.5.0' -or $script:ui.RangePanel.Body.Text -match 'noter for 1.0.0') {throw 'Actual range worker or renderer lost interval boundaries'}
                Save-FeatureImage 'range'
                $script:ui.Tabs.SelectedIndex=0
                $script:ui.Cards.codex.ButtonUpdate.PerformClick();$script:featurePhase='progress'
            }
            'progress' {
                if ($script:work -and $script:work.Kind -eq 'update' -and $script:ui.OperationOutput.Text -match 'trin 1') {
                    if (-not $script:ui.OperationPanel.Visible -or $script:ui.OperationTitle.Text -notmatch 'Codex CLI' -or $script:ui.OperationMeta.Text -notmatch 'Tid') {throw 'Actual operation view lacks program or elapsed time'}
                    if (-not $script:featureEarly) {Save-FeatureImage 'progress';$script:featureEarly=$true}
                }
                if ($script:work -or $script:status.codex.Installed -ne '2.0.0') {return}
                if (-not $script:featureEarly -or $script:ui.OperationPanel.Visible) {throw 'Live progress did not appear before exit or was not cleared'}
                $script:ui.Tabs.SelectedTab=$script:ui.HistoryTab
                $entries=@(Get-ManagerHistory $StateDirectory)
                if ($entries.Count -ne 1 -or $entries[0].Outcome -ne 'Success' -or $script:ui.HistoryGrid.Rows.Count -ne 1 -or $script:ui.HistoryOutput.Text -notmatch 'færdig') {throw 'Real update result did not reach persistent history and grid'}
                Save-FeatureImage 'history'
                $script:ui.Tabs.SelectedIndex=0
                $script:ui.Cards.codex_app.ButtonOpen.PerformClick()
                if ($script:openedKey -ne 'codex_app') {throw 'Real open-app callback targeted the wrong app'}
                Apply-ManagerToolConfiguration @{HiddenKeys=@('codex');CustomTools=@(@{Key='custom_runtime';Name='Synthetic extra package';Type='App';PackageId='Synthetic.Example';PackageSource='winget';LaunchName=''})}
                $script:featurePhase='catalog'
            }
            'catalog' {
                if ($script:work) {return}
                if ($script:status.Count -ne 7 -or $script:status.Contains('codex') -or -not $script:status.Contains('custom_runtime') -or $script:ui.Cards.Contains('codex') -or $script:ui.RangePanel.Body.Text -match 'Syntetiske noter') {throw 'Runtime custom/hide selection, worker catalog or note reset failed'}
                Save-FeatureImage 'catalog'
                $allKeys=@((Get-ToolCatalog -IncludeHidden).Key)
                Apply-ManagerToolConfiguration @{HiddenKeys=$allKeys;CustomTools=(Get-ManagerToolConfiguration).CustomTools}
                $script:featurePhase='empty'
            }
            'empty' {
                if ($script:work) {return}
                if ($script:status.Count -ne 0 -or $script:ui.Cards.Count -ne 0 -or -not $script:ui.Empty.Visible -or -not $script:ui.Manage.Enabled -or $script:notify.Text -match 'fejlede') {throw 'Zero-tool catalog is not usable or version check failed'}
                Save-FeatureImage 'empty'
                Apply-ManagerToolConfiguration @{HiddenKeys=@();CustomTools=@()}
                $script:featurePhase='restore'
            }
            'restore' {
                if ($script:work) {return}
                if ($script:status.Count -ne 7 -or $script:ui.Cards.Count -ne 7 -or $script:ui.ResultSummary.Text -notmatch '7 af 7') {throw 'Original catalog was not restored'}
                $script:featurePhase='finish';$script:featureTimer.Stop()
                Save-ManagerJson (Join-Path $StateDirectory 'feature-evidence.json') @{Version='3.2.0';Ticks=$script:featureTicks;EarlyOutput=$script:featureEarly;History=@(Get-ManagerHistory $StateDirectory);Tools=@($script:status.Keys);OpenTarget=$script:openedKey;SyntheticInstaller=$true;ExternalNetwork=$false}
                Request-ManagerExit -Reason 'Isoleret funktionstest gennemført'
            }
        }
    } catch {
        $script:featureFailure=$_.Exception.Message+"`n"+$_.ScriptStackTrace;$script:featureTimer.Stop()
        if ($script:work) {$script:work.PowerShell.Stop();$script:work.PowerShell.Dispose();$script:work=$null}
        if ($script:appContext) {Request-ManagerExit -Reason 'Isoleret funktionstest fejlede'}
    }
})
try {$script:featureTimer.Start();. "$testRoot/ai-tray-updater.ps1" -StateDirectory $StateDirectory}
finally {$script:featureTimer.Stop();$script:featureTimer.Dispose()}
if ($script:featureFailure) {throw $script:featureFailure}
if ($script:featurePhase -ne 'finish') {throw 'Feature runtime exited before completion'}
Write-Output "PASS: real entry point and message loop, owned dialog layout, filters/reset, release range, early installer output, history, app callback, custom/hide/empty/restore catalogs. External boundaries synthetic. Evidence: $StateDirectory"
