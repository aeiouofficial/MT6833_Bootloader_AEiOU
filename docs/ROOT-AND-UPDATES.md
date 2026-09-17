# Root, updates, and recovery

## Verified root path

The verified LineageOS 23.2 / Android 16 target uses an Android boot image header v2 with a real ramdisk, A/B `boot_a` / `boot_b`, `vendor_boot_a` / `vendor_boot_b`, and no `init_boot` partition. Recovery is carried by `boot.img` rather than a separate recovery partition.

For this profile, root is implemented by patching the **exact `boot.img` belonging to the installed ROM build** with the official stable Magisk patcher. The source image is never overwritten.

`root-magisk.ps1` performs these gates:

1. Validate the pinned source boot SHA-256.
2. Validate the pinned official Magisk APK SHA-256.
3. Verify the connected post-ROM device profile.
4. Extract `boot_patch.sh` and the required ARM64 Magisk binaries from the official APK.
5. Run the official patcher on the target Android device with verity/encryption preservation enabled.
6. Pull the generated image and verify Android boot magic plus a different SHA-256 from the source.
7. Reboot Fastboot, require `unlocked: yes`, and require the Fastboot slot to equal the Android slot.
8. Flash only the matching `boot_<slot>`, reboot, require Android boot completion, `magiskd`, and SELinux `Enforcing`.

The first `su` request can still require one explicit approval in the Magisk app. The toolkit never bypasses the device PIN or that authorization prompt.
## LineageOS updates

A ROM update can replace the active boot partition and therefore remove Magisk. Do not reuse an old patched image against a new ROM build.

For each ROM update:

1. Obtain the `boot.img` from that exact new build.
2. Update the manifest filename and SHA-256 only after verification.
3. Patch that new source image with the selected official Magisk release.
4. Flash only the slot that the updated Android system reports as active.
5. Run `postflight.ps1` again.

Keep the untouched source `boot.img` for every installed ROM build. If a Magisk-patched boot image fails to boot, the recovery path is to return to Fastboot and flash the matching untouched source boot image back to that slot.

## What the toolkit deliberately does not do

- It does not relock an unlocked bootloader.
- It does not weaken verified-boot settings just to obtain root.
- It does not use a boot image from a different ROM release.
- It does not automate PIN entry or Superuser consent.
- It does not commit generated patched images, ROM ZIPs, GApps ZIPs, or Magisk APKs to Git.
## Android 16 credential-unlock boundary

On the verified LineageOS 23.2 / Android 16 build, Magisk's normal `MainActivity` is not resolvable before the first credential unlock after reboot. `magiskd` can already be running as root at that point, but the Manager UI remains behind Android Direct Boot. Unlock the device normally once before opening Magisk or approving Superuser policy.

For ADB automation, the verified Shell policy appears as `[SharedUID] Shell` / `com.android.shell` in Magisk's Superuser tab. `postflight.ps1` now requires an actual `su -c id` result containing `uid=0(root)`; a running daemon alone is not accepted as complete root verification.
