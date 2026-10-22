# Submitting an extension's release to the rhun extensions index on Windows, for
# src/app/submitext.s: the steps of runtime/jobs/submitext.sh with curl.exe, and gh.exe when it is
# installed. The inputs come in RHUN_SX_STEP (prepare or submit), RHUN_SX_DIR, RHUN_SX_TAG ("-":
# vVERSION), RHUN_SX_GITHUB, RHUN_SX_API, RHUN_SX_RAW (prepare), RHUN_SX_WORK, RHUN_SX_CATEGORY,
# RHUN_SX_KEYWORDS, RHUN_SX_MAINTAINER and RHUN_SX_HOW (submit); the lines are runtime/jobs/
# submitext.sh's.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$utf8 = New-Object System.Text.UTF8Encoding $false
$work = $null
function Fail([string]$why) {
    if ($work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Output "fail $why"
    exit 1
}
function Step([int]$n, [int]$m, [string]$text) { Write-Output "step $n $m $text" }
$curl = Join-Path (Join-Path $env:SystemRoot 'System32') 'curl.exe'
function Fetch([string]$url, [string]$file) {
    $proto = @()
    if ($url -like 'https:*') { $proto = @('--proto', '=https', '--proto-redir', '=https') }
    & $curl -fsL @proto --max-time 120 --max-filesize 67108864 -o $file $url 2>$null
    return ($LASTEXITCODE -eq 0)
}
function Key([string]$text, [string]$key) {
    if ($text -match "(?m)^$key *= *([^\r\n]*)") { return $Matches[1].Trim() }
    return ''
}
function Gh { & gh @args 2>&1 | Out-String }

if ($env:RHUN_SX_STEP -eq 'prepare') {
    $dir = $env:RHUN_SX_DIR
    $ini = Join-Path $dir 'extension.ini'
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { Fail "$dir has no extension.ini" }
    $manifest = [IO.File]::ReadAllText($ini, $utf8)
    $owner = Key $manifest 'owner'
    $name = Key $manifest 'name'
    $version = Key $manifest 'version'
    if ($owner -notmatch '^[A-Za-z0-9_-][A-Za-z0-9._-]*$') { Fail 'extension.ini has no usable owner' }
    if ($name -notmatch '^[A-Za-z0-9_-][A-Za-z0-9._-]*$') { Fail 'extension.ini has no usable name' }
    $tag = $env:RHUN_SX_TAG
    if ($tag -eq '-') {
        if (-not $version) { Fail 'extension.ini has no version' }
        $tag = "v$version"
    }
    if ($tag -notmatch '^[0-9A-Za-z._-]+$') { Fail "$tag is not a release tag" }
    $full = "$owner/$name"
    $temp = if ($env:TMPDIR) { $env:TMPDIR } else { [IO.Path]::GetTempPath() }
    $folder = Join-Path $temp ('rhun-submit-' + [IO.Path]::GetRandomFileName().Replace('.', ''))
    try { New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null } catch { Fail 'cannot create a temporary folder' }
    $work = $folder
    Write-Output "work $work"
    [IO.File]::WriteAllText((Join-Path $work 'full'), "$full`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'tag'), "$tag`n", $utf8)
    if (-not (Test-Path -LiteralPath $curl)) { Fail 'Windows has no curl.exe (it comes with Windows 10 1803 and later)' }
    Step 1 3 "Reading the release $tag of $full"
    $rel = "$($env:RHUN_SX_GITHUB)/$full/releases/download/$tag"
    $sums = Join-Path $work 'sums'
    if (-not (Fetch "$rel/sha256sums.txt" $sums)) { Fail "$full has no release $tag with a sha256sums.txt ($rel/sha256sums.txt)" }
    $targets = @{}
    foreach ($line in Get-Content -LiteralPath $sums) {
        $f = $line.Trim() -split '\s+', 2
        if ($f.Count -ne 2) { continue }
        $file = $f[1].TrimStart('*')
        $digest = $f[0].ToLowerInvariant()
        if ($file -match "^$([regex]::Escape($name))-([a-z0-9_-]+)\.tar\.gz$" -and $digest -match '^[0-9a-f]{64}$') { $targets[$Matches[1]] = $digest }
    }
    if ($targets.Count -eq 0) { Fail "the release's sha256sums.txt lists no $name-TARGET.tar.gz" }
    Step 2 3 "Reading the commit of $tag"
    $url = "$($env:RHUN_SX_API)/repos/$full/commits/$tag"
    $json = Join-Path $work 'commit.json'
    if (-not (Fetch $url $json)) { Fail "could not read the commit of $tag ($url)" }
    $text = [IO.File]::ReadAllText($json, $utf8)
    if ($text -notmatch '^[^"]*"sha" *: *"([0-9a-f]{40})"') { Fail "the answer for the commit of $tag has no sha ($url)" }
    $commit = $Matches[1]
    $pins = "tag = $tag`ncommit = $commit`n"
    foreach ($t in ($targets.Keys | Sort-Object { [string]$_ } -CaseSensitive)) { $pins += "sha256.$t = $($targets[$t])`n" }
    [IO.File]::WriteAllText((Join-Path $work 'pins'), $pins, $utf8)
    Write-Output "full $full"
    Write-Output "tag $tag"
    Step 3 3 "Looking for $full in the index"
    $old = Join-Path $work 'old'
    if ((Fetch "$($env:RHUN_SX_RAW)/rhun-editor/extensions/main/$full.ini" $old) -and ([IO.File]::ReadAllText($old, $utf8) -match '(?m)^tag *=')) {
        Write-Output 'existing yes'
        $entry = [IO.File]::ReadAllText($old, $utf8)
        foreach ($k in 'category', 'keywords', 'maintainer') {
            $v = Key $entry $k
            if ($v) { Write-Output "$k $v" }
        }
    } else {
        Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
        Write-Output 'existing no'
    }
    $wf = Join-Path $dir '.github/workflows/release.yml'
    if (-not ((Test-Path -LiteralPath $wf -PathType Leaf) -and ([IO.File]::ReadAllText($wf, $utf8) -match 'actions/attest-build-provenance'))) {
        Write-Output "warn .github/workflows/release.yml does not attest the archives (actions/attest-build-provenance): the index's check needs that attestation, so add it (as the templates have it) and release again"
    }
    $login = '-'
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        & gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $l = (Gh api user --jq .login).Trim()
            if ($LASTEXITCODE -eq 0 -and $l -match '^[A-Za-z0-9][A-Za-z0-9-]*$') { $login = $l }
        }
    }
    Write-Output "gh $login"
    Write-Output 'ok'
    exit 0
}

