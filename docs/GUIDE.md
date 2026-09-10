# AI Manager for Windows — User Guide

AI Manager 3.2 is a native Windows tray application written in PowerShell 7 with Windows Forms. It combines version checks, release notes, deliberate update actions, and local history. The interface is currently in Danish; this guide gives the English meaning of the important labels and messages.

## 1. Before you start

Keep the extracted repository in a stable folder. The launchers, Scheduled Task, notification shortcut, and notification protocol all refer to that folder. Moving it later can break those links until autostart and the notification identity are recreated.

Check the two command-line prerequisites:

```powershell
pwsh --version
winget --version
```

The application also relies on Windows Forms, Task Scheduler for optional autostart, and per-user Windows notification registration. The public project does not claim support for a particular Windows release because it has not been tested against a version matrix.

## 2. Start and exit

Double-click `start-tray.cmd`, or run:

```powershell
.\start-tray.cmd
```

The launcher locates PowerShell 7 through the Windows Apps alias and then under `%ProgramFiles%\PowerShell\7`. It starts `ai-tray-updater.ps1` in STA mode with no visible console window.

Only one manager instance is allowed for each Windows user and state directory. Starting it again brings the existing window forward. Closing the window hides it in the notification area. Choose **Afslut** in the tray menu to end it.

You can also request a clean exit from PowerShell:

```powershell
pwsh -NoProfile -File .\ai-tray-updater.ps1 -ExitExisting
```

An active update is protected; an exit request is handled only when the current operation can close safely.

## 3. Understand the dashboard

The main labels are:

| Danish UI | English meaning |
| --- | --- |
| `Tjek nu` | Check now |
| `Opdatér` | Update this tool |
| `Opdatér alle` | Update every confirmed update |
| `Se nyheder` | View release notes |
| `Åbn app` | Open the installed desktop app |
| `Værktøjer` | Tools |
| `Versionsnyt` | Release notes |
| `Historik` | History |
| `Aktivitet` | Current activity and output |
| `Skjul til bakken` | Hide to the notification area |
| `Kræver opmærksomhed` | Needs attention |

The built-in catalog contains Antigravity CLI, Codex CLI, Claude Code, GitHub CLI, Antigravity Desktop, Claude Desktop, and the ChatGPT / Codex Windows app. The **Administrer** control can add WinGet or Microsoft Store package IDs and hide catalog entries. Custom entries are validated and stored in the local `tools.json` file.

## 4. Check status without updating

Press **Tjek nu**, or use the command-line check:

```powershell
pwsh -NoProfile -NonInteractive -File .\ai-tray-updater.ps1 -CheckNowAndExit
```

For JSON:

```powershell
pwsh -NoProfile -NonInteractive -File .\ai-tray-updater.ps1 -CheckNowAndExit -Json
```

A check reads local executable or package versions and compares them with configured publisher or package-manager sources. It does not run an update command, stop an application, or close a service. The command-line form exits with code `2` if any tool is unknown or errored.

The status model is deliberately conservative:

- **Update** means a newer version was confirmed.
- **Current** means installed and published versions match.
- **Ahead** means the local version is newer than the published comparison version.
- **Missing** means the tool was not found.
- **Unknown** or **Error** means the comparison was not reliable.
- **NeedsClose** means an update is available but a matching desktop app or service must be closed first.

Unknown, offline, or invalid responses never appear as current.

## 5. Run an explicit update

Updates start only from an **Opdatér** button or **Opdatér alle**. AI Manager accepts only catalog keys that currently have a confirmed update.

For WinGet-managed packages it uses an exact package ID and source with silent, non-interactive agreement flags. The three AI CLIs use their own `update` command; GitHub CLI and the desktop applications use WinGet. AI Manager waits for the process, captures its exit status and output, and performs a fresh installed-version check.

An update is marked successful only when both conditions hold:

1. The update process exits successfully within its bounded runtime.
2. The installed version after the operation is the requested published version or newer.

If a desktop application is still open, AI Manager explains what must be closed. It does not terminate applications or stop services itself. Save work, close the named application through its own menu, and press **Tjek nu** again before updating.

## 6. Release notes and history

**Se nyheder** fetches release information from allow-listed publisher sources. The release view identifies stale cache entries, incomplete version ranges, and notes that do not exactly match the requested version. Source buttons open only validated publisher links.

The history tab records pending attempts, verified results, failures, and externally observed version changes. Local history helps explain what happened on this computer; it is not publisher proof and is not sent anywhere by this project.

## 7. Configure autostart

Inspect the current configuration:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action status
```

Enable autostart:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action enable
```

The script registers `\AI-CLI-Updater` for the current interactive user's SID. It runs PowerShell 7 with limited rights, starts the manager minimized 15 seconds after sign-in, stores no password, ignores a second concurrent start, has no execution time limit, and allows three restart attempts one minute apart. It verifies the resulting task before reporting it enabled. The task name is shared at machine level: an existing task's principal and sign-in trigger must both belong to the current user before it is changed. Separate simultaneous autostart tasks for multiple users are not supported.

If an exact legacy `AI-CLI-Updater.lnk` created for this manager exists in the user's Startup folder, successful enablement moves it to `%LOCALAPPDATA%\Hovborg\AI-Manager\startup-backup`. A shortcut with another target is preserved and produces a warning.

