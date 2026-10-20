# Investigation log

How the Windows 11 black screen on a Dell Inspiron 5591 2-in-1 with its screen removed was diagnosed. Everything was done from Safe Mode with Networking, one change at a time, with backups before each change. Dates and times are from a single day of work. Personal and network details are redacted; the monitor's EDID serial is shown as `<serial>`.

## Setup

- Dell Inspiron 5591 2-in-1, Core i5-10210U, Intel UHD Graphics (`PCI\VEN_8086&DEV_9B41&SUBSYS_095E1028`), BIOS 1.7.0.
- Lid assembly fully removed (panel, webcam, mic, cables). External monitor: Dell P2219H on HDMI.
- Windows 11 Pro 26H2 (build label 26300, binaries 10.0.26100.9711) after a Dell factory reset plus in-place upgrade.
- Symptom: normal boot → black screen with a movable cursor. BIOS, WinRE and Safe Mode display fine.
- Already tried before this log: Startup Repair, DISM, clean boot, uninstalling the quality update (it failed), boot logging.

## 1. Read-only diagnosis

| Check | Result |
|---|---|
| Winlogon `Shell` / `Userinit` | `explorer.exe` / `userinit.exe,`. Correct, no IFEO hijacks |
| Startup Repair log (SrtTrail.txt) | 0 root causes |
| DISM | No corruption |
| Intel GPU | Problem code 22 (disabled by an earlier test), driver 27.20.100.9664 (2021) |
| BCD | `safeboot network` set permanently (via msconfig, to keep Safe Mode with internet) |
| `ntbtlog.txt` | `BOOTLOG_NOT_LOADED` for the Intel driver is normal in Safe Mode sessions. Diffing a failing normal session against a Safe Mode session was more useful: the only display-path difference was `monitor.sys` |

