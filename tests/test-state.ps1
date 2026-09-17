$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\Workflow.psm1') -Force
$failures=0
function Check([bool]$ok,[string]$msg){ if($ok){Write-Host "PASS: $msg"} else {$script:failures++; Write-Host "FAIL: $msg"} }
function Throws([scriptblock]$fn){ try { & $fn; return $false } catch { return $true } }
$temp=Join-Path $env:TEMP ('aeiou-state-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$state=[ordered]@{ stage='root'; serial='SERIAL-A'; product='camellia'; slot='a'; sourceBootSha256='abc' }
$path=Write-WorkflowState -StateRoot $temp -State $state
Check (Test-Path $path) 'writes state file'
$loaded=Read-WorkflowState -StateRoot $temp
Check ($loaded.stage -eq 'root' -and $loaded.serial -eq 'SERIAL-A') 'reads state file'
$current=[pscustomobject]@{ serial='SERIAL-A'; product='camellia'; slot='a' }
Check (Assert-ResumeCompatible -State $loaded -Current $current) 'accepts matching resume identity'
$changed=[pscustomobject]@{ serial='SERIAL-B'; product='camellia'; slot='a' }
Check (Throws { Assert-ResumeCompatible -State $loaded -Current $changed | Out-Null }) 'rejects changed serial'
Remove-Item $temp -Recurse -Force
if($failures -gt 0){ throw "$failures state test(s) failed" }
Write-Host 'STATE TESTS PASSED'
