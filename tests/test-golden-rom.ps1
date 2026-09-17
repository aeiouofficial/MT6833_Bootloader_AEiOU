$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$manifestPath=Join-Path $root 'config\golden-rom-apps.json'
if(-not(Test-Path $manifestPath)){throw 'golden ROM manifest missing'}
$m=Get-Content $manifestPath -Raw|ConvertFrom-Json
$apps=@($m.apps)
if($apps.Count -ne 8){throw "expected 8 golden apps, got $($apps.Count)"}
$expected=@{
 'com.topjohnwu.magisk'='30.7';
 'dev.imranr.obtainium'='1.6.17';
 'com.machiav3lli.backup'='8.3.18';
 'com.termux'='0.119.0-beta.3';
 'io.github.muntashirakon.AppManager'='4.1.1';
 'com.celzero.bravedns'='v0.5.6';
 'ch.protonvpn.android'='5.20.21.0';
 'duress.keyboard'='7.4'
}
foreach($pkg in $expected.Keys){
 $app=$apps|Where-Object package -eq $pkg
 if(-not $app){throw "missing golden package: $pkg"}
 if([string]$app.version -ne $expected[$pkg]){throw "version mismatch for $pkg"}
 if(([string]$app.systemDir) -notmatch '^AEiOU_[A-Za-z0-9_]+$'){throw "unsafe systemDir for $pkg"}
 if(([string]$app.apkName) -notmatch '^[A-Za-z0-9_.-]+\.apk$'){throw "unsafe apkName for $pkg"}
}
foreach($file in 'golden-rom-capture.ps1','golden-rom-build.ps1','golden-rom-flash.ps1','scripts\golden-product-build.sh'){
 if(-not(Test-Path (Join-Path $root $file))){throw "missing golden ROM component: $file"}
}
$all=(Get-Content (Join-Path $root 'golden-rom-capture.ps1') -Raw)+(Get-Content (Join-Path $root 'golden-rom-build.ps1') -Raw)+(Get-Content (Join-Path $root 'golden-rom-flash.ps1') -Raw)
foreach($forbidden in 'fastboot flashing lock','fastboot oem lock','flash vbmeta','--disable-verity','--disable-verification','format userdata','wipeData','set-active-admin','ime set duress.keyboard'){
 if($all -match [regex]::Escape($forbidden)){throw "forbidden golden ROM token: $forbidden"}
}
Write-Host 'GOLDEN-ROM CONTRACT TESTS PASSED'
