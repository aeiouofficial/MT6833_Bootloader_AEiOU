[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [Parameter(Mandatory)][string]$ProvisionerApk,
    [Parameter(Mandatory)][string]$ProvisionerCertSha256,
    [Parameter(Mandatory)][string]$Aapt2Path,
    [Parameter(Mandatory)][string]$ApkSignerPath,
    [string]$OutputRoot
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$s=[IO.File]::OpenRead($Path);try{return ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$s.Dispose()}}finally{$sha.Dispose()}
}
function To-Wsl([string]$Path){
    $full=[IO.Path]::GetFullPath($Path)
    if($full -notmatch '^([A-Za-z]):\\(.*)$'){throw "Not a Windows drive path: $full"}
    return '/mnt/'+$Matches[1].ToLowerInvariant()+'/'+($Matches[2]-replace '\\','/')
}
$repo=Split-Path $PSScriptRoot -Parent
$configPath=Join-Path $PSScriptRoot 'config\apps.json'
$permPath=Join-Path $PSScriptRoot 'product\privapp-permissions-aeiou-golden.xml'
$builder=Join-Path $PSScriptRoot 'scripts\build-product-v2.sh'
$source=Join-Path $CaptureRoot 'source-product.img'
$appsRoot=Join-Path $CaptureRoot 'apps'
foreach($p in $configPath,$permPath,$builder,$source,$ProvisionerApk,$Aapt2Path,$ApkSignerPath){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing required file: $p"}}
if(-not(Test-Path -LiteralPath $appsRoot -PathType Container)){throw "Missing captured apps directory: $appsRoot"}
if(-not$OutputRoot){$OutputRoot=Join-Path $CaptureRoot 'golden-v2-output'}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$m=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
if(@($m.apps).Count -ne 8){throw 'Golden v2 requires exactly eight pinned apps'}
$badging=(& $Aapt2Path dump badging $ProvisionerApk 2>&1|Out-String)
if($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='com\.aeiou\.goldenprovisioner'"){throw 'Provisioner package identity check failed'}
$perms=(& $Aapt2Path dump permissions $ProvisionerApk 2>&1|Out-String)
if($LASTEXITCODE -ne 0 -or $perms -notmatch 'android.permission.INSTALL_PACKAGES'){throw 'Provisioner INSTALL_PACKAGES declaration missing'}
foreach($forbidden in 'android.permission.BIND_DEVICE_ADMIN','android.permission.DELETE_PACKAGES'){if($perms -match [regex]::Escape($forbidden)){throw "Forbidden provisioner permission: $forbidden"}}
$verify=(& $ApkSignerPath verify --verbose --print-certs $ProvisionerApk 2>&1|Out-String)
if($LASTEXITCODE -ne 0){throw "Provisioner signature verification failed: $verify"}
if($verify -notmatch '(?im)certificate SHA-256 digest:\s*([0-9a-f:]+)'){throw 'Cannot read provisioner certificate digest'}
$cert=($Matches[1]-replace ':','').ToLowerInvariant()
if($cert -ne ($ProvisionerCertSha256-replace ':','').ToLowerInvariant()){throw "Provisioner certificate mismatch: $cert"}
$lines=New-Object Collections.Generic.List[string]
foreach($app in @($m.apps)){
    $src=Join-Path $appsRoot ([string]$app.file)
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Missing pinned APK: $src"}
    $item=Get-Item -LiteralPath $src
    if($item.Length -ne [int64]$app.bytes){throw "APK size mismatch: $($app.file)"}
    $sha=Get-Sha256 $src
    if($sha -ne ([string]$app.sha256).ToLowerInvariant()){throw "APK SHA-256 mismatch: $($app.file)"}
    $systemDir=if($app.PSObject.Properties.Name -contains 'systemDir'){[string]$app.systemDir}else{''}
    $lines.Add("$($app.mode)`t$systemDir`t$($app.file)`tapps/$($app.file)`t$sha")
}
$tsv=Join-Path $OutputRoot 'apps.tsv'
[IO.File]::WriteAllLines($tsv,$lines,[Text.UTF8Encoding]::new($false))
$candidate=Join-Path $OutputRoot 'golden-v2-product.img'
if($WhatIfPreference){Write-Host "WHATIF: offline build only -> $candidate";return}
$args=@('-e','bash',(To-Wsl $builder),(To-Wsl $CaptureRoot),(To-Wsl $candidate),(To-Wsl $ProvisionerApk),(To-Wsl $configPath),(To-Wsl $permPath),(To-Wsl $tsv))
$out=(& wsl.exe @args 2>&1|Out-String)
if($LASTEXITCODE -ne 0){throw "WSL golden v2 build failed:`n$out"}
Write-Host $out.Trim()
$sourceHash=Get-Sha256 $source
$candidateHash=Get-Sha256 $candidate
$result=[ordered]@{
 schemaVersion=2; buildId=[string]$m.buildId; createdUtc=[DateTime]::UtcNow.ToString('o');
 sourceProduct=[ordered]@{file='source-product.img';bytes=(Get-Item $source).Length;sha256=$sourceHash};
 goldenProduct=[ordered]@{file='golden-v2-product.img';bytes=(Get-Item $candidate).Length;sha256=$candidateHash};
 provisioner=[ordered]@{file=(Split-Path $ProvisionerApk -Leaf);sha256=(Get-Sha256 $ProvisionerApk);certificateSha256=$cert;package='com.aeiou.goldenprovisioner';version='1.0.0'};
 apps=@($m.apps)
}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputRoot 'golden-v2-build-manifest.json') -Encoding UTF8
Write-Host "GOLDEN_V2_BUILD_COMPLETE sha256=$candidateHash"
