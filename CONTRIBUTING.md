# Contributing

Thanks for helping improve AI Manager for Windows.

## Before opening a change

1. Keep the application Windows-native and compatible with PowerShell 7 and WinForms.
2. Preserve the boundary between a read-only status check and an explicit update.
3. Never treat an unknown or failed lookup as current, and verify the installed version after every update.
4. Do not add automatic process termination, service stops, credential handling, or remote script execution.
5. Keep UI text in Danish unless a change intentionally introduces a complete language-selection design; keep English and Danish guides aligned.

## Validate your change

Run the safe synthetic suite:

```powershell
pwsh -NoProfile -NonInteractive -File .\tests\test-public-package.ps1
pwsh -NoProfile -NonInteractive -STA -File .\tests\test-all.ps1
```

Tests must use mocks, synthetic data, temporary state directories, or controlled loopback endpoints. A pull request must not enable autostart, install or update packages, send live notifications, query private state, or rely on the author's computer. The aggregate writes ignored test evidence under `artifacts/`; remove it before preparing a source archive.

For UI changes, regenerate the documentation renders and inspect them at normal and high DPI:

```powershell
pwsh -NoProfile -NonInteractive -STA -File .\tests\test-ui.ps1 `
  -RenderPath .\docs\images\dashboard.png `
  -RenderDetailsPath .\docs\images\release-notes.png `
  -RenderHistoryPath .\docs\images\history.png
```

## Pull requests

Describe the behavior before and after the change, the exact validation commands, and any remaining Windows or package-manager limitations. Keep unrelated refactors out of the same pull request.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
