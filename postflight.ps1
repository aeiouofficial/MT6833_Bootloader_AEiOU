[CmdletBinding()]
param(
    [string]$ArtifactsRoot,
    [string]$AdbPath,
    [string]$OutputJson
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $ArtifactsRoot){$ArtifactsRoot=$PSScriptRoot}
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $ArtifactsRoot
Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 60 | Out-Null
$results=[ordered]@{}
function Add-Check([string]$Name,[bool]$Pass,[string]$Evidence){
    $script:results[$Name]=[ordered]@{status=$(if($Pass){'PASS'}else{'FAIL'});evidence=$Evidence.Trim()}
}
function Shell([string]$Command){return ((& $adb shell $Command 2>&1)|Out-String).Trim()}
$boot=Shell 'getprop sys.boot_completed'
$selinux=Shell 'getenforce'
$crypto=Shell 'getprop ro.crypto.state'
$slot=Shell 'getprop ro.boot.slot_suffix'
$avb=Shell 'getprop ro.boot.vbmeta.device_state'
Add-Check 'boot' ($boot -eq '1') "sys.boot_completed=$boot"
Add-Check 'selinux' ($selinux -eq 'Enforcing') $selinux
Add-Check 'encryption' ($crypto -eq 'encrypted') "ro.crypto.state=$crypto"
Add-Check 'slot' ($slot -match '^_[ab]$') "slot=$slot avb=$avb"
$gms=Shell 'pm path com.google.android.gms; pm path com.android.vending; pm path com.google.android.gsf'
Add-Check 'gapps' (($gms -match 'GmsCore') -and ($gms -match 'Phonesky')) $gms
$battery=Shell 'dumpsys battery'
Add-Check 'battery' ($battery -match '(?m)^\s*health:\s*2\s*$') ($battery -split "`n" | Select-String 'level:|health:|USB powered:|temperature:' | Out-String)
$camera=Shell 'dumpsys media.camera'
$cameraCountMatch=[regex]::Match($camera,'Number of camera devices:\s*(\d+)')
$cameraOk=$cameraCountMatch.Success -and ([int]$cameraCountMatch.Groups[1].Value -gt 0) -and ($camera -match 'Camera error traces \(0\)')
Add-Check 'camera' $cameraOk (($camera -split "`n" | Select-String 'Number of camera devices|Camera error traces|Fatal' | Select-Object -First 20 | Out-String))
$sensors=Shell 'dumpsys sensorservice'
Add-Check 'sensors' ($sensors -match '(?i)accelerometer' -and $sensors -match '(?i)gyroscope') (($sensors -split "`n" | Select-String 'accelerometer|gyroscope|proximity|light' | Select-Object -First 20 | Out-String))
$nfc=Shell 'dumpsys nfc'
Add-Check 'nfc' ($nfc -match 'mState=on|mState=off') (($nfc -split "`n" | Select-String 'mState=|mEnableHostRouting' | Select-Object -First 10 | Out-String))
$wifi=Shell 'cmd wifi status'
Add-Check 'wifi-service' ($wifi -match 'Wifi is (enabled|disabled)') (($wifi -split "`n" | Select-Object -First 8) -join "`n")
$bt=Shell 'dumpsys bluetooth_manager'
Add-Check 'bluetooth-service' ($bt -match 'Bluetooth Status') (($bt -split "`n" | Select-Object -First 12) -join "`n")
$audio=Shell 'dumpsys media.audio_flinger'
Add-Check 'audio' ($audio -match 'Output thread' -and $audio -notmatch 'writeErrors=[1-9]') (($audio -split "`n" | Select-String 'Output thread|writeErrors=|underruns=' | Select-Object -First 20 | Out-String))
$thermal=Shell 'dumpsys thermalservice'
Add-Check 'thermal' ($thermal -match '(?i)Thermal Status.*0|status.*NONE') (($thermal -split "`n" | Select-Object -First 20) -join "`n")
$storage=Shell 'f=/data/local/tmp/aeiou-postflight-rw; echo AEIOU > $f && cat $f && rm $f'
Add-Check 'storage-rw' ($storage -match 'AEIOU') $storage
$usb=Shell 'dumpsys usb'
Add-Check 'usb' ($usb -match 'connected=true' -and $usb -match 'usb_data_status=enabled') (($usb -split "`n" | Select-String 'connected=|configured=|usb_data_status=' | Select-Object -First 15 | Out-String))
$radio=Shell 'getprop gsm.sim.state; getprop gsm.network.type'
Add-Check 'radio-stack' ($radio -match 'LOADED|ABSENT') $radio
$magisk=Shell 'ps -A | grep -i magiskd'
Add-Check 'magisk-daemon' ($magisk -match '\bmagiskd\b') $magisk
$rootId=Shell 'su -c id'
Add-Check 'root-su' ($rootId -match 'uid=0\(root\)') $rootId
$crash=Shell 'logcat -b crash -d -v brief'
Add-Check 'crash-buffer' ($crash -notmatch 'FATAL EXCEPTION|Fatal signal|ANR in ') ($(if($crash){$crash}else{'empty'}))
$failed=@($results.GetEnumerator() | Where-Object {$_.Value.status -eq 'FAIL'})
$report=[ordered]@{timestamp=(Get-Date).ToString('o');checks=$results;summary=[ordered]@{pass=$results.Count-$failed.Count;fail=$failed.Count}}
$json=$report | ConvertTo-Json -Depth 8
if($OutputJson){$json | Set-Content -LiteralPath $OutputJson -Encoding UTF8}
$results.GetEnumerator() | ForEach-Object {Write-Host ("{0,-20} {1}" -f $_.Key,$_.Value.status)}
Write-Host "POSTFLIGHT: PASS=$($report.summary.pass) FAIL=$($report.summary.fail)"
if($failed.Count -gt 0){throw "Postflight has $($failed.Count) blocking failure(s)."}
return [pscustomobject]$report
