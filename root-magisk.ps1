[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Manifest,
    [string]$ArtifactsRoot,
    [string]$AdbPath,
    [string]$FastbootPath,
    [switch]$UseLatestStableMetadata
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $Manifest){$Manifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
if(-not $ArtifactsRoot){$ArtifactsRoot=$PSScriptRoot}
$m=Read-WorkflowManifest $Manifest
if($WhatIfPreference){Write-Host 'WHATIF: verify exact boot/Magisk hashes and profile; official boot_patch.sh on device; validate patched image; flash active boot slot only; reboot/verify Magisk';return}
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $ArtifactsRoot
$fastboot=Resolve-AndroidTool -Name fastboot -ExplicitPath $FastbootPath -ArtifactsRoot $ArtifactsRoot
$boot=Join-Path $ArtifactsRoot $m.artifacts.boot.file
$apk=Join-Path $ArtifactsRoot $m.artifacts.magisk.file
Assert-ArtifactHash $boot $m.artifacts.boot.sha256 | Out-Null
Assert-ArtifactHash $apk $m.artifacts.magisk.sha256 | Out-Null
if(-not(Test-AndroidBootImage $boot)){throw 'Source boot image is invalid'}
if($UseLatestStableMetadata){
    $latest=Get-LatestStableMagiskAsset
    if($latest.Sha256 -ne $m.artifacts.magisk.sha256){throw 'Latest stable Magisk differs from pinned manifest; review explicitly.'}
}
$id=Get-AdbIdentity $adb
if(-not(Test-DeviceProfile -Profile $m.profile -Device $id -Phase PostRom)){throw 'Connected Android identity does not match verified post-ROM profile'}
$r=Invoke-NativeChecked $adb @('install','-r',$apk); Write-Host $r.Output
$work='/data/local/tmp/aeiou-magisk-patch'
Invoke-NativeChecked $adb @('shell',"rm -rf $work && mkdir -p $work") | Out-Null
$extract=Join-Path ([IO.Path]::GetTempPath()) ('aeiou-magisk-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $extract | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $map=@{
            'assets/boot_patch.sh'='boot_patch.sh'
            'assets/util_functions.sh'='util_functions.sh'
            'assets/stub.apk'='stub.apk'
            'lib/arm64-v8a/libinit-ld.so'='init-ld'
            'lib/arm64-v8a/libmagisk.so'='magisk'
            'lib/arm64-v8a/libmagiskboot.so'='magiskboot'
            'lib/arm64-v8a/libmagiskinit.so'='magiskinit'
        }
        foreach($src in $map.Keys){
            $entry=$zip.GetEntry($src)
            if(-not $entry){throw "Magisk APK missing $src"}
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $extract $map[$src]),$true)
        }
    } finally {$zip.Dispose()}
    Invoke-NativeChecked $adb @('push',$boot,"$work/boot.img") | Out-Null
    Get-ChildItem $extract -File | ForEach-Object {
        Invoke-NativeChecked $adb @('push',$_.FullName,"$work/$($_.Name)") | Out-Null
    }
    $patch="cd $work && chmod 755 boot_patch.sh util_functions.sh init-ld magisk magiskboot magiskinit && chmod 644 stub.apk boot.img && BOOTMODE=true KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false RECOVERYMODE=false sh ./boot_patch.sh ./boot.img"
    $r=Invoke-NativeChecked $adb @('shell',$patch); Write-Host $r.Output
    $patched=Join-Path $ArtifactsRoot ('magisk_patched-'+$m.artifacts.magisk.version+'-'+[IO.Path]::GetFileNameWithoutExtension($m.artifacts.boot.file)+'.img')
    Invoke-NativeChecked $adb @('pull',"$work/new-boot.img",$patched) | Out-Null
    if(-not(Test-AndroidBootImage $patched)){throw 'Patched boot image failed Android boot magic validation'}
    $sourceHash=Get-Sha256 $boot
    $patchedHash=Get-Sha256 $patched
    if($sourceHash -eq $patchedHash){throw 'Patched boot image is byte-identical to source'}
    Write-Host "Source boot SHA256:  $sourceHash"
    Write-Host "Patched boot SHA256: $patchedHash"
    & $adb reboot bootloader
    Start-Sleep 3
    # Explicit safety gate equivalent to: fastboot getvar unlocked
    if((Get-FastbootVariable $fastboot 'unlocked') -ne 'yes'){throw 'Bootloader is not unlocked'}
    $fbSlot=Normalize-Slot (Get-FastbootVariable $fastboot 'current-slot')
    if($fbSlot -ne $id.slot){throw "Slot changed unexpectedly: Android=$($id.slot) Fastboot=$fbSlot"}
    $partition=Get-BootPartitionName $fbSlot
    $r=Invoke-NativeChecked $fastboot @('flash',$partition,$patched); Write-Host $r.Output
    Invoke-NativeChecked $fastboot @('reboot') | Out-Null
    Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 240 | Out-Null
    $selinux=((& $adb shell getenforce) | Out-String).Trim()
    $proc=((& $adb shell 'ps -A | grep -i magiskd') | Out-String)
    if($proc -notmatch '\bmagiskd\b'){throw 'Magisk daemon is not running after reboot'}
    if($selinux -ne 'Enforcing'){throw "SELinux is not Enforcing: $selinux"}
    Write-Host "MAGISK BOOT VERIFIED: slot=$fbSlot SELinux=$selinux"
    Write-Host 'First su request can require one-time approval in the Magisk app.'
} finally {
    if(Test-Path $extract){Remove-Item $extract -Recurse -Force}
}