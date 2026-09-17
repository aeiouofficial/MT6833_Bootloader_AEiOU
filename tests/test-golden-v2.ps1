$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$v2=Join-Path $root 'golden-v2'
if(-not(Test-Path $v2)){throw 'golden-v2 directory missing'}
$manifestPath=Join-Path $v2 'config\apps.json'
if(-not(Test-Path $manifestPath)){throw 'golden-v2 app manifest missing'}
$m=Get-Content $manifestPath -Raw|ConvertFrom-Json
$apps=@($m.apps)
if($apps.Count -ne 8){throw "expected 8 apps, got $($apps.Count)"}
$system=@($apps|Where-Object mode -eq 'system')
$provision=@($apps|Where-Object mode -eq 'provision')
if($system.Count -ne 2){throw "expected 2 system apps, got $($system.Count)"}
if($provision.Count -ne 6){throw "expected 6 provisioned apps, got $($provision.Count)"}
foreach($pkg in 'com.termux','duress.keyboard'){if(-not($system.package -contains $pkg)){throw "missing required system app: $pkg"}}
if(($apps|Where-Object package -eq 'io.github.muntashirakon.AppManager').mode -ne 'provision'){throw 'App Manager must never be a system app'}
$required=@('build-golden-v2.ps1','scripts\build-product-v2.sh','provisioner\app\src\main\AndroidManifest.xml','product\privapp-permissions-aeiou-golden.xml')
foreach($f in $required){if(-not(Test-Path (Join-Path $v2 $f))){throw "missing v2 component: $f"}}
$manifestXml=Get-Content (Join-Path $v2 'provisioner\app\src\main\AndroidManifest.xml') -Raw
if($manifestXml -notmatch 'android.permission.INSTALL_PACKAGES'){throw 'provisioner must request INSTALL_PACKAGES'}
foreach($bad in 'BIND_DEVICE_ADMIN','wipeData','DEVICE_ADMIN','ACTION_INSTALL_PACKAGE','REQUEST_DELETE_PACKAGES'){
 if($manifestXml -match [regex]::Escape($bad)){throw "forbidden provisioner manifest token: $bad"}
}
$permXml=Get-Content (Join-Path $v2 'product\privapp-permissions-aeiou-golden.xml') -Raw
if($permXml -notmatch 'android.permission.INSTALL_PACKAGES'){throw 'privapp allowlist must grant INSTALL_PACKAGES'}
$java=(Get-ChildItem (Join-Path $v2 'provisioner') -Recurse -File -Filter *.java|ForEach-Object{Get-Content $_.FullName -Raw}) -join "`n"
foreach($need in 'PackageInstaller','INSTALL_REASON_DEVICE_RESTORE','INSTALL_SCENARIO_DEVICE_RESTORE','SHA-256'){
 if($java -notmatch [regex]::Escape($need)){throw "missing provisioner safety token: $need"}
}
foreach($bad in 'set-active-admin','wipeData(','DevicePolicyManager','ime set','INSTALL_DISABLE_VERIFICATION'){
 if($java -match [regex]::Escape($bad)){throw "forbidden provisioner code token: $bad"}
}
$build=(Get-Content (Join-Path $v2 'build-golden-v2.ps1') -Raw)+(Get-Content (Join-Path $v2 'scripts\build-product-v2.sh') -Raw)
foreach($bad in 'fastboot flash','adb reboot','format userdata','wipeData','flashing lock','oem lock'){
 if($build -match [regex]::Escape($bad)){throw "forbidden build token: $bad"}
}
foreach($need in 'source-product.img','e2fsck','sha256sum','debugfs'){
 if($build -notmatch [regex]::Escape($need)){throw "missing offline build token: $need"}
}
Write-Host 'GOLDEN-ROM-V2 CONTRACT TESTS PASSED'