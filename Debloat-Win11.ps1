# --- Remove built-in bloat apps ---
$appsToRemove = @("onenote", "bingweather", "bingnews", "solitairecollection", "3dviewer", "paint3d", "zunevideo", "zunemusic", "skypeapp", "cortana", "Teams")
foreach ($app in $appsToRemove) {
    Get-AppxPackage -AllUsers $app | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# --- Disable unnecessary services ---
$servicesToDisable = @("DiagTrack", "WSearch", "SysMain", "RemoteRegistry", "XboxGipSvc", "XblAuthManager", "XblGameSave")
foreach ($svc in $servicesToDisable) {
    try { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue; Set-Service -Name $svc -StartupType Disabled } catch {}
}

# --- Disable telemetry scheduled tasks ---
$tasksToDisable = @("\Microsoft\Windows\Autochk\Proxy", "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator", "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip", "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector")
foreach ($task in $tasksToDisable) {
    Disable-ScheduledTask -TaskPath ($task.Substring(0, $task.LastIndexOf('\') + 1)) -TaskName ($task.Split('\')[-1]) -ErrorAction SilentlyContinue
}

# --- Disable optional features ---
$featuresToDisable = @("WindowsMediaPlayer")
foreach ($feature in $featuresToDisable) { Disable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue }

# --- Clean up temp files ---
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# --- Disable OneDrive startup ---
$onedriveKeys = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run")
foreach ($key in $onedriveKeys) { Remove-ItemProperty -Path $key -Name "OneDrive" -ErrorAction SilentlyContinue }

# --- Registry Tweaks: Disable Feedback, Live Tiles, Bing Search ---
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 1
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "CortanaConsent" -Value 0
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Value 0
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Value 0 -ErrorAction SilentlyContinue

# --- Restart Explorer to apply changes ---
Stop-Process -Name explorer -Force
Write-Host "`n Debloating complete. Permanent minimal RAM/CPU configuration applied." -ForegroundColor Green
