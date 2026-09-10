# Release metadata is untrusted display text. Never execute Markdown, HTML, or returned links.
function ConvertTo-ReleaseVersion {
    param([string]$Version)
    if ($Version.Length -gt 80 -or $Version -cnotmatch '^v?\d+(?:\.\d+){1,3}(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
        throw 'Versionsnummeret er ikke gyldigt til opslag af ændringsnoter.'
    }
    $value=$Version -creplace '^v',''
    # WinGet/MSIX can report the same release with a zero fourth component.
    return ($value -replace '^(\d+\.\d+\.\d+)\.0$','$1')
}

function Test-ReleaseKey {
    param([string]$Key)
    # Keys name cache files and select fixed sources. Custom catalog keys (custom_<guid>) are valid names without a source.
    return [bool]($Key -cmatch '^[a-z][a-z0-9_]{0,79}$')
}

function Get-ReleaseSource {
    param([string]$Key,[string]$Version)
    switch ($Key) {
        'codex' {return @{Kind='github';Repo='openai/codex';TagPrefix='rust-v';Tag="rust-v$Version";Url="https://api.github.com/repos/openai/codex/releases/tags/rust-v$Version";SourceUrl="https://github.com/openai/codex/releases/tag/rust-v$Version"}}
        'gh' {return @{Kind='github';Repo='cli/cli';TagPrefix='v';Tag="v$Version";Url="https://api.github.com/repos/cli/cli/releases/tags/v$Version";SourceUrl="https://github.com/cli/cli/releases/tag/v$Version"}}
        'claude' {return @{Kind='markdown';Url='https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md';SourceUrl='https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md'}}
        'agy' {return @{Kind='markdown';Url='https://raw.githubusercontent.com/google-antigravity/antigravity-cli/refs/heads/main/CHANGELOG.md';SourceUrl='https://github.com/google-antigravity/antigravity-cli/blob/main/CHANGELOG.md'}}
        'antigravity_app' {return @{Kind='antigravity';Url='https://antigravity.google/changelog';SourceUrl='https://antigravity.google/changelog'}}
        'claude_app' {return @{Kind='claude-news';Url='https://support.claude.com/en/articles/12138966-release-notes';SourceUrl='https://support.claude.com/en/articles/12138966-release-notes'}}
        'codex_app' {return @{Kind='openai-app-news';Url='https://learn.chatgpt.com/docs/changelog';SourceUrl='https://learn.chatgpt.com/docs/changelog'}}
        default {throw "Ukendt værktøj til versionsnyt: $Key"}
    }
}

function Get-ReleaseRangeSource {
    param([string]$Key)
    # The range reads a list source. GitHub uses the paged release list; the other kinds reuse the single-version document.
    $source=Get-ReleaseSource $Key '0.0.0'
    if ($source.Kind -eq 'github') {
        return @{Kind='github';Repo=$source.Repo;TagPrefix=$source.TagPrefix;Url="https://api.github.com/repos/$($source.Repo)/releases?per_page=100&page=";SourceUrl="https://github.com/$($source.Repo)/releases"}
    }
    return @{Kind=$source.Kind;Url=$source.Url;SourceUrl=$source.SourceUrl}
}

function Test-ManagerReleaseUrl {
    param([string]$Url)
    $uri=$null
    if (-not [uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri)) {return $false}
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or -not $uri.IsDefaultPort) {return $false}
    return ($uri.Host -eq 'github.com' -and $uri.AbsolutePath -match '^/(openai/codex|cli/cli|anthropics/claude-code|google-antigravity/antigravity-cli)/') -or
        ($uri.Host -eq 'antigravity.google' -and $uri.AbsolutePath -in @('/changelog','/releases')) -or
        ($uri.Host -eq 'support.claude.com' -and $uri.AbsolutePath -eq '/en/articles/12138966-release-notes') -or
        ($uri.Host -eq 'learn.chatgpt.com' -and $uri.AbsolutePath -eq '/docs/changelog')
}

