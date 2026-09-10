$ErrorActionPreference='Stop'
. "$PSScriptRoot/../updater-core.ps1"
$module=Join-Path $PSScriptRoot '../updater-releases.ps1'
if (-not (Test-Path -LiteralPath $module)) {throw 'Release notes module is missing: installed and available versions have no notes'}
. $module
$script:assertions=0
function Assert-Release($Condition,[string]$Message) {
    if (-not $Condition) {throw $Message}; $script:assertions++
}
$markdown=@'
# Changelog
## 2.1.20
- Newer unrelated release
## [2.1.2] - 2026-09-01
### Fixes
- Correct release with **bold** and `code`.
## 2.1.1
- Old unrelated release
'@
$body=Read-VersionChangelog $markdown '2.1.2'
Assert-Release ($body -match 'Correct release' -and $body -notmatch 'unrelated') 'Version selection leaked neighboring releases'
Assert-Release ($null -eq (Read-VersionChangelog $markdown '2.1.3')) 'Missing version borrowed a different version'
Assert-Release ((ConvertTo-ReleaseVersion '1.44121.2.0') -eq '1.44121.2') 'MSIX zero revision did not normalize'
Assert-Release ((ConvertTo-ReleaseVersion '1.2.3.4') -eq '1.2.3.4') 'Nonzero revision was removed'
Assert-Release ((ConvertTo-ReleaseVersion 'v0.154.0-beta.2') -eq '0.154.0-beta.2') 'Prerelease changed'
$rejected=$false
try {ConvertTo-ReleaseVersion '../../bad' | Out-Null} catch {$rejected=$true}
Assert-Release $rejected 'Unsafe version accepted'
$html=@'
<div data-list-panel="hub"><div class="section-row-wrapper" data-section-row><a href="/releases?tab=hub&amp;version=2.12.2">2.12.2</a><br>September 3, 2026<h3>Right version</h3><p>Fast &amp; stable</p><details><summary>Fixes (1)</summary><ul><li>Correct desktop fix</li></ul></details></div><div data-section-row><a href="/releases?tab=hub&amp;version=2.12.0">2.12.0</a><p>Wrong version</p></div></div><div data-list-panel="cli"><div data-section-row><a>2.12.2</a><p>Wrong product</p></div></div>
'@
$desktop=Read-AntigravityRelease $html '2.12.2'
Assert-Release ($desktop -match 'Correct desktop fix' -and $desktop -match 'Fast & stable' -and $desktop -notmatch 'Wrong') 'Desktop notes leaked another version/product'
Assert-Release ($null -eq (Read-AntigravityRelease $html '2.12.9')) 'Missing desktop version borrowed newer notes'
$general=Read-ClaudeProductNews '<nav>Wrong navigation</nav><article><h3>September 1, 2026</h3><p>Real news</p><script>bad()</script></article><footer>Wrong footer</footer>'
Assert-Release ($general -match 'Real news' -and $general -notmatch 'Wrong|bad\(\)') 'HTML extraction included navigation/script'
$openaiHtml=@'
<nav>Wrong navigation</nav><li data-codex-topics="codex-cli"><time>2026-09-09</time><h3>Wrong CLI</h3><article>Wrong CLI notes</article></li><li data-codex-topics="general,codex-app"><time>2026-09-08</time><h3>Desktop news</h3><article><ul><li>Right app news</li></ul><script>bad()</script></article></li><li data-codex-topics="codex-mobile"><article>Wrong mobile</article></li><footer>Wrong footer</footer>
'@
$appNews=Read-OpenAIDesktopNews $openaiHtml
Assert-Release ($appNews -match 'Right app news' -and $appNews -match '2026-09-08' -and $appNews -notmatch 'Wrong|bad\(\)') 'OpenAI app news leaked CLI/mobile or navigation'
$brokenApp='<li data-codex-topics="codex-app"><time>2026-09-10</time><h3>Desktop headline only</h3></li><li data-codex-topics="codex-cli"><time>2026-09-09</time><article>CLI_ONLY_SENTINEL</article></li>'
$rejected=$false
try {Read-OpenAIDesktopNews $brokenApp | Out-Null} catch {$rejected=$true}
Assert-Release $rejected 'App entry without its own article borrowed the next CLI entry'
Assert-Release ((Read-OpenAIDesktopNews ($brokenApp+$openaiHtml)) -notmatch 'CLI_ONLY_SENTINEL') 'Malformed app entry contaminated later valid desktop news'

