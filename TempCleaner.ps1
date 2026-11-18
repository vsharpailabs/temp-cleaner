#Requires -Version 5.1
<#
  Temp Cleaner for Windows
  Version 1.1.0  -  Published by V-Sharp AI Labs Limited
  - Sits on the desktop showing how much space your Temp folder (%TEMP%) uses
  - "Clean now" deletes temporary files safely (files in use are skipped)
  - Optional automatic clean at startup or once a day
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ======================= SETTINGS (edit these) =======================
$Config = @{
    OlderThanDays   = 1     # "safe" mode only deletes files not changed for this many days
    ConfirmClean    = $true # ask before a manual clean
}
# =====================================================================

$AppName      = 'Temp Cleaner'
$AppVersion   = '1.1.0'
$AppPublisher = 'V-Sharp AI Labs Limited'

# --- only one copy at a time ---
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\VSharp_TempCleaner', [ref]$created)
if (-not $created) { exit }

# --- the folder we clean, with safety checks ---
$TempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$TempOk = (Test-Path -LiteralPath $TempRoot -PathType Container) -and
          ($TempRoot -match '\\Temp(\\\d+)?$') -and
          ($TempRoot.Length -gt 8) -and
          ($TempRoot -ne $env:USERPROFILE.TrimEnd('\')) -and
          ($TempRoot -ne $env:SystemRoot.TrimEnd('\'))

# --- saved state ---
$DataDir   = Join-Path $env:APPDATA 'TempCleaner'
$StateFile = Join-Path $DataDir 'state.json'
$LogFile   = Join-Path $DataDir 'error.log'
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
function Log([string]$m) { try { Add-Content -Path $LogFile -Value "$(Get-Date -Format s)  $m" } catch {} }

$State = [pscustomobject]@{ Mode = 'older'; AutoMode = 'off'; CheckHours = 1; LastClean = ''; LastFreed = 0; TotalFreed = 0; Left = $null; Top = $null }
if (Test-Path $StateFile) {
    try {
        $saved = Get-Content $StateFile -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $State | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    } catch { Log "state load: $_" }
}
function Save-State { try { $State | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8 } catch {} }
function Get-Days { if ($State.Mode -eq 'all') { 0 } else { [int]$Config.OlderThanDays } }

function Format-Size([double]$b) {
    if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) }
    elseif ($b -ge 1MB) { '{0:N0} MB' -f ($b / 1MB) }
    elseif ($b -ge 1KB) { '{0:N0} KB' -f ($b / 1KB) }
    else { '{0:N0} bytes' -f $b }
}

# --- background worker: measures and (optionally) cleans, never follows links out of Temp ---
$Worker = {
    param([string]$root, [int]$days, [bool]$delete)
    $cutoff = if ($days -gt 0) { (Get-Date).AddDays(-$days) } else { [datetime]::MaxValue }
    $r = @{ Files = 0; Bytes = [int64]0; CanFiles = 0; CanBytes = [int64]0
            Deleted = 0; Freed = [int64]0; Skipped = 0; DirsRemoved = 0 }
    $dirs  = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    $stack = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $stack.Push((New-Object System.IO.DirectoryInfo $root))
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($e -is [System.IO.DirectoryInfo]) { $dirs.Add($e); $stack.Push($e); continue }
            $len = [int64]$e.Length
            $r.Files++; $r.Bytes += $len
            if ($e.LastWriteTime -lt $cutoff) {
                $r.CanFiles++; $r.CanBytes += $len
                if ($delete) {
                    try {
                        if ($e.IsReadOnly) { $e.IsReadOnly = $false }
                        $e.Delete(); $r.Deleted++; $r.Freed += $len
                    } catch { $r.Skipped++ }
                }
            }
        }
    }
    if ($delete) {
        # remove folders that are now empty, deepest first
        foreach ($d in ($dirs | Sort-Object { $_.FullName.Length } -Descending)) {
            try { if ($d.CreationTime -lt $cutoff) { $d.Delete($false); $r.DirsRemoved++ } } catch {}
        }
        $r.Bytes -= $r.Freed; $r.Files -= $r.Deleted
        $r.CanBytes -= $r.Freed; $r.CanFiles -= $r.Deleted
    }
    [pscustomobject]$r
}

