# Optional post-install app bundle

The verified Redmi Note 10 5G workflow can optionally continue after `postflight` and install a pinned utility/security bundle over USB ADB.

## Enable it

Run the normal end-to-end workflow with the additional switch:

```powershell
.\install-all.ps1 -Manifest .\config\verified-camellia.json `
  -ArtifactsRoot 'C:\path\to\verified-artifacts' `
  -AcknowledgeDataLoss `
  -InstallOptionalApps
```

`-InstallOptionalApps` extends the default end stage from `postflight` to `optional-apps`. The stage can also be run by itself:

```powershell
.\install-all.ps1 -FromStage optional-apps -InstallOptionalApps
```

Use `-WhatIf` to print the complete plan without downloading files, requiring ADB hardware, or changing the device.

## Pinned bundle

The manifest pins the exact version, download URL, SHA-256, Android package name, and target architecture where applicable.

- Obtainium 1.6.17 (`dev.imranr.obtainium`)
- Neo Backup 8.3.18 (`com.machiav3lli.backup`)
- Termux 0.118.3 ARM64 GitHub build (`com.termux`)
- App Manager 4.1.1 (`io.github.muntashirakon.AppManager`)
- Rethink DNS + Firewall 0.5.6 ARM64 (`com.celzero.bravedns`)
- Proton VPN 5.20.21.0 (`ch.protonvpn.android`)
- DuressKeyboard 7.4 (`duress.keyboard`)
- scrcpy 4.1 Win64 on the PC

Large APK/ZIP files are downloaded to the artifact directory and are not committed to Git.

## Verification and offline-device behavior

The PC downloads every artifact. The phone does not need Wi-Fi or mobile data for installation, and this stage does not enable or modify Wi-Fi, mobile data, airplane mode, or VPN state.

Before Android changes are made, the script verifies the connected device against the post-ROM MT6833 profile and requires `arm64-v8a`. Every downloaded file must match its pinned SHA-256. After each APK install, `dumpsys package` must report the pinned package version or the stage fails.

scrcpy is hash-verified before extraction and its executable must report the pinned version before the stage completes.

## Manual setup boundaries

Some installed applications require user-owned secrets or privileged consent after installation:

- Neo Backup and App Manager may request Magisk superuser access when their root features are first used.
- Proton VPN requires network access when a tunnel is actually used. Installation itself does not require phone-side internet.
- Rethink and Proton VPN both normally use Android `VpnService`, so they cannot both own the active VPN slot simultaneously. Installing both is supported; running both VPN modes at the same time is not.
- DuressKeyboard is installed with Android's documented low-target-SDK bypass required by the upstream project, but the automation intentionally does **not** activate Device Admin, select it as the default IME, alter lock credentials, configure a duress secret, set failed-password wipe limits, or arm any wipe trigger. Those security-sensitive steps remain manual.

## Standalone installer

Advanced users can run the stage entrypoint directly:

```powershell
.\optional-apps-install.ps1 `
  -Manifest .\config\verified-camellia.json `
  -ArtifactsRoot .\artifacts\optional-apps `
  -AdbPath 'C:\path\to\adb.exe'
```

The installer is idempotent at the artifact level: existing downloads are reused only when their SHA-256 still matches the manifest. APK installation itself is repeated from the verified artifact so Android signature checks remain authoritative.
