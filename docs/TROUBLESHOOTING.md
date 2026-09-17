# Troubleshooting

## `struct.error: unpack requires a buffer of 12 bytes`

If the traceback ends at `GET_RAM_INFO` / `status()` after a prior DA session, check for a stale `.state` in the mtkclient root.

This toolkit automatically moves it aside before every preflight/unlock run. The verified failure occurred when mtkclient saw a valid `.state`, connected to a fresh/non-matching USB state, and attempted `daloader.reinit()` as though stage 2 were still alive.

Do not fix this by repeatedly flashing or erasing partitions.

## `Handshake failed, retrying...`

The phone is not in a clean BROM handshake window. On the verified Redmi Note 10 5G:

1. Unplug USB.
2. Hold Power long enough to leave any existing DA/preloader state.
3. With the phone off, hold Power + Volume Up + Volume Down.
4. Connect USB.
5. Release all buttons immediately on the Windows USB-connect sound.

Holding buttons too long may send the device to Fastboot, recovery, or normal boot instead.

## `MediaTek DA USB VCOM (Android) (COMx)` / `0E8D:2001`

This is a MediaTek DA/preloader-stage USB state, not normal Android or Fastboot. If a new mtkclient process cannot safely attach, power-cycle and start a fresh BROM session rather than assuming the old DA is reusable.
## UsbDk or MediaTek driver missing

`setup.ps1` checks for `UsbDk.sys` and for a MediaTek driver in the Windows DriverStore. Install both before attempting BROM mode.

The hardware-verified machine used UsbDk 1.0.22 and the MediaTek CDC/ACM driver package.

## `camellia` vs `camellian`

The verified `M2103K19G` identifies through Android as `camellian` / `camellian_eea`. Do not infer the exact regional device solely from a similarly named preloader file.

The successful current mtkclient flow did not require forcing a local preloader file; it dumped the device preloader from RAM after the BROM security bypass and completed DRAM/EMI setup successfully.

## Old batch file says `Bootloader unlocked` after an error

Do not trust it. Some older wrappers print a success line unconditionally after `mtk` exits, even when DA upload failed.

This toolkit deliberately validates upstream output and the process exit code before reporting success.

## Fastboot verification variable unavailable

Some bootloaders do not expose `fastboot getvar unlocked`. `verify.ps1` reports that as inconclusive rather than inventing a result. Keep the mtkclient unlock log and use the bootloader UI / ROM prerequisites as an additional verification path.
