[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Manifest,
    [string]$ArtifactsRoot,
    [string]$AdbPath,
    [string]$ToolsRoot
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $Manifest){$Manifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
if(-not $ArtifactsRoot){$ArtifactsRoot=Join-Path $PSScriptRoot 'artifacts\optional-apps'}
if(-not $ToolsRoot){$ToolsRoot=Join-Path $PSScriptRoot 'tools'}
$m=Read-WorkflowManifest $Manifest
if(-not $m.PSObject.Properties['optionalApps']){throw 'Manifest missing optionalApps'}
if(-not $m.PSObject.Properties['pcTools'] -or -not $m.pcTools.PSObject.Properties['scrcpy']){throw 'Manifest missing pcTools.scrcpy'}
$apps=@($m.optionalApps)
$scrcpy=$m.pcTools.scrcpy
if($WhatIfPreference){
    foreach($app in $apps){Write-Host "WHATIF: download, SHA256-verify, ADB-install and verify $($app.name) $($app.version) [$($app.package)]"}
    Write-Host "WHATIF: download, SHA256-verify and expand scrcpy $($scrcpy.version)"
    return
}
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $PSScriptRoot
Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 180|Out-Null
$identity=Get-AdbIdentity -Adb $adb
if(-not(Test-DeviceProfile -Profile $m.profile -Device $identity -Phase PostRom)){throw "Connected Android device does not match verified post-ROM profile: $($identity.model) / $($identity.device) / $($identity.soc)"}
$abi=((& $adb shell getprop ro.product.cpu.abi 2>$null)|Out-String).Trim()
if($abi -ne 'arm64-v8a'){throw "Optional bundle requires arm64-v8a, got: $abi"}
New-Item -ItemType Directory -Path $ArtifactsRoot -Force|Out-Null
New-Item -ItemType Directory -Path $ToolsRoot -Force|Out-Null
function Get-PinnedArtifact([object]$Entry,[string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){
        $tmp=$Path+'.download'
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        try {
            Invoke-WebRequest -UseBasicParsing -Uri ([string]$Entry.url) -OutFile $tmp
            Assert-ArtifactHash -Path $tmp -ExpectedSha256 ([string]$Entry.sha256)|Out-Null
            Move-Item -LiteralPath $tmp -Destination $Path -Force
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Assert-ArtifactHash -Path $Path -ExpectedSha256 ([string]$Entry.sha256)|Out-Null
}
function Get-InstalledVersion([string]$Package){
    $r=Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','dumpsys','package',$Package) -AllowFailure
    if($r.ExitCode -ne 0){return $null}
    if($r.Output -match '(?m)^\s*versionName=([^\r\n]+)\s*$'){return $Matches[1].Trim()}
    return $null
}
function Get-GlobalSetting([string]$Name){
    $r=Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','settings','get','global',$Name) -AllowFailure
    if($r.ExitCode -ne 0){throw "Unable to read Android global setting: $Name`n$($r.Output)"}
    return $r.Output.Trim()
}
function Restore-GlobalSetting([string]$Name,[string]$Value){
    if([string]::IsNullOrWhiteSpace($Value) -or $Value -eq 'null'){
        [void](Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','settings','delete','global',$Name))
    } else {
        [void](Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','settings','put','global',$Name,$Value))
    }
}
function Invoke-WithTemporaryAdbVerifierBypass([scriptblock]$Action){
    $names=@('verifier_verify_adb_installs','package_verifier_enable')
    $before=@{}
    foreach($name in $names){$before[$name]=Get-GlobalSetting -Name $name}
    try {
        foreach($name in $names){[void](Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','settings','put','global',$name,'0'))}
        return (& $Action)
    } finally {
        foreach($name in $names){Restore-GlobalSetting -Name $name -Value ([string]$before[$name])}
    }
}
foreach($app in $apps){
    $actual=Get-InstalledVersion -Package ([string]$app.package)
    if($actual -eq [string]$app.version){
        Write-Host "PASS: $($app.name) $actual already installed as $($app.package)"
        if($app.PSObject.Properties['requiresManualSetup'] -and [bool]$app.requiresManualSetup){Write-Warning "$($app.name) requires manual security setup. This script intentionally does not activate Device Admin, change the default IME, change lock credentials, or arm wipe triggers."}
        continue
    }
    $path=Join-Path $ArtifactsRoot ([string]$app.file)
    Get-PinnedArtifact -Entry $app -Path $path
    $bypass=$app.PSObject.Properties['bypassLowTargetSdkBlock'] -and [bool]$app.bypassLowTargetSdkBlock
    $verifierBypass=$app.PSObject.Properties['temporaryAdbVerifierBypass'] -and [bool]$app.temporaryAdbVerifierBypass
    $installAction={
        if($bypass){
            $remote='/data/local/tmp/aeiou-optional-app.apk'
            try {
                [void](Invoke-NativeChecked -FilePath $adb -ArgumentList @('push',$path,$remote))
                return (Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','pm','install','--bypass-low-target-sdk-block','-r',$remote))
            } finally {
                [void](Invoke-NativeChecked -FilePath $adb -ArgumentList @('shell','rm','-f',$remote) -AllowFailure)
            }
        }
        return (Invoke-NativeChecked -FilePath $adb -ArgumentList @('install','-r',$path))
    }
    if($verifierBypass){
        Write-Warning "$($app.name) uses a temporary ADB package-verifier bypass for this hash-pinned install. Original Android verifier settings are restored in finally."
        $install=Invoke-WithTemporaryAdbVerifierBypass -Action $installAction
    } else {
        $install=& $installAction
    }
    if(-not $install -or $install.Output -notmatch '(?im)^Success\s*$'){throw "APK install did not report Success for $($app.name):`n$($install.Output)"}
    $actual=Get-InstalledVersion -Package ([string]$app.package)
    if($actual -ne [string]$app.version){throw "Installed version mismatch for $($app.package). Expected=$($app.version) Actual=$actual"}
    Write-Host "PASS: $($app.name) $actual installed as $($app.package)"
    if($app.PSObject.Properties['requiresManualSetup'] -and [bool]$app.requiresManualSetup){Write-Warning "$($app.name) requires manual security setup. This script intentionally does not activate Device Admin, change the default IME, change lock credentials, or arm wipe triggers."}
}
$zip=Join-Path $ArtifactsRoot ([string]$scrcpy.file)
Get-PinnedArtifact -Entry $scrcpy -Path $zip
$target=Join-Path $ToolsRoot ('scrcpy-'+[string]$scrcpy.version)
if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Recurse -Force}
New-Item -ItemType Directory -Path $target -Force|Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
$exe=Join-Path $target ([string]$scrcpy.executable)
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "scrcpy executable missing after extraction: $exe"}
$versionText=(& $exe --version 2>&1|Out-String)
if($versionText -notmatch ('scrcpy\s+'+[regex]::Escape([string]$scrcpy.version))){throw "scrcpy version verification failed:`n$versionText"}
Write-Host "PASS: scrcpy $($scrcpy.version) installed at $exe"
Write-Host 'OPTIONAL APP BUNDLE COMPLETE.'
