# Temp Cleaner 1.1.0 - V-Sharp AI Labs Limited
# Installs Temp Cleaner: starts with Windows + adds a Desktop shortcut, then launches it.
# Running it again updates an existing installation (settings are kept).

# stop any running copy so the new version starts
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*TempCleaner.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'TempCleaner'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item (Join-Path $src 'TempCleaner.ps1') $dest -Force
Copy-Item (Join-Path $src 'Uninstall.ps1') $dest -Force
Get-ChildItem $dest | Unblock-File

$script  = Join-Path $dest 'TempCleaner.ps1'
$ps      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$script`""
$icon    = "$env:SystemRoot\System32\cleanmgr.exe,0"

$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'))) {
    $lnk = $shell.CreateShortcut((Join-Path $folder 'Temp Cleaner.lnk'))
    $lnk.TargetPath = $ps
    $lnk.Arguments = $argLine
    $lnk.WorkingDirectory = $dest
    $lnk.IconLocation = $icon
    $lnk.Description = 'Temp Cleaner by V-Sharp AI Labs Limited'
    $lnk.WindowStyle = 7
    $lnk.Save()
}

# list it under Settings > Apps > Installed apps, with publisher name
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TempCleaner'
New-Item -Path $key -Force | Out-Null
$props = @{
    DisplayName     = 'Temp Cleaner'
    DisplayVersion  = '1.1.0'
    Publisher       = 'V-Sharp AI Labs Limited'
    InstallLocation = $dest
    DisplayIcon     = $icon
    UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dest 'Uninstall.ps1')`""
    InstallDate     = (Get-Date -Format 'yyyyMMdd')
}
foreach ($k in $props.Keys) { Set-ItemProperty -Path $key -Name $k -Value $props[$k] }
Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord

Start-Process $ps -ArgumentList $argLine -WindowStyle Hidden
Write-Host "Temp Cleaner installed and running. It will start automatically with Windows." -ForegroundColor Green
Write-Host "Right-click the widget > About for help."
Start-Sleep -Seconds 4
