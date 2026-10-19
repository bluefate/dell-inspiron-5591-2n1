# Read-only: report the lid switch, console display and monitor power states as Windows' power manager sees them.
# Windows sends the current value of each setting right after RegisterPowerSettingNotification.
param([string]$Out)
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Windows.Forms; using System.Collections.Generic;
public class PowerStateReader : Form {
  [DllImport("user32.dll")] static extern IntPtr RegisterPowerSettingNotification(IntPtr h, ref Guid g, int flags);
  [StructLayout(LayoutKind.Sequential, Pack=4)] struct PBS { public Guid PowerSetting; public uint DataLength; public uint Data; }
  public List<string> Results = new List<string>();
  static readonly Dictionary<Guid,string> Names = new Dictionary<Guid,string> {
    { new Guid("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3"), "LIDSWITCH_STATE (0=closed, 1=open)" },
    { new Guid("6FE69556-704A-47A0-8F24-C28D936FDA47"), "CONSOLE_DISPLAY_STATE (0=off, 1=on, 2=dimmed)" },
    { new Guid("02731015-4510-4526-99E6-E5A17EBD1AEA"), "MONITOR_POWER_ON (0=off, 1=on)" },
    { new Guid("2B84C20E-AD23-4DDF-93DB-05FFBD7EFCA5"), "SESSION_DISPLAY_STATUS (0=off, 1=on, 2=dimmed)" },
    { new Guid("0E796BDB-100D-47D6-A2D5-F7D2DAA51F51"), "AWAYMODE / (ignore)" } };
  protected override void OnHandleCreated(EventArgs e) {
    base.OnHandleCreated(e);
    foreach (var g in Names.Keys) { var x = g; RegisterPowerSettingNotification(this.Handle, ref x, 0); }
    var t = new Timer(); t.Interval = 1500; t.Tick += (s, a) => this.Close(); t.Start();
  }
  protected override void WndProc(ref Message m) {
    if (m.Msg == 0x218 && m.WParam.ToInt32() == 0x8013) {
      var p = (PBS)Marshal.PtrToStructure(m.LParam, typeof(PBS));
      string n; Results.Add((Names.TryGetValue(p.PowerSetting, out n) ? n : p.PowerSetting.ToString()) + " = " + p.Data);
    }
    base.WndProc(ref m);
  }
  public PowerStateReader() { ShowInTaskbar = false; Opacity = 0; WindowState = FormWindowState.Minimized; }
}
'@
$f = New-Object PowerStateReader
[System.Windows.Forms.Application]::Run($f)
$lines = @("Power states at $(Get-Date -Format o):") + ($f.Results | ForEach-Object { "  $_" })
if ($Out) { $lines | Out-File -FilePath $Out -Append -Encoding utf8 } else { $lines }
