# Install or remove rhun for the current Windows user. Close rhun before updating.
[CmdletBinding()]
param(
    [string]$Version,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\rhun'),
    [string]$ReleasesUrl = 'https://github.com/vshvedov/rhun/releases',
    [switch]$NoModifyPath,
    [switch]$NoShortcut,
    [switch]$Uninstall,
    # Internal updater modes. Preparation never changes a running installation.
    [switch]$PrepareUpdate,
    [switch]$ApplyUpdate,
    [switch]$DiscardUpdate,
    [string]$UpdateStage,
    [int]$WaitPid
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

function File-Sha256([string]$Path) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
    } finally { $hasher.Dispose() }
}

# Removes a folder without following links: a junction is removed, never its target.
function Remove-Folder([string]$Path) { [IO.Directory]::Delete($Path, $true) }

# Staged updates whose editor is gone (it quit or crashed before restarting, or its process ID now
# belongs to another program), and interrupted downloads and swaps older than an hour.
function Remove-StaleUpdates([string]$Parent) {
    $hourAgo = [DateTime]::UtcNow.AddHours(-1)
    foreach ($dir in @(Get-ChildItem -LiteralPath $Parent -Directory -Force -Filter '.rhun-update-*')) {
        if ($dir.Name -notmatch '^\.rhun-update-(\d{1,9})$') { continue }
        $process = Get-Process -Id ([int]$Matches[1]) -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -match '^rhun(\.com)?$') {
            # A running editor's pending update stays, unless the folder is older than the
            # process: then the editor that staged it is gone and its ID was reused.
            $started = $null
            try { $started = $process.StartTime.ToUniversalTime() } catch { }
            if (-not $started -or $started -le $dir.CreationTimeUtc) { continue }
        }
        Remove-Folder $dir.FullName
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $Parent -Directory -Force) +
                     @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Force -Filter 'rhun-download-*')) {
        if ($dir.Name -match '^(\.rhun-stage-|\.rhun-old-|rhun-download-)[0-9a-f]{32}$' -and $dir.LastWriteTimeUtc -lt $hourAgo) {
            Remove-Folder $dir.FullName
        }
    }
}

if ($PrepareUpdate -or $ApplyUpdate -or $DiscardUpdate) {
    $modes = @($PrepareUpdate, $ApplyUpdate, $DiscardUpdate | Where-Object { $_ }).Count
    if ($Uninstall -or $modes -ne 1 -or -not $UpdateStage -or $WaitPid -le 0) { throw 'Invalid update arguments.' }
    $expectedStage = Join-Path (Split-Path -Parent $InstallDir) ('.rhun-update-' + $WaitPid)
    $UpdateStage = [IO.Path]::GetFullPath($UpdateStage).TrimEnd('\', '/')
    if ($UpdateStage -ine $expectedStage) { throw 'Invalid update staging directory.' }
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'rhun.exe') -PathType Leaf)) {
        throw 'The running installation was not found.'
    }
}

if ($DiscardUpdate) {
    # The editor quit without restarting: its staged download goes once it has exited.
    $parentProcess = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
    if ($parentProcess) { [void]$parentProcess.WaitForExit(60000) }
    if (Test-Path -LiteralPath $UpdateStage) { Remove-Folder $UpdateStage }
    return
}

if ($ApplyUpdate) {
    $receipt = Get-Content -LiteralPath (Join-Path $UpdateStage 'update.json') -Raw | ConvertFrom-Json
    if ($receipt.target -ine $InstallDir -or $receipt.version -cne $Version) { throw 'Invalid staged update.' }
    $files = @('rhun.exe', 'rhun.com', 'LICENSE', 'install.ps1')
    foreach ($name in $files) {
        $destination = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $destination) {
            $item = Get-Item -LiteralPath $destination -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'The update destination contains a directory or link in place of an application file.'
            }
        }
        $actual = File-Sha256 (Join-Path $UpdateStage $name)
        if ($actual -ine $receipt.hashes.$name) { throw 'The staged update checksum does not match.' }
    }
    $parentProcess = Get-Process -Id $WaitPid -ErrorAction SilentlyContinue
    if ($parentProcess -and -not $parentProcess.WaitForExit(60000)) { throw 'The editor did not close.' }
    # Check every binary before changing any files. Another editor instance may still own them.
    foreach ($name in @('rhun.exe', 'rhun.com')) {
        $path = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $path) {
            $probe = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
            $probe.Dispose()
        }
    }
    $backupDir = Join-Path $UpdateStage 'backup'
    New-Item -ItemType Directory -Path $backupDir | Out-Null
    $changed = @()
    try {
        foreach ($name in $files) {
            $destination = Join-Path $InstallDir $name
            if (Test-Path -LiteralPath $destination) {
                Move-Item -LiteralPath $destination -Destination (Join-Path $backupDir $name)
            }
            $changed += $name
            Move-Item -LiteralPath (Join-Path $UpdateStage $name) -Destination $destination
        }
        $marker = Join-Path $InstallDir '.rhun-install'
        if (Test-Path -LiteralPath $marker) { [IO.File]::WriteAllText($marker, "rhun $Version`n") }
    } catch {
        foreach ($name in $changed) {
            $destination = Join-Path $InstallDir $name
            if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
            $old = Join-Path $backupDir $name
            if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination $destination }
        }
        throw
    }
    Remove-Item -LiteralPath $UpdateStage -Recurse -Force
    return
}

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
if (-not $PrepareUpdate -and (Test-Path -LiteralPath $InstallDir)) {
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
if (-not $PrepareUpdate -and $running.Count -gt 0) { throw 'Close rhun before updating or uninstalling it.' }
# Process metadata is not always available. Loaded PE files cannot be opened for writing.
foreach ($name in @('rhun.exe', 'rhun.com') | Where-Object { -not $PrepareUpdate }) {
    $file = Join-Path $InstallDir $name
    if (Test-Path -LiteralPath $file) {
        try {
            $probe = [IO.File]::Open($file, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $probe.Dispose()
        } catch {
            throw 'Close rhun before updating or uninstalling it, and check that its files are writable.'
        }
    }
}

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
    $actual = File-Sha256 $archive
    if ($actual -ine $matchesFound[0].Groups[1].Value) { throw 'The archive checksum does not match.' }
    $parent = Split-Path -Parent $InstallDir
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    if ($PrepareUpdate) { Remove-StaleUpdates $parent }
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
    if ($PrepareUpdate) {
        $hashes = @{}
        foreach ($name in @('rhun.exe', 'rhun.com', 'LICENSE', 'install.ps1')) {
            $hashes[$name] = File-Sha256 (Join-Path $stage $name)
        }
        @{ target = $InstallDir; version = $Version; hashes = $hashes } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $stage 'update.json') -Encoding UTF8
        # Stale stages are gone (Remove-StaleUpdates); one that appeared since is not ours to remove.
        if (Test-Path -LiteralPath $UpdateStage) { throw 'An update is already staged for this editor.' }
        Move-Item -LiteralPath $stage -Destination $UpdateStage
        $stage = $null
        Write-Output 'The update is ready to install when rhun restarts.'
        return
    }
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
