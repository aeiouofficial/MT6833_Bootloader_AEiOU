# Verified device record

**Verification date:** 2026-09-17

| Field | Verified value |
|---|---|
| Model | Xiaomi Redmi Note 10 5G (`M2103K19G`) |
| Codename | `camellian` |
| Regional product | `camellian_eea` |
| SoC | MediaTek MT6833 / Dimensity 700 5G |
| Firmware | MIUI `V14.0.4.0.TKSEUXM` |
| Storage model | `MT128GASAO4U21` |
| mtkclient | 2.1.4 |
| mtkclient commit | `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3` |
| Host OS | Windows x64 |
| UsbDk | 1.0.22 |

## Hardware evidence

The successful session reached all of the following milestones:

- `BROM mode detected.`
- MT6833 Kamakiri payload accepted
- XFlash stage 1 accepted
- `DRAM setup passed.`
- XFlash stage 2 accepted
- UFS model enumerated correctly
- DA extensions loaded
- GPT enumerated including `seccfg`
- V4 lock state parsed
- upstream mtkclient reported `Device is already unlocked`
- process exited with code `0`
## Privacy note

The public record intentionally omits ME_ID, SOC_ID, Android serial number, UFS CID/serial, and other device-unique identifiers. They are not required to reproduce the method.

## Result interpretation

The verified run reported `Device is already unlocked` because the preceding successful session had already changed the bootloader state. That message is emitted by upstream mtkclient after parsing the current `seccfg` lock state and is accepted by this wrapper only together with exit code `0` and MT6833 evidence.
