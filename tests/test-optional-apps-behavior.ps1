$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path $env:TEMP ('aeiou-optional-behavior-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try {
    $artifacts=Join-Path $temp 'artifacts'; New-Item -ItemType Directory -Path $artifacts|Out-Null
    $tools=Join-Path $temp 'tools'
    $adbLog=Join-Path $temp 'adb.log'; $env:AEIOU_FAKE_ADB_LOG=$adbLog
    $duressMarker=Join-Path $temp 'duress-installed.marker'; $env:AEIOU_FAKE_DURESS_MARKER=$duressMarker
    $verifierMarker=Join-Path $temp 'verifier-disabled.marker'; $env:AEIOU_FAKE_VERIFIER_MARKER=$verifierMarker
    $adb=Join-Path $temp 'adb.cmd'
    @'
@echo off
if not "%AEIOU_FAKE_ADB_LOG%"=="" echo %*>>"%AEIOU_FAKE_ADB_LOG%"
if "%1"=="devices" (echo List of devices attached&echo testserial device&exit /b 0)
if "%1"=="get-serialno" (echo testserial&exit /b 0)
if "%1"=="push" (echo 1 file pushed&exit /b 0)
if "%1"=="install" (echo unexpected direct install 1>&2&exit /b 9)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="sys.boot_completed" (echo 1&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.name" (echo lineage_test&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.model" (echo TEST&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.device" (echo camellia&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.board.platform" (echo MT6833&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.hardware" (echo MT6833&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.boot.slot_suffix" (echo _a&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.cpu.abi" (echo arm64-v8a&exit /b 0)
if "%1"=="shell" if "%2"=="dumpsys" if "%3"=="package" if "%4"=="already.pkg" (echo versionName=1.0&exit /b 0)
if "%1"=="shell" if "%2"=="dumpsys" if "%3"=="package" if "%4"=="duress.keyboard" (if exist "%AEIOU_FAKE_DURESS_MARKER%" echo versionName=7.4&exit /b 0)
if "%1"=="shell" if "%2"=="settings" if "%3"=="get" (echo null&exit /b 0)
if "%1"=="shell" if "%2"=="settings" if "%3"=="put" (type nul > "%AEIOU_FAKE_VERIFIER_MARKER%"&exit /b 0)
if "%1"=="shell" if "%2"=="settings" if "%3"=="delete" (del /q "%AEIOU_FAKE_VERIFIER_MARKER%" 2>nul&exit /b 0)
if "%1"=="shell" if "%2"=="pm" if "%3"=="install" (if exist "%AEIOU_FAKE_VERIFIER_MARKER%" (echo Success&type nul > "%AEIOU_FAKE_DURESS_MARKER%"&exit /b 0) else (echo Failure [INSTALL_FAILED_VERIFICATION_FAILURE]&exit /b 1))
if "%1"=="shell" if "%2"=="rm" (exit /b 0)
exit /b 0
'@ | Set-Content -LiteralPath $adb -Encoding ASCII
    $already=Join-Path $artifacts 'already.apk'; [IO.File]::WriteAllBytes($already,[byte[]](9,8,7))
    $alreadyHash=(Get-FileHash -Algorithm SHA256 $already).Hash.ToLowerInvariant()
    $duress=Join-Path $artifacts 'duress.apk'; [IO.File]::WriteAllBytes($duress,[byte[]](1,2,3,4,5))
    $duressHash=(Get-FileHash -Algorithm SHA256 $duress).Hash.ToLowerInvariant()
    $scrcpySource=Join-Path $temp 'scrcpy-win64-v9.9'; New-Item -ItemType Directory -Path $scrcpySource|Out-Null
    '@echo off`necho scrcpy 9.9 ^<https://example.invalid^>' | Set-Content -LiteralPath (Join-Path $scrcpySource 'scrcpy.cmd') -Encoding ASCII
    $zip=Join-Path $artifacts 'scrcpy.zip'; Compress-Archive -Path $scrcpySource -DestinationPath $zip
    $zipHash=(Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
    $manifest=Join-Path $temp 'manifest.json'
    [ordered]@{
        schemaVersion=2
        profile=[ordered]@{soc='MT6833';preRomModels=@('TEST');preRomDevices=@('camellia');postRomModels=@('TEST');postRomDevices=@('camellia')}
        artifacts=[ordered]@{}
        optionalApps=@(
            [ordered]@{name='Already';version='1.0';package='already.pkg';file='already.apk';url='https://example.invalid/already.apk';sha256=$alreadyHash},
            [ordered]@{name='DuressKeyboard';version='7.4';package='duress.keyboard';file='duress.apk';url='https://example.invalid/duress.apk';sha256=$duressHash;bypassLowTargetSdkBlock=$true;temporaryAdbVerifierBypass=$true;requiresManualSetup=$true}
        )
        pcTools=[ordered]@{scrcpy=[ordered]@{version='9.9';file='scrcpy.zip';url='https://example.invalid/scrcpy.zip';sha256=$zipHash;executable='scrcpy-win64-v9.9\scrcpy.cmd'}}
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifest -Encoding UTF8
    $output=(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'optional-apps-install.ps1') -Manifest $manifest -ArtifactsRoot $artifacts -ToolsRoot $tools -AdbPath $adb 2>&1|Out-String)
    if($LASTEXITCODE -ne 0){throw "optional app behavior run failed:`n$output"}
    if($output -notmatch 'Already 1.0 already installed'){throw 'exact installed version was not skipped'}
    if($output -notmatch 'OPTIONAL APP BUNDLE COMPLETE'){throw 'bundle did not reach completion marker'}
    if(-not(Test-Path (Join-Path $tools 'scrcpy-9.9\scrcpy-win64-v9.9\scrcpy.cmd'))){throw 'scrcpy was not extracted'}
    $calls=Get-Content $adbLog -Raw
    if($calls -match 'install -r .*already\.apk'){throw 'already-installed exact version was reinstalled'}
    foreach($token in 'settings get global verifier_verify_adb_installs','settings get global package_verifier_enable','settings put global verifier_verify_adb_installs 0','settings put global package_verifier_enable 0','pm install --bypass-low-target-sdk-block -r','settings delete global verifier_verify_adb_installs','settings delete global package_verifier_enable','dumpsys package duress.keyboard','rm -f /data/local/tmp/aeiou-optional-app.apk'){if($calls -notmatch [regex]::Escape($token)){throw "missing fake ADB evidence: $token"}}
    foreach($forbidden in 'svc wifi','svc data','airplane_mode'){if($calls -match [regex]::Escape($forbidden)){throw "installer touched phone network state: $forbidden"}}
    Write-Host 'OPTIONAL-APPS BEHAVIOR TEST PASSED'
} finally {
    Remove-Item Env:AEIOU_FAKE_ADB_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:AEIOU_FAKE_DURESS_MARKER -ErrorAction SilentlyContinue
    Remove-Item Env:AEIOU_FAKE_VERIFIER_MARKER -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
