$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\src\Toolkit.psm1'
if (-not (Test-Path $module)) { throw "Expected module missing: $module" }
Import-Module $module -Force

$failures = 0
function Assert-True([bool]$Condition,[string]$Message){
    if(-not $Condition){$script:failures++; Write-Host "FAIL: $Message"}
    else {Write-Host "PASS: $Message"}
}
function Assert-False([bool]$Condition,[string]$Message){ Assert-True (-not $Condition) $Message }

$temp = Join-Path $env:TEMP ('mt6833-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
Set-Content (Join-Path $temp '.state') '{"flashmode":"XFLASH"}'
$backup = Backup-MtkState -MtkRoot $temp
Assert-True (Test-Path $backup) 'stale state is backed up'
Assert-False (Test-Path (Join-Path $temp '.state')) 'active .state is removed from active path'
Assert-True ($backup -match '\.state\.stale-') 'backup name is explicit'
Assert-True (Test-Mt6833Evidence 'CPU: MT6833(Dimensity 700 5G k6833)') 'MT6833 evidence accepted'
Assert-False (Test-Mt6833Evidence 'CPU: MT6765') 'non-MT6833 evidence rejected'

$gate = "CPU: MT6833(Dimensity 700 5G k6833)`nBROM mode detected.`nDRAM setup passed.`nSuccessfully uploaded stage 2`nGPT Table:"
Assert-True (Test-ReadOnlyGateEvidence $gate) 'complete read-only gate accepted'
Assert-False (Test-ReadOnlyGateEvidence 'DRAM setup passed.') 'partial gate rejected'

Assert-True (Test-UnlockEvidence -Output 'DaHandler - [LIB]: Device is already unlocked' -ExitCode 0) 'already-unlocked + exit 0 accepted'
Assert-False (Test-UnlockEvidence -Output 'Device is already unlocked' -ExitCode 1) 'nonzero exit rejected'
Assert-False (Test-UnlockEvidence -Output 'Bootloader unlocked.' -ExitCode 0) 'wrapper-only success text rejected'

Remove-Item $temp -Recurse -Force
if($failures -gt 0){ throw "$failures test(s) failed" }
Write-Host 'ALL TESTS PASSED'

