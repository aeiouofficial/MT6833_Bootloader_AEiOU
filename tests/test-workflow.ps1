$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\src\Workflow.psm1'
Import-Module $module -Force
$failures = 0
function Check([bool]$ok,[string]$msg){ if($ok){Write-Host "PASS: $msg"} else {$script:failures++; Write-Host "FAIL: $msg"} }
function Throws([scriptblock]$fn){ try { & $fn; return $false } catch { return $true } }

Check ((Normalize-Slot '_a') -eq 'a') 'normalizes _a'
Check ((Normalize-Slot 'b') -eq 'b') 'normalizes b'
Check (Throws { Normalize-Slot 'c' | Out-Null }) 'rejects unknown slot'
Check ((Get-BootPartitionName '_a') -eq 'boot_a') 'maps slot to boot_a'

$temp = Join-Path $env:TEMP ('aeiou-workflow-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$file = Join-Path $temp 'artifact.bin'
[IO.File]::WriteAllBytes($file,[byte[]](1,2,3,4))
$hash = Get-Sha256 $file
Check ($hash -eq '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a') 'computes SHA256'
Check (Assert-ArtifactHash -Path $file -ExpectedSha256 $hash) 'accepts exact artifact hash'
Check (Throws { Assert-ArtifactHash -Path $file -ExpectedSha256 ('0' * 64) | Out-Null }) 'rejects hash mismatch'

$profile=[pscustomobject]@{ soc='MT6833'; preRomModels=@('M2103K19G'); preRomDevices=@('camellian'); postRomModels=@('M2103K19C','M2103K19G'); postRomDevices=@('camellia','camellian') }
$pre=[pscustomobject]@{ soc='MT6833'; model='M2103K19G'; device='camellian' }
$post=[pscustomobject]@{ soc='MT6833'; model='M2103K19C'; device='camellia' }
$wrong=[pscustomobject]@{ soc='MT6765'; model='x'; device='x' }
Check (Test-DeviceProfile -Profile $profile -Device $pre -Phase PreRom) 'accepts verified stock identity'
Check (Test-DeviceProfile -Profile $profile -Device $post -Phase PostRom) 'accepts verified Lineage identity'
Check (-not (Test-DeviceProfile -Profile $profile -Device $wrong -Phase PostRom)) 'rejects wrong SoC'
Check (Test-SideloadEvidence -Output 'Total xfer: 1.00x' -ExitCode 0) 'accepts complete sideload'
Check (-not (Test-SideloadEvidence -Output 'Total xfer: 0.47x' -ExitCode 1)) 'rejects failed sideload'
Check (Test-RootEvidence -IdOutput 'uid=0(root) gid=0(root)' -ProcessOutput 'root 883 1 magiskd' -Selinux 'Enforcing') 'accepts root evidence'
Check (-not (Test-RootEvidence -IdOutput 'uid=2000(shell)' -ProcessOutput 'magiskd' -Selinux 'Enforcing')) 'rejects non-root id'
Remove-Item $temp -Recurse -Force
if($failures -gt 0){ throw "$failures workflow test(s) failed" }
Write-Host 'WORKFLOW TESTS PASSED'
