$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. "$root/updater-core.ps1"
$queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
$ps=[powershell]::Create();$exe=(Get-Process -Id $PID).Path
try {
    [void]$ps.AddScript('param($Root,$Queue,$Exe) . (Join-Path $Root "updater-core.ps1"); Set-ManagerEventQueue $Queue; $script:ManagerCaptureOutput=$true; $script:ManagerCurrentOperation=@{Key="probe";Name="Synthetic probe"}; Invoke-ToolProcess $Exe @("-NoProfile","-Command",''[Console]::Out.Write("first"); Start-Sleep -Milliseconds 1400; [Console]::Out.Write("last"); [Console]::Error.Write("stderr"); exit 7'') 10').AddArgument($root).AddArgument($queue).AddArgument($exe)
    $handle=$ps.BeginInvoke();$early=$false;$events=@();$deadline=(Get-Date).AddSeconds(12)
    do {
        $event=$null
        while ($queue.TryDequeue([ref]$event)) {$events+=$event;if ($event.Type -eq 'Output' -and $event.Text -match 'first' -and -not $handle.IsCompleted) {$early=$true}}
        Start-Sleep -Milliseconds 30
    } while (-not $handle.IsCompleted -and (Get-Date) -lt $deadline)
    if (-not $handle.IsCompleted) {throw 'Progress probe did not complete'}
    $result=$ps.EndInvoke($handle)
    if ($ps.HadErrors) {throw ($ps.Streams.Error | Out-String)}
    if (-not $early) {throw 'Output was not visible before the process completed'}
    if ($result.Count -ne 1 -or $result[0].ExitCode -ne 7 -or $result[0].Success -or $result[0].Output -notmatch 'firstlaststderr') {throw 'Streaming changed final output or failed exit status'}
    $huge=Invoke-ToolProcess $exe @('-NoProfile','-Command','[Console]::Out.Write(("x"*400000)); [Console]::Out.Write("tail")') 10
    if (-not $huge.Success -or $huge.Output.Length -gt 270000 -or $huge.Output -notlike '*tail') {throw 'Large output was not bounded and drained'}
    Write-Output 'PASS: real output before process exit, stdout/stderr, failure code, bounded large stream'
} finally {if ($ps.InvocationStateInfo.State -eq 'Running') {$ps.Stop()};$ps.Dispose()}
