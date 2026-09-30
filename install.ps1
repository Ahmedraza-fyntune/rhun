# Install or remove rhun for the current Windows user. Close rhun before updating.
[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\rhun'),
    [string]$ReleasesUrl = 'https://github.com/vshvedov/rhun/releases',
    [switch]$NoModifyPath,
    [switch]$NoShortcut,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'rhun requires 64-bit Windows 10 version 1809 or later.'
}
if ([Environment]::OSVersion.Version.Build -lt 17763) {
    throw 'rhun requires Windows 10 version 1809 or later.'
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\', '/')
$knownFiles = @('rhun.exe', 'rhun.com', 'LICENSE', 'install.ps1', '.rhun-install')
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'rhun.lnk'

function Update-UserPath([bool]$Remove) {
    $value = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($value -split ';' | Where-Object { $_ -ne '' })
    $matching = @($parts | Where-Object {
        [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\', '/') -ieq $InstallDir
    })
    if ($Remove) {
        $parts = @($parts | Where-Object {
            [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\', '/') -ine $InstallDir
        })
    } elseif ($matching.Count -eq 0) {
        $parts += $InstallDir
    }
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

function Read-ReleaseText([string]$Url) {
    $content = (Invoke-WebRequest -UseBasicParsing -Uri $Url).Content
    if ($content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($content) }
    return [string]$content
}

# The directory swap below owns only an existing rhun installation, never an arbitrary folder.
if (Test-Path -LiteralPath $InstallDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'rhun.exe') -PathType Leaf)) {
        throw "The destination is not a rhun installation: $InstallDir"
    }
    $unknown = @(Get-ChildItem -LiteralPath $InstallDir -Force | Where-Object {
        $_.PSIsContainer -or $_.Name -notin $knownFiles
    })
    if ($unknown.Count -gt 0) {
        throw "The installation folder contains other files. Move them before updating: $InstallDir"
    }
}
$running = @(Get-Process -Name rhun,rhun.com -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and ([IO.Path]::GetDirectoryName($_.Path) -ieq $InstallDir)
})
if ($running.Count -gt 0) { throw 'Close rhun before updating or uninstalling it.' }

if ($Uninstall) {
    if (Test-Path -LiteralPath $InstallDir) {
        foreach ($name in $knownFiles) {
            $file = Join-Path $InstallDir $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        Remove-Item -LiteralPath $InstallDir
    }
    if (-not $NoModifyPath) { Update-UserPath $true }
    if (-not $NoShortcut -and (Test-Path -LiteralPath $shortcut)) {
        Remove-Item -LiteralPath $shortcut -Force
    }
    Write-Output 'rhun was removed. Settings and saved sessions were kept.'
    return
}

$ReleasesUrl = $ReleasesUrl.TrimEnd('/')
$baseUri = [Uri]$ReleasesUrl
if ($baseUri.Scheme -ne 'https' -and -not ($baseUri.Scheme -eq 'http' -and $baseUri.IsLoopback)) {
    throw 'The release URL must use HTTPS (HTTP is allowed only for a local test server).'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('rhun-download-' + [Guid]::NewGuid().ToString('N'))
$stage = $null
$backup = $null
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    if (-not $Version) {
        $Version = (Read-ReleaseText "$ReleasesUrl/latest/download/VERSION").Trim()
    }
    if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$' -or $Version.Length -gt 31) {
        throw 'The release version is invalid.'
    }
    $asset = "rhun-$Version-windows-x86_64.zip"
    $download = "$ReleasesUrl/download/v$Version"
    $archive = Join-Path $temporary $asset
    Invoke-WebRequest -UseBasicParsing -Uri "$download/$asset" -OutFile $archive
    $checksums = Read-ReleaseText "$download/SHA256SUMS"
    $pattern = '(?m)^([0-9a-fA-F]{64})\s+\*?' + [Regex]::Escape($asset) + '\r?$'
    $matchesFound = [Regex]::Matches($checksums, $pattern)
    if ($matchesFound.Count -ne 1) { throw 'The archive checksum is missing or ambiguous.' }
    # Use .NET directly, including when Windows PowerShell inherits PowerShell 7's module path.
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($archive)
        try { $actual = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
    } finally { $hasher.Dispose() }
    if ($actual -ine $matchesFound[0].Groups[1].Value) { throw 'The archive checksum does not match.' }
    $parent = Split-Path -Parent $InstallDir
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $stage = Join-Path $parent ('.rhun-stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        # Extract only the four known files to explicit destinations, never archive-supplied paths.
        foreach ($name in @('rhun.exe', 'rhun.com', 'LICENSE', 'install.ps1')) {
            $entries = @($zip.Entries | Where-Object { $_.FullName -ceq "rhun-$Version/$name" })
            if ($entries.Count -ne 1) { throw "The archive must contain exactly one $name." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], (Join-Path $stage $name), $false)
        }
    } finally { $zip.Dispose() }
    $reported = & (Join-Path $stage 'rhun.com') --version
    if ($LASTEXITCODE -ne 0 -or $reported -cne "rhun $Version") { throw 'The staged executable has the wrong version.' }
    [IO.File]::WriteAllText((Join-Path $stage '.rhun-install'), "rhun $Version`n")
    if (Test-Path -LiteralPath $InstallDir) {
        $backup = Join-Path $parent ('.rhun-old-' + [Guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $InstallDir -Destination $backup
    }
    try {
        Move-Item -LiteralPath $stage -Destination $InstallDir
        $stage = $null
    } catch {
        if ($backup -and -not (Test-Path -LiteralPath $InstallDir)) {
            Move-Item -LiteralPath $backup -Destination $InstallDir
            $backup = $null
        }
        throw
    }
    if ($backup) { Remove-Item -LiteralPath $backup -Recurse -Force; $backup = $null }
    if (-not $NoModifyPath) { Update-UserPath $false }
    if (-not $NoShortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $link.TargetPath = Join-Path $InstallDir 'rhun.exe'
        $link.WorkingDirectory = $env:USERPROFILE
        $link.IconLocation = $link.TargetPath
        $link.Save()
    }
    Write-Output "Installed rhun $Version in $InstallDir. Open a new terminal to use the rhun command."
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    Remove-Item -LiteralPath $temporary -Recurse -Force
    # A backup surviving failed rollback is retained for recovery.
    if ($backup) { Write-Warning "The previous installation was retained at $backup" }
}
