# Pure status/selection helpers and bounded external operations. No GUI or startup side effects.
. "$PSScriptRoot/updater-catalog.ps1"
. "$PSScriptRoot/updater-events.ps1"
function Compare-ToolVersion {
    param([string]$Left, [string]$Right)
    $pattern = '^v?(\d+(?:\.\d+){1,3})(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$'
    $a = [regex]::Match($Left, $pattern); $b = [regex]::Match($Right, $pattern)
    if (-not $a.Success -or -not $b.Success) { throw "Ugyldig version: '$Left' / '$Right'" }
    $an = $a.Groups[1].Value.Split('.'); $bn = $b.Groups[1].Value.Split('.')
    for ($i=0; $i -lt [Math]::Max($an.Count,$bn.Count); $i++) {
        $av = if ($i -lt $an.Count) { [long]$an[$i] } else { 0L }
        $bv = if ($i -lt $bn.Count) { [long]$bn[$i] } else { 0L }
        if ($av -ne $bv) { return [Math]::Sign($av - $bv) }
    }
    $ap=$a.Groups[2].Value; $bp=$b.Groups[2].Value
    if (-not $ap -and -not $bp) { return 0 }
    if (-not $ap) { return 1 }; if (-not $bp) { return -1 }
    $at=$ap.Split('.'); $bt=$bp.Split('.')
    for ($i=0; $i -lt [Math]::Min($at.Count,$bt.Count); $i++) {
        if ($at[$i] -ceq $bt[$i]) { continue }
        $ai=$at[$i] -match '^\d+$'; $bi=$bt[$i] -match '^\d+$'
        if ($ai -and $bi) { return ([System.Numerics.BigInteger]::Parse($at[$i])).CompareTo([System.Numerics.BigInteger]::Parse($bt[$i])) }
        if ($ai) { return -1 }; if ($bi) { return 1 }
        return [Math]::Sign([string]::CompareOrdinal($at[$i],$bt[$i]))
    }
    return [Math]::Sign($at.Count - $bt.Count)
}

