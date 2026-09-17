[CmdletBinding()]
param([string]$MtkRoot)
$ErrorActionPreference = 'Stop'
if(-not $MtkRoot){ $MtkRoot = Join-Path $PSScriptRoot 'tools\mtkclient' }
Import-Module (Join-Path $PSScriptRoot 'src\Toolkit.psm1') -Force
$Py = Join-Path $MtkRoot '.venv-cli\Scripts\python.exe'
$Mtk = Join-Path $MtkRoot 'mtk.py'
if(-not (Test-Path $Py) -or -not (Test-Path $Mtk)){ throw 'Run setup.ps1 first.' }

$old = Backup-MtkState -MtkRoot $MtkRoot
if($old){ Write-Host "Backed up stale mtkclient state: $old" }
$log = Join-Path $PSScriptRoot 'unlock-last.log'
Remove-Item $log -Force -ErrorAction SilentlyContinue
Write-Warning 'Bootloader unlocking can affect device security and may cause data loss on some devices. Back up important data first.'
Write-Host 'Power off the phone, hold Power + Vol+ + Vol-, connect USB, then release all buttons on the Windows USB sound.'

Push-Location $MtkRoot
try {
    & $Py $Mtk da seccfg unlock 2>&1 | Tee-Object -FilePath $log
    $code = $LASTEXITCODE
} finally { Pop-Location }
$output = Get-Content $log -Raw -ErrorAction SilentlyContinue
if(-not (Test-Mt6833Evidence $output)){ throw "No MT6833 evidence found. Refusing to claim success. See $log" }
if(-not (Test-UnlockEvidence -Output $output -ExitCode $code)){ throw "Unlock not verified. Exit=$code. See $log" }
Write-Host 'UNLOCK VERIFIED BY MTKCLIENT EVIDENCE.'
Write-Host 'Next: power-cycle to Fastboot and run .\verify.ps1.'

