# AI Manager til Windows — brugervejledning

AI Manager 3.2 er et Windows-program i PowerShell 7 og Windows Forms. Det samler versionskontrol, versionsnyt, bevidste opdateringer og lokal historik. Brugerfladen er på dansk.

## 1. Før du starter

Behold den udpakkede mappe på en fast placering. Startere, planlagt opgave og Windows-notifikationer peger på denne mappe. Hvis den flyttes senere, kan disse henvisninger gå i stykker, indtil autostart og notifikationsidentitet er oprettet igen.

Kontrollér forudsætningerne:

```powershell
pwsh --version
winget --version
```

Programmet bruger desuden Windows Forms, Opgavestyring til valgfri autostart og brugerens Windows-notifikationer. Det offentlige projekt lover ikke understøttelse af en bestemt Windows-version, fordi pakken ikke er prøvet på en versionsmatrix.

## 2. Start og afslut

Dobbeltklik på `start-tray.cmd`, eller kør:

```powershell
.\start-tray.cmd
```

Starteren finder PowerShell 7 via Windows Apps-aliaset og derefter under `%ProgramFiles%\PowerShell\7`. Den starter `ai-tray-updater.ps1` i STA-tilstand uden et synligt konsolvindue.

Der kan kun køre én instans pr. Windows-bruger og datamappe. En ny start viser den eksisterende instans. Krydset skjuler vinduet i systembakken. Vælg **Afslut** i bakkemenuen for at lukke programmet.

Du kan også anmode om en ren afslutning:

```powershell
pwsh -NoProfile -File .\ai-tray-updater.ps1 -ExitExisting
```

En igangværende opdatering beskyttes; afslutningen sker først, når den aktuelle handling kan lukke sikkert.

## 3. Forstå status

Den indbyggede liste indeholder Antigravity CLI, Codex CLI, Claude Code, GitHub CLI, Antigravity Desktop, Claude Desktop og ChatGPT / Codex til Windows. Under **Administrer** kan du tilføje præcise WinGet- eller Microsoft Store-pakke-id'er og skjule værktøjer. Egne poster valideres og gemmes i `tools.json`.

Status er bevidst forsigtig:

- **Opdatering klar** betyder, at en nyere version er bekræftet.
- **Ajour** betyder, at installeret og udgivet version er ens.
- **Nyere** betyder, at den lokale version ligger foran sammenligningskilden.
- **Mangler** betyder, at værktøjet ikke blev fundet.
- **Ukendt** eller **Fejl** betyder, at sammenligningen ikke var pålidelig.
- **Skal lukkes** betyder, at en opdatering findes, men en tilhørende app eller tjeneste stadig er åben.

Offline, ugyldige eller ukendte svar vises aldrig som ajour.

## 4. Versionskontrol ændrer ingen programmer

Tryk **Tjek nu**, eller kør:

```powershell
pwsh -NoProfile -NonInteractive -File .\ai-tray-updater.ps1 -CheckNowAndExit
```

Maskinlæsbart JSON-output:

```powershell
pwsh -NoProfile -NonInteractive -File .\ai-tray-updater.ps1 -CheckNowAndExit -Json
```

Kontrollen læser lokale program- eller pakkeversioner og sammenligner dem med de konfigurerede udgiver- og pakkekilder. Den kører ingen opdateringskommando, lukker ingen app og stopper ingen tjeneste. Kommandolinjeformen returnerer kode `2`, hvis mindst ét resultat er ukendt eller fejlet.

## 5. En opdatering kræver et aktivt valg

En opdatering starter kun via **Opdatér** eller **Opdatér alle**, og kun for værktøjer med en bekræftet nyere version.

For WinGet-pakker bruges det præcise pakke-id og den præcise kilde med lydløse, ikke-interaktive argumenter. De tre AI-CLI'er bruger deres egen `update`-kommando; GitHub CLI og desktop-apps bruger WinGet. AI Manager venter på processen, gemmer returkode og output og læser derefter den installerede version igen.