function Find-ToolExecutable {
    param([string]$Name, [string[]]$Candidates=@())
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    # GUI/login processes can have a stale PATH. Read the persisted Windows paths too.
    $paths = @([Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine'), $env:PATH) -join ';'
    foreach ($folder in $paths.Split(';')) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        $candidate = Join-Path ([Environment]::ExpandEnvironmentVariables($folder.Trim('"'))) "$Name.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-BuiltInToolCatalog {
    @(
        @{Key='agy'; Name='Antigravity CLI'; Type='CLI'; Path=(Find-ToolExecutable 'agy' @("$env:LOCALAPPDATA\agy\bin\agy.exe")); Source='Google · officiel changelog'; Url='https://raw.githubusercontent.com/google-antigravity/antigravity-cli/refs/heads/main/CHANGELOG.md'; Format='changelog'},
        @{Key='codex'; Name='Codex CLI'; Type='CLI'; Path=(Find-ToolExecutable 'codex' @("$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin\codex.exe")); Source='OpenAI · stabil kanal'; Url='https://releases.openai.com/codex/channels/latest'; Format='tag'},
        @{Key='claude'; Name='Claude Code'; Type='CLI'; Path=(Find-ToolExecutable 'claude' @("$env:USERPROFILE\.local\bin\claude.exe")); Source='Anthropic · npm latest'; Url='https://registry.npmjs.org/@anthropic-ai/claude-code/latest'; Format='npm'},
        @{Key='gh'; Name='GitHub CLI'; Type='CLI'; Path=(Find-ToolExecutable 'gh' @("$env:ProgramFiles\GitHub CLI\gh.exe")); Source='GitHub · stabil release'; Url='https://api.github.com/repos/cli/cli/releases/latest'; Format='tag'; PackageId='GitHub.cli'},
        @{Key='claude_app'; Name='Claude Desktop'; Type='App'; PackageId='Anthropic.Claude'; Source='WinGet · Anthropic.Claude'},
        @{Key='antigravity_app'; Name='Antigravity Desktop'; Type='App'; PackageId='Google.Antigravity'; Source='WinGet · Google.Antigravity'},
        @{Key='codex_app'; Name='ChatGPT / Codex'; Type='App'; PackageId='9PLM9XGG6VKS'; PackageSource='msstore'; Format='openai-store'; Source='OpenAI · Windows-app · stabil kanal'}
    )
}

function Invoke-ToolProcess {
    param([string]$FilePath, [string[]]$Arguments, [ValidateRange(1,1800)][int]$TimeoutSeconds=20)
    if (-not $FilePath) { throw 'Programfilen blev ikke fundet.' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$FilePath; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true; $start.RedirectStandardInput=$true
    $start.StandardOutputEncoding=[Text.Encoding]::UTF8; $start.StandardErrorEncoding=[Text.Encoding]::UTF8
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start; $started=$false
    try {
        [void]$process.Start(); $started=$true; $process.StandardInput.Close()
        $streams=@(foreach ($reader in @($process.StandardOutput,$process.StandardError)) {
            $buffer=[char[]]::new(4096)
            @{Reader=$reader;Buffer=$buffer;Task=$reader.ReadAsync($buffer,0,$buffer.Length);Closed=$false}
        })
        $outputBuffer=[Text.StringBuilder]::new()
        $clock=[Diagnostics.Stopwatch]::StartNew(); $timedOut=$false
        # Short waits let PowerShell observe runspace cancellation and execute finally.
        while (-not $process.HasExited) {
            Read-ManagerProcessStreams $streams $outputBuffer
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {$timedOut=$true; break}
            $pending=[Threading.Tasks.Task[]]@($streams | Where-Object {-not $_.Closed} | ForEach-Object {$_.Task})
            if ($pending.Count) {[void][Threading.Tasks.Task]::WaitAny($pending,100)} else {[void]$process.WaitForExit(100)}
        }
        if ($timedOut) { $process.Kill($true); [void]$process.WaitForExit(5000) }
        # A detached installer can inherit a pipe. Do not wait forever on that pipe either.
        $drainClock=[Diagnostics.Stopwatch]::StartNew()
        do {
            Read-ManagerProcessStreams $streams $outputBuffer
            $drained=@($streams | Where-Object {-not $_.Closed}).Count -eq 0
            if (-not $drained) {
                $pending=[Threading.Tasks.Task[]]@($streams | Where-Object {-not $_.Closed} | ForEach-Object {$_.Task})
                [void][Threading.Tasks.Task]::WaitAny($pending,100)
            }
        } while (-not $drained -and $drainClock.ElapsedMilliseconds -lt 3000)
        $output=$outputBuffer.ToString()
        if (-not $drained) {$output+="`nOutputstrømmen blev ikke afsluttet."}
        $exitCode=if ($timedOut) { -1 } else { $process.ExitCode }
        [pscustomobject]@{Success=($exitCode -eq 0 -and -not $timedOut -and $drained); ExitCode=$exitCode; TimedOut=$timedOut; Output=$output.Trim()}
    } finally {
        if ($started -and -not $process.HasExited) {$process.Kill($true); [void]$process.WaitForExit(1000)}
        $process.Dispose()
    }
}

function New-ToolStatus {
    param($Tool, [string]$Installed, [string]$Latest, [string]$Path, [string]$Problem)
    $state='Unknown'; $hasUpdate=$false
    if (-not $Installed) { $state=if ($Problem) { 'Error' } else { 'Missing' } }
    elseif ($Latest -and -not $Problem) {
        try {
            $comparison=Compare-ToolVersion $Installed $Latest
            $state=if ($comparison -lt 0) { 'Update' } elseif ($comparison -gt 0) { 'Ahead' } else { 'Current' }
            $hasUpdate=$comparison -lt 0
        } catch { $Problem=$_.Exception.Message }
    }
    [pscustomobject]@{Key=$Tool.Key; Name=$Tool.Name; Type=$Tool.Type; Installed=$Installed; Latest=$Latest; Path=$Path; Source=$Tool.Source; State=$state; HasUpdate=$hasUpdate; Error=$Problem; CheckedAt=(Get-Date).ToString('o');CanLaunch=$false;LaunchMessage=''}
}

function Read-WingetRow {
    param([string]$Text, [string]$PackageId)
    $escaped=[regex]::Escape($PackageId)
    $match=[regex]::Match($Text,"(?m)^.*?\s$escaped\s+(\d+(?:\.\d+){1,3})(?:\s+(\d+(?:\.\d+){1,3}))?")
    if (-not $match.Success) { return $null }
    [pscustomobject]@{Installed=$match.Groups[1].Value; Available=$(if ($match.Groups[2].Success) {$match.Groups[2].Value} else {$null})}
}

function Get-ToolCloseRequirement {
    param($Tool)
    if ($Tool.Key -eq 'codex_app') {
        # The Store app is named ChatGPT but its package identity is OpenAI.Codex.
        # A separate CLI and the Beta package must not block the standard app.
        $packageRoot=[regex]::Escape((Join-Path $env:ProgramFiles 'WindowsApps'))
        $appPattern="^$packageRoot\\OpenAI\.Codex_\d+(?:\.\d+){3}_(?:x64|arm64|x86)__2p2nqsd0c76g0\\app\\(?:ChatGPT|Codex)\.exe$"
        foreach ($process in @(Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue)) {
            if (-not $process.Path) {throw 'En ChatGPT/Codex-proces kunne ikke identificeres. Luk appen og tryk Tjek igen.'}
            if ($process.Path -match $appPattern) {
                return 'Luk ChatGPT / Codex helt via appens menu eller ikonet ved uret > Quit/Afslut. Gem dit arbejde først, og tryk derefter Tjek igen. At lukke vinduet er ikke altid nok.'
            }
        }
        return ''
    }
    if ($Tool.Key -ne 'claude_app') {return ''}
    # Match the Desktop package, never the identically named Claude Code executable.
    $packageRoot=[regex]::Escape((Join-Path $env:ProgramFiles 'WindowsApps'))
    # SYSTEM services may hide their executable path from process enumeration.
    # Read the service configuration; never stop it as part of a status check.
    $service=Get-CimInstance -ClassName Win32_Service -Filter "Name='CoworkVMService'" -OperationTimeoutSec 5 -ErrorAction Stop
    $servicePattern="^`"?$packageRoot\\Claude_\d+(?:\.\d+){3}_(?:x64|arm64|x86)__pzs8sxrjxfjjc\\app\\resources\\cowork-svc\.exe(?:`"|\s|$)"
    if ($service -and $service.State -ne 'Stopped' -and $service.PathName -match $servicePattern) {
        return 'Cowork-tjenesten holder Claude åben, selv når vinduet er lukket. Afslut Cowork-arbejde; tjenesten CoworkVMService skal stoppes før opdatering. Dette kræver administratorrettigheder. Manageren stopper den ikke automatisk.'
    }
    $desktopPattern="^$packageRoot\\Claude_\d+(?:\.\d+){3}_(?:x64|arm64|x86)__pzs8sxrjxfjjc\\app\\Claude\.exe$"
    foreach ($process in @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue)) {
        if ($process.Path -match $desktopPattern) {
            return 'Luk Claude helt via Claude-ikonet ved uret > Quit/Afslut. Gem dit arbejde først, og tryk derefter Tjek igen. At lukke vinduet er ikke altid nok.'
        }
    }
    return ''
}

function Get-OpenAIDesktopLatest {
    # This is the same stable-channel manifest used by the installed OpenAI app.
    # Never use the independent Codex CLI version or the Beta feed for this package.
    $manifest=Invoke-RestMethod -Uri 'https://persistent.oaistatic.com/codex-app-prod/windows-store-update.json' -TimeoutSec 10 -MaximumRedirection 0 -Headers @{'User-Agent'='AI-Manager/3.1'} -ErrorAction Stop
    if ($manifest.schemaVersion -ne 1 -or $manifest.storeProductId -cne '9PLM9XGG6VKS' -or $manifest.packageIdentity -cne 'OpenAI.Codex') {
        throw 'OpenAI-kildens kanal eller pakkeidentitet matcher ikke ChatGPT / Codex-appen.'
    }
    $version=[string]$manifest.buildVersion
    if ($version -cnotmatch '^\d{1,5}(?:\.\d{1,5}){3}$' -or @($version.Split('.') | Where-Object {[int]$_ -gt 65535}).Count) {
        throw 'OpenAI-kilden returnerede ikke et gyldigt Windows-appversionsnummer.'
    }
    return $version
}

function Get-OneToolStatus {
    param($Tool)
    $installed=$null; $latest=$null; $problem=''; $path=$Tool.Path
    try {
        if ($Tool.Type -eq 'CLI' -and $Tool.Format -ne 'winget') {
            if (-not $path) { return (New-ToolStatus $Tool '' '' '' '') }
            $result=Invoke-ToolProcess $path @('--version') 15
            if (-not $result.Success) { throw "Versionskommando fejlede (kode $($result.ExitCode)): $($result.Output)" }
            if ($result.Output -match '(\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?)') { $installed=$Matches[1] }
            else { throw 'Installeret version kunne ikke læses.' }
            $response=Invoke-RestMethod -Uri $Tool.Url -TimeoutSec 10 -Headers @{'User-Agent'='AI-Manager/2.0'} -ErrorAction Stop
            $versionText=switch ($Tool.Format) { 'tag' {$response.tag_name} 'npm' {$response.version} 'changelog' { if ($response -match '(?m)^##\s*\[?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)') {$Matches[1]} } }
            if ($versionText -match '(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)') { $latest=$Matches[1] }
            else { throw 'Kilden returnerede ingen læsbar version.' }
        } else {
            $path=Find-ToolExecutable 'winget'
            $packageSource=if ($Tool.PackageSource) {$Tool.PackageSource} else {'winget'}
            $result=Invoke-ToolProcess $path @('list','--exact','--id',$Tool.PackageId,'--source',$packageSource,'--disable-interactivity') 30
            $row=Read-WingetRow $result.Output $Tool.PackageId
            # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND = 0x8A150014.
            if ($result.ExitCode -eq -1978335212) { return (New-ToolStatus $Tool '' '' $path '') }
            if (-not $result.Success -or -not $row) { throw "WinGet kunne ikke læse installationen (kode $($result.ExitCode)): $($result.Output)" }
            $installed=$row.Installed; $latest=$row.Available
            if ($Tool.Format -eq 'openai-store') {$latest=Get-OpenAIDesktopLatest}
            elseif (-not $latest) {
                $online=Invoke-ToolProcess $path @('show','--exact','--id',$Tool.PackageId,'--versions','--source',$packageSource,'--disable-interactivity') 30
                if ($online.Success -and $online.Output -match '(?m)^\s*(\d+(?:\.\d+){1,3})\s*\r?$') { $latest=$Matches[1] }
                else { throw "WinGet-kildens version kunne ikke kontrolleres (kode $($online.ExitCode))." }
            }
        }
    } catch { $problem=$_.Exception.Message }
    $status=New-ToolStatus $Tool $installed $latest $path $problem
    if ($Tool.Type -eq 'App' -and $installed) {
        try {$status.CanLaunch=$null -ne (Find-ManagerLaunchTarget $Tool)} catch {$status.LaunchMessage=$_.Exception.Message}
        if (-not $status.CanLaunch -and -not $status.LaunchMessage) {$status.LaunchMessage='Ingen entydig appgenvej fundet i Startmenuen.'}
    }
    if ($status.HasUpdate) {
        try {
            $closeReason=Get-ToolCloseRequirement $Tool
            if ($closeReason) {$status.State='NeedsClose'; $status.Error=$closeReason}
        } catch {$status.State='Unknown'; $status.HasUpdate=$false; $status.Error="Kunne ikke kontrollere om $($Tool.Name) er i brug: $($_.Exception.Message)"}
    }
    $status
}

function Get-AllToolStatus {
    $status=[ordered]@{}
    $catalog=@(Get-ToolCatalog);$index=0
    foreach ($tool in $catalog) {
        $index++;$script:ManagerCurrentOperation=@{Key=$tool.Key;Name=$tool.Name;Index=$index;Total=$catalog.Count;Phase='Kontrollerer versioner'}
        Publish-ManagerEvent 'Stage' 'Læser installeret version og kontrollerer udgiverens kilde.'
        $status[$tool.Key]=Get-OneToolStatus $tool
    }
    return $status
}

function Get-UpdateTargets {
    param([string]$Target, $StatusMap)
    if ([string]::IsNullOrWhiteSpace($Target)) { throw 'Intet værktøj valgt.' }
    if ($Target -notin @('all','all_clis','all_apps') -and -not $StatusMap.Contains($Target)) { throw "Ukendt værktøj: $Target" }
    foreach ($key in $StatusMap.Keys) {
        $item=$StatusMap[$key]
        if (-not $item.HasUpdate -or -not $item.Installed -or $item.State -eq 'NeedsClose') { continue }
        if ($Target -eq 'all' -or $Target -eq $key -or ($Target -eq 'all_clis' -and $item.Type -eq 'CLI') -or ($Target -eq 'all_apps' -and $item.Type -eq 'App')) { $key }
    }
}

function Invoke-ManagedUpdate {
    param([string[]]$Keys, $StatusMap, $AttemptIds)
    $catalog=Get-ToolCatalog
    $index=0
    foreach ($key in $Keys) {
        $tool=$catalog | Where-Object Key -eq $key | Select-Object -First 1
        if (-not $tool -or -not $StatusMap.Contains($key) -or -not $StatusMap[$key].HasUpdate) { throw "Opdateringen er ikke tilladt for '$key'." }
        $before=$StatusMap[$key]; $code=$null; $output=''; $verified=$false; $after=$null; $requiresClose=$false
        $index++;$id=if ($AttemptIds -and $AttemptIds.Contains($key)) {$AttemptIds[$key]} else {[guid]::NewGuid().ToString('N')}
        $script:ManagerCurrentOperation=@{Key=$key;Name=$tool.Name;Index=$index;Total=$Keys.Count;Id=$id;Phase='Forbereder opdatering'}
        Publish-ManagerEvent 'Stage' 'Kontrollerer om appen skal lukkes først.'
        try {
            $closeReason=Get-ToolCloseRequirement $tool
            if ($closeReason) {$requiresClose=$true; throw $closeReason}
            if ($tool.PackageId) {
                $exe=Find-ToolExecutable 'winget'
                $packageSource=if ($tool.PackageSource) {$tool.PackageSource} else {'winget'}
                $arguments=@('upgrade','--exact','--id',$tool.PackageId,'--source',$packageSource,'--silent','--disable-interactivity','--accept-source-agreements','--accept-package-agreements')
            } else { $exe=$tool.Path; $arguments=@('update') }
            $script:ManagerCurrentOperation.Phase='Installerer';Publish-ManagerEvent 'Stage' 'Installationsprogrammet arbejder. Output vises, når programmet leverer det.'
            $script:ManagerCaptureOutput=$true
            try {$result=Invoke-ToolProcess $exe $arguments 600} finally {$script:ManagerCaptureOutput=$false}
            $code=$result.ExitCode; $output=$result.Output
            if (-not $result.Success) { throw "Opdatering fejlede (kode $code, timeout: $($result.TimedOut)). $output" }
            $script:ManagerCurrentOperation.Phase='Verificerer version';Publish-ManagerEvent 'Stage' 'Læser den installerede version efter opdateringen.'
            $after=Get-OneToolStatus $tool
            $verified=$after.Installed -and ((Compare-ToolVersion $after.Installed $before.Latest) -ge 0)
            if (-not $verified) {
                $requiresClose=$after.State -eq 'NeedsClose'
                throw "Kommandoen afsluttede, men version $($before.Latest) blev ikke bekræftet. Fundet: $($after.Installed). $($after.Error)`r`nInstallationsoutput: $output"
            }
        } catch { $output=$_.Exception.Message }
        $completion=[pscustomobject]@{Id=$id;Key=$key; Name=$tool.Name; Success=[bool]$verified; RequiresClose=$requiresClose; ExitCode=$code; Before=$before.Installed; After=$after.Installed; Output=$output}
        Publish-ManagerEvent 'Result' '' $completion
        $completion
    }
}

function Get-ManagerSettings {
    param([string]$Path)
    $settings=@{CheckIntervalMinutes=60; Notifications=$true; LastNotification=''}
    if (Test-Path -LiteralPath $Path) {
        try {
            $saved=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($saved.CheckIntervalMinutes -in @(15,30,60,120,240)) {$settings.CheckIntervalMinutes=[int]$saved.CheckIntervalMinutes}
            if ($saved.Notifications -is [bool]) {$settings.Notifications=$saved.Notifications}
            if ($saved.LastNotification -is [string]) {$settings.LastNotification=$saved.LastNotification}
        } catch { Write-Warning 'Indstillingsfilen kunne ikke læses; standardværdier bruges.' }
    }
    return $settings
}

function Save-ManagerJson {
    param([string]$Path, $Value)
    $directory=Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary="$Path.$PID.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$Path,$true)
}
