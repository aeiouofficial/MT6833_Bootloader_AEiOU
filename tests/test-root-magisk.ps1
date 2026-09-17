$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\Workflow.psm1') -Force
$root=Split-Path $PSScriptRoot -Parent
$failures=0
function Check([bool]$ok,[string]$msg){if($ok){Write-Host "PASS: $msg"}else{$script:failures++;Write-Host "FAIL: $msg"}}
function Throws([scriptblock]$fn){try{& $fn;return $false}catch{return $true}}
$release=[pscustomobject]@{tag_name='v30.7';name='Magisk v30.7';draft=$false;prerelease=$false;assets=@([pscustomobject]@{name='Magisk-v30.7.apk';browser_download_url='https://example/Magisk-v30.7.apk';digest='sha256:e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5'})}
$a=Get-MagiskAssetInfo -Release $release
Check ($a.Version -eq '30.7') 'parses Magisk version'
Check ($a.Sha256 -eq 'e0d32d2123532860f97123d927b1bb86c4e08e6fd8a48bfc6b5bee0afae9ebd5') 'parses GitHub asset digest'
Check (Throws { Get-MagiskAssetInfo -Release ([pscustomobject]@{tag_name='v1';draft=$false;prerelease=$true;assets=@()}) | Out-Null }) 'rejects prerelease'
$temp=Join-Path $env:TEMP ('boot-'+[guid]::NewGuid()+'.img'); [IO.File]::WriteAllBytes($temp,[Text.Encoding]::ASCII.GetBytes('ANDROID!payload'))
Check (Test-AndroidBootImage $temp) 'accepts Android boot magic'; Remove-Item $temp -Force
$script=Join-Path $root 'root-magisk.ps1'; Check (Test-Path $script) 'root-magisk entrypoint exists'
if(Test-Path $script){$t=Get-Content $script -Raw; Check ($t -match 'boot_patch\.sh') 'uses official Magisk boot patcher'; Check ($t -notmatch '(?i)flash\s+vbmeta|--disable-verity|--disable-verification') 'does not weaken vbmeta/verity'}
if($failures){throw "$failures root test(s) failed"}; Write-Host 'ROOT MAGISK TESTS PASSED'
