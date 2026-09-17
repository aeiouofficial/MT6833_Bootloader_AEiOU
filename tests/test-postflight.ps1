$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent;$p=Join-Path $root 'postflight.ps1';if(-not(Test-Path $p)){throw 'postflight.ps1 missing'};$t=Get-Content $p -Raw
foreach($token in 'sys.boot_completed','getenforce','ro.crypto.state','com.google.android.gms','dumpsys battery','dumpsys media.camera','dumpsys sensorservice','dumpsys nfc','logcat -b crash'){if($t -notmatch [regex]::Escape($token)){throw "postflight missing: $token"}}
if($t -match 'screencap|screenrecord|location get|camera.*capture'){throw 'postflight must not collect private media/location'}
Write-Host 'POSTFLIGHT TESTS PASSED'

if($t -match '\$gms\$battery'){throw 'postflight gapps/battery statements are concatenated'}
if($t -match '\)\$storage='){throw 'postflight thermal/storage statements are concatenated'}
if($t -notmatch 'Camera error traces'){throw 'postflight camera gate must check explicit camera error-trace count'}
Write-Host 'POSTFLIGHT REGRESSION TESTS PASSED'