$state=Join-Path $PSScriptRoot ('../artifacts/releases-test-'+[guid]::NewGuid().ToString('N'))
$script:requests=[Collections.Generic.List[string]]::new(); $script:offline=$false; $script:wrongTag=$false
# GitHub list fixture: one entry per release, deliberately unordered, with prerelease, draft and foreign tags.
function New-GitHubRelease([string]$Tag,[string]$Date='2026-09-01T00:00:00Z',[bool]$Prerelease=$false,[bool]$Draft=$false,[string]$Body='') {
    @{tag_name=$Tag;name=$Tag;prerelease=$Prerelease;draft=$Draft;published_at=$Date;body=$(if ($Body) {$Body} else {"Notes for $Tag"})}
}
$script:codexPages=@(,@(
    (New-GitHubRelease 'rust-v0.154.0' '2026-09-02T00:00:00Z'),
    (New-GitHubRelease 'rust-v0.156.0' '2026-09-06T00:00:00Z'),
    (New-GitHubRelease 'rust-v0.155.0' '2026-09-04T00:00:00Z'),
    (New-GitHubRelease 'rust-v0.155.0-beta.1' '2026-09-03T00:00:00Z' $true),
    (New-GitHubRelease 'rust-v0.154.5' '2026-09-03T00:00:00Z' $false $true),
    (New-GitHubRelease 'v0.154.9' '2026-09-03T00:00:00Z'),
    (New-GitHubRelease 'rust-v0.153.10' '2026-09-01T12:00:00Z'),
    (New-GitHubRelease 'rust-v0.153.9' '2026-09-01T00:00:00Z'),
    (New-GitHubRelease 'rust-v0.153.0' '2026-08-20T00:00:00Z')))
