$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent;$failures=0
function Check([bool]$ok,[string]$msg){if($ok){Write-Host "PASS: $msg"}else{$script:failures++;Write-Host "FAIL: $msg"}}
foreach($n in 'rom-install.ps1','gapps-install.ps1'){Check (Test-Path (Join-Path $root $n)) "$n exists"}
if(Test-Path (Join-Path $root 'rom-install.ps1')){$t=Get-Content (Join-Path $root 'rom-install.ps1') -Raw;Check($t -match 'AcknowledgeDataLoss') 'ROM requires data-loss acknowledgement';Check($t -match 'Assert-ArtifactHash') 'ROM hash gate';Check($t -match 'getvar unlocked') 'ROM unlock gate';Check($t -match 'reboot recovery') 'ROM enters recovery'}
if(Test-Path (Join-Path $root 'gapps-install.ps1')){$t=Get-Content (Join-Path $root 'gapps-install.ps1') -Raw;Check($t -match 'Assert-ArtifactHash') 'GApps hash gate';Check($t -match 'sideload') 'GApps uses adb sideload'}
if($failures){throw "$failures ROM/GApps test(s) failed"};Write-Host 'ROM/GAPPS TESTS PASSED'
