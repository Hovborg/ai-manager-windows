# No packages required. Executes the real core; external update installers are never run.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../updater-core.ps1"
$script:passed = 0
function Assert-Equal($Actual, $Expected, $Name) {
    if ($Actual -cne $Expected) { throw "$Name : expected '$Expected', got '$Actual'" }
    $script:passed++
}
Assert-Equal (Compare-ToolVersion '1.9.0' '1.10.0') -1 'numeric order'
Assert-Equal (Compare-ToolVersion '1.2.0-beta.2' '1.2.0-beta.10') -1 'prerelease numeric order'
Assert-Equal (Compare-ToolVersion '1.2.0-rc.1' '1.2.0') -1 'stable beats prerelease'
Assert-Equal (Compare-ToolVersion '1.2.0+abc' '1.2.0+xyz') 0 'metadata ignored'
Assert-Equal (Compare-ToolVersion '1.2.0.0' '1.2.0') 0 'Windows four-part version'
$tool = @{ Key='codex'; Name='Codex'; Type='CLI'; Source='official' }
Assert-Equal (New-ToolStatus $tool '1.0.0' $null '' 'offline').State 'Unknown' 'offline is not current'
Assert-Equal (New-ToolStatus $tool $null '2.0.0' '' '').State 'Missing' 'missing is not current'
Assert-Equal (New-ToolStatus $tool $null '2.0.0' '' 'version command failed').State 'Error' 'detection failure'
Assert-Equal (New-ToolStatus $tool '1.0.0' '2.0.0' '' '').HasUpdate $true 'update detection'
Assert-Equal (New-ToolStatus $tool '2.0.0' '1.0.0' '' '').State 'Ahead' 'local newer'
$map = [ordered]@{
    codex = New-ToolStatus $tool '1.0.0' '2.0.0' '' ''
    missing = New-ToolStatus @{Key='missing';Name='Missing';Type='CLI';Source=''} $null '2.0.0' '' ''
    current = New-ToolStatus @{Key='current';Name='Current';Type='CLI';Source=''} '2.0.0' '2.0.0' '' ''
    app = New-ToolStatus @{Key='app';Name='App';Type='App';Source=''} '1.0.0' '2.0.0' '' ''
}
Assert-Equal ((Get-UpdateTargets 'all_clis' $map) -join ',') 'codex' 'bulk skips missing/current'
Assert-Equal ((Get-UpdateTargets 'all' $map) -join ',') 'codex,app' 'bulk includes app'
$rejected=$false
try { Get-UpdateTargets '' $map } catch { $rejected=$true }
Assert-Equal $rejected $true 'empty target rejected'
$r = Invoke-ToolProcess (Get-Process -Id $PID).Path @('-NoProfile','-Command','[Console]::Out.Write("out"); [Console]::Error.Write("bad"); exit 7') 10
Assert-Equal $r.ExitCode 7 'nonzero exit preserved'
Assert-Equal $r.Success $false 'failed process is not success'
Assert-Equal $r.Output 'outbad' 'stdout and stderr captured'
$r = Invoke-ToolProcess (Get-Process -Id $PID).Path @('-NoProfile','-Command','Start-Sleep 30') 1
Assert-Equal $r.TimedOut $true 'hung process bounded'
Assert-Equal $r.Success $false 'timeout not success'
$r = Read-WingetRow "Claude Anthropic.Claude 1.40609.1.0 1.44121.2" 'Anthropic.Claude'
Assert-Equal $r.Installed '1.40609.1.0' 'winget four-part version'
Assert-Equal $r.Available '1.44121.2' 'winget available'
$r = Read-WingetRow 'Antigravity 2.12.2 Google.Antigravity 2.12.2' 'Google.Antigravity'
Assert-Equal $r.Available $null 'absent online field stays unknown'
Write-Output "PASS: $script:passed core assertions"
