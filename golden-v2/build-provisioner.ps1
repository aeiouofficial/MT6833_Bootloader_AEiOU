[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GradleExe,
    [Parameter(Mandatory)][string]$JavaHome,
    [Parameter(Mandatory)][string]$AndroidSdkRoot,
    [Parameter(Mandatory)][string]$SigningRoot,
    [Parameter(Mandatory)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
function Get-Sha256([string]$Path){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$s=[IO.File]::OpenRead($Path);try{return ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant()}finally{$s.Dispose()}}finally{$sha.Dispose()}
}
function Unprotect([string]$Path){
    $s=Get-Content -LiteralPath $Path -Raw|ConvertTo-SecureString
    $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}
}
$project=$PSScriptRoot
$keytool=Join-Path $JavaHome 'bin\keytool.exe'
$apksigner=Join-Path $AndroidSdkRoot 'build-tools\36.0.0\apksigner.bat'
$zipalign=Join-Path $AndroidSdkRoot 'build-tools\36.0.0\zipalign.exe'
foreach($p in $GradleExe,$keytool,$apksigner,$zipalign){if(-not(Test-Path -LiteralPath $p)){throw "Missing build tool: $p"}}
New-Item -ItemType Directory -Path $SigningRoot,$OutputRoot -Force|Out-Null
$ks=Join-Path $SigningRoot 'aeiou-golden-provisioner.p12'
$pwFile=Join-Path $SigningRoot 'aeiou-golden-provisioner.pass.dpapi'
$alias='aeiou-golden-provisioner'
if(-not(Test-Path $ks)){
    $bytes=New-Object byte[] 32
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    $pw=[Convert]::ToBase64String($bytes)
    & $keytool -genkeypair -noprompt -storetype PKCS12 -keystore $ks -storepass $pw -keypass $pw -alias $alias -keyalg RSA -keysize 3072 -validity 36500 -dname 'CN=AEiOU Golden ROM Provisioner,O=AEiOU' | Out-Null
    if($LASTEXITCODE -ne 0){throw 'keytool failed'}
    ConvertTo-SecureString $pw -AsPlainText -Force|ConvertFrom-SecureString|Set-Content -LiteralPath $pwFile -Encoding ASCII
}else{
    if(-not(Test-Path $pwFile)){throw "DPAPI password file missing for existing keystore: $pwFile"}
    $pw=Unprotect $pwFile
}
$oldJava=$env:JAVA_HOME
$env:JAVA_HOME=$JavaHome
try{
    & $GradleExe -p (Join-Path $project 'provisioner') :app:clean :app:assembleRelease --no-daemon
    if($LASTEXITCODE -ne 0){throw 'Gradle release build failed'}
}finally{$env:JAVA_HOME=$oldJava}
$unsigned=Get-ChildItem (Join-Path $project 'provisioner\app\build\outputs\apk\release') -Filter '*release-unsigned.apk'|Select-Object -First 1
if(-not$unsigned){throw 'Unsigned release APK not found'}
$aligned=Join-Path $OutputRoot 'AEiOUGoldenProvisioner-aligned.apk'
$signed=Join-Path $OutputRoot 'AEiOUGoldenProvisioner.apk'
& $zipalign -p -f 4 $unsigned.FullName $aligned
if($LASTEXITCODE -ne 0){throw 'zipalign failed'}
& $apksigner sign --ks $ks --ks-key-alias $alias --ks-pass "pass:$pw" --key-pass "pass:$pw" --out $signed $aligned
if($LASTEXITCODE -ne 0){throw 'apksigner sign failed'}
$verify=(& $apksigner verify --verbose --print-certs $signed 2>&1|Out-String)
if($LASTEXITCODE -ne 0){throw "apksigner verify failed: $verify"}
if($verify -notmatch '(?im)certificate SHA-256 digest:\s*([0-9a-f:]+)'){throw 'Cannot parse provisioner certificate digest'}
$cert=($Matches[1]-replace ':','').ToLowerInvariant()
$meta=[ordered]@{package='com.aeiou.goldenprovisioner';version='1.0.0';apk=(Split-Path $signed -Leaf);bytes=(Get-Item $signed).Length;sha256=(Get-Sha256 $signed);certificateSha256=$cert}
$meta|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputRoot 'provisioner-build.json') -Encoding UTF8
Write-Host "PROVISIONER_BUILD_OK apk=$signed sha256=$($meta.sha256) certSha256=$cert"
$pw=$null