function ConvertFrom-ReleaseHtml {
    param([string]$Html)
    $value=[regex]::Replace($Html,'(?is)<(script|style)\b[^>]*>.*?</\1>','')
    $value=[regex]::Replace($value,'(?is)<!--.*?-->','')
    $value=[regex]::Replace($value,'(?i)<li\b[^>]*>',"`n• ")
    $value=[regex]::Replace($value,'(?i)<br\b[^>]*>|</(?:p|h[1-6]|li|summary|details|ul|ol)>',"`n")
    $value=[regex]::Replace($value,'<[^>]+>','')
    $value=[Net.WebUtility]::HtmlDecode($value)
    $value=$value -replace '[\t\x20\u00a0]+',' ' -replace '[\x00-\x08\x0b\x0c\x0e-\x1f]',''
    return (($value -replace '\r','' -replace '\n[ \t]+',"`n" -replace '\n{3,}',"`n`n").Trim())
}

function Read-ChangelogSections {
    param([string]$Markdown)
    # Every H2 that starts with a version, with the text up to the next H2 (including non-version sections).
    $headings=[regex]::Matches($Markdown,'(?m)^##[ \t]+([^\r\n]+)')
    $sections=[Collections.Generic.List[object]]::new()
    for ($i=0; $i -lt $headings.Count; $i++) {
        $heading=$headings[$i]
        $match=[regex]::Match($heading.Groups[1].Value,'^\[?(v?\d+(?:\.\d+){1,3}(?:-[0-9A-Za-z.-]+)?)(?:\]|\s|$)')
        if (-not $match.Success) {continue}
        $start=$heading.Index+$heading.Length
        $end=if ($i+1 -lt $headings.Count) {$headings[$i+1].Index} else {$Markdown.Length}
        $sections.Add(@{Version=(ConvertTo-ReleaseVersion $match.Groups[1].Value);Body=$Markdown.Substring($start,$end-$start).Trim();PublishedAt=''})
    }
    return $sections
}

function Read-VersionChangelog {
    param([string]$Markdown,[string]$Version)
    $wanted=ConvertTo-ReleaseVersion $Version
    # Never prefix-match 2.1.2 against 2.1.20; the first non-empty exact section wins.
    foreach ($section in (Read-ChangelogSections $Markdown)) {
        if ($section.Version -ceq $wanted -and $section.Body) {return $section.Body}
    }
    return $null
}

function Read-AntigravityReleases {
    param([string]$Html)
    # Only the Hub panel describes the Desktop app; the page also holds CLI, SDK and IDE releases.
    $panel=[regex]::Match($Html,'(?is)<div\b[^>]*\bdata-list-panel=["'']hub["''][^>]*>(.*?)(?=<div\b[^>]*\bdata-list-panel=|<footer\b|$)')
    if (-not $panel.Success) {throw 'Antigravity-kildens desktop-afsnit kunne ikke genkendes.'}
    # Boolean attributes can end directly at >, so split with a lookahead at the attribute boundary.
    $rows=[regex]::Split($panel.Groups[1].Value,'(?is)<div\b(?=[^>]*\bdata-section-row(?:\s|=|>))[^>]*>')
    $releases=[Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $link=[regex]::Match($row,'(?is)<a\b[^>]*href=["''][^"'']*[?&](?:amp;)?version=([0-9.]+)[^"'']*["''][^>]*>\s*([0-9.]+)\s*</a>')
        if (-not $link.Success -or $link.Groups[1].Value -cne $link.Groups[2].Value) {continue}
        $releases.Add(@{Version=$link.Groups[1].Value;Body=(ConvertFrom-ReleaseHtml $row);PublishedAt=''})
    }
    return $releases
}

function Read-AntigravityRelease {
    param([string]$Html,[string]$Version)
    foreach ($release in (Read-AntigravityReleases $Html)) {
        if ($release.Version -ceq $Version -and $release.Body) {return $release.Body}
    }
    return $null
}

