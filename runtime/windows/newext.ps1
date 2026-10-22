# A new extension on Windows, for src/app/newext.s: the steps of runtime/jobs/newext.sh, with the
# curl.exe and tar.exe Windows 10 1803 and later ship, and extinstall.ps1's rules for an archive
# (plain files and folders only, nothing outside itself, at most 64 MB). The inputs come in
# RHUN_NE_NAME, RHUN_NE_OWNER, RHUN_NE_LANG (rust or go), RHUN_NE_SKILLS (yes or no), RHUN_NE_DIR,
# RHUN_NE_BASE and RHUN_NE_UI (cli: a report for the terminal; gui: "tmp PATH", "step N M TEXT",
# then "ok DIR" or "fail WHY"), never through the command line. PowerShell's names ignore case:
# $lang and $LangName are two variables only because they are spelled apart.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$name = $env:RHUN_NE_NAME
$owner = $env:RHUN_NE_OWNER
$lang = $env:RHUN_NE_LANG
$skills = $env:RHUN_NE_SKILLS
$dir = $env:RHUN_NE_DIR
$base = $env:RHUN_NE_BASE
$ui = $env:RHUN_NE_UI
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = $null
function Fail([string]$why) {
    if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    if ($ui -eq 'gui') { Write-Output "fail $why" } else { [Console]::Error.WriteLine("rhun new-extension: $why") }
    exit 1
}
function Step([int]$n, [string]$text) {
    if ($ui -eq 'gui') { Write-Output "step $n $script:total $text" } else { Write-Output $text }
}
if ($lang -eq 'rust') { $LangName = 'Rust' } elseif ($lang -eq 'go') { $LangName = 'Go' } else { Fail "the language is rust or go, not $lang" }
if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$') { Fail "the name is lowercase letters, digits and dashes: $name" }
if ($lang -eq 'rust' -and $name -match '^[0-9]') { Fail "a Rust package name starts with a letter: $name" }
if ($owner -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { Fail "the owner is a GitHub user or organization: $owner" }
$dir = [IO.Path]::GetFullPath($dir)
if (Test-Path -LiteralPath $dir) {
    $item = Get-Item -LiteralPath $dir -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Fail "$dir is there and is not a folder" }
    if (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1) { Fail "$dir is not empty" }
}
$parent = Split-Path -Parent $dir
try { New-Item -ItemType Directory -Force -Path $parent -ErrorAction Stop | Out-Null } catch { Fail "cannot create $parent" }
$folder = Join-Path $parent ('.rhun-new-' + [IO.Path]::GetRandomFileName().Replace('.', ''))
try { New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null } catch { Fail "cannot create a folder in $parent" }
$tmp = $folder
if ($ui -eq 'gui') { Write-Output "tmp $tmp" }
$script:total = 3
if ($skills -eq 'yes') { $script:total = 4 }
$system = Join-Path $env:SystemRoot 'System32'
$curl = Join-Path $system 'curl.exe'
$tar = Join-Path $system 'tar.exe'
if (-not (Test-Path -LiteralPath $curl)) { Fail 'Windows has no curl.exe (it comes with Windows 10 1803 and later)' }
if (-not (Test-Path -LiteralPath $tar)) { Fail 'Windows has no tar.exe (it comes with Windows 10 1803 and later)' }
$proto = @()
if ($base -like 'https:*') { $proto = @('--proto', '=https', '--proto-redir', '=https') }
function Fetch([string]$url, [string]$file) {
    & $curl -fsL @proto --max-time 120 --max-filesize 67108864 -o $file $url 2>$null
    return ($LASTEXITCODE -eq 0)
}
function Unpack([string]$archive, [string]$dest, [string]$what) {
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
    foreach ($entry in (& $tar -tzf $archive 2>$null)) {
        if ($entry -match '^([/\\]|[A-Za-z]:)' -or $entry -match '(^|[/\\])\.\.([/\\]|$)') { Fail "the $what reaches outside itself" }
    }
    New-Item -ItemType Directory -Path $dest | Out-Null
    & $tar -xzf $archive -C $dest 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "the $what cannot be unpacked" }
    $entries = @(Get-ChildItem -LiteralPath $dest -Force)
    if ($entries.Count -ne 1 -or -not $entries[0].PSIsContainer) { Fail "the $what does not hold one folder" }
    return $entries[0].FullName
}
# Edit FILE { text -> text }: in place, UTF-8 without a BOM, line endings as they were
function Edit([string]$file, [scriptblock]$change) {
    $path = Join-Path $src $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    try {
        $text = [IO.File]::ReadAllText($path, $utf8)
        [IO.File]::WriteAllText($path, (& $change $text), $utf8)
    } catch { Fail "cannot change $file" }
}

Step 1 "Downloading the $LangName template"
$url = "$base/rhun-editor/template-$lang/tar.gz/refs/heads/main"
$archive = Join-Path $tmp 't.tgz'
if (-not (Fetch $url $archive)) { Fail "could not download the $LangName template ($url)" }
$src = Unpack $archive (Join-Path $tmp 't') 'template'
Remove-Item -LiteralPath $archive -Force
if (-not (Test-Path -LiteralPath (Join-Path $src 'extension.ini') -PathType Leaf)) { Fail 'the template has no extension.ini' }

