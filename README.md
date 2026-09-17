# MT6833 Bootloader AEiOU

A Windows-first, reproducible bootloader-unlock workflow for MediaTek MT6833 / Dimensity 700 devices using the actively maintained upstream [bkerler/mtkclient](https://github.com/bkerler/mtkclient).

This repository contains **wrapper scripts, safety checks, tests, and documentation**. It does not vendor or redistribute mtkclient.

## Verified hardware

Hardware-tested on 2026-09-17:

- Xiaomi Redmi Note 10 5G (`M2103K19G`)
- Device codename: `camellian`
- EEA product: `camellian_eea`
- SoC: MediaTek MT6833 / Dimensity 700 5G
- UFS model: `MT128GASAO4U21`
- Tested firmware: MIUI `V14.0.4.0.TKSEUXM`
- mtkclient: `2.1.4`, commit `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`

Other MT6833 devices may behave differently. Do not assume compatibility solely from the chipset name.

## Important warning

Bootloader unlocking changes the device security state. Depending on device/firmware, unlocking can trigger data loss or make a device unbootable if interrupted or misused. Back up important data first. Use this only on devices you own or are authorized to modify.
## Quick start

Open an **Administrator PowerShell** in this repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

Install UsbDk and a MediaTek CDC/ACM driver if `setup.ps1` reports either missing.

Recommended read-only hardware gate:

```powershell
.\preflight.ps1
```

For BROM entry on the verified Redmi Note 10 5G:

1. Disconnect USB and power the phone fully off.
2. Hold **Power + Volume Up + Volume Down**.
3. Connect USB.
4. On the Windows USB-connect sound, immediately release all three buttons.
5. Press nothing while mtkclient runs.

`preflight.ps1` must reach BROM, DRAM setup, DA stage 2, and GPT enumeration before it reports PASS.
Then power-cycle the phone and run a fresh unlock session:

```powershell
.\unlock.ps1
```

The wrapper only accepts success when mtkclient exits with code `0` **and** emits explicit upstream evidence such as `Device is already unlocked` or `Successfully wrote seccfg.`. It never trusts an unconditional wrapper message.

Afterward, reboot to Fastboot (Power + Volume Down) and verify:

```powershell
.\verify.ps1
```

If your bootloader exposes the variable, the expected result is `unlocked: yes`.

## Why this wrapper exists

A stale mtkclient `.state` file can make a new process treat a fresh connection as an existing DA session. On MT6833 this reproduced as:

```text
GET_RAM_INFO
struct.error: unpack requires a buffer of 12 bytes
```

This toolkit backs up stale state before every hardware session and never assumes a DA session survives across separate mtkclient processes.

## More documentation

- [Technical flow](docs/TECHNICAL.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Verified device record](docs/VERIFIED-DEVICE.md)
- [Upstream/credits](docs/CREDITS.md)

## License

AEiOU wrapper code: MIT. Upstream mtkclient is GPL-3.0 and remains subject to its own license.
