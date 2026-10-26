[CmdletBinding()]
param([string]$KeilRoot = 'C:\Keil_v5')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolRoot=Join-Path $KeilRoot 'C51'
foreach($toolName in @('C51.EXE','A51.EXE','BL51.EXE','OH51.EXE')) {
    if(-not (Test-Path -LiteralPath (Join-Path $toolRoot "BIN\$toolName") -PathType Leaf)) { throw "Missing Keil C51 tool: $toolName" }
}
$startup=Join-Path $toolRoot 'LIB\STARTUP.A51'
if(-not (Test-Path -LiteralPath $startup -PathType Leaf)) { throw 'Install Keil C51 with its licensed startup template first.' }
# Older C51 tools may not handle Unicode checkout paths. Build in our own temp directory.
$temporaryBuild=Join-Path ([IO.Path]::GetTempPath()) ('counter-8051-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryBuild | Out-Null
$outputRoot=Join-Path $projectRoot '.runtime\build'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'src\main.c') -Destination (Join-Path $temporaryBuild 'main.c')
    Copy-Item -LiteralPath $startup -Destination (Join-Path $temporaryBuild 'STARTUP.A51')
    Push-Location -LiteralPath $temporaryBuild
    try {
        & (Join-Path $toolRoot 'BIN\C51.EXE') 'main.c' "INCDIR($toolRoot\INC)" 'OBJECT(main.obj)' | ForEach-Object { $_ -replace '(?i)SN:\s*\S+','SN: [REDACTED]' }
        if($LASTEXITCODE -ne 0) { throw 'C51 compilation failed.' }
        & (Join-Path $toolRoot 'BIN\A51.EXE') 'STARTUP.A51' 'OBJECT(STARTUP.obj)' | ForEach-Object { $_ -replace '(?i)SN:\s*\S+','SN: [REDACTED]' }
        if($LASTEXITCODE -ne 0) { throw 'A51 assembly failed.' }
        & (Join-Path $toolRoot 'BIN\BL51.EXE') 'main.obj,STARTUP.obj' 'TO' 'counter' | ForEach-Object { $_ -replace '(?i)SN:\s*\S+','SN: [REDACTED]' }
        if($LASTEXITCODE -ne 0) { throw 'BL51 linking failed.' }
        & (Join-Path $toolRoot 'BIN\OH51.EXE') 'counter' 'HEXFILE(counter.hex)'
        if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath 'counter.hex')) { throw 'Intel HEX generation failed.' }
    } finally { Pop-Location }
    Get-ChildItem -LiteralPath $temporaryBuild -File | Copy-Item -Destination $outputRoot
    Write-Output ('Built '+(Join-Path $outputRoot 'counter.hex'))
    Write-Output 'Compilation is not evidence of Proteus or physical-board correctness.'
} finally {
    # Delete only the explicit GUID-named temporary directory created above.
    $verifiedTemp=[IO.Path]::GetFullPath($temporaryBuild)
    $verifiedParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($verifiedTemp) -eq $verifiedParent -and [IO.Path]::GetFileName($verifiedTemp).StartsWith('counter-8051-')) {
        Remove-Item -LiteralPath $verifiedTemp -Recurse -Force
    }
}
