[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Manifest,
    [string]$ArtifactsRoot,
    [string]$AdbPath,
    [string]$FastbootPath,
    [switch]$AcknowledgeDataLoss,
    [switch]$SkipFormatPrompt
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $Manifest){$Manifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
if(-not $ArtifactsRoot){$ArtifactsRoot=$PSScriptRoot}
$m=Read-WorkflowManifest $Manifest
if(-not $AcknowledgeDataLoss){throw 'ROM installation requires -AcknowledgeDataLoss because factory reset destroys user data.'}
if($WhatIfPreference){Write-Host 'WHATIF: verify hashes/profile/unlocked slot; flash exact boot; reboot recovery; wait for format/sideload; sideload exact ROM';return}
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $ArtifactsRoot
$fastboot=Resolve-AndroidTool -Name fastboot -ExplicitPath $FastbootPath -ArtifactsRoot $ArtifactsRoot
$boot=Join-Path $ArtifactsRoot $m.artifacts.boot.file
$rom=Join-Path $ArtifactsRoot $m.artifacts.rom.file
Assert-ArtifactHash $boot $m.artifacts.boot.sha256 | Out-Null
Assert-ArtifactHash $rom $m.artifacts.rom.sha256 | Out-Null
if(-not(Test-AndroidBootImage $boot)){throw 'boot.img is not a valid Android boot image'}
$identity=Get-AdbIdentity $adb
if(-not(Test-DeviceProfile -Profile $m.profile -Device $identity -Phase PreRom)){throw 'Device does not match verified pre-ROM profile'}
& $adb reboot bootloader
Start-Sleep 3
# Safety gate equivalent to: fastboot getvar unlocked
if((Get-FastbootVariable $fastboot 'unlocked') -ne 'yes'){throw 'Bootloader is not unlocked'}
$slot=Normalize-Slot (Get-FastbootVariable $fastboot 'current-slot')
$partition=Get-BootPartitionName $slot
$r=Invoke-NativeChecked $fastboot @('flash',$partition,$boot); Write-Host $r.Output
$r=Invoke-NativeChecked $fastboot @('reboot','recovery'); Write-Host $r.Output
if(-not $SkipFormatPrompt){
    Write-Host 'RECOVERY ACTION REQUIRED: Factory Reset -> Format data / factory reset -> confirm.'
    Write-Host 'Then select Apply update -> Apply from ADB. The script continues only in sideload mode.'
}
Wait-AdbState -Adb $adb -State sideload -TimeoutSeconds 900 | Out-Null
$r=Invoke-NativeChecked $adb @('sideload',$rom) -AllowFailure
Write-Host $r.Output
if(-not(Test-SideloadEvidence -Output $r.Output -ExitCode $r.ExitCode)){throw "ROM sideload failed or incomplete. Exit=$($r.ExitCode)"}
Write-Host 'ROM SIDELOAD VERIFIED. Reboot recovery before installing GApps.'