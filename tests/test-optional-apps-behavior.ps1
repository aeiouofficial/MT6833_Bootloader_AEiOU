$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path $env:TEMP ('aeiou-optional-behavior-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force|Out-Null
try {
    $artifacts=Join-Path $temp 'artifacts'; New-Item -ItemType Directory -Path $artifacts|Out-Null
    $tools=Join-Path $temp 'tools'
    $adbLog=Join-Path $temp 'adb.log'; $env:AEIOU_FAKE_ADB_LOG=$adbLog
    $adb=Join-Path $temp 'adb.cmd'
    @'
@echo off
if not "%AEIOU_FAKE_ADB_LOG%"=="" echo %*>>"%AEIOU_FAKE_ADB_LOG%"
if "%1"=="devices" (echo List of devices attached&echo testserial device&exit /b 0)
if "%1"=="get-serialno" (echo testserial&exit /b 0)
if "%1"=="push" (echo 1 file pushed&exit /b 0)
if "%1"=="install" (echo Success&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="sys.boot_completed" (echo 1&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.name" (echo lineage_test&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.model" (echo TEST&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.device" (echo camellia&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.board.platform" (echo MT6833&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.hardware" (echo MT6833&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.boot.slot_suffix" (echo _a&exit /b 0)
if "%1"=="shell" if "%2"=="getprop" if "%3"=="ro.product.cpu.abi" (echo arm64-v8a&exit /b 0)
if "%1"=="shell" if "%2"=="pm" if "%3"=="install" (echo Success&exit /b 0)
if "%1"=="shell" if "%2"=="rm" (exit /b 0)
if "%1"=="shell" if "%2"=="dumpsys" if "%3"=="package" (echo versionName=7.4&exit /b 0)
exit /b 0
'@ | Set-Content -LiteralPath $adb -Encoding ASCII
    $apk=Join-Path $artifacts 'duress.apk'; [IO.File]::WriteAllBytes($apk,[byte[]](1,2,3,4,5))
    $apkHash=(Get-FileHash -Algorithm SHA256 $apk).Hash.ToLowerInvariant()
    $scrcpySource=Join-Path $temp 'scrcpy-win64-v9.9'; New-Item -ItemType Directory -Path $scrcpySource|Out-Null
    '@echo off`necho scrcpy 9.9 ^<https://example.invalid^>' | Set-Content -LiteralPath (Join-Path $scrcpySource 'scrcpy.cmd') -Encoding ASCII
    $zip=Join-Path $artifacts 'scrcpy.zip'; Compress-Archive -Path $scrcpySource -DestinationPath $zip
    $zipHash=(Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
    $manifest=Join-Path $temp 'manifest.json'
    [ordered]@{
        schemaVersion=2
        profile=[ordered]@{soc='MT6833';preRomModels=@('TEST');preRomDevices=@('camellia');postRomModels=@('TEST');postRomDevices=@('camellia')}
        artifacts=[ordered]@{}
        optionalApps=@([ordered]@{name='DuressKeyboard';version='7.4';package='duress.keyboard';file='duress.apk';url='https://example.invalid/duress.apk';sha256=$apkHash;bypassLowTargetSdkBlock=$true;requiresManualSetup=$true})
        pcTools=[ordered]@{scrcpy=[ordered]@{version='9.9';file='scrcpy.zip';url='https://example.invalid/scrcpy.zip';sha256=$zipHash;executable='scrcpy-win64-v9.9\scrcpy.cmd'}}
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifest -Encoding UTF8
    $output=(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'optional-apps-install.ps1') -Manifest $manifest -ArtifactsRoot $artifacts -ToolsRoot $tools -AdbPath $adb 2>&1|Out-String)
    if($LASTEXITCODE -ne 0){throw "optional app behavior run failed:`n$output"}
    if($output -notmatch 'OPTIONAL APP BUNDLE COMPLETE'){throw 'bundle did not reach completion marker'}
    if(-not(Test-Path (Join-Path $tools 'scrcpy-9.9\scrcpy-win64-v9.9\scrcpy.cmd'))){throw 'scrcpy was not extracted'}
    $calls=Get-Content $adbLog -Raw
    foreach($token in 'push','pm install --bypass-low-target-sdk-block -r','dumpsys package duress.keyboard','rm -f /data/local/tmp/aeiou-optional-app.apk'){if($calls -notmatch [regex]::Escape($token)){throw "missing fake ADB evidence: $token"}}
    foreach($forbidden in 'svc wifi','svc data','airplane_mode'){if($calls -match [regex]::Escape($forbidden)){throw "installer touched phone network state: $forbidden"}}
    Write-Host 'OPTIONAL-APPS BEHAVIOR TEST PASSED'
} finally {
    Remove-Item Env:AEIOU_FAKE_ADB_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
