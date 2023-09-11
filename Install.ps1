#Requires -Version 5.1 # or 7

using namespace System.Management.Automation
using namespace System.Runtime.InteropServices
using namespace System.Security.Principal

<#
.SYNOPSIS
    Installs fonts.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    # Path containing .ttf files to install.  If omitted, one of the following default paths is used:
    #
    # $PSScriptRoot\dist\iosevka-sharpie\ttf  (if it exists)
    # $PSScriptRoot                           (otherwise)
    [Parameter(ValueFromPipeline)]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [SupportsWildcards()]
    [string]
    $SourcePath
,
    # Install a font even if the same version of that font is already installed.
    [Parameter()]
    [switch]
    $Force
)

begin {
    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version 2.0

    if ($PSEdition -ne "Desktop" -and -not $IsWindows) {
        throw "This command supports Windows only."
    }

    $User    = [WindowsPrincipal]::new([WindowsIdentity]::GetCurrent())
    $IsAdmin = $User.IsInRole([WindowsBuiltInRole]::Administrator)
}

process {
    # Elevate if required
    if (-not $IsAdmin) {
        if (Get-Command pwsh.exe -ErrorAction Ignore) {
            $PowerShellBinary = "pwsh"
        } else {
            $PowerShellBinary = "powershell"
        }
        $Self = Start-Process $PowerShellBinary -Verb RunAs -Wait -PassThru -ArgumentList @(
            "-File"; "`"$PSCommandPath`""
            if ($SourcePath) { "-SourcePath"; "`"$SourcePath`"" }
            if ($Force)      { "-Force" }
            if ($WhatIfPreference)                                      { "-WhatIf" }
            if ($VerbosePreference -notin "SilentlyContinue", "Ignore") { "-Verbose" }
            if ($DebugPreference   -notin "SilentlyContinue", "Ignore") { "-Debug" }
        )
        if ($Self.ExitCode -ne 0) {
            $PSCmdlet.ThrowTerminatingError([ErrorRecord]::new(
                [ExternalException]::new("The elevated script encountered an error."),
                $null, 'InvalidResult', [Environment]::MachineName
            ))
        }
        return
    }

    try {
        Add-Type -AssemblyName PresentationCore

        if (!$SourcePath) {
            $SourcePath = Join-Path $PSScriptRoot dist\iosevka-sharpie\ttf -Resolve -ErrorAction Ignore
        }
        if (!$SourcePath) {
            $SourcePath = $PSScriptRoot
        }
        $FontPattern = Join-Path $SourcePath *.ttf
        $FontFiles   = Get-Item -Path $FontPattern | Sort-Object Name
        $TargetPath  = [Environment]::GetFolderPath([Environment+SpecialFolder]::Fonts) 
        $RegistryKey = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        Write-Debug "Source Path: $SourcePath"
        Write-Debug "Target Path: $TargetPath"
        Write-Debug "RegistryKey: $RegistryKey"

        $FontFiles | ForEach-Object {
            $SourceFile = $_
            $TargetFile = Join-Path $TargetPath $_.Name | Get-Item -ErrorAction Ignore
            Write-Debug "Source File: $SourceFile"
            Write-Debug "Target File: $TargetFile"

            $SourceHash = $SourceFile | Get-FileHash | ForEach-Object Hash -WhatIf:$false
            $TargetHash = $TargetFile | Get-FileHash | ForEach-Object Hash -WhatIf:$false
            Write-Debug "Source Hash: $SourceHash"
            Write-Debug "Target Hash: $TargetHash"

            $Font   = [System.Windows.Media.GlyphTypeface]::new($SourceFile.FullName)
            $Family = $Font.Win32FamilyNames.Values | Select-Object -First 1
            $Style  = $Font.Win32FaceNames.Values   | Select-Object -First 1
            Write-Debug "Font Family: $Family"
            Write-Debug "Font Style:  $Style"

            if ($SourceHash -eq $TargetHash -and !$Force) {
                Write-Host Skipping: -ForegroundColor Cyan -NoNewline
                Write-Host "" $Family $Style "" -NoNewline
                Write-Host "(already installed)" -ForegroundColor DarkGray
            } else {
                Write-Host Installing: -ForegroundColor Cyan -NoNewline
                Write-Host "" $Family $Style

                Copy-Item $SourceFile $TargetFile -Force

                $RegistryKey | Set-ItemProperty `
                    -Name  "$Family $Style (TrueType)" `
                    -Value $TargetFile.Name -Force
            }
        }
    }
    catch {
        Write-Error $_ -CategoryActivity $MyInvocation.MyCommand.Name -ErrorAction Continue
        exit 1
    }
    finally {
        Write-Host
        Write-Host "Press a key to exit."
        [Console]::ReadKey(<#intercept#> $true) > $null
    }
}
