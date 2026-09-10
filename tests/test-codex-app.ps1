$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
$script:assertions=0
function Assert-App($Condition,[string]$Message) {if (-not $Condition) {throw $Message};$script:assertions++}
$tool=Get-ToolCatalog | Where-Object Key -eq 'codex_app'
Assert-App ($null -ne $tool -and $tool.Type -eq 'App') 'ChatGPT / Codex Desktop is absent from the catalog'
Assert-App ((Get-ToolCatalog | Where-Object Key -eq 'codex').Name -eq 'Codex CLI') 'CLI and Desktop names are ambiguous'
$script:installed='26.903.8094.0';$script:exitCode=0;$script:installerCalls=0;$script:afterInstall=''
$script:processes=@();$script:offline=$false;$script:manifest=@{schemaVersion=1;buildVersion='26.903.9818.0';storeProductId='9PLM9XGG6VKS';packageIdentity='OpenAI.Codex'}
function Find-ToolExecutable {'fixture-winget.exe'}
function Get-Process {param($Name,$ErrorAction) $script:processes}
function Invoke-ToolProcess {param($FilePath,$Arguments,$TimeoutSeconds)
    Assert-App ($FilePath -eq 'fixture-winget.exe' -and $Arguments -contains '9PLM9XGG6VKS' -and $Arguments -contains 'msstore' -and $Arguments -contains '--exact') 'Wrong package or source reached WinGet'
    if ($Arguments[0] -eq 'upgrade') {
        $script:installerCalls++
        if ($script:afterInstall) {$script:installed=$script:afterInstall}
        return [pscustomobject]@{Success=($script:exitCode -eq 0);ExitCode=$script:exitCode;TimedOut=$false;Output='Store installer diagnostic'}
    }
    Assert-App ($Arguments[0] -eq 'list') 'A read-only status check attempted installation or an unrelated lookup'
    [pscustomobject]@{Success=($script:exitCode -eq 0);ExitCode=$script:exitCode;Output="ChatGPT 9PLM9XGG6VKS $script:installed"}
}
function Invoke-RestMethod {param($Uri,$TimeoutSec,$Headers,$ErrorAction,$MaximumRedirection)
    Assert-App ($Uri -ceq 'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json' -and $MaximumRedirection -eq 0 -and $TimeoutSec -le 12) 'Unbounded or incorrect app manifest request'
    if ($script:offline) {throw 'Synthetic offline'}
    [pscustomobject]$script:manifest
}
$status=Get-OneToolStatus $tool
Assert-App ($status.State -eq 'Update' -and $status.HasUpdate -and $status.Installed -eq $script:installed -and $status.Latest -eq '26.903.9818.0') 'Four-part Desktop update was not detected'
Assert-App ($script:installerCalls -eq 0) 'Checking versions invoked an installer'
$script:processes=@([pscustomobject]@{Path="$env:ProgramFiles\WindowsApps\OpenAI.Codex_26.903.8094.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe"})
$status=Get-OneToolStatus $tool
Assert-App ($status.State -eq 'NeedsClose' -and $status.HasUpdate -and $status.Error -match 'Luk ChatGPT') 'Running app concealed its available update'
$map=[ordered]@{codex_app=$status}
Assert-App (@(Get-UpdateTargets 'all' $map).Count -eq 0) 'Bulk update includes an active Desktop app'
$r=Invoke-ManagedUpdate @('codex_app') $map
Assert-App (-not $r.Success -and $r.RequiresClose -and $script:installerCalls -eq 0) 'Install boundary failed to recheck the active app'
$script:processes=@([pscustomobject]@{Path="$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe"},[pscustomobject]@{Path="$env:ProgramFiles\WindowsApps\OpenAI.CodexBeta_26.727.4816.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe"})
Assert-App ((Get-OneToolStatus $tool).State -eq 'Update') 'CLI or Beta process was confused with the standard Desktop app'
$script:processes=@([pscustomobject]@{Path=$null})
Assert-App ((Get-OneToolStatus $tool).State -eq 'Unknown') 'Unreadable process identity was treated as safe to update'
$script:processes=@();$script:offline=$true
$status=Get-OneToolStatus $tool
Assert-App ($status.State -eq 'Unknown' -and $status.Installed -eq $script:installed -and -not $status.HasUpdate -and $status.Error -match 'offline') 'Offline source looked current or lost installed version'
$script:offline=$false
foreach ($case in @(@('packageIdentity','OpenAI.CodexBeta'),@('storeProductId','9N8CJ4W95TBZ'),@('schemaVersion',2),@('buildVersion','26.903.9818.0;bad'),@('buildVersion','26.903.999999.0'))) {
    $old=$script:manifest[$case[0]];$script:manifest[$case[0]]=$case[1]
    Assert-App ((Get-OneToolStatus $tool).State -eq 'Unknown') "Invalid app manifest accepted: $($case[0])"
    $script:manifest[$case[0]]=$old
}
$script:manifest.buildVersion=$script:installed
Assert-App ((Get-OneToolStatus $tool).State -eq 'Current') 'Equal app build was not current'
$script:manifest.buildVersion='26.902.1.0'
Assert-App ((Get-OneToolStatus $tool).State -eq 'Ahead') 'Newer installed app was offered a downgrade'
$script:manifest.buildVersion='26.903.9818.0';$script:exitCode=-1978335212
Assert-App ((Get-OneToolStatus $tool).State -eq 'Missing') 'Missing standard app was confused with an installed CLI or Beta'
$script:exitCode=5
Assert-App ((Get-OneToolStatus $tool).State -eq 'Error') 'WinGet detection failure was treated as a missing app'
$script:exitCode=0;$map.codex_app=Get-OneToolStatus $tool
$r=Invoke-ManagedUpdate @('codex_app') $map
Assert-App (-not $r.Success -and $r.Output -match 'Store installer diagnostic') 'Unchanged version was reported as updated'
$script:afterInstall='26.903.9818.0'
$r=Invoke-ManagedUpdate @('codex_app') $map
Assert-App ($r.Success -and $r.Before -eq '26.903.8094.0' -and $r.After -eq '26.903.9818.0') 'Verified Store update was not recognized'
Write-Output "PASS: $script:assertions ChatGPT / Codex app assertions (Store identity, official feed, offline, active app, Beta/CLI isolation, verified installation; no real installers)"
