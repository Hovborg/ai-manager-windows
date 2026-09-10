$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$worker=[powershell]::Create()
$exe=(Get-Process -Id $PID).Path
try {
    [void]$worker.AddScript('param($Root,$Exe) . (Join-Path $Root "updater-core.ps1"); Invoke-ToolProcess $Exe @("-NoProfile","-Command","Start-Sleep -Seconds 30") 30').AddArgument($root).AddArgument($exe)
    $handle=$worker.BeginInvoke()
    Start-Sleep -Milliseconds 800
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $worker.Stop()
    $watch.Stop()
    if ($watch.ElapsedMilliseconds -gt 2000 -or -not $handle.IsCompleted) {throw "Cancelled check blocked shutdown for $($watch.ElapsedMilliseconds) ms"}
    Write-Output "PASS: cancelled check stopped in $($watch.ElapsedMilliseconds) ms"
} finally {$worker.Dispose()}