function ConvertTo-ReleaseTimestamp {
    param($Value)
    # ConvertFrom-Json turns ISO dates into DateTime; keep an unambiguous ISO string instead of a culture-formatted one.
    if ($Value -is [datetime]) {return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')}
    return [string]$Value
}

function Read-GitHubReleaseList {
    param([string]$Json,[string]$TagPrefix)
    # Published stable releases of this product only. Drafts, prereleases and other products' tags are ignored.
    $list=ConvertFrom-Json -InputObject $Json -NoEnumerate -ErrorAction Stop
    if ($list -isnot [array]) {throw 'Kildens udgivelsesliste har et uventet format.'}
    $releases=[Collections.Generic.List[object]]::new()
    foreach ($entry in $list) {
        if ($entry.draft -or $entry.prerelease) {continue}
        $tag=[string]$entry.tag_name
        if (-not $tag.StartsWith($TagPrefix,[StringComparison]::Ordinal)) {continue}
        $version=$tag.Substring($TagPrefix.Length)
        if ($version -cnotmatch '^\d+(?:\.\d+){1,3}$') {continue}
        $releases.Add(@{Version=$version;Body=[string]$entry.body;PublishedAt=(ConvertTo-ReleaseTimestamp $entry.published_at)})
    }
    return @{Releases=$releases;Count=$list.Count}
}

function Read-ClaudeProductNews {
    param([string]$Html)
    $article=[regex]::Match($Html,'(?is)<article\b[^>]*>(.*?)</article>')
    if (-not $article.Success) {throw 'Claude-kildens nyhedsartikel kunne ikke genkendes.'}
    $content=$article.Groups[1].Value
    # Read three dated entries; these are product news, never exact Desktop release notes.
    $dates=[regex]::Matches($content,'(?i)<h3\b')
    if ($dates.Count -gt 3) {$content=$content.Substring(0,$dates[3].Index)}
    $text=ConvertFrom-ReleaseHtml $content
    if (-not $text) {throw 'Claude returnerede en tom nyhedsartikel.'}
    return $text
}

function Invoke-ReleaseRequest {
    param([string]$Url)
    # Fixed public endpoints only. No credentials, shell commands, installed browser or cookies.
    $handler=[Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect=$false
    # The official server may compress even when earlier requests returned plain HTML.
    # Stream and size-limit the decoded content, not the much smaller wire payload.
    $handler.AutomaticDecompression=[Net.DecompressionMethods]::All
    $client=[Net.Http.HttpClient]::new($handler)
    $cancel=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(12))
    $response=$null; $stream=$null; $bufferStream=[IO.MemoryStream]::new()
    try {
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('AI-Manager/3.0')
        $response=$client.GetAsync($Url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancel.Token).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {throw "Versionskilden svarede HTTP $([int]$response.StatusCode)."}
        $stream=$response.Content.ReadAsStreamAsync($cancel.Token).GetAwaiter().GetResult()
        $buffer=[byte[]]::new(16384)
        while (($count=$stream.ReadAsync($buffer,0,$buffer.Length,$cancel.Token).GetAwaiter().GetResult()) -gt 0) {
            if ($bufferStream.Length+$count -gt 8MB) {throw 'Versionskildens svar var for stort.'}
            $bufferStream.Write($buffer,0,$count)
        }
        return [Text.Encoding]::UTF8.GetString($bufferStream.ToArray())
    } finally {
        if ($stream) {$stream.Dispose()}; if ($response) {$response.Dispose()}
        $bufferStream.Dispose(); $cancel.Dispose(); $client.Dispose(); $handler.Dispose()
    }
}

function Read-OpenAIDesktopNews {
    param([string]$Html)
    # The official changelog mixes CLI, mobile and desktop entries. Only entries
    # explicitly tagged codex-app describe this product; never imply a build match.
    $entries=[regex]::Matches($Html,'(?is)<li\b[^>]*\bdata-codex-topics=["'']([^"'']*)["''][^>]*>')
    $selected=@(for ($i=0; $i -lt $entries.Count; $i++) {
        $entry=$entries[$i]
        if ('codex-app' -notin $entry.Groups[1].Value.Split(',')) {continue}
        # Bound the entry before looking for its article. A missing article must
        # never consume the next CLI/mobile entry's content.
        $start=$entry.Index+$entry.Length
        $end=if ($i+1 -lt $entries.Count) {$entries[$i+1].Index} else {$Html.Length}
        $article=[regex]::Match($Html.Substring($start,$end-$start),'(?is)^(.*?)<article\b[^>]*>(.*?)</article>')
        if (-not $article.Success) {continue}
        $text=ConvertFrom-ReleaseHtml ($article.Value -replace '(?i)</time>',"</time>`n")
        if ($text) {$text}
    })
    if (-not $selected.Count) {throw 'OpenAI-kildens desktopnyheder kunne ikke genkendes.'}
    return (($selected | Select-Object -First 3) -join "`n`n")
}

function Get-ReleaseResponse {
    param([string]$Url,[Collections.IDictionary]$Responses)
    # One download per endpoint per bundle; a failure is memoized too so no retry storms occur.
    if ($Responses -and $Responses.Contains($Url)) {
        $entry=$Responses[$Url]
        if ($entry.Error) {throw $entry.Error}; return $entry.Body
    }
    try {
        $raw=Invoke-ReleaseRequest $Url
        if ($null -ne $Responses) {$Responses[$Url]=@{Body=$raw;Error=''}}
        return $raw
    } catch {
        if ($null -ne $Responses) {$Responses[$Url]=@{Body='';Error=$_.Exception.Message}}
        throw
    }
}

function Read-ReleaseCache {
    param([string]$Path,[scriptblock]$Predicate)
    # Returns the cached hashtable and its age in hours, or $null when the file is missing, too large, malformed or for another request.
    if (-not (Test-Path -LiteralPath $Path)) {return $null}
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt 1MB) {throw 'Cache for stor'}
        $candidate=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($candidate -isnot [Collections.IDictionary] -or $candidate.Schema -ne 1 -or $candidate.State -notin @('Ready','Unavailable') -or
            $candidate.Body -isnot [string] -or $candidate.ExactVersion -isnot [bool] -or -not $candidate.RetrievedAt -or
            -not (& $Predicate $candidate)) {throw 'Cache matcher ikke forespørgslen'}
        $age=([datetimeoffset]::Now-[datetimeoffset]::Parse($candidate.RetrievedAt)).TotalHours
        return @{Value=$candidate;Age=$age}
    } catch {return $null}
}