Resultatet markeres kun som gennemført, når:

1. Opdateringsprocessen afslutter korrekt inden for tidsgrænsen.
2. Den installerede version bagefter er den ønskede version eller nyere.

Hvis en desktop-app er åben, viser AI Manager, hvad du skal lukke. Programmet tvangslukker ikke apps og stopper ikke tjenester. Gem arbejdet, luk den viste app gennem dens egen menu, og tryk **Tjek nu** igen.

## 6. Versionsnyt og historik

**Se nyheder** henter udgivelsesoplysninger fra tilladte udgiverkilder. Visningen markerer ældre cache, ufuldstændige versionsintervaller og noter uden et præcist versionsmatch. Kildeknapper åbner kun validerede udgiverlinks.

Historikken registrerer afventende forsøg, verificerede resultater, fejl og observerede eksterne versionsændringer. Den er lokal dokumentation for denne computer, ikke udgiverbevis, og projektet sender den ikke videre.

## 7. Autostart

Se status uden at ændre noget:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action status
```

Aktivér autostart:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action enable
```

Scriptet opretter `\AI-CLI-Updater` for den aktuelle interaktive brugers SID. Opgaven bruger PowerShell 7 med begrænsede rettigheder, starter minimeret 15 sekunder efter login, gemmer ingen adgangskode, ignorerer dobbeltstart, har ingen køretidsgrænse og kan prøve genstart tre gange med ét minuts mellemrum. Konfigurationen kontrolleres, før den meldes aktiv.

Hvis en helt bestemt ældre `AI-CLI-Updater.lnk` fra AI Manager findes i brugerens Startup-mappe, flyttes den efter en vellykket kontrol til `%LOCALAPPDATA%\Hovborg\AI-Manager\startup-backup`. En genvej med et andet mål bevares med en advarsel.

