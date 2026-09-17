$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$installer=Join-Path $root 'optional-apps-install.ps1'
if(-not(Test-Path $installer)){throw 'optional-apps-install.ps1 missing'}
$manifest=Get-Content (Join-Path $root 'config\verified-camellia.json') -Raw|ConvertFrom-Json
$apps=@($manifest.optionalApps)
if($apps.Count -ne 7){throw "expected 7 optional Android apps, got $($apps.Count)"}
$expected=@('dev.imranr.obtainium','com.machiav3lli.backup','com.termux','io.github.muntashirakon.AppManager','com.celzero.bravedns','ch.protonvpn.android','duress.keyboard')
foreach($pkg in $expected){if($apps.package -notcontains $pkg){throw "missing optional package: $pkg"}}
foreach($app in $apps){
    foreach($p in 'name','version','package','file','url','sha256'){if(-not $app.PSObject.Properties[$p] -or -not [string]$app.$p){throw "optional app missing $p"}}
    if(([string]$app.sha256) -notmatch '^[0-9a-f]{64}$'){throw "invalid SHA256 for $($app.name)"}
}
$termux=$apps|Where-Object package -eq 'com.termux'
if($termux.version -ne '0.119.0-beta.3'){throw "Termux pin must be 0.119.0-beta.3, got $($termux.version)"}
if($termux.sha256 -ne '3bb969df2400d884ccb929b7d79cc76861f291c98942c401e12408d734a460f3'){throw 'Termux ARM64 beta SHA256 pin mismatch'}
if(-not $termux.temporaryAdbVerifierBypass){throw 'Termux must use bounded temporary ADB verifier bypass'}
$duress=$apps|Where-Object package -eq 'duress.keyboard'
if(-not $duress.requiresManualSetup){throw 'DuressKeyboard must require manual setup'}
if(-not $duress.bypassLowTargetSdkBlock){throw 'DuressKeyboard must use the documented low-target-SDK install bypass'}
if(-not $duress.temporaryAdbVerifierBypass){throw 'DuressKeyboard must use bounded temporary ADB verifier bypass'}
$scrcpy=$manifest.pcTools.scrcpy
foreach($p in 'version','file','url','sha256','executable'){if(-not $scrcpy.PSObject.Properties[$p] -or -not [string]$scrcpy.$p){throw "scrcpy missing $p"}}
$t=Get-Content $installer -Raw
foreach($token in 'Assert-ArtifactHash','Get-InstalledVersion','already installed','verifier_verify_adb_installs','package_verifier_enable','settings','delete','bypass-low-target-sdk-block','requiresManualSetup','Expand-Archive'){if($t -notmatch [regex]::Escape($token)){throw "optional installer missing contract token: $token"}}
foreach($forbidden in 'set-active-admin','ime set duress.keyboard','locksettings set-password','wipeData'){if($t -match [regex]::Escape($forbidden)){throw "optional installer must not arm DuressKeyboard: $forbidden"}}
Write-Host 'OPTIONAL-APPS TESTS PASSED'