# --- Windows helpers (desktop pinning, icons) ---
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TCNative {
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr FindWindow(string cls, string name);
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtr")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int i, IntPtr v);
    [DllImport("user32.dll", EntryPoint="SetWindowLong")]    static extern int SetWindowLong32(IntPtr h, int i, int v);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static void SetOwner(IntPtr h, IntPtr owner) {
        if (IntPtr.Size == 8) SetWindowLongPtr64(h, -8, owner); else SetWindowLong32(h, -8, owner.ToInt32());
    }
    public static void SendToBottom(IntPtr h) { SetWindowPos(h, new IntPtr(1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }
}
'@

# --- widget window ---
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Temp Cleaner" Width="300" Height="104"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="Card" CornerRadius="14" Background="#E61E1F24" Padding="16,10" Cursor="SizeAll">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="26"
                 Foreground="#CCFFFFFF" VerticalAlignment="Center" Margin="0,0,14,0"/>
      <StackPanel Grid.Column="1" VerticalAlignment="Center">
        <TextBlock x:Name="Size" Text="Measuring..." FontSize="24" FontWeight="SemiBold"
                   Foreground="White" FontFamily="Segoe UI"/>
        <TextBlock x:Name="Sub" Text="Temp folder" FontSize="11.5"
                   Foreground="#D9FFFFFF" FontFamily="Segoe UI" TextTrimming="CharacterEllipsis"/>
        <TextBlock x:Name="Last" Text="" FontSize="10.5"
                   Foreground="#99FFFFFF" FontFamily="Segoe UI" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
      <Button x:Name="CleanBtn" Grid.Column="2" Content="Clean now" Width="86" Height="32"
              VerticalAlignment="Center" Margin="10,0,0,0" Cursor="Hand"
              Background="#30D158" Foreground="#0B1A10" FontWeight="SemiBold" FontFamily="Segoe UI" BorderThickness="0"/>
    </Grid>
  </Border>
</Window>
'@
$window   = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$Card     = $window.FindName('Card')
$SizeTxt  = $window.FindName('Size')
$SubTxt   = $window.FindName('Sub')
$LastTxt  = $window.FindName('Last')
$CleanBtn = $window.FindName('CleanBtn')
$window.Title = "$AppName - $AppPublisher"

# position: saved spot if on screen, otherwise top-right (below the Battery Widget's default spot)
$wa  = [System.Windows.SystemParameters]::WorkArea
$vsL = [System.Windows.SystemParameters]::VirtualScreenLeft
$vsT = [System.Windows.SystemParameters]::VirtualScreenTop
$vsR = $vsL + [System.Windows.SystemParameters]::VirtualScreenWidth
$vsB = $vsT + [System.Windows.SystemParameters]::VirtualScreenHeight
if ($null -ne $State.Left -and $State.Left -ge $vsL -and $State.Left -le ($vsR - 60) -and
    $null -ne $State.Top  -and $State.Top  -ge $vsT -and $State.Top  -le ($vsB - 40)) {
    $window.Left = [double]$State.Left; $window.Top = [double]$State.Top
} else {
    $window.Left = $wa.Right - $window.Width - 24; $window.Top = $wa.Top + 128
}

function Get-Hwnd { (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle }
function Set-DesktopMode {
    $window.Topmost = $false
    $h = Get-Hwnd
    if ($h -eq [IntPtr]::Zero) { return }
    [TCNative]::SetOwner($h, [TCNative]::FindWindow('Progman', $null))
    [TCNative]::SendToBottom($h)
}
$window.Add_Activated({ [TCNative]::SendToBottom((Get-Hwnd)) })
$Card.Add_MouseLeftButtonDown({
    try { $window.DragMove() } catch {}
    $State.Left = $window.Left; $State.Top = $window.Top; Save-State
    [TCNative]::SendToBottom((Get-Hwnd))
})

function Brush([string]$hex) { [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }

# --- tray icon ---
$tray = New-Object System.Windows.Forms.NotifyIcon
try { $tray.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $env:SystemRoot 'System32\cleanmgr.exe')) }
catch { $tray.Icon = [System.Drawing.SystemIcons]::Application }
$tray.Text = "$AppName - $AppPublisher"
$tray.Visible = $true
function Info([string]$text) { try { $tray.ShowBalloonTip(5000, $AppName, $text, [System.Windows.Forms.ToolTipIcon]::Info) } catch {} }

# --- running the worker in the background ---
$script:job = $null
$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(400)

function Start-Work([bool]$delete, [bool]$auto = $false) {
    if ($script:job -or -not $TempOk) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($Worker).AddArgument($TempRoot).AddArgument((Get-Days)).AddArgument($delete)
    $script:job = @{ PS = $ps; Handle = $ps.BeginInvoke(); Delete = $delete; Auto = $auto }
    $CleanBtn.IsEnabled = $false
    if ($delete) { $SizeTxt.Text = 'Cleaning...'; $CleanBtn.Content = 'Cleaning' }
    $pollTimer.Start()
}

function Show-LastClean {
    if ($State.LastClean) {
        $when = [datetime]::Parse($State.LastClean)
        $day  = if ($when.Date -eq (Get-Date).Date) { 'today' } elseif ($when.Date -eq (Get-Date).Date.AddDays(-1)) { 'yesterday' } else { $when.ToString('d MMM') }
        $LastTxt.Text = "Last cleaned $day $($when.ToString('HH:mm')) - freed $(Format-Size $State.LastFreed)"
    } else { $LastTxt.Text = 'Not cleaned yet' }
}

$pollTimer.Add_Tick({
    if (-not $script:job -or -not $script:job.Handle.IsCompleted) { return }
    $pollTimer.Stop()
    $j = $script:job; $script:job = $null
    try {
        $r = $j.PS.EndInvoke($j.Handle) | Select-Object -Last 1
        if ($j.Delete) {
            $State.LastClean  = (Get-Date).ToString('o')
            $State.LastFreed  = [int64]$r.Freed
            $State.TotalFreed = [int64]$State.TotalFreed + [int64]$r.Freed
            Save-State
            $msg = "Freed $(Format-Size $r.Freed) ($($r.Deleted) files)."
            if ($r.Skipped -gt 0) { $msg += " $($r.Skipped) files in use were skipped." }
            Info $msg
        }
        $SizeTxt.Text = Format-Size $r.Bytes
        $modeTxt = if ($State.Mode -eq 'all') { 'cleanable' } else { "older than $($Config.OlderThanDays) day" }
        $SubTxt.Text = "Temp folder - $(Format-Size $r.CanBytes) $modeTxt"
        $tip = "$AppName - Temp: $(Format-Size $r.Bytes)"
        $tray.Text = $tip.Substring(0, [math]::Min(63, $tip.Length))
        Show-LastClean
    } catch { Log "worker: $_"; $SizeTxt.Text = 'Error'; $SubTxt.Text = 'See error.log' }
    finally {
        $j.PS.Dispose()
        $CleanBtn.IsEnabled = $true; $CleanBtn.Content = 'Clean now'
    }
})

function Clean-Now([bool]$auto = $false) {
    if (-not $TempOk) { [void][System.Windows.MessageBox]::Show("Temp folder not found or not safe to clean:`n$TempRoot", $AppName); return }
    if (-not $auto -and $Config.ConfirmClean) {
        $what = if ($State.Mode -eq 'all') { 'all temporary files that are not in use' } else { "temporary files older than $($Config.OlderThanDays) day(s)" }
        $ans = [System.Windows.MessageBox]::Show(
            "Delete $what from:`n$TempRoot`n`nFiles that are in use will be skipped. Deleted files do not go to the Recycle Bin.",
            "$AppName - $AppPublisher", 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
    }
    Start-Work $true $auto
}
function Refresh-Size { Start-Work $false }

# --- settings actions ---
function Set-Mode([string]$m)     { $State.Mode = $m; Save-State; Refresh-Size }
function Set-AutoMode([string]$m) {
    $State.AutoMode = $m; Save-State
    $t = switch ($m) { 'start' { 'Will clean automatically each time the widget starts.' }
                       'daily' { 'Will clean automatically once a day.' }
                       default { 'Automatic cleaning is off.' } }
    Info $t
}
function Test-DailyDue {
    if ($State.AutoMode -ne 'daily') { return $false }
    if (-not $State.LastClean) { return $true }
    ((Get-Date) - [datetime]::Parse($State.LastClean)).TotalHours -ge 24
}

# --- start automatically with Windows ---
$ScriptPath  = $MyInvocation.MyCommand.Path
$StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Temp Cleaner.lnk'
function Test-AutoStart { Test-Path $StartupLink }
function Set-AutoStart([bool]$on) {
    try {
        if ($on) {
            $ps  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($StartupLink)
            $lnk.TargetPath = $ps
            $lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$ScriptPath`""
            $lnk.WorkingDirectory = Split-Path $ScriptPath
            $lnk.IconLocation = "$env:SystemRoot\System32\cleanmgr.exe,0"
            $lnk.Description  = "$AppName by $AppPublisher"
            $lnk.WindowStyle  = 7
            $lnk.Save()
            Info 'Will start automatically when Windows starts.'
        } else {
            Remove-Item $StartupLink -Force -ErrorAction Stop
            Info 'Will NOT start automatically. Use the desktop shortcut to open it.'
        }
    } catch { Log "autostart: $_" }
}

# --- About window ---
[xml]$aboutXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="About Temp Cleaner" Width="470" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Topmost="True" ShowInTaskbar="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.8"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="AboutCard" CornerRadius="16" Background="#F51E1F24" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="26,22">
    <StackPanel>
      <Grid>
        <StackPanel>
          <TextBlock x:Name="AName" FontSize="24" FontWeight="SemiBold" Foreground="White" FontFamily="Segoe UI"/>
          <TextBlock x:Name="AVer" FontSize="12.5" Foreground="#B3FFFFFF" FontFamily="Segoe UI" Margin="0,2,0,0"/>
        </StackPanel>
        <Button x:Name="AClose" Content="&#x2715;" HorizontalAlignment="Right" VerticalAlignment="Top"
                Width="30" Height="30" Background="Transparent" Foreground="#B3FFFFFF" FontSize="14" Cursor="Hand"/>
      </Grid>
      <Border Height="1" Background="#26FFFFFF" Margin="0,16,0,6"/>
      <StackPanel x:Name="ABody"/>
      <Border Height="1" Background="#26FFFFFF" Margin="0,14,0,12"/>
      <Grid>
        <TextBlock x:Name="ACopy" FontSize="11.5" Foreground="#8CFFFFFF" FontFamily="Segoe UI" VerticalAlignment="Center"/>
        <Button x:Name="AOk" Content="OK" HorizontalAlignment="Right" Width="84" Height="30"
                Background="#30D158" Foreground="#0B1A10" FontWeight="SemiBold" Cursor="Hand"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@

function Show-About {
    if ($script:aboutWin -and $script:aboutWin.IsVisible) { $script:aboutWin.Activate() | Out-Null; return }
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $aboutXaml))
    $w.FindName('AName').Text = $AppName
    $w.FindName('AVer').Text  = "Version $AppVersion   |   Published by $AppPublisher"
    $w.FindName('ACopy').Text = "$([char]0x00A9) $((Get-Date).Year) $AppPublisher. All rights reserved."
    $body = $w.FindName('ABody')
    $add = {
        param([string]$text, [string]$kind)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        if ($kind -eq 'h') {
            $tb.Text = $text; $tb.FontSize = 14; $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tb.Foreground = Brush '#FFFFFF'; $tb.Margin = New-Object System.Windows.Thickness(0, 12, 0, 6)
        } else {
            $tb.Text = "$([char]0x2022)  $text"; $tb.FontSize = 12.5
            $tb.Foreground = Brush '#D9FFFFFF'; $tb.Margin = New-Object System.Windows.Thickness(4, 0, 0, 5)
        }
        [void]$body.Children.Add($tb)
    }
    $modeNow = if ($State.Mode -eq 'all') { 'Everything not in use' } else { "Only files older than $($Config.OlderThanDays) day(s)" }
    $autoNow = switch ($State.AutoMode) { 'start' { 'each time the widget starts' } 'daily' { 'once a day' } default { 'off' } }
    $startNow = if (Test-AutoStart) { 'ON' } else { 'OFF' }
    $checkNow = if ([int]$State.CheckHours -gt 0) { "every $($State.CheckHours) hour(s)" } else { 'on demand only' }

    & $add 'What this widget does' 'h'
    & $add "Shows how much space your Temp folder is using: $TempRoot" 'b'
    & $add 'Apps and Windows leave temporary files here and often never remove them. Over time this can take up gigabytes.' 'b'
    & $add "'Clean now' deletes these temporary files. Files that are in use are skipped automatically, so open apps are not affected." 'b'
    & $add 'It only touches your own Temp folder. Your documents, photos and other folders are never touched. Shortcuts or links inside Temp are never followed.' 'b'

    & $add 'What you need to do' 'h'
    & $add "Click 'Clean now' whenever the size looks large, then click Yes to confirm." 'b'
    & $add 'Deleted files do not go to the Recycle Bin. Temporary files are not needed, but if you saved something important in Temp, move it elsewhere first.' 'b'
    & $add 'For the best result, close other apps (especially installers) before cleaning.' 'b'

    & $add 'Options (right-click the widget)' 'h'
    & $add "Clean mode: 'Only files older than $($Config.OlderThanDays) day' (safest, default) or 'Everything not in use'. Currently: $modeNow." 'b'
    & $add "Automatic clean: Off, each time the widget starts, or once a day. Currently: $autoNow." 'b'
    & $add "Check size: how often the widget measures the Temp folder - every 1, 3, 6, 12 or 24 hours, or on demand only (when you click Refresh size or Clean now). Less often means less disk activity. Currently: $checkNow." 'b'
    & $add "Start with Windows: 'Start automatically at startup' or 'Do not start automatically at startup'. Currently: $startNow." 'b'

    & $add 'Tips' 'h'
    & $add 'The widget sits on the desktop behind your apps. Drag it to move it.' 'b'
    & $add "'Open Temp folder' in the right-click menu lets you see what is there." 'b'
    & $add "Total space freed so far: $(Format-Size $State.TotalFreed)." 'b'

    $script:aboutWin = $w
    $w.FindName('AboutCard').Add_MouseLeftButtonDown({ try { $script:aboutWin.DragMove() } catch {} })
    $w.FindName('AClose').Add_Click({ $script:aboutWin.Close() })
    $w.FindName('AOk').Add_Click({ $script:aboutWin.Close() })
    $w.Add_KeyDown({ param($s, $e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $script:aboutWin.Close() } })
    $w.Show(); $w.Activate() | Out-Null
}

function Show-Widget { $window.Show(); Set-DesktopMode }
function Exit-Widget { $app.Shutdown() }

# --- right-click menu on the widget ---
$menu = New-Object System.Windows.Controls.ContextMenu
function New-MI([string]$header, [scriptblock]$action, $parent = $menu) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    if ($action) { $mi.Add_Click($action) }
    [void]$parent.Items.Add($mi); $mi
}
function Add-Sep { [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator)) }

$null      = New-MI 'Clean now' { Clean-Now }
$null      = New-MI 'Refresh size' { Refresh-Size }
$null      = New-MI 'Open Temp folder' { Start-Process explorer.exe -ArgumentList "`"$TempRoot`"" }
Add-Sep
$miMode    = New-MI 'Clean mode' $null
$miOlder   = New-MI "Only files older than $($Config.OlderThanDays) day (safest)" { Set-Mode 'older' } $miMode
$miAll     = New-MI 'Everything not in use' { Set-Mode 'all' } $miMode
$miAuto    = New-MI 'Automatic clean' $null
$miAOff    = New-MI 'Off' { Set-AutoMode 'off' } $miAuto
$miAStart  = New-MI 'Each time the widget starts' { Set-AutoMode 'start' } $miAuto
$miADaily  = New-MI 'Once a day' { Set-AutoMode 'daily' } $miAuto
$miCheck   = New-MI 'Check size' $null
$CheckChoices = [ordered]@{ 1 = 'Every 1 hour'; 3 = 'Every 3 hours'; 6 = 'Every 6 hours'; 12 = 'Every 12 hours'; 24 = 'Every 24 hours'; 0 = 'On demand only' }
$miChecks = @{}
foreach ($kv in $CheckChoices.GetEnumerator()) {
    $hh = [int]$kv.Key
    $miChecks[$hh] = New-MI ([string]$kv.Value) ([scriptblock]::Create("Set-CheckHours $hh")) $miCheck
}
$miStart   = New-MI 'Start with Windows' $null
$miSOn     = New-MI 'Start automatically at startup' { Set-AutoStart $true } $miStart
$miSOff    = New-MI 'Do not start automatically at startup' { Set-AutoStart $false } $miStart
Add-Sep
$null      = New-MI 'About' { Show-About }
$null      = New-MI 'Hide (tray icon stays)' { $window.Hide() }
$null      = New-MI 'Exit' { Exit-Widget }
$menu.Add_Opened({
    $miOlder.IsChecked = $State.Mode -ne 'all'; $miAll.IsChecked = $State.Mode -eq 'all'
    $miAOff.IsChecked = $State.AutoMode -eq 'off'; $miAStart.IsChecked = $State.AutoMode -eq 'start'; $miADaily.IsChecked = $State.AutoMode -eq 'daily'
    $a = Test-AutoStart; $miSOn.IsChecked = $a; $miSOff.IsChecked = -not $a
    foreach ($k in $miChecks.Keys) { $miChecks[$k].IsChecked = ($k -eq [int]$State.CheckHours) }
})
$Card.ContextMenu = $menu
$CleanBtn.Add_Click({ Clean-Now })

# --- tray menu ---
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$trayMenu.Items.Add('Show widget', $null, { Show-Widget })
[void]$trayMenu.Items.Add('Clean now',   $null, { Clean-Now })
[void]$trayMenu.Items.Add('About',       $null, { Show-About })
[void]$trayMenu.Items.Add('Exit',        $null, { Exit-Widget })
$tray.ContextMenuStrip = $trayMenu
$tray.Add_DoubleClick({ Show-Widget })

# --- timers & run ---
# size check: every N hours, or only on demand (CheckHours = 0)
$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Add_Tick({ try { Refresh-Size } catch { Log "refresh: $_" } })
function Apply-CheckHours {
    $refreshTimer.Stop()
    $h = [int]$State.CheckHours
    if ($h -gt 0) { $refreshTimer.Interval = [TimeSpan]::FromHours($h); $refreshTimer.Start() }
}
function Set-CheckHours([int]$h) {
    $State.CheckHours = $h; Save-State; Apply-CheckHours
    if ($h -gt 0) { Info "Will check the Temp folder size every $h hour$(if ($h -gt 1) {'s'})." }
    else { Info "Will check the size only when you click Refresh size or Clean now." }
}

# daily auto-clean check: no disk scanning, just looks at the clock every 15 minutes
$dailyTimer = New-Object System.Windows.Threading.DispatcherTimer
$dailyTimer.Interval = [TimeSpan]::FromMinutes(15)
$dailyTimer.Add_Tick({ try { if (Test-DailyDue) { Clean-Now $true } } catch { Log "daily: $_" } })

$app = [System.Windows.Application]::Current
if ($null -eq $app) { $app = New-Object System.Windows.Application }
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$app.Add_DispatcherUnhandledException({ param($s, $e) Log "unhandled: $($e.Exception.ToString())"; $e.Handled = $true })
$app.Add_Exit({
    $refreshTimer.Stop(); $dailyTimer.Stop(); $pollTimer.Stop()
    $State.Left = $window.Left; $State.Top = $window.Top; Save-State
    $tray.Visible = $false; $tray.Dispose()
})

$window.Add_SourceInitialized({ Set-DesktopMode })
$window.Add_Loaded({
    Show-LastClean
    if (-not $TempOk) { $SizeTxt.Text = 'Unavailable'; $SubTxt.Text = 'Temp folder not found'; $CleanBtn.IsEnabled = $false }
    elseif ($State.AutoMode -eq 'start' -or (Test-DailyDue)) { Clean-Now $true }
    else { Refresh-Size }
    Apply-CheckHours; $dailyTimer.Start()
})
$window.Show()
try { [void]$app.Run() } catch { Log "run: $_" }
try { $mutex.ReleaseMutex() } catch {}