Disable future automatic starts:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action disable
```

Disable leaves the task registered and does not stop the current process. `status` is read-only. If a task with the same name has another description, enable and disable refuse to change it.

## 8. Settings, files, and notifications

The default state directory is:

```text
%LOCALAPPDATA%\Hovborg\AI-Manager
```

It can contain:

- `settings.json` — check interval and notification preference
- `tools.json` — hidden built-ins and validated custom packages
- `history.json` and `observed-versions.json` — local history
- `runtime.json` and `updater.log` — current state and bounded diagnostics
- `release-notes\` — publisher-note cache
- `notification-icon.png` and `startup-backup\` — Windows integration files

For an isolated state directory, launch the main script directly:

```powershell
pwsh -NoProfile -STA -File .\ai-tray-updater.ps1 -StateDirectory "$env:TEMP\AI-Manager-Demo"
```

Notifications are registered lazily when the manager first needs to show one. The fixed per-user identity is `Hovborg.AIManager`; the fixed protocol is `hovborg-ai-manager:`. Protocol activation launches only the bundled `start-tray.vbs` path and does not pass arbitrary URL input to a shell command.

## 9. Troubleshooting

**PowerShell 7 was not found**

Install PowerShell 7 using its Microsoft Store alias or default MSI location (`%ProgramFiles%\PowerShell\7\pwsh.exe`), then confirm `pwsh --version`. A portable installation elsewhere can run the main script directly with `pwsh -NoProfile -STA -File .\ai-tray-updater.ps1`, but the silent launcher and autostart helper only search the two locations above. AI Manager does not install its own prerequisite.

**A tool is missing**

Confirm it is installed and available on the user or machine `PATH`. AI Manager also checks built-in conventional locations. For custom packages, verify the exact WinGet or Microsoft Store package ID.

**Status is unknown**

Read the tool's error text in the dashboard. Network failure, publisher response changes, ambiguous application identity, or an unreadable local version intentionally produce an uncertain state.

**Update completed but is reported failed**

AI Manager could not confirm the expected installed version afterward. Review the captured output and run **Tjek nu** again. Do not treat the package manager's exit code alone as proof.

**The desktop app must close**

Save your work and quit that exact desktop app through its own tray or application menu. AI Manager does not terminate it. Claude's Cowork service may require separate administrator action; AI Manager reports this but does not stop the service.

**Autostart does not validate**

Run the status command and inspect `ConfigurationValid`, `Execute`, `Arguments`, `User`, and `State`. The script refuses to take over a same-named task with another description or an unknown/different owner.

## 10. Remove AI Manager

First disable future starts and request that the running instance exit:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action disable
pwsh -NoProfile -File .\ai-tray-updater.ps1 -ExitExisting
```

Verify the manager has exited before deleting its extracted folder. The disable command leaves the Scheduled Task registered but disabled. To remove it completely, verify its full configuration and current-user ownership first. Run this block from the extracted project in PowerShell 7:

```powershell
$task = Get-ScheduledTask -TaskName 'AI-CLI-Updater' -TaskPath '\' -ErrorAction SilentlyContinue
$status = & .\manage-startup.ps1 -Action status -PassThru
if ($task -and -not $status.ConfigurationValid) {
    throw 'Task ownership or configuration does not match this installation. Nothing was removed.'
}
if ($task -and $status.ConfigurationValid) {
    Unregister-ScheduledTask -InputObject $task -Confirm:$false
}
```

You may then delete the extracted repository folder. To remove local settings and history too, delete `%LOCALAPPDATA%\Hovborg\AI-Manager`.

If Windows notifications were used, the Start-menu shortcut and per-user registrations can remain. The following cleanup refuses to remove registry keys unless their `ManagedBy` marker matches this application:

```powershell
$appKey = 'HKCU:\Software\Classes\AppUserModelId\Hovborg.AIManager'
$protocolKey = 'HKCU:\Software\Classes\hovborg-ai-manager'
foreach ($key in @($appKey, $protocolKey)) {
    if (Test-Path -LiteralPath $key) {
        $owner = (Get-ItemProperty -LiteralPath $key -Name ManagedBy -ErrorAction Stop).ManagedBy
        if ($owner -ne 'Hovborg.AIManager') { throw "Refusing to remove unowned key: $key" }
        Remove-Item -LiteralPath $key -Recurse
    }
}
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'AI Manager.lnk'
if (Test-Path -LiteralPath $shortcut) {
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($shortcut)
        $expectedTarget = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $expectedArguments = '"' + (Join-Path (Get-Location) 'start-tray.vbs') + '"'
        if ($link.TargetPath -ne $expectedTarget -or $link.Arguments -ne $expectedArguments) {
            throw 'Refusing to remove a Start-menu shortcut with another target.'
        }
        Remove-Item -LiteralPath $shortcut
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}
```

Run that block from the extracted repository folder before deleting it. These removal commands are instructions for the user; the project does not run them automatically.

## 11. Validate the public package

The default test aggregate contains synthetic, isolated tests only:

```powershell
pwsh -NoProfile -NonInteractive -File .\tests\test-public-package.ps1
pwsh -NoProfile -NonInteractive -STA -File .\tests\test-all.ps1
```

Run the package-boundary check first on a clean tree. The aggregate writes ignored synthetic evidence under `artifacts/`; remove that directory before creating a release archive.

To reproduce the documentation screenshots with controlled test data:

```powershell
pwsh -NoProfile -NonInteractive -STA -File .\tests\test-ui.ps1 `
  -RenderPath .\docs\images\dashboard.png `
  -RenderDetailsPath .\docs\images\release-notes.png `
  -RenderHistoryPath .\docs\images\history.png
```

The screenshot command renders actual WinForms controls. It does not query installed tools or prove runtime behavior on another computer.
