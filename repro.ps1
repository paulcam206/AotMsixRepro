#Requires -Version 7
<#
.SYNOPSIS
    Publishes this NativeAOT WinUI 3 single-project MSIX app five ways and
    reports, for each, the exit code, any build errors, and whether an .msix
    was produced.

.PARAMETER MsixToolingVersion
    Optional Microsoft.Windows.SDK.BuildTools.MSIX version to use instead of
    the one Microsoft.WindowsAppSDK brings in.
#>
param([string] $MsixToolingVersion)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
# Each case starts from an empty bin\ and obj\, except the last, which reuses
# the full build the control case left behind.
$cases = [ordered]@{
    'default'                   = @{ Clean = $true; Properties = @() }
    'FixXamlReferences'         = @{ Clean = $true; Properties = @('-p:FixXamlReferences=true') }
    'both fixes'                = @{ Clean = $true; Properties = @('-p:FixXamlReferences=true', '-p:FixMsixPackaging=true') }
    'UseOptimizedPublish=false' = @{ Clean = $true; Properties = @('-p:UseOptimizedPublish=false') }
    'FixXamlReferences, after a full build' = @{ Clean = $false; Properties = @('-p:FixXamlReferences=true') }
}

function Get-MsixEntries([string] $Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try { @($zip.Entries | ForEach-Object { '{0}|{1}' -f $_.FullName, $_.Length }) }
    finally { $zip.Dispose() }
}

# global.json is found from the working directory, not the project path.
Push-Location $root
try {
    $sdk = @(dotnet --version)
    if ($LASTEXITCODE -ne 0) { throw 'dotnet --version failed.' }
    Write-Host "SDK: $($sdk[0])"
    $common = @()
    if ($MsixToolingVersion) {
        $common += "-p:MsixToolingVersion=$MsixToolingVersion"
        Write-Host "MSIX tooling: $MsixToolingVersion"
    }

    $results = foreach ($name in $cases.Keys) {
        $case = $cases[$name]
        $slug = ($name -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
        $caseDir = Join-Path $root "out\$slug"
        $stale = @($caseDir)
        if ($case.Clean) { $stale += (Join-Path $root 'bin'), (Join-Path $root 'obj') }
        foreach ($dir in $stale) {
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        }
        New-Item -ItemType Directory -Path $caseDir | Out-Null

        Write-Host "Publishing: $name"
        $arguments = @(
            'publish', 'AotMsixRepro.csproj',
            '-c', 'Release', '-r', 'win-x64', '-p:Platform=x64',
            '-p:GenerateAppxPackageOnBuild=true',
            "-p:AppxPackageDir=$caseDir/appx/",
            '-o', (Join-Path $caseDir 'publish'),
            '--nologo', '-v:minimal'
        ) + $common + $case.Properties
        $output = @(& dotnet @arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        [IO.File]::WriteAllLines((Join-Path $caseDir 'publish.log'), [string[]]$output)

        $packages = @(Get-ChildItem -LiteralPath $caseDir -Filter '*.msix' -File -Recurse)
        $errors = @($output | Select-String -Pattern 'error ([A-Z]+[0-9]+)' -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        [pscustomobject]@{
            Case     = $name
            ExitCode = $exitCode
            Errors   = if ($errors.Count) { $errors -join ', ' } else { '-' }
            Package  = if ($packages.Count) { $packages[0].Name } else { '(none)' }
            Path     = if ($packages.Count) { $packages[0].FullName } else { $null }
        }
    }

    $results | Format-Table Case, ExitCode, Errors, Package -AutoSize | Out-Host

    $fixed = $results | Where-Object Case -eq 'both fixes'
    $control = $results | Where-Object Case -eq 'UseOptimizedPublish=false'
    if ($fixed.Path -and $control.Path) {
        $fixedEntries = Get-MsixEntries $fixed.Path
        $difference = @(Compare-Object $fixedEntries (Get-MsixEntries $control.Path))
        Write-Host ("'both fixes' vs 'UseOptimizedPublish=false': {0} package entries, {1} differing by name or size." -f $fixedEntries.Count, $difference.Count)
    }
}
finally {
    Pop-Location
}
