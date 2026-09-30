# The normal LLVM installer omits llvm-mc. Use the complete, pinned upstream archive.
[CmdletBinding()]
param([string]$Destination = (Join-Path $PSScriptRoot '..\build\llvm'))
$ErrorActionPreference = 'Stop'
$Destination = [IO.Path]::GetFullPath($Destination)
$package = 'clang+llvm-23.1.2-x86_64-pc-windows-msvc'
$checksum = '8fb91cdc44fcbbdcf6b3ffd0a1f9859abd14a3c3aae4423c2b6d4a4f90bf0095'
$bin = Join-Path $Destination 'bin'
$required = @('llvm-mc.exe', 'llvm-dlltool.exe', 'llvm-rc.exe', 'lld-link.exe')
$missing = @($required | Where-Object { -not (Test-Path (Join-Path $bin $_)) })
if ($missing.Count -gt 0) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $archive = Join-Path $Destination ($package + '.tar.xz')
    try {
        & curl.exe --fail --location --retry 3 --output $archive "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.2/$package.tar.xz"
        if ($LASTEXITCODE -ne 0) { throw 'Could not download the LLVM tools.' }
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $checksum) {
            throw 'The LLVM archive checksum does not match.'
        }
        & tar.exe -xf $archive -C $Destination --strip-components=1 "$package/bin"
        if ($LASTEXITCODE -ne 0) { throw 'Could not extract the LLVM tools.' }
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}
foreach ($name in $required) {
    if (-not (Test-Path (Join-Path $bin $name))) { throw "The LLVM archive is missing $name." }
}
$env:LLVM_BIN = $bin
$env:Path = "$bin;$env:Path"
if ($env:GITHUB_PATH) { $bin | Out-File -FilePath $env:GITHUB_PATH -Append }
Write-Output "LLVM tools: $bin"
