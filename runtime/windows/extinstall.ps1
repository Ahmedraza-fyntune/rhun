# Installing an extension on Windows, for src/app/extinstall.s: the steps of its POSIX job, with the
# curl.exe and tar.exe Windows 10 1803 and later ship. The inputs come in RHUN_EI_OWNER,
# RHUN_EI_NAME, RHUN_EI_TARGET, RHUN_EI_ROOT, RHUN_EI_BASE, RHUN_EI_TAG (a tag, or "latest"),
# RHUN_EI_WANT (the index's digest, or "-"), RHUN_EI_FILE (a local archive or folder, or "-") and
# RHUN_EI_KIND (github, archive or folder), never through the command line; the last output line
# is "ok SHA256 TAG DIR" (DIR the unpacked extension's folder's parent), or why it failed.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
# native programs report on their own error stream; Stop would turn that into an exception
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
# started from PowerShell 7 (a CI shell, a terminal), Windows PowerShell inherits 7's module path
# and cannot load its own modules; only the machine's own module folders, then
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$owner = $env:RHUN_EI_OWNER
$name = $env:RHUN_EI_NAME
$target = $env:RHUN_EI_TARGET
$root = $env:RHUN_EI_ROOT
$base = $env:RHUN_EI_BASE
$tag = $env:RHUN_EI_TAG
$want = $env:RHUN_EI_WANT
$file = $env:RHUN_EI_FILE
$kind = $env:RHUN_EI_KIND
$tmp = $null
function Fail([string]$why) {
    if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Output $why
    exit 1
}
function Sums([string]$path, [string]$asset) {
    foreach ($line in Get-Content -LiteralPath $path) {
        $fields = $line.Trim() -split '\s+', 2
        if ($fields.Count -eq 2 -and ($fields[1] -eq $asset -or $fields[1] -eq "*$asset")) { return $fields[0].ToLowerInvariant() }
    }
    return ''
}
try { New-Item -ItemType Directory -Force -Path $root -ErrorAction Stop | Out-Null } catch { Fail "cannot create $root" }
$folder = Join-Path $root ('.install-' + [IO.Path]::GetRandomFileName().Replace('.', ''))
try { New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null } catch { Fail "cannot create a folder in $root" }
$tmp = $folder
$system = Join-Path $env:SystemRoot 'System32'
$curl = Join-Path $system 'curl.exe'
$tar = Join-Path $system 'tar.exe'
if (-not (Test-Path -LiteralPath $tar)) { Fail 'Windows has no tar.exe (it comes with Windows 10 1803 and later)' }
# https stays https through redirects
$proto = @()
if ($base -like 'https:*') { $proto = @('--proto', '=https', '--proto-redir', '=https') }
$archive = Join-Path $tmp 'a.tgz'
$what = 'archive'
$wantsum = ''
if ($kind -eq 'github') {
    if (-not (Test-Path -LiteralPath $curl)) { Fail 'Windows has no curl.exe (it comes with Windows 10 1803 and later)' }
    if ($tag -eq 'latest' -and $base -like 'file:*') {
        $url = "$base/$owner/$name/releases/latest/download"
    } else {
        if ($tag -eq 'latest') {
            $loc = & $curl -fsS @proto -o NUL --max-time 20 -w '%{redirect_url}' "$base/$owner/$name/releases/latest" 2>$null
            if ($LASTEXITCODE -ne 0) { Fail "no answer from $base" }
            if ("$loc" -match '/releases/tag/([^/]+)$') { $tag = $Matches[1] } else { Fail "$owner/$name has no release" }
            if ($tag -notmatch '^[0-9A-Za-z._-]+$') { Fail 'the latest release has an unusable tag' }
        }
        $url = "$base/$owner/$name/releases/download/$tag"
    }
    $asset = "$name-$target.tar.gz"
    & $curl -fsL @proto --max-time 120 --max-filesize 67108864 -o $archive "$url/$asset" 2>$null
    if ($LASTEXITCODE -ne 0) {
        if ($tag -eq 'latest') { Fail "no release of $owner/$name for $target" }
        Fail "no release $tag of $owner/$name for $target"
    }
    $sums = Join-Path $tmp 'sums'
    & $curl -fsL @proto --max-time 120 -o $sums "$url/sha256sums.txt" 2>$null
    if ($LASTEXITCODE -ne 0) { Fail 'the release has no sha256sums.txt' }
    $wantsum = Sums $sums $asset
    if (-not $wantsum) { Fail "the release's sha256sums.txt does not list $asset" }
} elseif ($kind -eq 'archive') {
    $asset = Split-Path -Leaf $file
    try { Copy-Item -LiteralPath $file -Destination $archive -ErrorAction Stop } catch { Fail "cannot read $file" }
    $beside = Join-Path (Split-Path -Parent $file) 'sha256sums.txt'
    if (Test-Path -LiteralPath $beside -PathType Leaf) {
        $wantsum = Sums $beside $asset
        if (-not $wantsum) { Fail "the sha256sums.txt beside it does not list $asset" }
    }
} elseif ($kind -eq 'folder') {
    $what = 'folder'
    if (-not (Test-Path -LiteralPath (Join-Path $file 'extension.ini') -PathType Leaf)) { Fail 'the folder has no extension.ini' }
    & $tar -czf $archive -C $file . 2>$null
    if ($LASTEXITCODE -ne 0) { Fail 'the folder cannot be read' }
} else { Fail 'unknown source' }
# .NET directly: no module to load
$have = ''
try {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($archive)
    try { $have = -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) } finally { $stream.Close() }
} catch { Fail "the $what cannot be read" }
if ($wantsum -and $wantsum -ne $have) { Fail 'the download does not match its checksum' }
if ($want -ne '-' -and $want -ne $have) { Fail 'the download is not the version the rhun extensions index reviewed' }
# plain files and folders only: a link, hard link or device in the listing ends it; at most 64 MB
$listing = & $tar -tvzf $archive 2>$null
if ($LASTEXITCODE -ne 0) { Fail "the $what cannot be read" }
$size = [double]0
foreach ($line in $listing) {
    if ($line -notmatch '^[-d]') { Fail "the $what holds links or devices" }
    $fields = $line.Trim() -split '\s+'
    if ($fields.Count -gt 4) {
        $field = if ($fields[1] -like '*/*') { $fields[2] } else { $fields[4] }
        $n = 0.0
        if ([double]::TryParse($field, [ref]$n)) { $size += $n }
    }
}
if ($size -gt 67108864) { Fail "the $what unpacks to more than 64 MB" }
$entries = & $tar -tzf $archive 2>$null
foreach ($entry in $entries) {
    if ($entry -match '^([/\\]|[A-Za-z]:)' -or $entry -match '(^|[/\\])\.\.([/\\]|$)') {
        Fail "the $what reaches outside itself"
    }
}
$unpacked = Join-Path $tmp 'x'
New-Item -ItemType Directory -Path $unpacked | Out-Null
& $tar -xzf $archive -C $unpacked 2>$null
if ($LASTEXITCODE -ne 0) { Fail "the $what cannot be unpacked" }
if (-not (Test-Path -LiteralPath (Join-Path $unpacked 'extension.ini') -PathType Leaf)) { Fail "the $what has no extension.ini" }
Remove-Item -LiteralPath $archive -Force
Remove-Item -LiteralPath (Join-Path $tmp 'sums') -Force -ErrorAction SilentlyContinue
Write-Output "ok $have $tag $tmp"
