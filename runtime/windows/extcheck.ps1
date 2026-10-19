# The extension update check on Windows, for src/app/extupdate.s: GitHub's /releases/latest
# redirect for each name, with the curl.exe Windows 10 1803 and later ship. The inputs come in
# RHUN_EC_BASE and RHUN_EC_REPOS (owner/name, space separated), never through the command line.
# Each name gets a line, "owner/name TAG" or "owner/name - why".
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$base = $env:RHUN_EC_BASE
$curl = Join-Path (Join-Path $env:SystemRoot 'System32') 'curl.exe'
if (-not (Test-Path -LiteralPath $curl)) { Write-Output 'needs curl.exe (it comes with Windows 10 1803 and later)'; exit 1 }
$proto = @()
if ($base -like 'https:*') { $proto = @('--proto', '=https', '--proto-redir', '=https') }
foreach ($r in ($env:RHUN_EC_REPOS -split ' ')) {
    if (-not $r) { continue }
    $out = & $curl -sS @proto -o NUL --max-time 20 -w '%{http_code} %{redirect_url}' "$base/$r/releases/latest" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Output "$r - no answer"; continue }
    $code, $loc = "$out" -split ' ', 2
    if ($code -eq '404') { Write-Output "$r - not found"; continue }
    if ($loc -match '/releases/tag/([^/]+)$') { Write-Output "$r $($Matches[1])" }
    elseif ($loc -match '^(.*)/releases/latest$') {
        $moved = $Matches[1]
        if ($moved.StartsWith("$base/")) { $moved = $moved.Substring($base.Length + 1) }
        Write-Output "$r - moved to $moved"
    }
    else { Write-Output "$r - no release" }
}
