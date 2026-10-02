# The installer scriptblock is embedded by the build. Parameters are environment data,
# never interpolated into PowerShell source or downloaded as executable script text.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$exe = [IO.Path]::GetFullPath($env:RHUN_UP_EXE)
$directory = Split-Path -Parent $exe
$stage = Join-Path (Split-Path -Parent $directory) ('.rhun-update-' + $env:RHUN_UP_PID)
$options = @{
    InstallDir = $directory
    Version = $env:RHUN_UP_VERSION
    ReleasesUrl = $env:RHUN_UP_URL
    UpdateStage = $stage
    WaitPid = [int]$env:RHUN_UP_PID
    NoModifyPath = $true
    NoShortcut = $true
}
try {
    if ($env:RHUN_UP_ACTION -eq 'prepare') {
        & $installer @options -PrepareUpdate
    } elseif ($env:RHUN_UP_ACTION -eq 'apply') {
        & $installer @options -ApplyUpdate
        # Start-Process joins ArgumentList as command text. A Windows project directory
        # cannot contain quotes; double a trailing backslash before the closing quote.
        $project = $env:RHUN_UP_PROJECT.Replace('/', '\').TrimEnd('\') + '\'
        $argument = '"' + $project + '\"'
        Start-Process -FilePath $exe -ArgumentList $argument -WorkingDirectory $env:USERPROFILE
    } else { throw 'Invalid update action.' }
} catch {
    if ($env:RHUN_UP_ACTION -eq 'apply') {
        # The editor has exited. Keep the failed stage and show a visible recovery message.
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show("The update could not be installed. $($_.Exception.Message)`nThe previous installation and the update files are in $directory and $stage.", 'rhun update') | Out-Null
        if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe }
    }
    Write-Output $_.Exception.Message
    exit 1
}
