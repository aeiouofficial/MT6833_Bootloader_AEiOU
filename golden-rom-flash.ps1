[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [string]$AdbPath,
    [string]$FastbootPath,
    [string]$DeviceManifest,
    [switch]$AcknowledgeProductFlash
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $DeviceManifest){$DeviceManifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
$deviceConfig=Read-WorkflowManifest -Path $DeviceManifest
$buildManifest=Join-Path $CaptureRoot 'golden-product-manifest.json'
if(-not(Test-Path $buildManifest -PathType Leaf)){throw "Golden product manifest missing: $buildManifest"}
$m=Get-Content -LiteralPath $buildManifest -Raw|ConvertFrom-Json
$candidate=Join-Path $CaptureRoot ([string]$m.goldenProduct.file)
$source=Join-Path $CaptureRoot ([string]$m.sourceProduct.file)
Assert-ArtifactHash -Path $candidate -ExpectedSha256 ([string]$m.goldenProduct.sha256)|Out-Null
Assert-ArtifactHash -Path $source -ExpectedSha256 ([string]$m.sourceProduct.sha256)|Out-Null
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $PSScriptRoot
$fastboot=Resolve-AndroidTool -Name fastboot -ExplicitPath $FastbootPath -ArtifactsRoot $PSScriptRoot
Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 180|Out-Null
$id=Get-AdbIdentity -Adb $adb
if(-not(Test-DeviceProfile -Profile $deviceConfig.profile -Device $id -Phase PostRom)){throw 'Connected device does not match verified post-ROM camellia profile'}
$slot=Normalize-Slot $id.slot
if($slot -ne [string]$m.device.slot){throw "Slot differs from captured golden image. Captured=$($m.device.slot) Current=$slot"}
$verifiedBootState=((& $adb shell getprop ro.boot.verifiedbootstate 2>$null)|Out-String).Trim()
$verityMode=((& $adb shell getprop ro.boot.veritymode 2>$null)|Out-String).Trim()
if($verifiedBootState -ne 'orange'){throw "Golden product flash requires unlocked/orange boot state, got: $verifiedBootState"}
if($verityMode -ne 'disabled'){throw "Golden product flash requires current veritymode=disabled, got: $verityMode"}
$rootId=((& $adb shell su -c id 2>$null)|Out-String).Trim()
if($rootId -notmatch '(?i)uid=0\(root\)'){throw "Root preflight failed: $rootId"}
$partition="product_$slot"
if($WhatIfPreference){Write-Host "WHATIF: verify and flash only $partition with $candidate using 64M sparse chunks; keep $source as rollback; reboot and verify eight product apps";return}
if(-not $AcknowledgeProductFlash){throw 'Refusing product flash without -AcknowledgeProductFlash'}
function Wait-FastbootDevice([int]$TimeoutSeconds=90){
    $stop=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do { $txt=((& $fastboot devices 2>$null)|Out-String); if($txt -match '(?m)^\S+\s+fastboot\s*$'){return $true}; Start-Sleep 1 } while([DateTime]::UtcNow -lt $stop)
    throw 'Timed out waiting for fastboot device'
}
function Enter-Fastbootd {
    Invoke-NativeChecked -FilePath $adb -ArgumentList @('reboot','fastboot')|Out-Null
    Wait-FastbootDevice|Out-Null
    $userspace=Get-FastbootVariable -Fastboot $fastboot -Name 'is-userspace'
    if($userspace -ne 'yes'){throw "Expected userspace fastbootd, got is-userspace=$userspace"}
    $fbSlot=Normalize-Slot (Get-FastbootVariable -Fastboot $fastboot -Name 'current-slot')
    if($fbSlot -ne $slot){throw "Fastboot slot changed unexpectedly. Android=$slot Fastboot=$fbSlot"}
}
function Wait-ForRollbackTransport([int]$TimeoutSeconds=120){
    $stop=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $fb=((& $fastboot devices 2>$null)|Out-String).Trim()
        if($fb){
            $userspace=Get-FastbootVariable -Fastboot $fastboot -Name 'is-userspace'
            if($userspace -eq 'yes'){return}
        }
        $adbState=((& $adb get-state 2>$null)|Out-String).Trim()
        if($adbState -eq 'device'){
            $boot=((& $adb shell getprop sys.boot_completed 2>$null)|Out-String).Trim()
            if($boot -eq '1'){Enter-Fastbootd;return}
        }
        Start-Sleep 2
    } while([DateTime]::UtcNow -lt $stop)
    throw 'Timed out waiting for Android or fastbootd transport for rollback'
}
function Invoke-GoldenPostflight {
    Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 240|Out-Null
    $selinux=((& $adb shell getenforce 2>$null)|Out-String).Trim()
    if($selinux -ne 'Enforcing'){throw "SELinux is not Enforcing: $selinux"}
    $proc=((& $adb shell 'ps -A | grep -i magiskd' 2>$null)|Out-String)
    if($proc -notmatch '\bmagiskd\b'){throw 'magiskd is not running'}
    $su=((& $adb shell su -c id 2>$null)|Out-String).Trim()
    if($su -notmatch '(?i)uid=0\(root\)'){throw "Root verification failed: $su"}
    foreach($app in @($m.apps)){
        $remote="/product/app/$($app.systemDir)/$($app.apkName)"
        $exists=((& $adb shell "test -f $remote && echo PRESENT" 2>$null)|Out-String).Trim()
        if($exists -ne 'PRESENT'){throw "Golden product APK missing after reboot: $remote"}
        $remoteHash=((& $adb shell "sha256sum $remote" 2>$null)|Out-String).Trim()
        if($remoteHash -notmatch ('^'+[regex]::Escape([string]$app.sha256)+'\s')){throw "Golden product APK hash mismatch after reboot: $remote"}
        $dump=((& $adb shell dumpsys package ([string]$app.package) 2>$null)|Out-String)
        if($dump -notmatch '(?m)^\s*versionName=([^\r\n]+)\s*$'){throw "Package missing after golden flash: $($app.package)"}
        if($Matches[1].Trim() -ne [string]$app.version){throw "Package version mismatch after golden flash: $($app.package) expected=$($app.version) actual=$($Matches[1].Trim())"}
    }
}
$flashAttempted=$false
$flashed=$false
try {
    Enter-Fastbootd
    $sizeHex=Get-FastbootVariable -Fastboot $fastboot -Name ("partition-size:$partition")
    if($sizeHex -match '^0x([0-9a-fA-F]+)$'){$partitionBytes=[Convert]::ToInt64($Matches[1],16);if($partitionBytes -ne (Get-Item $candidate).Length){throw "Partition/candidate size mismatch. Partition=$partitionBytes Candidate=$((Get-Item $candidate).Length)"}}
    $flashAttempted=$true
    $r=Invoke-NativeChecked -FilePath $fastboot -ArgumentList @('-S','64M','flash',$partition,$candidate); Write-Host $r.Output
    $flashed=$true
    Invoke-NativeChecked -FilePath $fastboot -ArgumentList @('reboot')|Out-Null
    Invoke-GoldenPostflight
    Write-Host "GOLDEN PRODUCT FLASH VERIFIED: partition=$partition sha256=$($m.goldenProduct.sha256)"
} catch {
    $failure=$_
    if($flashAttempted){
        Write-Warning "Golden product write/postflight failed; attempting product rollback from captured source image: $($failure.Exception.Message)"
        try {
            Wait-ForRollbackTransport -TimeoutSeconds 120
            $userspace=Get-FastbootVariable -Fastboot $fastboot -Name 'is-userspace'
            if($userspace -ne 'yes'){throw 'Rollback device is not in fastbootd'}
            $rollback=Invoke-NativeChecked -FilePath $fastboot -ArgumentList @('-S','64M','flash',$partition,$source)
            Write-Host $rollback.Output
            Invoke-NativeChecked -FilePath $fastboot -ArgumentList @('reboot')|Out-Null
            Write-Warning 'Original captured product image was flashed back. Verify Android boot manually.'
        } catch { Write-Warning "Automatic rollback could not complete: $($_.Exception.Message). Rollback artifact remains at $source" }
    }
    throw $failure
}