$script:ghPages=@(,@((New-GitHubRelease 'v2.97.0'),(New-GitHubRelease 'v2.96.0'),(New-GitHubRelease 'gh-2.95.5'),(New-GitHubRelease 'v2.95.0')))
# Only the external HTTP boundary is replaced; parser, cache and selection are real.
function Invoke-ReleaseRequest([string]$Url) {
    $script:requests.Add($Url)
    if ($script:offline) {throw 'Synthetic network timeout'}
    if ($Url -like '*openai/codex/releases/tags/*') {
        $tag=($Url -split '/')[-1]
        return (@{tag_name=$(if ($script:wrongTag) {'rust-v9.9.9'} else {$tag});body="Notes for $tag";published_at='2026-09-01T00:00:00Z'} | ConvertTo-Json)
    }
    $list=[regex]::Match($Url,'^https://api\.github\.com/repos/(openai/codex|cli/cli)/releases\?per_page=100&page=(\d+)$')
    if ($list.Success) {
        # Direct assignment keeps the outer page array; an if-expression would unroll a single page.
        $pages=$script:codexPages; if ($list.Groups[1].Value -eq 'cli/cli') {$pages=$script:ghPages}
        $index=[int]$list.Groups[2].Value-1
        $page=@(); if ($index -lt $pages.Count) {$page=@($pages[$index])}
        return (ConvertTo-Json -InputObject $page -Depth 4 -Compress)
    }
    if ($Url -like '*anthropics/claude-code*') {return $markdown}
    if ($Url -eq 'https://antigravity.google/changelog') {return $html}
    if ($Url -like 'https://support.claude.com/*') {return '<article><h3>September 1, 2026</h3><p>General Claude news</p></article>'}
    if ($Url -eq 'https://learn.chatgpt.com/docs/changelog') {return $brokenApp+$openaiHtml}
    throw "Unexpected test request: $Url"
}
$tool=@{Key='codex';Name='OpenAI Codex';Type='CLI';Source='Test'}
$status=New-ToolStatus $tool '0.153.0' '0.154.0' '' ''
$bundle=Get-ToolReleaseBundle $status $state
Assert-Release ($bundle.Installed.Body -match 'rust-v0.153.0' -and $bundle.Available.Body -match 'rust-v0.154.0') 'Installed/available versions were swapped'
Assert-Release ($bundle.Installed.ExactVersion -and $bundle.Available.State -eq 'Ready') 'Exact release marked unavailable'
# Two exact tag lookups plus one release list page for the range.
Assert-Release ($script:requests.Count -eq 3) 'Wrong number of initial fetches'
Assert-Release ($bundle.Range.State -eq 'Ready' -and $bundle.Range.Complete -and $bundle.Range.ReleaseCount -eq 3) 'Range 0.153.0 → 0.154.0 did not include every intermediate stable release'
$again=Get-ToolReleaseBundle $status $state
Assert-Release ($script:requests.Count -eq 3 -and -not $again.Installed.IsStale -and -not $again.Range.IsStale) 'Fresh cache not reused'
$script:offline=$true
$fallback=Get-ToolReleaseBundle $status $state -Force
Assert-Release ($fallback.Installed.IsStale -and $fallback.Available.IsStale -and $fallback.Installed.Body -match '0.153.0') 'Network failure discarded cached notes'
Assert-Release ($fallback.Installed.Message -match 'timeout' -and $fallback.Installed.RetrievedAt -eq $bundle.Installed.RetrievedAt) 'Offline data appeared freshly retrieved'
Assert-Release ($fallback.Range.IsStale -and $fallback.Range.Body -match 'rust-v0.153.10' -and $fallback.Range.Message -match 'timeout' -and $fallback.Range.RetrievedAt -eq $bundle.Range.RetrievedAt -and $fallback.Range.Complete) 'Offline range lost its cached body, original retrieval time or completeness'
$reselected=Get-ToolReleaseBundle $status $state
Assert-Release ($reselected.Installed.IsStale -and $reselected.Installed.Message -match 'timeout') 'Reselecting after failed refresh falsely cleared stale state'
Assert-Release ($reselected.Range.IsStale -and $reselected.Range.Message -match 'timeout') 'Reselecting after failed range refresh falsely cleared stale state'
$noCache=Get-ToolReleaseRange 'codex' '0.100.0' '0.101.0' $state -Force
Assert-Release ($noCache.State -eq 'Error' -and -not $noCache.Body -and -not $noCache.Complete -and $noCache.ReleaseCount -eq 0) 'Offline range without cache invented releases'
$unknown=Get-OneReleaseNotes 'codex' '9.9.8' $state -Force
Assert-Release ($unknown.State -eq 'Error' -and -not $unknown.Body) 'Offline without cache invented release notes'
$script:offline=$false; $script:wrongTag=$true
$mismatch=Get-OneReleaseNotes 'codex' '9.9.7' $state -Force
Assert-Release ($mismatch.State -eq 'Error' -and -not $mismatch.Body) 'Mismatched API tag accepted'
$script:wrongTag=$false
$recovered=Get-ToolReleaseBundle $status $state -Force
Assert-Release (-not $recovered.Installed.IsStale -and $recovered.Installed.Message -notmatch 'timeout') 'Successful refresh did not clear stale state'
Assert-Release (-not $recovered.Range.IsStale -and $recovered.Range.Message -notmatch 'timeout') 'Successful range refresh did not clear stale state'

