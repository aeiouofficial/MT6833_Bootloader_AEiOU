[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$AdbPath,
    [string]$Manifest,
    [string]$DeviceManifest
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
if(-not $Manifest){$Manifest=Join-Path $PSScriptRoot 'config\golden-rom-apps.json'}
if(-not $DeviceManifest){$DeviceManifest=Join-Path $PSScriptRoot 'config\verified-camellia.json'}
$gold=Get-Content -LiteralPath $Manifest -Raw|ConvertFrom-Json
$deviceConfig=Read-WorkflowManifest -Path $DeviceManifest
$adb=Resolve-AndroidTool -Name adb -ExplicitPath $AdbPath -ArtifactsRoot $PSScriptRoot
Wait-AndroidBootCompleted -Adb $adb -TimeoutSeconds 180|Out-Null
$id=Get-AdbIdentity -Adb $adb
if(-not(Test-DeviceProfile -Profile $deviceConfig.profile -Device $id -Phase PostRom)){throw 'Connected device does not match verified post-ROM camellia profile'}
$slot=Normalize-Slot $id.slot
$verifiedBootState=((& $adb shell getprop ro.boot.verifiedbootstate 2>$null)|Out-String).Trim()
$verityMode=((& $adb shell getprop ro.boot.veritymode 2>$null)|Out-String).Trim()
$rootId=((& $adb shell su -c id 2>$null)|Out-String).Trim()
if($rootId -notmatch '(?i)uid=0\(root\)'){throw "Root unavailable for golden capture: $rootId"}
$lpdump=((& $adb shell lpdump 2>$null)|Out-String)
$partition="product_$slot"
$extent=[regex]::Match($lpdump,"(?ms)Name:\s*$([regex]::Escape($partition))\s+.*?Extents:\s*\r?\n\s*0\s*\.\.\s*(\d+)\s+linear")
if(-not $extent.Success){throw "Could not resolve logical partition extent for $partition"}
$expectedProductBytes=([int64]$extent.Groups[1].Value+1L)*512L
$remoteProduct="/dev/block/mapper/$partition"
$blockCheck=((& $adb shell su -c "test -b $remoteProduct && echo BLOCK_OK" 2>$null)|Out-String).Trim()
if($blockCheck -ne 'BLOCK_OK'){throw "Logical product block not available: $remoteProduct"}
if($WhatIfPreference){
    Write-Host "WHATIF: capture $remoteProduct ($expectedProductBytes bytes) and exact APK bytes for $(@($gold.apps).Count) packages to $OutputRoot"
    return
}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$appRoot=Join-Path $OutputRoot 'apps'; New-Item -ItemType Directory -Path $appRoot -Force|Out-Null
function Invoke-AdbBinaryCapture {
    param([Parameter(Mandatory)][string]$RemotePath,[Parameter(Mandatory)][string]$Destination)
    if($RemotePath -notmatch '^/[A-Za-z0-9_./+=@~:-]+$'){throw "Unsafe remote capture path: $RemotePath"}
    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$adb
    $psi.Arguments='exec-out su -c "cat '+$RemotePath+'"'
    $psi.UseShellExecute=$false
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.CreateNoWindow=$true
    $p=New-Object System.Diagnostics.Process
    $p.StartInfo=$psi
    if(-not $p.Start()){throw 'Failed to start adb binary capture'}
    $errTask=$p.StandardError.ReadToEndAsync()
    $fs=[IO.File]::Open($Destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$p.StandardOutput.BaseStream.CopyTo($fs)} finally {$fs.Dispose()}
    $p.WaitForExit()
    $stderr=$errTask.Result
    if($p.ExitCode -ne 0){Remove-Item $Destination -Force -ErrorAction SilentlyContinue; throw "ADB capture failed ($($p.ExitCode)) for $RemotePath`n$stderr"}
    if(-not(Test-Path $Destination -PathType Leaf)){throw "ADB capture produced no file: $Destination"}
}
$productFile=Join-Path $OutputRoot 'source-product.img'
Invoke-AdbBinaryCapture -RemotePath $remoteProduct -Destination $productFile
$productInfo=Get-Item -LiteralPath $productFile
if($productInfo.Length -ne $expectedProductBytes){throw "Captured product size mismatch. Expected=$expectedProductBytes Actual=$($productInfo.Length)"}
$productSha=Get-Sha256 -Path $productFile
$capturedApps=@()
foreach($app in @($gold.apps)){
    $pkg=[string]$app.package
    $dump=((& $adb shell dumpsys package $pkg 2>$null)|Out-String)
    if($dump -notmatch '(?m)^\s*versionName=([^\r\n]+)\s*$'){throw "Installed package/version not found: $pkg"}
    $actualVersion=$Matches[1].Trim()
    if($actualVersion -ne [string]$app.version){throw "Installed version mismatch for $pkg. Expected=$($app.version) Actual=$actualVersion"}
    $paths=@((& $adb shell pm path $pkg 2>$null)|ForEach-Object{([string]$_).Trim()}|Where-Object{$_ -match '^package:'}|ForEach-Object{$_.Substring(8)})
    if($paths.Count -ne 1){throw "Golden ROM requires exactly one standalone APK for $pkg; found $($paths.Count) paths"}
    $remote=[string]$paths[0]
    $dest=Join-Path $appRoot ([string]$app.apkName)
    Invoke-AdbBinaryCapture -RemotePath $remote -Destination $dest
    $fi=Get-Item -LiteralPath $dest
    $capturedApps+=[ordered]@{name=[string]$app.name;package=$pkg;version=$actualVersion;systemDir=[string]$app.systemDir;apkName=[string]$app.apkName;remotePath=$remote;file=('apps/'+[string]$app.apkName);size=[int64]$fi.Length;sha256=(Get-Sha256 $dest)}
}
$out=[ordered]@{
    schemaVersion=1
    capturedAt=(Get-Date).ToUniversalTime().ToString('o')
    device=[ordered]@{model=$id.model;device=$id.device;soc=$id.soc;slot=$slot;verifiedBootState=$verifiedBootState;verityMode=$verityMode}
    sourceProduct=[ordered]@{partition=$partition;remotePath=$remoteProduct;file='source-product.img';size=[int64]$productInfo.Length;sha256=$productSha}
    apps=$capturedApps
}
$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputRoot 'capture-manifest.json') -Encoding UTF8
Write-Host "GOLDEN CAPTURE COMPLETE: product=$productSha apps=$($capturedApps.Count) output=$OutputRoot"