Step 2 "Naming it $owner/$name"
$manifest = [IO.File]::ReadAllText((Join-Path $src 'extension.ini'), $utf8)
$old = if ($manifest -match '(?m)^name *= *([^\r\n]*)') { $Matches[1].Trim() } else { '' }
$oldowner = if ($manifest -match '(?m)^owner *= *([^\r\n]*)') { $Matches[1].Trim() } else { '' }
if ($old -cnotmatch '^[a-z0-9][a-z0-9-]*$') { Fail "the template's manifest has no usable name" }
if ($oldowner -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { Fail "the template's manifest has no usable owner" }
$title = (($name -split '-') | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ' '
$o = [regex]::Escape($old)
$oo = [regex]::Escape($oldowner)
Edit 'extension.ini' {
    param($t)
    $t = $t -replace '(?m)^name *=[^\r\n]*', "name = $name"
    $t = $t -replace '(?m)^owner *=[^\r\n]*', "owner = $owner"
    $t = $t -replace '(?m)^title *=[^\r\n]*', "title = $title"
    $t -replace "(?m)^(run[.a-z0-9_-]* *=[^\r\n]*/)$o([.-])", "`${1}$name`${2}"
}
Edit 'go.mod' { param($t) $t -replace '(?m)^module [^\r\n]*', "module github.com/$owner/$name" }
Edit 'Cargo.toml' { param($t) $t -replace "(?m)^name = `"$o`"", "name = `"$name`"" }
Edit 'Cargo.lock' { param($t) $t -replace "(?m)^name = `"$o`"", "name = `"$name`"" }
$tests = Join-Path $src 'tests'
if (Test-Path -LiteralPath $tests -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $tests -File) {
        Edit ('tests/' + $f.Name) {
            param($t)
            $t = $t.Replace("$oldowner/$old", "$owner/$name").Replace("$oldowner\/$old", "$owner\/$name")
            $t = $t -replace "([ =,])$o\.", "`${1}$name."
            $t = $t -replace "(?m)^wait-ext $o ", "wait-ext $name "
            $t -replace "(?m)^ext=$o ", "ext=$name "
        }
    }
}
Edit 'README.md' { param($t) ([regex]'^# [^\r\n]*').Replace($t, "# $title", 1) }

if ($skills -eq 'yes') {
    Step 3 'Adding the agent skills'
    $url = "$base/rhun-editor/skills/tar.gz/refs/heads/main"
    $archive = Join-Path $tmp 's.tgz'
    if (-not (Fetch $url $archive)) { Fail "could not download the agent skills ($url)" }
    $sk = Unpack $archive (Join-Path $tmp 's') 'skills archive'
    Remove-Item -LiteralPath $archive -Force
    $sk = Join-Path $sk 'plugins/rhun/skills/rhun-extension'
    if (-not (Test-Path -LiteralPath (Join-Path $sk 'SKILL.md') -PathType Leaf)) { Fail 'the skills archive has no plugins/rhun/skills/rhun-extension' }
    # Claude Code reads .claude/skills, Codex .agents/skills (and .codex/skills), from the project
    foreach ($d in '.claude/skills', '.agents/skills') {
        $to = Join-Path $src $d
        try {
            Remove-Item -LiteralPath (Join-Path $to 'rhun-extension') -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $to -ErrorAction Stop | Out-Null
            Copy-Item -LiteralPath $sk -Destination $to -Recurse -ErrorAction Stop
        } catch { Fail "cannot copy the skills to $d" }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $src 'AGENTS.md'))) {
        [IO.File]::WriteAllText((Join-Path $src 'AGENTS.md'), "# Working on this rhun extension`n`nThis is an extension for the rhun editor. Read the rhun-extension skill first:`n``.agents/skills/rhun-extension/SKILL.md`` (the same skill as ``.claude/skills/rhun-extension``).`nThe protocol: https://rhun.app/extensions/v1/`n", $utf8)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $src 'CLAUDE.md'))) {
        [IO.File]::WriteAllText((Join-Path $src 'CLAUDE.md'), "@AGENTS.md`n", $utf8)
    }
}

Step $script:total "Creating $dir"
try {
    if (Test-Path -LiteralPath $dir) {
        # the empty folder stays (Windows refuses to remove a process's current folder, such as
        # rhun.com's for "rhun new-extension ."): the template's files move into it
        Get-ChildItem -LiteralPath $src -Force | Move-Item -Destination $dir -ErrorAction Stop
    } else {
        Move-Item -LiteralPath $src -Destination $dir -ErrorAction Stop
    }
} catch { Fail "cannot create $dir" }
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
$tmp = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    & git init -q $dir 2>$null | Out-Null
}
if ($ui -eq 'gui') { Write-Output "ok $dir"; exit 0 }
Write-Output ''
Write-Output "Created $owner/$name ($LangName) in $dir"
Write-Output ''
Write-Output 'Next:'
Write-Output "  cd $dir"
if ($lang -eq 'go') {
    Write-Output "  go build -o bin/$name-windows-x64.exe .      # the program extension.ini runs"
} else {
    Write-Output "  cargo build --release; mkdir bin; copy target\release\$name.exe bin\$name-windows-x64.exe"
}
Write-Output '  then in rhun: Link Extension Folder (development) with that folder, and Restart after each build'