# "Nyt siden din version": every published stable release after the installed version up to the available one.
$range=$recovered.Range
Assert-Release ($range.Schema -eq 1 -and $range.Key -eq 'codex' -and $range.Version -eq '0.153.0 → 0.154.0' -and $range.FromVersion -eq '0.153.0' -and $range.ToVersion -eq '0.154.0') 'Range identity fields are wrong'
Assert-Release ($range.ExactVersion -and $range.SourceUrl -eq 'https://github.com/openai/codex/releases' -and (Test-ManagerReleaseUrl $range.SourceUrl)) 'Range source is not the official release list'
Assert-Release ($range.Body -match 'Notes for rust-v0.154.0' -and $range.Body -match 'Notes for rust-v0.153.10' -and $range.Body -match 'Notes for rust-v0.153.9') 'Intermediate stable releases are missing from the range'
Assert-Release ($range.Body -notmatch 'rust-v0.153.0\b' -and $range.Body -notmatch '0\.155\.0' -and $range.Body -notmatch '0\.156\.0') 'Range included the installed or a future version'
Assert-Release ($range.Body -notmatch 'beta' -and $range.Body -notmatch '0\.154\.5' -and $range.Body -notmatch 'v0\.154\.9') 'Range included a prerelease, draft or foreign-product tag'
Assert-Release ($range.Body.IndexOf('0.154.0') -lt $range.Body.IndexOf('0.153.10') -and $range.Body.IndexOf('0.153.10') -lt $range.Body.IndexOf('0.153.9')) 'Range is not ordered numerically newest first (0.153.10 must sort above 0.153.9)'
Assert-Release ($range.PublishedAt -eq '2026-09-02T00:00:00Z' -and $range.Message -match 'siden') 'Range publish date/message do not describe the newest included release'
$numeric=Get-ToolReleaseRange 'codex' '0.153.9' '0.153.10' $state
Assert-Release ($numeric.ReleaseCount -eq 1 -and $numeric.Body -match 'rust-v0.153.10' -and $numeric.Body -notmatch 'rust-v0.153.9\b' -and $numeric.Complete) 'Numeric comparison failed for 0.153.9 → 0.153.10'
$requestCount=$script:requests.Count
foreach ($case in @(@('0.154.0','0.154.0'),@('0.155.0','0.154.0'),@('0.153.0',''),@('','0.154.0'),@('abc','0.154.0'))) {
    $note=Get-ToolReleaseRange 'codex' $case[0] $case[1] $state -Force
    Assert-Release ($note.State -eq 'Unavailable' -and -not $note.Body -and -not $note.Complete -and $note.ReleaseCount -eq 0 -and $note.Message) "Range for '$($case[0])' → '$($case[1])' was not a clear Unavailable"
}
Assert-Release ($script:requests.Count -eq $requestCount) 'Same/ahead/unknown version made a network request for the range'
$sameBundle=Get-ToolReleaseBundle (New-ToolStatus $tool '0.154.0' '0.154.0' '' '') $state
Assert-Release ($sameBundle.Range.State -eq 'Unavailable' -and $sameBundle.Range.Message -match 'nyeste' -and $sameBundle.Installed.State -eq 'Ready' -and $sameBundle.Available.Version -eq '0.154.0') 'Current tool lost its installed/available notes or got a fake range'
# GitHub does not guarantee numeric version order. Read to exhaustion or the three-page cap.
$script:codexPages=@(
    @(200..101 | ForEach-Object {New-GitHubRelease "rust-v1.0.$_" "2026-08-$('{0:d2}' -f (1+$_%28))T00:00:00Z"}),
    @(100..1 | ForEach-Object {New-GitHubRelease "rust-v1.0.$_"}),
    @(50..1 | ForEach-Object {New-GitHubRelease "rust-v0.9.$_"}))