Slå fremtidig autostart fra:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action disable
```

Kommandoen deaktiverer opgaven, men sletter den ikke og stopper ikke et kørende program. `status` er kun læsning. Opgavenavnet er fælles for maskinen; både opgavens bruger og login-triggerens bruger kontrolleres før ændringer. En opgave med ukendt ejerskab, en anden bruger eller en anden beskrivelse bliver ikke ændret. Flere brugeres samtidige autostartopsætninger understøttes ikke.

## 8. Lokale filer og notifikationer

Standardmappen er:

```text
%LOCALAPPDATA%\Hovborg\AI-Manager
```

Den kan indeholde indstillinger, validerede egne værktøjer, historik, observerede versioner, runtime-status, en begrænset log, cachede udgivelsesnoter, notifikationsikon og backup af en gammel startgenvej.

Start med en isoleret datamappe sådan:

```powershell
pwsh -NoProfile -STA -File .\ai-tray-updater.ps1 -StateDirectory "$env:TEMP\AI-Manager-Demo"
```

Notifikationsidentiteten oprettes først, når en notifikation skal vises. Den faste identitet er `Hovborg.AIManager`, og protokollen er `hovborg-ai-manager:`. Protokollen starter kun pakkens `start-tray.vbs` og sender ikke vilkårlige URL-argumenter videre til en shell.

## 9. Fejlfinding

**PowerShell 7 blev ikke fundet**

Installér PowerShell 7 gennem din normale softwarekanal og kontrollér `pwsh --version`. AI Manager installerer ikke selv sin forudsætning.

**Et værktøj mangler**

Kontrollér installation og brugerens eller maskinens `PATH`. Ved egne værktøjer skal pakke-id og kilde være præcise.

**Status er ukendt**

Læs fejlteksten for værktøjet. Netværksfejl, ændrede udgiversvar, uklar appidentitet eller en ulæselig lokal version giver med vilje en usikker status.

**Installationsprogrammet sluttede, men resultatet er fejl**

Den forventede installerede version blev ikke bekræftet bagefter. Læs outputtet, og kør **Tjek nu** igen. Returkode alene er ikke bevis.

**En app skal lukkes**

Gem arbejdet og afslut netop den viste desktop-app gennem dens egen bakke- eller programmenu. AI Manager tvangslukker den ikke. Claudes Cowork-tjeneste kan kræve en særskilt administratorhandling; AI Manager viser kravet, men stopper ikke tjenesten.

## 10. Fjern AI Manager

Deaktivér først nye automatiske starter og bed en kørende instans om at afslutte:

```powershell
pwsh -NoProfile -File .\manage-startup.ps1 -Action disable
pwsh -NoProfile -File .\ai-tray-updater.ps1 -ExitExisting
```

Kontrollér, at programmet er lukket, før programmappen slettes. Den planlagte opgave er nu deaktiveret, men stadig registreret. Slet kun opgaven helt, når dens samlede konfiguration og ejerskab passer til denne installation og den aktuelle bruger. Kør blokken fra programmappen i PowerShell 7:

```powershell
$task = Get-ScheduledTask -TaskName 'AI-CLI-Updater' -TaskPath '\' -ErrorAction SilentlyContinue
$status = & .\manage-startup.ps1 -Action status -PassThru
if ($task -and -not $status.ConfigurationValid) {
    throw 'Opgavens ejerskab eller konfiguration passer ikke til denne installation. Intet blev slettet.'
}
if ($task -and $status.ConfigurationValid) {
    Unregister-ScheduledTask -InputObject $task -Confirm:$false
}
```

Slet derefter den udpakkede programmappe. Slet `%LOCALAPPDATA%\Hovborg\AI-Manager`, hvis indstillinger og historik også skal væk.

Hvis Windows-notifikationer har været brugt, kan Startmenu-genvejen og to brugerregistreringer være tilbage. Denne oprydning nægter at slette registreringsnøgler uden programmets eget `ManagedBy`-mærke:

```powershell
$appKey = 'HKCU:\Software\Classes\AppUserModelId\Hovborg.AIManager'
$protocolKey = 'HKCU:\Software\Classes\hovborg-ai-manager'
foreach ($key in @($appKey, $protocolKey)) {
    if (Test-Path -LiteralPath $key) {
        $owner = (Get-ItemProperty -LiteralPath $key -Name ManagedBy -ErrorAction Stop).ManagedBy
        if ($owner -ne 'Hovborg.AIManager') { throw "Nægter at slette en nøgle uden korrekt ejer: $key" }
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
            throw 'Nægter at slette en Startmenu-genvej med et andet mål.'
        }
        Remove-Item -LiteralPath $shortcut
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}
```

Kør blokken fra den udpakkede projektmappe, før den slettes. Projektet kører aldrig disse fjernelseskommandoer automatisk.

## 11. Syntetiske kontroller

Den offentlige standardtest indeholder kun isolerede og syntetiske kontroller:

```powershell
pwsh -NoProfile -NonInteractive -File .\tests\test-public-package.ps1
pwsh -NoProfile -NonInteractive -STA -File .\tests\test-all.ps1
```

Kør pakkekontrollen først på et rent træ. Den samlede test skriver ignoreret, syntetisk evidens under `artifacts/`; fjern mappen, før der laves et udgivelsesarkiv.

Dokumentationens WinForms-billeder kan genskabes med styrede testdata:

```powershell
pwsh -NoProfile -NonInteractive -STA -File .\tests\test-ui.ps1 `
  -RenderPath .\docs\images\dashboard.png `
  -RenderDetailsPath .\docs\images\release-notes.png `
  -RenderHistoryPath .\docs\images\history.png
```

Billederne er rigtige WinForms-renderinger. De læser ikke installerede værktøjer og dokumenterer ikke live-adfærd på en anden computer.
