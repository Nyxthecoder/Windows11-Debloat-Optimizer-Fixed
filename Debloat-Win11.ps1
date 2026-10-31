#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Conservative Windows 10/11 debloat. Preview first with:  .\Debloat.ps1 -WhatIf

.DESCRIPTION
    Run from an elevated *Windows PowerShell 5.1* (powershell.exe), not pwsh 7:
    the Appx cmdlets are unreliable there.

    HKCU tweaks only apply to the account running the script.
    Feature updates can reinstall apps and reset settings; re-run if needed.

.PARAMETER DisableSearchIndexer
    Disables Windows Search (WSearch). Breaks Start/Explorer search results.

.PARAMETER DisableXboxServices
    Disables the Xbox services. Breaks Game Pass / Store-game sign-in and cloud saves.

.PARAMETER DisableSysMain
    Disables SysMain (Superfetch). Only worth it on SSD-only machines.

.PARAMETER SkipRestorePoint
    Don't create a restore point first.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DisableSearchIndexer,
    [switch]$DisableXboxServices,
    [switch]$DisableSysMain,
    [switch]$SkipRestorePoint
)

if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this in Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.'
}

$ErrorActionPreference = 'Stop'
$failed = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------- helpers ---

function Invoke-Step {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if (-not $PSCmdlet.ShouldProcess($Name)) { return }
    try {
        & $Action
        Write-Host "[ok]   $Name" -ForegroundColor Green
    }
    catch {
        Write-Warning "[fail] $Name : $($_.Exception.Message)"
        $failed.Add($Name)
    }
}

function Set-RegDword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

# ---------------------------------------------------------- restore point ---

if (-not $SkipRestorePoint) {
    # Needs System Protection enabled; Windows also throttles this to one per 24 h.
    Invoke-Step 'Create restore point' {
        Checkpoint-Computer -Description 'Before debloat' -RestorePointType MODIFY_SETTINGS
    }
}

# ------------------------------------------------------------------- apps ---

$apps = @(
    'Microsoft.Office.OneNote'               # Store OneNote, not the Office desktop app
    'Microsoft.BingWeather'
    'Microsoft.BingNews'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MSPaint'                      # Paint 3D (classic Paint is Microsoft.Paint)
    'Microsoft.ZuneVideo'                    # Movies & TV
    'Microsoft.ZuneMusic'                    # Groove / the new Media Player on Win11
    'Microsoft.SkypeApp'
    'Microsoft.549981C3F5F10'                # Cortana
    'MicrosoftTeams'                         # consumer Teams (Win10)
    'MSTeams'                                # consumer Teams (Win11)
)

foreach ($app in $apps) {
    Invoke-Step "Remove app $app" {
        Get-AppxPackage -AllUsers -Name $app | Remove-AppxPackage -AllUsers
        Get-AppxProvisionedPackage -Online |
            Where-Object DisplayName -eq $app |
            Remove-AppxProvisionedPackage -Online | Out-Null
    }
}

# --------------------------------------------------------------- services ---

$services = @('DiagTrack', 'dmwappushservice')
if ($DisableSearchIndexer) { $services += 'WSearch' }
if ($DisableSysMain)       { $services += 'SysMain' }
if ($DisableXboxServices)  { $services += 'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc' }

foreach ($svc in $services) {
    Invoke-Step "Disable service $svc" {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $s) { return }
        if ($s.Status -ne 'Stopped') { Stop-Service -Name $svc -Force }
        Set-Service -Name $svc -StartupType Disabled
    }
}

# ------------------------------------------------------- scheduled tasks ---

$tasks = @(
    @{ Path = '\Microsoft\Windows\Autochk\';                                 Name = 'Proxy' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' }
    @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' }
    @{ Path = '\Microsoft\Windows\DiskDiagnostic\';                          Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
)

foreach ($t in $tasks) {
    Invoke-Step "Disable task $($t.Path)$($t.Name)" {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task) { $task | Disable-ScheduledTask | Out-Null }
    }
}

# -------------------------------------------------- legacy Media Player ---

Invoke-Step 'Disable legacy Windows Media Player feature' {
    $f = Get-WindowsOptionalFeature -Online |
         Where-Object { $_.FeatureName -eq 'WindowsMediaPlayer' -and $_.State -eq 'Enabled' }
    if ($f) { Disable-WindowsOptionalFeature -Online -FeatureName WindowsMediaPlayer -NoRestart | Out-Null }
}

Invoke-Step 'Remove Windows Media Player capability (Win11 24H2+)' {
    Get-WindowsCapability -Online -Name '*Media.WindowsMediaPlayer*' |
        Where-Object State -eq 'Installed' |
        Remove-WindowsCapability -Online | Out-Null
}

# --------------------------------------------------------------- registry ---

$regTweaks = @(
    # machine-wide
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';                 Name = 'DoNotShowFeedbackNotifications'; Value = 1 }
    # current user
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';        Name = 'Start_TrackProgs';               Value = 0 }
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SystemPaneSuggestionsEnabled';    Value = 0 }
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';   Name = 'SubscribedContent-338393Enabled'; Value = 0 }
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                   Name = 'BingSearchEnabled';              Value = 0 }  # Win10
    @{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer';                       Name = 'DisableSearchBoxSuggestions';    Value = 1 }  # current Win11
)

foreach ($r in $regTweaks) {
    Invoke-Step "Registry $($r.Path)\$($r.Name) = $($r.Value)" {
        Set-RegDword -Path $r.Path -Name $r.Name -Value $r.Value
    }
}

Invoke-Step 'Stop OneDrive autostart (current user)' {
    # OneDrive can re-add this after an update or sign-in.
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------- temp ---

Invoke-Step 'Clear temp folders' {
    # Files in use are skipped on purpose.
    foreach ($p in $env:TEMP, "$env:WINDIR\Temp") {
        Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------- finish -----

Invoke-Step 'Restart Explorer' { Stop-Process -Name explorer -Force }

if ($failed.Count -gt 0) {
    Write-Warning ("{0} step(s) failed:`n  - {1}" -f $failed.Count, ($failed -join "`n  - "))
}
else {
    Write-Host "`nFinished with no failed steps." -ForegroundColor Green
}