$requestCount=$script:requests.Count
$onePage=Get-ToolReleaseRange 'codex' '1.0.150' '1.0.200' $state -Force
Assert-Release ($script:requests.Count -eq $requestCount+3 -and $onePage.Complete -and $onePage.ReleaseCount -eq 50) 'A lower version on page 1 stopped pagination before list exhaustion'
$twoPages=Get-ToolReleaseRange 'codex' '1.0.50' '1.0.200' $state -Force
Assert-Release ($script:requests.Count -eq $requestCount+6 -and $twoPages.Complete -and $twoPages.ReleaseCount -eq 150 -and $twoPages.Body -match 'rust-v1\.0\.51\b' -and $twoPages.Body -notmatch 'rust-v1\.0\.50\b') 'Second page was not fetched or was mis-filtered'
$partial=Get-ToolReleaseRange 'codex' '0.8.0' '1.0.200' $state -Force
Assert-Release ($script:requests.Count -eq $requestCount+9 -and $partial.State -eq 'Ready' -and -not $partial.Complete -and $partial.Message -match '^Delvis' -and $partial.ReleaseCount -eq 250) 'Uncovered installed version after three pages was not marked partial'
$script:codexPages+=,@(100..51 | ForEach-Object {New-GitHubRelease "rust-v0.8.$_"})
$script:codexPages[2]=@(100..1 | ForEach-Object {New-GitHubRelease "rust-v0.9.$_"})
$threeFull=Get-ToolReleaseRange 'codex' '0.1.0' '1.0.200' $state -Force
Assert-Release ($script:requests.Count -eq $requestCount+12 -and -not $threeFull.Complete -and $threeFull.Message -match '^Delvis.*seneste udgivelser' -and $threeFull.ReleaseCount -eq 300) 'Three full pages without coverage did not stop at the page limit with a truthful message'
$cappedCovered=Get-ToolReleaseRange 'codex' '1.0.150' '1.0.200' $state -Force
Assert-Release (-not $cappedCovered.Complete -and $cappedCovered.Message -match '^Delvis') 'Reaching both endpoints falsely proved that a capped list was complete'
$script:codexPages=$script:codexPages[0..2]; $script:codexPages[2]=@(50..1 | ForEach-Object {New-GitHubRelease "rust-v0.9.$_"})
$missingTop=Get-ToolReleaseRange 'codex' '1.0.199' '1.0.201' $state -Force
Assert-Release ($missingTop.State -eq 'Ready' -and -not $missingTop.Complete -and $missingTop.Message -match '^Delvis' -and $missingTop.Message -match '1\.0\.201' -and $missingTop.ReleaseCount -eq 1) 'Available version absent from the source was not marked partial'
$gapInstalled=Get-ToolReleaseRange 'codex' '0.9.50' '1.0.2' $state -Force
Assert-Release ($gapInstalled.Complete -and $gapInstalled.ReleaseCount -eq 2 -and $gapInstalled.Body -notmatch 'rust-v0\.9\.') 'Installed version absent but older releases present should still be complete'
$script:codexPages=@(,@((New-GitHubRelease 'rust-v3.0.0'),(New-GitHubRelease 'rust-v2.0.0-rc.1' '2026-09-01T00:00:00Z' $true),(New-GitHubRelease 'rust-v1.0.0')))
$nothing=Get-ToolReleaseRange 'codex' '3.0.0' '3.1.0' $state -Force
Assert-Release ($nothing.State -eq 'Unavailable' -and -not $nothing.Complete -and $nothing.ReleaseCount -eq 0 -and -not $nothing.Body) 'No published stable release after installed version should be Unavailable, not fabricated'
$script:codexPages=@(,@((New-GitHubRelease 'rust-v4.0.0' '2026-09-01T00:00:00Z' $false $false ('x'*70000)),(New-GitHubRelease 'rust-v3.9.0')))
$long=Get-ToolReleaseRange 'codex' '3.9.0' '4.0.0' $state -Force
Assert-Release ($long.Body.Length -lt 61000 -and $long.Body -match 'forkortet') 'Oversized range body was not truncated and marked'
$first=@((New-GitHubRelease 'rust-v2.0.0'),(New-GitHubRelease 'rust-v0.9.9'))+@(1..98 | ForEach-Object {New-GitHubRelease "rust-v3.0.0-alpha.$_" '2026-09-01T00:00:00Z' $true})
$script:codexPages=@($first,@((New-GitHubRelease 'rust-v1.5.0'),(New-GitHubRelease 'rust-v1.0.0')))
$unordered=Get-ToolReleaseRange 'codex' '1.0.0' '2.0.0' $state -Force
Assert-Release ($unordered.Complete -and $unordered.ReleaseCount -eq 2 -and $unordered.Body -match '1.5.0') 'An older republished release hid an intermediate release on page 2'
$emptyRelease=New-GitHubRelease 'rust-v1.5.0';$emptyRelease.body=''
$script:codexPages=@(,@((New-GitHubRelease 'rust-v2.0.0'),$emptyRelease,(New-GitHubRelease 'rust-v1.0.0')))
$missingBody=Get-ToolReleaseRange 'codex' '1.0.0' '2.0.0' $state -Force
Assert-Release (-not $missingBody.Complete -and $missingBody.ReleaseCount -eq 2 -and $missingBody.Body -match '1.5.0' -and $missingBody.Body -match 'ikke offentliggjort' -and $missingBody.Message -match '^Delvis') 'A known release without notes was silently omitted from a claimed complete interval'
$gh=Get-ToolReleaseRange 'gh' '2.95.0' '2.97.0' $state
Assert-Release ($gh.Complete -and $gh.ReleaseCount -eq 2 -and $gh.Body -notmatch 'gh-2\.95\.5' -and $gh.SourceUrl -eq 'https://github.com/cli/cli/releases') 'gh range accepted a foreign tag or wrong source'
# Markdown changelogs: every exact H2 version section inside the interval.
$claudeRange=Get-ToolReleaseRange 'claude' '2.1.1' '2.1.20' $state
Assert-Release ($claudeRange.State -eq 'Ready' -and $claudeRange.Complete -and $claudeRange.ReleaseCount -eq 2 -and $claudeRange.ExactVersion) 'Claude markdown range did not include both newer sections'
Assert-Release ($claudeRange.Body -match 'Correct release' -and $claudeRange.Body -match 'Newer unrelated' -and $claudeRange.Body -notmatch 'Old unrelated') 'Claude markdown range leaked the installed section or lost a newer one'
$claudePartial=Get-ToolReleaseRange 'claude' '2.1.0' '2.1.20' $state
Assert-Release ($claudePartial.State -eq 'Ready' -and -not $claudePartial.Complete -and $claudePartial.Message -match '^Delvis' -and $claudePartial.ReleaseCount -eq 3) 'Changelog without the installed version was claimed complete'
$claudeMissingTop=Get-ToolReleaseRange 'claude' '2.1.2' '2.1.21' $state
Assert-Release (-not $claudeMissingTop.Complete -and $claudeMissingTop.ReleaseCount -eq 1 -and $claudeMissingTop.Message -match '^Delvis') 'Changelog without the available version was claimed complete'
# Antigravity Desktop: only Hub rows, never CLI rows.
$agyRange=Get-ToolReleaseRange 'antigravity_app' '2.12.0' '2.12.2' $state
Assert-Release ($agyRange.Complete -and $agyRange.ReleaseCount -eq 1 -and $agyRange.Body -match 'Correct desktop fix' -and $agyRange.Body -notmatch 'Wrong') 'Antigravity range leaked another version/product'
$agyPartial=Get-ToolReleaseRange 'antigravity_app' '2.11.0' '2.12.2' $state
Assert-Release (-not $agyPartial.Complete -and $agyPartial.ReleaseCount -eq 2 -and $agyPartial.Message -match '^Delvis') 'Antigravity range without the oldest interval was claimed complete'
# General product news: shown as news, never as changes since the exact build.
$requestCount=$script:requests.Count
$appRange=Get-ToolReleaseBundle @{Key='codex_app';Installed='26.903.8094.0';Latest='26.903.9818.0'} $state -Force
Assert-Release ($appRange.Range.State -eq 'Ready' -and -not $appRange.Range.ExactVersion -and -not $appRange.Range.Complete -and $appRange.Range.Message -match 'generelle' -and $appRange.Range.Body -match 'Right app news' -and $appRange.Range.Body -notmatch 'CLI_ONLY_SENTINEL') 'Desktop range claimed exact build changes or leaked CLI news'
# Installed, available and range all read the same endpoint text: one download per bundle.
Assert-Release ($script:requests.Count -eq $requestCount+1) 'Endpoint text was downloaded more than once for one bundle'
$claudeApp=Get-ToolReleaseRange 'claude_app' '1.44121.2.0' '1.44200.1.0' $state
Assert-Release ($claudeApp.State -eq 'Ready' -and -not $claudeApp.ExactVersion -and -not $claudeApp.Complete -and $claudeApp.Message -match 'generelle' -and $claudeApp.Body -match 'General Claude news') 'Claude Desktop range did not present itself as general news'
# Custom WinGet/msstore catalog keys have no registered exact change source.
$requestCount=$script:requests.Count
$custom=Get-OneReleaseNotes 'custom_a1b2c3' '1.0.0' $state
Assert-Release ($custom.State -eq 'Unavailable' -and -not $custom.Body -and -not $custom.SourceUrl -and $custom.Message -match 'kilde') 'Unknown custom key threw or invented a source'
$customBundle=Get-ToolReleaseBundle @{Key='custom_a1b2c3';Installed='1.0.0';Latest='1.1.0'} $state -Force
Assert-Release ($customBundle.Installed.State -eq 'Unavailable' -and $customBundle.Available.State -eq 'Unavailable' -and $customBundle.Range.State -eq 'Unavailable' -and -not $customBundle.Range.SourceUrl) 'Custom catalog bundle was not an honest Unavailable'
foreach ($badKey in @('../evil','Codex','custom_'+('x'*80),'')) {
    $bad=Get-OneReleaseNotes $badKey '1.0.0' $state -Force
    Assert-Release ($bad.State -eq 'Unavailable' -and -not $bad.SourceUrl) "Invalid key '$badKey' was not rejected safely"
    $badRange=Get-ToolReleaseRange $badKey '1.0.0' '1.1.0' $state -Force
    Assert-Release ($badRange.State -eq 'Unavailable' -and -not $badRange.SourceUrl) "Invalid key '$badKey' produced a range"
}
Assert-Release ($script:requests.Count -eq $requestCount) 'Unknown/invalid key made a network request'
Assert-Release (-not (Get-ChildItem -LiteralPath (Join-Path $state 'release-notes') -Filter '*custom*' -ErrorAction SilentlyContinue) -and -not (Get-ChildItem -LiteralPath (Join-Path $state 'release-notes') -Filter '*evil*' -ErrorAction SilentlyContinue)) 'Unknown/invalid key created a cache file'
# Range cache validation: a file for another interval or source must be ignored, not trusted.
$script:codexPages=@(,@((New-GitHubRelease 'rust-v5.1.0'),(New-GitHubRelease 'rust-v5.0.0')))
$fresh=Get-ToolReleaseRange 'codex' '5.0.0' '5.1.0' $state
$rangeCache=Join-Path $state 'release-notes/range-codex-5.0.0-5.1.0.json'
Assert-Release ((Test-Path -LiteralPath $rangeCache) -and $fresh.ReleaseCount -eq 1) 'Range cache file was not written where expected'
$tampered=Get-Content -LiteralPath $rangeCache -Raw | ConvertFrom-Json -AsHashtable
$tampered.SourceUrl='https://evil.example/releases'; $tampered.Body='Injected'
Save-ManagerJson $rangeCache $tampered
$requestCount=$script:requests.Count
$revalidated=Get-ToolReleaseRange 'codex' '5.0.0' '5.1.0' $state
Assert-Release ($script:requests.Count -eq $requestCount+1 -and $revalidated.Body -notmatch 'Injected' -and $revalidated.SourceUrl -eq 'https://github.com/openai/codex/releases') 'Tampered range cache was trusted'
$claude=Get-OneReleaseNotes 'claude' '2.1.2' $state
Assert-Release ($claude.ExactVersion -and $claude.Body -match 'Correct release') 'Claude exact changelog unavailable'
$missing=Get-OneReleaseNotes 'claude' '2.1.3' $state
Assert-Release ($missing.State -eq 'Unavailable' -and -not $missing.ExactVersion) 'Unknown Claude version falsely has exact notes'
$news=Get-OneReleaseNotes 'claude_app' '1.44121.2.0' $state
Assert-Release ($news.State -eq 'Ready' -and -not $news.ExactVersion -and $news.Message -match 'generelle' -and $news.Body -match 'General Claude news') 'General product news claimed a specific app version'
$appBundle=Get-ToolReleaseBundle @{Key='codex_app';Installed='26.903.8094.0';Latest='26.903.9818.0'} $state
Assert-Release ($appBundle.Installed.State -eq 'Ready' -and -not $appBundle.Installed.ExactVersion -and -not $appBundle.Available.ExactVersion -and $appBundle.Available.Message -match 'generelle.*ChatGPT' -and $appBundle.Available.Body -match 'Right app news') 'Desktop news falsely claimed exact build notes or used CLI notes'
Assert-Release ($appBundle.Installed.Version -eq '26.903.8094.0' -and $appBundle.Available.Version -eq '26.903.9818.0') 'OpenAI Desktop version panels lost their four-part build'
$agy=Get-OneReleaseNotes 'antigravity_app' '2.12.2' $state
Assert-Release ($agy.ExactVersion -and $agy.Body -match 'Correct desktop fix') 'Antigravity exact notes unavailable'
$requestCount=$script:requests.Count
$empty=Get-OneReleaseNotes 'codex' '' $state
Assert-Release ($empty.State -eq 'Unavailable' -and $script:requests.Count -eq $requestCount) 'Unknown version made a network request'
foreach ($url in @('file:///C:/Windows/notepad.exe','https://evil.example/a','https://github.com@evil.example/a','http://github.com/openai/codex')) {
    Assert-Release (-not (Test-ManagerReleaseUrl $url)) "Unsafe source link accepted: $url"
}
Assert-Release (Test-ManagerReleaseUrl 'https://github.com/openai/codex/releases/tag/rust-v0.154.0') 'Official source rejected'
Assert-Release (Test-ManagerReleaseUrl 'https://learn.chatgpt.com/docs/changelog') 'Official app changelog link rejected'
Assert-Release (-not (Test-ManagerReleaseUrl 'https://learn.chatgpt.com/other')) 'Unrelated app-domain path accepted'
Write-Output "PASS: $script:assertions release assertions (exact versions, HTML, cache, offline, missing notes, links). Evidence: $state"