function Limit-ReleaseBody {
    param([string]$Body)
    if ($Body.Length -gt 60000) {return $Body.Substring(0,60000)+"`n`nVisningen er forkortet. Åbn kilden for hele teksten."}
    return $Body
}

function Get-OneReleaseNotes {
    param([string]$Key,[string]$Version,[string]$StateDirectory,[switch]$Force,[Collections.IDictionary]$Responses)
    $note=[ordered]@{Schema=1;Key=$Key;Version=$Version;Body='';State='Unavailable';Message='Versionsnummeret er ikke kendt endnu.';SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$false}
    # Custom catalog entries (WinGet/msstore) have no registered exact change source: say so, never build a URL or a cache file.
    if (-not (Test-ReleaseKey $Key)) {$note.Message='Værktøjsnøglen er ikke gyldig til opslag af versionsnyt.'; return [pscustomobject]$note}
    if (-not $Version) {return [pscustomobject]$note}
    $normalized=ConvertTo-ReleaseVersion $Version
    try {$source=Get-ReleaseSource $Key $normalized} catch {
        $note.Message='Der er ingen registreret officiel ændringskilde for dette værktøj. Se udgiverens egen side.'
        return [pscustomobject]$note
    }
    $note.SourceUrl=$source.SourceUrl
    $cachePath=Join-Path $StateDirectory "release-notes/$Key-$normalized.json"
    $cached=$null
    $hit=Read-ReleaseCache $cachePath {param($c) $c.Key -ceq $Key -and (ConvertTo-ReleaseVersion $c.Version) -ceq $normalized -and $c.SourceUrl -ceq $source.SourceUrl}
    if ($hit) {
        $cached=$hit.Value; $cached.Version=$Version
        $ttl=if ($cached.State -eq 'Ready') {6} else {0.25}
        if (-not $Force -and $hit.Age -ge 0 -and $hit.Age -lt $ttl) {return [pscustomobject]$cached}
    }
    try {
        $raw=Get-ReleaseResponse $source.Url $Responses
        switch ($source.Kind) {
            'github' {
                $release=$raw | ConvertFrom-Json -ErrorAction Stop
                if ($release.tag_name -cne $source.Tag) {throw 'Kildens version matcher ikke den valgte version.'}
                $note.Body=[string]$release.body; $note.PublishedAt=ConvertTo-ReleaseTimestamp $release.published_at
            }
            'markdown' {$note.Body=[string](Read-VersionChangelog $raw $normalized)}
            'antigravity' {$note.Body=[string](Read-AntigravityRelease $raw $normalized)}
            'claude-news' {$note.Body=Read-ClaudeProductNews $raw}
            'openai-app-news' {$note.Body=Read-OpenAIDesktopNews $raw}
        }
        if ($note.Body.Trim()) {
            $note.State='Ready'; $note.ExactVersion=$source.Kind -notin @('claude-news','openai-app-news')
            $note.Message=if ($note.ExactVersion) {'Officielle ændringsnoter til denne version.'}
                elseif ($source.Kind -eq 'openai-app-news') {'Dette er generelle ChatGPT / Codex-desktopnyheder og kan omfatte flere platforme. OpenAI knytter dem ikke til dette præcise Windows-versionsnummer.'}
                else {'Dette er generelle Claude-produktnyheder. Udgiveren knytter dem ikke til dette Desktop-versionsnummer.'}
            $note.Body=Limit-ReleaseBody $note.Body
        } else {$note.Message='Udgiveren har ikke offentliggjort ændringsnoter til denne præcise version i den kontrollerede kilde.'}
        $note.RetrievedAt=[datetimeoffset]::Now.ToString('o')
        try {Save-ManagerJson $cachePath $note} catch {$note.Message+=' Noterne kunne ikke gemmes lokalt.'}
    } catch {
        if ($cached -and $cached.State -eq 'Ready' -and $cached.Body) {
            $cached.IsStale=$true
            $cached.Message="Viser tidligere hentede noter. Onlinekontrol fejlede: $($_.Exception.Message)"
            if (-not $cached.ExactVersion) {$cached.Message+=' Dette er generelle produktnyheder, ikke noter til den præcise appversion.'}
            # A failed explicit refresh remains visible on reselection and after restarting.
            # Only a successful source request can clear IsStale; RetrievedAt stays unchanged.
            try {Save-ManagerJson $cachePath $cached} catch {$cached.Message+=' Fejlstatus kunne ikke gemmes lokalt.'}
            return [pscustomobject]$cached
        }
        $note.State='Error'; $note.Message="Versionsnyt kunne ikke hentes: $($_.Exception.Message)"; $note.Body=''; $note.ExactVersion=$false
    }
    return [pscustomobject]$note
}

