[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [string]$AdbPath,
    [string]$FastbootPath,
    [switch]$AcknowledgeProductFlash
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $AcknowledgeProductFlash){throw 'Refusing product rollback without -AcknowledgeProductFlash'}
$buildManifest=Join-Path $CaptureRoot 'golden-product-manifest.json'
if(-not(Test-Path $buildManifest -PathType Leaf)){throw "Golden product manifest missing: $buildManifest"}
$m=Get-Content -LiteralPath $buildManifest -Raw|ConvertFrom-Json
$source=Join-Path $CaptureRoot ([string]$m.sourceProduct.file)
Assert-ArtifactHash -Path $source -ExpectedSha256 ([string]$m.sourceProduct.sha256)|Out-Null
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $PSScriptRoot
$fastboot=Resolve-AndroidTool -Name fastboot -ExplicitPath $FastbootPath -ArtifactsRoot $PSScriptRoot
$state=((& $adb get-state 2>$null)|Out-String).Trim()
if($state -ne 'device'){throw "ADB device required for rollback entry: $state"}
$slot=Normalize-Slot ((& $adb shell getprop ro.boot.slot_suffix 2>$null|Out-String).Trim())
if($slot -ne [string]$m.device.slot){throw "Rollback slot mismatch. Captured=$($m.device.slot) Current=$slot"}
$partition="product_$slot"
if($WhatIfPreference){Write-Host "WHATIF: reboot to fastbootd and restore $partition from $source with 64M sparse chunks";return}
Invoke-NativeChecked -FilePath $adb -ArgumentList @('reboot','fastboot')|Out-Null
$stop=[DateTime]::UtcNow.AddSeconds(90)
do{$dev=((& $fastboot devices 2>$null)|Out-String).Trim();if($dev){break};Start-Sleep 1}while([DateTime]::UtcNow -lt $stop)
if(-not $dev){throw 'Timed out waiting for fastbootd'}
if((Get-FastbootVariable -Fastboot $fastboot -Name 'is-userspace') -ne 'yes'){throw 'Rollback target is not userspace fastbootd'}
$fbSlot=Normalize-Slot (Get-FastbootVariable -Fastboot $fastboot -Name 'current-slot')
if($fbSlot -ne $slot){throw "Fastboot slot mismatch. Android=$slot Fastboot=$fbSlot"}
$r=Invoke-NativeChecked -FilePath $fastboot -ArgumentList @('-S','64M','flash',$partition,$source)
Write-Host $r.Output
Invoke-NativeChecked -FilePath $fastboot -ArgumentList @('reboot')|Out-Null
Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 240|Out-Null
Write-Host "GOLDEN PRODUCT ROLLBACK VERIFIED: partition=$partition sourceSha256=$($m.sourceProduct.sha256)"
