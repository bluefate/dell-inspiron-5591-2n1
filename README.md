# Windows 11 black screen after removing the display from a Dell Inspiron 5591 2-in-1

**Symptom:** you removed the laptop's screen assembly (panel, webcam, mic, cables) and use an external HDMI monitor. Windows 11 now boots to a **black screen with a movable mouse cursor**: no sign-in screen, no desktop, no Task Manager. BIOS, Windows Recovery and Safe Mode all display fine on the same monitor.

**Fix:** in Safe Mode, **disable "Intel(R) Integrated Sensor Solution"** in Device Manager, then restart normally.

**Root cause:** on this 2-in-1, Windows 11 reads the laptop's sensor hub (accelerometers in the base *and in the lid*) to work out the device's posture. With the lid assembly gone, those readings no longer make sense, and Windows 11 keeps the display switched off. Moving the mouse or pressing keys doesn't wake it. Windows 10 and Linux don't do this, which is why they work on the same hardware. Safe Mode works because it doesn't start the sensor services.

---

## Does this apply to you?

Probably yes, if **all** of these are true:

- A 2-in-1 / convertible laptop with its built-in screen (lid assembly) removed or disconnected.
- External monitor via HDMI (or USB-C/DisplayPort).
- **Windows 11**: black screen with a cursor in normal boot.
- **Safe Mode works**, and so does BIOS. Linux or Windows 10 also work, if you've tried them.
- The problem started after removing the screen, not after an update. Windows updates and a factory reset don't fix it, and the reset itself may seem to help briefly.

Confirmed on: **Dell Inspiron 5591 2-in-1** (Intel Core i5-10210U, Intel UHD Graphics `PCI\VEN_8086&DEV_9B41`, sensor hub `PCI\VEN_8086&DEV_02FC`), Windows 11 26H2 (build 26300 / 26100.9711). A second identical laptop shows the same symptom. Other 2-in-1 models with an Intel Integrated Sensor Hub may well behave the same, but that's untested.

---

## Step-by-step fix

### 1. Get into Safe Mode

If you can't see anything in normal mode:

1. Turn the laptop on. When the Dell logo or spinning dots appear, **hold the power button until it shuts off**. Do this **two or three times** in a row.
2. Windows then starts **Automatic Repair / Windows Recovery**, which does display on HDMI.
3. Choose **Advanced options → Troubleshoot → Advanced options → Startup Settings → Restart**.
4. After the restart, press **4** (Safe Mode) or **5** (Safe Mode with Networking).

> If BitLocker or Device Encryption is on, Recovery may ask for your recovery key. Get it from https://account.microsoft.com/devices/recoverykey on another device.

### 2. Disable the sensor hub

**Using Device Manager:**

1. Right-click **Start → Device Manager**.
2. Expand **System devices**.
3. Right-click **Intel(R) Integrated Sensor Solution** → **Disable device** → **Yes**.

**Or from an elevated PowerShell (Run as administrator):**

```powershell
Get-PnpDevice -FriendlyName 'Intel(R) Integrated Sensor Solution' | Disable-PnpDevice -Confirm:$false
```

### 3. Restart normally

Restart and boot normally (not Safe Mode). The sign-in screen and desktop should now appear on the external monitor.

If the screen goes dark on the sign-in screen after about a minute, that's normal Windows screen timeout. Move the mouse and it comes back. (Before the fix, it never came back.)

### 4. Undo (if ever needed)

Device Manager → System devices → right-click **Intel(R) Integrated Sensor Solution** → **Enable device**. Or:

```powershell
Get-PnpDevice -FriendlyName 'Intel(R) Integrated Sensor Solution' | Enable-PnpDevice -Confirm:$false
```

### Side effects

Disabling the sensor hub turns off the laptop's built-in sensors: auto-rotate, tablet/tent posture detection, the ambient light sensor (if your model has one), and accelerometer/gyro. None of these are useful once the screen has been removed. Keyboard, touchpad, Wi-Fi, USB and the external display aren't affected.

---

## Things that did *not* fix it

These were tried during the investigation and made no difference:

- Startup Repair, DISM/SFC, clean boot, uninstalling updates, factory reset.
- `Win+P`, `Win+Ctrl+Shift+B`, `Ctrl+Alt+Del`, `Ctrl+Shift+Esc`.
- Resetting Windows' saved display layouts (`HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration` etc.).
- Disabling the Intel graphics adapter.
- Updating the Intel graphics driver from 27.20.100.9664 (2021) to 31.0.101.2145 (2026). Both failed the same way. A current driver is still worth having.
- Forcing HDMI-only output with `DisplaySwitch.exe /external`. Windows already sees the HDMI monitor as the one, primary display.
- Checking Winlogon `Shell`/`Userinit`. They were correct.

---

## How the cause was found (short version)

1. Every failing boot left **black-screen live dumps** in `C:\Windows\LiveKernelReports\WATCHDOG\` (`0x1A8 VIDEO_DXGKRNL_BLACK_SCREEN_LIVEDUMP`, P1=0x8 from a long power-button press). Safe Mode boots never did.
2. Event logs and the dumps showed Windows **fully running** behind the black screen: user signed in, Explorer, OneDrive and Edge started.
3. A sign-in probe ([`tools/probe.ps1`](tools/probe.ps1)) showed **one active display**: the HDMI monitor, primary, 1920×1080. There was no phantom internal screen.
4. The probe's power-state reading ([`tools/powerstate.ps1`](tools/powerstate.ps1)) showed **the lid switch reading "open" while Windows reported the console display and monitor as OFF**.
5. Facts that pointed to Windows 11 behaviour rather than drivers or hardware: Windows 10 and Linux work, a second identical laptop fails the same way, and it all worked before the screen was removed. Disabling the sensor hub fixed it on the first try.

The full investigation is in [`docs/investigation.md`](docs/investigation.md).

---

## Tools in this repo

| File | What it does |
|---|---|
| [`tools/probe.ps1`](tools/probe.ps1) | Logs active and available display paths (QueryDisplayConfig), screens and primary, monitor connection type, lid/display power states and sensor service status, plus a screenshot. Optionally runs `DisplaySwitch /external`. Writes to `C:\BlackScreenBackup\probe\`. Run it at sign-in (e.g. from `HKCU\...\Run`) to capture the state during a black screen. |
| [`tools/powerstate.ps1`](tools/powerstate.ps1) | Read-only. Prints the lid switch, console display, monitor power and session display states as Windows' power manager reports them. |
| [`evidence/`](evidence) | Probe output from a failing boot and from the fixed boot (lightly redacted). |

These scripts are diagnostic aids, provided as-is. Read them before running.

## Unrelated note

After the factory reset on this machine, the **audio controller** (`PCI\VEN_8086&DEV_02C8`, Intel Smart Sound) had no driver. Install Dell's audio drivers or use Windows Update. This has nothing to do with the black screen.
