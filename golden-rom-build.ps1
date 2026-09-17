[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [string]$Distro='Ubuntu-22.04'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Workflow.psm1') -Force
$captureManifest=Join-Path $CaptureRoot 'capture-manifest.json'
if(-not(Test-Path $captureManifest -PathType Leaf)){throw "Capture manifest missing: $captureManifest"}
$m=Get-Content -LiteralPath $captureManifest -Raw|ConvertFrom-Json
$source=Join-Path $CaptureRoot ([string]$m.sourceProduct.file)
Assert-ArtifactHash -Path $source -ExpectedSha256 ([string]$m.sourceProduct.sha256)|Out-Null
$lines=New-Object System.Collections.Generic.List[string]
foreach($app in @($m.apps)){
    $local=Join-Path $CaptureRoot ([string]$app.file)
    Assert-ArtifactHash -Path $local -ExpectedSha256 ([string]$app.sha256)|Out-Null
    $lines.Add(([string]$app.systemDir)+"`t"+([string]$app.apkName)+"`t"+([string]$app.file)+"`t"+([string]$app.sha256))
}
$tsv=Join-Path $CaptureRoot 'apps.tsv'
[IO.File]::WriteAllLines($tsv,$lines,(New-Object Text.UTF8Encoding($false)))
$candidate=Join-Path $CaptureRoot 'golden-product.img'
if($WhatIfPreference){Write-Host "WHATIF: build $candidate from $source and embed $(@($m.apps).Count) APKs via WSL2/debugfs";return}
$script=Join-Path $PSScriptRoot 'scripts\golden-product-build.sh'
if(-not(Test-Path $script -PathType Leaf)){throw "Golden product builder missing: $script"}
function Convert-ToWslPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path)
    if($full -notmatch '^([A-Za-z]):\\(.*)$'){throw "Unsupported Windows path for WSL conversion: $full"}
    $drive=$Matches[1].ToLowerInvariant()
    $tail=$Matches[2] -replace '\\','/'
    return "/mnt/$drive/$tail"
}
$scriptWsl=Convert-ToWslPath $script
$captureWsl=Convert-ToWslPath $CaptureRoot
$candidateWsl=Convert-ToWslPath $candidate
$r=Invoke-NativeChecked -FilePath 'wsl.exe' -ArgumentList @('-d',$Distro,'-u','root','--','bash',$scriptWsl,$captureWsl,$candidateWsl)
Write-Host $r.Output
if(-not(Test-Path $candidate -PathType Leaf)){throw 'Golden product image was not produced'}
$candidateInfo=Get-Item -LiteralPath $candidate
if($candidateInfo.Length -ne [int64]$m.sourceProduct.size){throw "Golden product size changed. Source=$($m.sourceProduct.size) Candidate=$($candidateInfo.Length)"}
$candidateSha=Get-Sha256 -Path $candidate
$out=[ordered]@{
    schemaVersion=1
    builtAt=(Get-Date).ToUniversalTime().ToString('o')
    captureManifestSha256=(Get-Sha256 $captureManifest)
    device=$m.device
    sourceProduct=$m.sourceProduct
    goldenProduct=[ordered]@{file='golden-product.img';size=[int64]$candidateInfo.Length;sha256=$candidateSha}
    apps=$m.apps
}
$out|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $CaptureRoot 'golden-product-manifest.json') -Encoding UTF8
Write-Host "GOLDEN PRODUCT COMPLETE: sha256=$candidateSha file=$candidate"