**Live kernel reports** were the key evidence. Each failing normal boot left dumps in `C:\Windows\LiveKernelReports\`:

- `WATCHDOG\*.dmp`: bug check `0x1A8` **VIDEO_DXGKRNL_BLACK_SCREEN_LIVEDUMP**, P1=`0x8` (long power-button hold)
- `WATCHDOG4400\*.dmp`: `0x1B8` **VIDEO_MINIPORT_BLACK_SCREEN_LIVEDUMP**, P1=`0x8` (only while the Intel driver was loaded)

No Safe Mode boot ever produced one. The bug check code and parameters can be read from the dump header without a debugger: the 32-bit code is at offset `0x38`, P1 at `0x40`.

A per-boot timeline (Kernel-General 12, Kernel-Power 41, Winlogon 7001, Shell-Core 9705) showed that **in failing boots the user was signed in and Explorer processed its Run keys**. Windows was fully working behind the black screen.

## 2. Hypotheses tested and eliminated

| # | Hypothesis | Test | Result |
|---|---|---|---|
| H4 | Shell / Explorer failure (incl. the KB5127648 Explorer crash-loop) | Winlogon values, crash events, Shell-Core events | Ruled out. No crashes; Explorer ran |
| H1 | Stale display topology (a migrated "render-only" `MSNIL…1414_008D…` layout found in a dump) | Backed up and renamed `GraphicsDrivers\{Configuration,Connectivity,ScaleFactors}`, re-enabled the Intel GPU | Windows rebuilt a clean single-monitor layout. **Still black** |
| H2 | Old Intel driver (27.20.100.9664) | Installed Intel 31.0.101.2145 (Sept 2026, SHA512-verified) | Same blackbox tag `_1b8_<ver>_9b41_3_c0000001_…_Blackscreen` with both drivers. **Still black** |
| H5 | Phantom internal panel (eDP) made primary, HDMI left as an empty secondary | Sign-in probe: QueryDisplayConfig + WmiMonitorConnectionParams + `DisplaySwitch /external` | **Exactly one path**: HDMI (output technology 5), active, primary, 1920×1080. No eDP target. Ruled out. The user also noted the cursor appears in the centre of the HDMI screen, which matches |
| – | Display powered off by the lid | Read power settings (`RegisterPowerSettingNotification`) | In Safe Mode: lid open, display on (sensors not running) |

## 3. The decisive facts

From the user, during the investigation:

1. A **second identical laptop** with its screen removed has the same black screen.
2. **Linux and Windows 10 work fine** on the same hardware without the screen.
3. Windows 11 **worked before** the screen was removed.

So the trigger is the hardware removal, the GPU/HDMI path is fine, and the behaviour is specific to Windows 11. On a 2-in-1 the lid carries more than the panel: an accelerometer (base and lid accelerometers together give the hinge angle / posture), the lid-switch magnet, possibly an ambient light sensor, the camera and the touch digitizer. Windows 11 uses posture on convertibles; Windows 10 doesn't. Safe Mode doesn't start `SensorService` / `SensrSvc` / `SensorDataService`.

Sensor hardware on this model: **Intel(R) Integrated Sensor Solution** (`PCI\VEN_8086&DEV_02FC`) with five *HID Sensor Collection V2* devices, plus a *GPIO Laptop or Slate Indicator*.

## 4. The fix

1. In Safe Mode: back up the device's Enum key, then `pnputil /disable-device` the Intel Integrated Sensor Solution.
2. Normal boot → **desktop appears on HDMI**.

The probe log from the fixed boot ([`evidence/probe-fixed-boot.txt`](../evidence/probe-fixed-boot.txt)) shows the mechanism. Right after sign-in, Windows reported `LIDSWITCH_STATE=1` (open) but `CONSOLE_DISPLAY_STATE=0`, `MONITOR_POWER_ON=0` (display off: the normal sign-in screen timeout). Kernel-Power then logged:

- `506` entering Modern Standby, reason *Idle Timeout*
- `507` exiting Modern Standby, reason *Input Mouse*, and the desktop became visible

In the failing boots, input never woke the display and no 506/507 transitions were logged. With the sensor hub disabled, display power behaves normally again.

## 5. Lessons

- On a black screen with a cursor, check `C:\Windows\LiveKernelReports\` first. Windows records exactly these situations.
- Diff boot-log sessions rather than reading individual `BOOTLOG_NOT_LOADED` lines.
- Prove the screen layout, not the theory: a small probe at sign-in (QueryDisplayConfig + power settings) settled two hypotheses in one boot.
- Ask what *else* was removed with the hardware. Here it was sensors, not the panel, that mattered.

## 6. Follow-up: remaining devices

After the fix, Device Manager still showed three problems. Windows Update was searched from the running system (`Microsoft.Update.Session`, `Type='Driver'`).

| Device | ID | State | Resolution |
|---|---|---|---|
| I2C HID Device | `ACPI\CUST0000` | Code 10 | Touchscreen digitizer from the removed lid. **Disabled.** (The touchpad is `ACPI\DELL095E` and is fine.) |
| Multimedia Audio Controller | `PCI\VEN_8086&DEV_02C8` | Code 28 since the reset | Windows Update offers *Intel Corporation - System - 10.23.0.2672* (Intel Smart Sound) |
| FingerPrint | `USB\VID_27C6&PID_538C` | Code 28 | Windows Update offers *Goodix - Biometric - 3.1.34.500* |

Windows Update also offered the old *Intel Display 27.20.100.9664* driver and Dell extension/firmware packages. Skip those: the display package would downgrade the newer graphics driver.

After installing Intel SST and Goodix: *Intel(R) Smart Sound Technology (Intel(R) SST) Audio Controller*, *Realtek(R) Audio*, *Intel(R) Display Audio* and *Goodix fingerprint* were OK. Two new child devices then needed drivers: *Intel High Definition DSP* (`INTELAUDIO\DSP_CTLR_DEV_02C8&VEN_8086&DEV_0222`, the digital-mic DSP; Windows Update offers Intel System 10.23.2672.2) and *Waves Audio Effects Component* (`APO\VEN_WAVES&AID_MA8MV5`; Windows Update offers Waves 5.2.0.307). Windows Update also offered the Realtek SoftwareComponent 11.0.6000.792.

After the DSP driver (it shows as *Intel(R) SST OED*) and Waves, two more children of the DSP appeared: *Digital microphone device* (`…LINKTYPE_02&DEVTYPE_01&VEN_8086&DEV_AE20`) and *Detection Verification* (`{DD8E82AE-…}\DetectionVerification`). Both serve the built-in mic array that left with the lid, so they were **disabled** rather than given drivers, to avoid a phantom default microphone.

**Final verified state:** no device errors. Exactly four devices are disabled (code 22), all intentionally: Intel Integrated Sensor Solution (the fix), touchscreen I2C HID (`ACPI\CUST0000`), Digital microphone device and Detection Verification. Graphics, Realtek audio, Intel Display Audio, Intel SST and the Goodix fingerprint reader are all OK.
