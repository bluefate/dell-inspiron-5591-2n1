# Black screen probe: log what displays Windows sees, then force HDMI-only (DisplaySwitch /external), then log again.
# Run by the "BlackScreenProbe" logon task. Output: C:\BlackScreenBackup\probe\probe-<timestamp>.txt
param([int]$Delay = 20, [switch]$NoSwitch)
$ErrorActionPreference = 'Continue'
$log = "C:\BlackScreenBackup\probe\probe-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
function W($t){ $t | Out-File -FilePath $log -Append -Encoding utf8 -Width 300 }

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class Dc {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Lo; public int Hi; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint N; public uint D; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology; public uint rotation; public uint scaling; public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_INFO { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] public struct MODE_INFO { public uint infoType; public uint id; public LUID adapterId; [MarshalAs(UnmanagedType.ByValArray, SizeConst=48)] public byte[] data; }
  [StructLayout(LayoutKind.Sequential)] public struct HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct TARGET_NAME { public HEADER header; public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath; }
  [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint np, out uint nm);
  [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint np, [Out] PATH_INFO[] p, ref uint nm, [Out] MODE_INFO[] m, IntPtr topo);
  [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME t);
  public static List<string> Paths(uint flags) {
    var r = new List<string>(); uint np, nm; int e = GetDisplayConfigBufferSizes(flags, out np, out nm);
    if (e != 0) { r.Add("GetDisplayConfigBufferSizes err " + e); return r; }
    var p = new PATH_INFO[np]; var m = new MODE_INFO[nm];
    e = QueryDisplayConfig(flags, ref np, p, ref nm, m, IntPtr.Zero);
    if (e != 0) { r.Add("QueryDisplayConfig err " + e); return r; }
    for (int i = 0; i < np; i++) {
      var t = new TARGET_NAME(); t.header.type = 2; t.header.size = (uint)Marshal.SizeOf(typeof(TARGET_NAME)); t.header.adapterId = p[i].targetInfo.adapterId; t.header.id = p[i].targetInfo.id;
      DisplayConfigGetDeviceInfo(ref t);
      r.Add(String.Format("path{0}: active={1} src={2} target={3} available={4} tech=0x{5:X} name='{6}' devpath='{7}' adapter={8:X}", i, (p[i].flags & 1) == 1, p[i].sourceInfo.id, p[i].targetInfo.id, p[i].targetInfo.targetAvailable != 0, p[i].targetInfo.outputTechnology, t.monitorFriendlyDeviceName, t.monitorDevicePath, p[i].targetInfo.adapterId.Lo));
    }
    return r;
  }
}
'@

function Shot($label){
  try {
    Add-Type -AssemblyName System.Drawing, System.Windows.Forms
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size); $g.Dispose()
    $png = $log -replace '\.txt$', "-$label.png"; $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    # sample brightness so the log alone tells us if the captured image is black
    $sum = 0; $n = 0; for ($x = 0; $x -lt $bmp.Width; $x += 40) { for ($y = 0; $y -lt $bmp.Height; $y += 40) { $c = $bmp.GetPixel($x, $y); $sum += ($c.R + $c.G + $c.B) / 3; $n++ } }
    $bmp.Dispose(); W ("--- Screenshot {0}: {1}  avg brightness {2:N1}/255 over {3} samples" -f $label, (Split-Path $png -Leaf), ($sum / $n), $n)
  } catch { W "--- Screenshot $label FAILED: $($_.Exception.Message)" }
}

function Snapshot($label){
  W "===== $label  $(Get-Date -Format o)"
  Shot ($label -replace '\W', '')
  try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\powerstate.ps1" -Out $log } catch { W "powerstate failed: $_" }
  W "--- Sensor services"; Get-Service SensorService,SensrSvc,SensorDataService -ErrorAction SilentlyContinue | ForEach-Object { W ("{0} {1}" -f $_.Name,$_.Status) }
  W "--- Active paths (QDC_ONLY_ACTIVE_PATHS)"; [Dc]::Paths(2) | ForEach-Object { W $_ }
  W "--- All available paths (QDC_ALL_PATHS, available only)"; [Dc]::Paths(1) | Where-Object { $_ -match 'available=True' } | ForEach-Object { W $_ }
  Add-Type -AssemblyName System.Windows.Forms
  W "--- Screens"; [System.Windows.Forms.Screen]::AllScreens | ForEach-Object { W ("{0} primary={1} bounds={2}" -f $_.DeviceName,$_.Primary,$_.Bounds) }
  W "--- WmiMonitorConnectionParams (5=HDMI, 11=eDP, 0x80000000=internal)"
  Get-CimInstance -Namespace root\wmi WmiMonitorConnectionParams -ErrorAction SilentlyContinue | ForEach-Object { W ("{0} active={1} tech={2}" -f $_.InstanceName,$_.Active,$_.VideoOutputTechnology) }
}

$boot = (Get-CimInstance Win32_ComputerSystem).BootupState
if ($boot -ne 'Normal boot') { $NoSwitch = $true }   # never switch displays in Safe Mode
W "Probe start. User=$env:USERNAME Session=$((Get-Process -Id $PID).SessionId) Boot='$boot' Delay=$Delay NoSwitch=$NoSwitch"
Start-Sleep -Seconds $Delay
Snapshot "BEFORE DisplaySwitch"
if (-not $NoSwitch) {
  W "--- Running DisplaySwitch.exe /external"
  Start-Process "$env:windir\System32\DisplaySwitch.exe" -ArgumentList '/external' -Wait
  Start-Sleep -Seconds 8
  Snapshot "AFTER DisplaySwitch /external"
}
W "Probe end."
