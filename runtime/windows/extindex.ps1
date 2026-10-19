# Fetching the rhun extensions index on Windows, for src/app/extindexfile.s: index.ini from
# rhun-editor/extensions' latest release, checked against its sha256sums.txt, with the curl.exe
# Windows 10 1803 and later ship. The inputs come in RHUN_EX_BASE and RHUN_EX_OUT (the cache file);
# the last output line is "ok", or why it failed.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$base = $env:RHUN_EX_BASE
$out = $env:RHUN_EX_OUT
$curl = Join-Path (Join-Path $env:SystemRoot 'System32') 'curl.exe'
if (-not (Test-Path -LiteralPath $curl)) { Write-Output 'needs curl.exe (it comes with Windows 10 1803 and later)'; exit 1 }
$proto = @()
if ($base -like 'https:*') { $proto = @('--proto', '=https', '--proto-redir', '=https') }
$tmp = "$out.tmp"
function Fail([string]$why) {
    Remove-Item -LiteralPath "$tmp.ini", "$tmp.sums" -Force -ErrorAction SilentlyContinue
    Write-Output $why
    exit 1
}
try { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) -ErrorAction Stop | Out-Null } catch { Fail 'cannot create the state folder' }
$url = "$base/rhun-editor/extensions/releases/latest/download"
& $curl -fsL @proto --max-time 60 --max-filesize 1048576 -o "$tmp.ini" "$url/index.ini" 2>$null
if ($LASTEXITCODE -ne 0) { Fail 'the index could not be downloaded' }
& $curl -fsL @proto --max-time 60 -o "$tmp.sums" "$url/sha256sums.txt" 2>$null
if ($LASTEXITCODE -ne 0) { Fail 'the index has no sha256sums.txt' }
$want = ''
foreach ($line in Get-Content -LiteralPath "$tmp.sums") {
    $fields = $line.Trim() -split '\s+', 2
    if ($fields.Count -eq 2 -and ($fields[1] -eq 'index.ini' -or $fields[1] -eq '*index.ini')) { $want = $fields[0].ToLowerInvariant() }
}
$have = ''
try {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead("$tmp.ini")
    try { $have = -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) } finally { $stream.Close() }
} catch { Fail 'the index cannot be read' }
if (-not $want -or $want -ne $have) { Fail 'the index does not match its checksum' }
try { Move-Item -LiteralPath "$tmp.ini" -Destination $out -Force -ErrorAction Stop } catch { Fail 'the index cannot be kept' }
Remove-Item -LiteralPath "$tmp.sums" -Force -ErrorAction SilentlyContinue
Write-Output 'ok'
