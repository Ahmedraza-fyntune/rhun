# A remote window's agent for Windows (src/app/remote.s): the Linux release's rhun, checked against
# the release's SHA256SUMS, with the curl.exe and tar.exe Windows 10 1803 and later ship. The inputs
# come in RHUN_RD_VERSION and RHUN_RD_OUT (the file to write), and RHUN_RELEASES_URL when it is
# set, never through the command line; when it fails its last output line says why.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
# native programs report on their own error stream; Stop would turn that into an exception
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
# started from PowerShell 7, Windows PowerShell inherits 7's module path and cannot load its own
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$v = $env:RHUN_RD_VERSION
$out = $env:RHUN_RD_OUT
$base = $env:RHUN_RELEASES_URL
if (-not $base) { $base = 'https://github.com/vshvedov/rhun/releases' }
$system = Join-Path $env:SystemRoot 'System32'
$curl = Join-Path $system 'curl.exe'
$tar = Join-Path $system 'tar.exe'
if (-not (Test-Path -LiteralPath $curl)) { Write-Output 'Windows has no curl.exe (it comes with Windows 10 1803 and later)'; exit 1 }
if (-not (Test-Path -LiteralPath $tar)) { Write-Output 'Windows has no tar.exe (it comes with Windows 10 1803 and later)'; exit 1 }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rhun-remote-' + [IO.Path]::GetRandomFileName().Replace('.', ''))
try { New-Item -ItemType Directory -Path $tmp -ErrorAction Stop | Out-Null } catch { Write-Output "cannot create $tmp"; exit 1 }
function Fail([string]$why) {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output $why
    exit 1
}
$name = "rhun-$v-linux-x86_64.tar.gz"
$archive = Join-Path $tmp $name
$sums = Join-Path $tmp 'SHA256SUMS'
& $curl -fsSL --connect-timeout 10 --retry 3 -o $archive "$base/download/v$v/$name" 2>$null
if ($LASTEXITCODE -ne 0) { Fail "cannot download $name" }
& $curl -fsSL --connect-timeout 10 --retry 3 -o $sums "$base/download/v$v/SHA256SUMS" 2>$null
if ($LASTEXITCODE -ne 0) { Fail 'cannot download SHA256SUMS' }
$want = ''
foreach ($line in Get-Content -LiteralPath $sums) {
    $fields = $line.Trim() -split '\s+', 2
    if ($fields.Count -eq 2 -and ($fields[1] -eq $name -or $fields[1] -eq "*$name")) { $want = $fields[0].ToLowerInvariant() }
}
$got = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if (-not $want -or $got -ne $want) { Fail "$name does not match SHA256SUMS" }
& $tar -xzf $archive -C $tmp "rhun-$v/bin/rhun" 2>$null
if ($LASTEXITCODE -ne 0) { Fail "cannot unpack $name" }
try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) -ErrorAction Stop | Out-Null
    Move-Item -LiteralPath (Join-Path $tmp "rhun-$v/bin/rhun") -Destination $out -Force -ErrorAction Stop
} catch { Fail "cannot write $out" }
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
