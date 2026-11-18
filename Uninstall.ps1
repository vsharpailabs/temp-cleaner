# Temp Cleaner - V-Sharp AI Labs Limited
# Removes Temp Cleaner
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*TempCleaner.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
foreach ($folder in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'))) {
    Remove-Item (Join-Path $folder 'Temp Cleaner.lnk') -ErrorAction SilentlyContinue
}
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TempCleaner' -Recurse -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'TempCleaner') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'TempCleaner') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Temp Cleaner removed." -ForegroundColor Green
Start-Sleep -Seconds 3
