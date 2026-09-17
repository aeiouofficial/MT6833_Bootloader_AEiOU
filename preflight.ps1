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
$log = Join-Path $PSScriptRoot 'preflight-last.log'
Remove-Item $log -Force -ErrorAction SilentlyContinue
Write-Host 'READ-ONLY PREFLIGHT: power off the phone, hold Power + Vol+ + Vol-, connect USB, release on the Windows USB sound.'

Push-Location $MtkRoot
try {
    & $Py $Mtk printgpt 2>&1 | Tee-Object -FilePath $log
    $code = $LASTEXITCODE
} finally { Pop-Location }
$output = Get-Content $log -Raw -ErrorAction SilentlyContinue
$post = Backup-MtkState -MtkRoot $MtkRoot
if($post){ Write-Host "Backed up generated DA state: $post" }

if($code -ne 0){ throw "Read-only preflight failed with exit code $code. See $log" }
if(-not (Test-ReadOnlyGateEvidence $output)){ throw "Preflight evidence incomplete. See $log" }
Write-Host 'PREFLIGHT PASS: MT6833 + BROM + DRAM + DA2 + GPT all verified.'
Write-Host 'Power-cycle the phone before running unlock.ps1; do not reuse this DA session.'