if ($env:RHUN_SX_STEP -ne 'submit') { Fail "unknown step $($env:RHUN_SX_STEP)" }
$work = $env:RHUN_SX_WORK
if (-not ($work -like '*rhun-submit-*') -or -not (Test-Path -LiteralPath (Join-Path $work 'pins'))) { $work = $null; Fail 'no prepared submission' }
$full = ([IO.File]::ReadAllText((Join-Path $work 'full'), $utf8)).Trim()
$tag = ([IO.File]::ReadAllText((Join-Path $work 'tag'), $utf8)).Trim()
$category = $env:RHUN_SX_CATEGORY
$keywords = $env:RHUN_SX_KEYWORDS
$maintainer = $env:RHUN_SX_MAINTAINER
if (@('languages', 'formatters', 'themes', 'testing', 'debugging', 'tools', 'packs', 'other') -cnotcontains $category) {
    Fail 'the category is one of languages formatters themes testing debugging tools packs other'
}
if ($keywords -cmatch '[^a-z0-9 ._+#-]') { Fail 'keywords are lowercase words' }
if ($maintainer -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { Fail 'the maintainer is a GitHub user' }
$entry = "# rhun-editor/extensions: $full.ini`ncategory = $category`n"
if ($keywords) { $entry += "keywords = $keywords`n" }
$entry += "maintainer = $maintainer`n"
$old = Join-Path $work 'old'
$existing = Test-Path -LiteralPath $old
if ($existing) {
    $was = [IO.File]::ReadAllText($old, $utf8)
    foreach ($k in 'featured', 'rhun') {
        $v = Key $was $k
        if ($v -match '^[0-9A-Za-z._-]+$') { $entry += "$k = $v`n" }
    }
}
$entry += "# the reviewed release; a new version is a new pull request`n"
$entry += [IO.File]::ReadAllText((Join-Path $work 'pins'), $utf8)
[IO.File]::WriteAllText((Join-Path $work 'entry.ini'), $entry, $utf8)
foreach ($line in ($entry.TrimEnd("`n") -split "`n")) { Write-Output "say $line" }
if ($env:RHUN_SX_HOW -eq 'gh') {
    $login = (Gh api user --jq .login).Trim()
    if ($LASTEXITCODE -ne 0 -or $login -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { Fail "gh is not logged in: $login" }
    Step 1 4 "Forking rhun-editor/extensions as $login/extensions"
    $parent = (Gh api "repos/$login/extensions" --jq .parent.full_name).Trim()
    if ($LASTEXITCODE -eq 0) {
        if ($parent -ne 'rhun-editor/extensions') { Fail "$login/extensions is there and is not a fork of rhun-editor/extensions" }
    } else {
        $out = Gh repo fork rhun-editor/extensions --clone=false --default-branch-only
        if ($LASTEXITCODE -ne 0) { Fail "gh could not fork rhun-editor/extensions: $out" }
    }
    $branch = 'submit-' + $full.Replace('/', '-') + "-$tag"
    Step 2 4 "Making the branch $branch"
    Gh api -X POST "repos/$login/extensions/merge-upstream" -f branch=main | Out-Null
    $sha = ''
    for ($i = 0; $i -lt 10; $i++) {
        $sha = (Gh api "repos/$login/extensions/git/ref/heads/main" --jq .object.sha).Trim()
        if ($LASTEXITCODE -eq 0 -and $sha) { break }
        $sha = ''
        Start-Sleep -Seconds 3
    }
    if (-not $sha) { Fail "the fork $login/extensions has no main branch yet; try again in a minute" }
    $out = Gh api -X POST "repos/$login/extensions/git/refs" -f "ref=refs/heads/$branch" -f "sha=$sha"
    if ($LASTEXITCODE -ne 0 -and $out -notmatch 'already exists') { Fail "gh could not make the branch ${branch}: $out" }
    Step 3 4 "Putting $full.ini on it"
    $was = (Gh api "repos/$login/extensions/contents/$full.ini?ref=$branch" --jq .sha).Trim()
    if ($LASTEXITCODE -ne 0) { $was = '' }
    $content = [Convert]::ToBase64String($utf8.GetBytes($entry))
    $put = @('api', '-X', 'PUT', "repos/$login/extensions/contents/$full.ini", '-f', "message=$full $tag", '-f', "content=$content", '-f', "branch=$branch")
    if ($was) { $put += @('-f', "sha=$was") }
    $out = Gh @put
    if ($LASTEXITCODE -ne 0) { Fail "gh could not put $full.ini on ${branch}: $out" }
    Step 4 4 'Opening the pull request'
    $commit = if ($entry -match '(?m)^commit = ([0-9a-f]+)') { $Matches[1] } else { '' }
    $body = "Release: https://github.com/$full/releases/tag/$tag`n`nThe index's checks (.github/workflows/check.yml) run on it:`n" +
        "- ``go run ./tools/genindex -check``: the pinned digests against the release's sha256sums.txt, one archive downloaded and its manifest's owner, name and version, the 64 MB limit, no links or devices`n" +
        "- ``rhun-ext-check`` on the Linux build`n" +
        "- ``gh attestation verify`` of the archive against commit $commit and $full's .github/workflows/release.yml`n" +
        "- a review of the source since the previously pinned commit`n`nMade by rhun submit-extension."
    $out = Gh pr create -R rhun-editor/extensions --base main --head "${login}:$branch" --title "$full $tag" --body $body
    if ($LASTEXITCODE -ne 0) { Fail "gh could not open the pull request: $out" }
    $m = [regex]::Matches($out, 'https://\S*/pull/[0-9]+')
    if ($m.Count -gt 0) { Write-Output "pr $($m[$m.Count - 1].Value)" } else { Write-Output "pr $($out.Trim())" }
} elseif ($env:RHUN_SX_HOW -eq 'browser') {
    if ($existing) {
        Write-Output 'edit yes'
        Write-Output "url https://github.com/rhun-editor/extensions/edit/main/$full.ini"
    } else {
        Write-Output "url https://github.com/rhun-editor/extensions/new/main?filename=$full.ini&value=$([Uri]::EscapeDataString($entry))"
    }
} else { Fail 'submit with gh or the browser' }
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
$work = $null
Write-Output 'ok'