function Select-ReleaseRange {
    param([Collections.Generic.List[object]]$Releases,[string]$Installed,[string]$Latest)
    # Newest first by numeric comparison; one entry per version; installed excluded, everything up to and including the available version kept.
    $selected=[Collections.Generic.List[object]]::new(); $seen=@{}
    $lowerCovered=$false; $upperFound=$false
    foreach ($release in $Releases) {
        $toInstalled=Compare-ToolVersion $release.Version $Installed
        if ($toInstalled -le 0) {$lowerCovered=$true; continue}
        $toLatest=Compare-ToolVersion $release.Version $Latest
        if ($toLatest -gt 0) {continue}
        if ($toLatest -eq 0) {$upperFound=$true}
        if ($seen.ContainsKey($release.Version)) {continue}
        $seen[$release.Version]=$true; $selected.Add($release)
    }
    $selected.Sort([Comparison[object]]{param($a,$b) Compare-ToolVersion $b.Version $a.Version})
    return @{Releases=$selected;LowerCovered=$lowerCovered;UpperFound=$upperFound}
}

function Get-ToolReleaseRange {
    param([string]$Key,[string]$Installed,[string]$Latest,[string]$StateDirectory,[switch]$Force,[Collections.IDictionary]$Responses)
    $note=[ordered]@{Schema=1;Key=$Key;Version="$Installed → $Latest";FromVersion=$Installed;ToVersion=$Latest;Body='';State='Unavailable';Message='';SourceUrl='';PublishedAt='';RetrievedAt='';IsStale=$false;ExactVersion=$false;ReleaseCount=0;Complete=$false}
    if (-not (Test-ReleaseKey $Key)) {$note.Message='Værktøjsnøglen er ikke gyldig til opslag af versionsnyt.'; return [pscustomobject]$note}
    if (-not $Installed -or -not $Latest) {$note.Message='Nyt siden din version kræver både en kendt installeret og en kendt tilgængelig version.'; return [pscustomobject]$note}
    # Same version, ahead or unknown numbering: a clear message and no network.
    try {$comparison=Compare-ToolVersion $Installed $Latest; $from=ConvertTo-ReleaseVersion $Installed; $to=ConvertTo-ReleaseVersion $Latest}
    catch {$note.Message='Versionsnumrene kan ikke sammenlignes, så intervallet kan ikke vises.'; return [pscustomobject]$note}
    if ($comparison -eq 0) {$note.Message='Den installerede version er den nyeste kendte. Der er intet interval at vise.'; return [pscustomobject]$note}
    if ($comparison -gt 0) {$note.Message='Den installerede version er nyere end den tilgængelige version. Der er intet interval at vise.'; return [pscustomobject]$note}
    try {$source=Get-ReleaseRangeSource $Key} catch {
        $note.Message='Der er ingen registreret officiel ændringskilde for dette værktøj. Se udgiverens egen side.'
        return [pscustomobject]$note
    }
    $note.SourceUrl=$source.SourceUrl
    $cachePath=Join-Path $StateDirectory "release-notes/range-$Key-$from-$to.json"
    $cached=$null
    $hit=Read-ReleaseCache $cachePath {param($c) $c.Key -ceq $Key -and (ConvertTo-ReleaseVersion $c.FromVersion) -ceq $from -and (ConvertTo-ReleaseVersion $c.ToVersion) -ceq $to -and
        $c.SourceUrl -ceq $source.SourceUrl -and $c.Complete -is [bool] -and ($c.ReleaseCount -is [int] -or $c.ReleaseCount -is [long]) -and $c.ReleaseCount -ge 0}
    if ($hit) {
        $cached=$hit.Value; $cached.FromVersion=$Installed; $cached.ToVersion=$Latest; $cached.Version=$note.Version
        $ttl=if ($cached.State -eq 'Ready') {6} else {0.25}
        if (-not $Force -and $hit.Age -ge 0 -and $hit.Age -lt $ttl) {return [pscustomobject]$cached}
    }
    try {
        $general=$source.Kind -in @('claude-news','openai-app-news')
        if ($general) {
            $raw=Get-ReleaseResponse $source.Url $Responses
            $note.Body=if ($source.Kind -eq 'claude-news') {Read-ClaudeProductNews $raw} else {Read-OpenAIDesktopNews $raw}
            $note.Message=if ($source.Kind -eq 'openai-app-news') {'Dette er generelle ChatGPT / Codex-desktopnyheder, ikke en liste over ændringer mellem de to præcise Windows-versioner. OpenAI knytter dem ikke til versionsnumrene.'}
                else {'Dette er generelle Claude-produktnyheder, ikke en liste over ændringer mellem de to præcise Desktop-versioner. Udgiveren knytter dem ikke til versionsnumrene.'}
        } else {
            $releases=[Collections.Generic.List[object]]::new(); $truncatedList=$false
            switch ($source.Kind) {
                'github' {
                    # Publication order is not numeric version order: a republished old
                    # release cannot prove that later pages contain no intermediate versions.
                    for ($page=1; $page -le 3; $page++) {
                        $pageResult=Read-GitHubReleaseList (Get-ReleaseResponse "$($source.Url)$page" $Responses) $source.TagPrefix
                        $releases.AddRange([Collections.Generic.List[object]]$pageResult.Releases)
                        if ($pageResult.Count -lt 100) {break}
                        if ($page -eq 3) {$truncatedList=$true}
                    }
                }
                'markdown' {$releases=Read-ChangelogSections (Get-ReleaseResponse $source.Url $Responses)}
                'antigravity' {$releases=Read-AntigravityReleases (Get-ReleaseResponse $source.Url $Responses)}
            }
            # Prereleases in changelogs are not published stable versions.
            $stable=[Collections.Generic.List[object]]::new()
            foreach ($release in $releases) {if ($release.Version -cmatch '^\d+(?:\.\d+){1,3}$') {$stable.Add($release)}}
            $selection=Select-ReleaseRange $stable $from $to
            $note.ReleaseCount=$selection.Releases.Count
            $missingNotes=@($selection.Releases | Where-Object {[string]::IsNullOrWhiteSpace($_.Body)}).Count
            $note.Complete=[bool]($selection.LowerCovered -and $selection.UpperFound -and -not $truncatedList -and -not $missingNotes)
            $parts=foreach ($release in $selection.Releases) {
                $day=[regex]::Match([string]$release.PublishedAt,'^\d{4}-\d{2}-\d{2}')
                $date=if ($day.Success) {" ($($day.Value))"} else {''}
                $body=if ([string]::IsNullOrWhiteSpace($release.Body)) {'Udgiveren har ikke offentliggjort ændringsnoter til denne version.'} else {$release.Body.Trim()}
                "## $($release.Version)$date`n`n$body"
            }
            $note.Body=($parts -join "`n`n")
            if ($selection.Releases.Count) {$note.PublishedAt=[string]$selection.Releases[0].PublishedAt}
            if ($note.Complete) {$note.Message="Officielle ændringsnoter for $($selection.Releases.Count) udgivelse$(if ($selection.Releases.Count -ne 1) {'r'}) siden den installerede version."}
            elseif (-not $selection.UpperFound -and $selection.LowerCovered) {$note.Message="Delvis: den tilgængelige version $Latest er endnu ikke offentliggjort i den kontrollerede kilde. Viser $($selection.Releases.Count) kendte udgivelse$(if ($selection.Releases.Count -ne 1) {'r'}) siden den installerede version."}
            elseif ($truncatedList) {$note.Message="Delvis: kilden viser kun de seneste udgivelser, og ældre ændringer siden $Installed er ikke medtaget."}
            else {$note.Message="Delvis: kilden dækker ikke hele intervallet fra $Installed. Ældre ændringer kan mangle$(if (-not $selection.UpperFound) {", og den tilgængelige version $Latest er endnu ikke offentliggjort i kilden"})."}
            if ($missingNotes) {
                $note.Message=if ($selection.LowerCovered -and $selection.UpperFound -and -not $truncatedList) {"Delvis: $missingNotes udgivelse$(if ($missingNotes -ne 1) {'r'}) i intervallet mangler offentliggjorte ændringsnoter."} else {$note.Message+" $missingNotes kendte udgivelser mangler ændringsnoter."}
            }
        }
        if ($note.Body.Trim()) {
            $note.State='Ready'; $note.ExactVersion=-not $general; $note.Body=Limit-ReleaseBody $note.Body
        } else {
            $note.State='Unavailable'; $note.PublishedAt=''
            $note.Message=if ($general) {'Udgiveren har ikke offentliggjort nyheder i den kontrollerede kilde.'} else {"Udgiveren har ikke offentliggjort stabile udgivelser efter $Installed i den kontrollerede kilde."}
        }
        $note.RetrievedAt=[datetimeoffset]::Now.ToString('o')
        try {Save-ManagerJson $cachePath $note} catch {$note.Message+=' Noterne kunne ikke gemmes lokalt.'}
    } catch {
        if ($cached -and $cached.State -eq 'Ready' -and $cached.Body) {
            $cached.IsStale=$true
            $cached.Message="Viser tidligere hentede noter. Onlinekontrol fejlede: $($_.Exception.Message)"
            if (-not $cached.ExactVersion) {$cached.Message+=' Dette er generelle produktnyheder, ikke ændringer mellem de præcise versioner.'}
            elseif (-not $cached.Complete) {$cached.Message+=' Den tidligere hentning dækkede kun en del af intervallet.'}
            try {Save-ManagerJson $cachePath $cached} catch {$cached.Message+=' Fejlstatus kunne ikke gemmes lokalt.'}
            return [pscustomobject]$cached
        }
        $note.State='Error'; $note.Message="Nyt siden din version kunne ikke hentes: $($_.Exception.Message)"; $note.Body=''; $note.ExactVersion=$false; $note.ReleaseCount=0; $note.Complete=$false; $note.PublishedAt=''
    }
    return [pscustomobject]$note
}

function Get-ToolReleaseBundle {
    param($Status,[string]$StateDirectory,[switch]$Force)
    $responses=@{}
    $installed=Get-OneReleaseNotes $Status.Key $Status.Installed $StateDirectory -Force:$Force -Responses $responses
    $available=if ($Status.Latest -and $Status.Installed -and
        (ConvertTo-ReleaseVersion $Status.Latest) -ceq (ConvertTo-ReleaseVersion $Status.Installed)) {
        $copy=$installed.PSObject.Copy(); $copy.Version=$Status.Latest; $copy
    } else {Get-OneReleaseNotes $Status.Key $Status.Latest $StateDirectory -Force:$Force -Responses $responses}
    # The range reuses the endpoint text already downloaded for the two panels above.
    $range=Get-ToolReleaseRange $Status.Key $Status.Installed $Status.Latest $StateDirectory -Force:$Force -Responses $responses
    [pscustomobject]@{Key=$Status.Key;Installed=$installed;Available=$available;Range=$range}
}
