[CmdletBinding()]
param([string]$InstallDir)
$ErrorActionPreference = 'Stop'
if(-not $InstallDir){ $InstallDir = Join-Path $PSScriptRoot 'tools\mtkclient' }
$PinnedCommit = 'cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3'
$Upstream = 'https://github.com/bkerler/mtkclient.git'
$Venv = Join-Path $InstallDir '.venv-cli'

function Require-Command([string]$Name){
    if(-not (Get-Command $Name -ErrorAction SilentlyContinue)){ throw "Required command not found: $Name" }
}
Require-Command git
Require-Command python

$usbDk = Test-Path "$env:WINDIR\System32\drivers\UsbDk.sys"
if(-not $usbDk){ Write-Warning 'UsbDk.sys not found. Install UsbDk 1.0.22 before using BROM mode.' }
$drivers = (& pnputil /enum-drivers 2>$null) -join "`n"
if($drivers -notmatch 'MediaTek'){ Write-Warning 'No MediaTek driver found in DriverStore. Install the MediaTek CDC/ACM driver first.' }

New-Item -ItemType Directory -Force (Split-Path $InstallDir -Parent) | Out-Null
if(-not (Test-Path (Join-Path $InstallDir '.git'))){ git clone $Upstream $InstallDir }
Set-Location $InstallDir
git fetch origin --tags --prune
git checkout --detach $PinnedCommit
if((git rev-parse HEAD).Trim() -ne $PinnedCommit){ throw 'Pinned mtkclient commit verification failed.' }
if(-not (Test-Path (Join-Path $Venv 'Scripts\python.exe'))){ python -m venv $Venv }
$Py = Join-Path $Venv 'Scripts\python.exe'
& $Py -m pip install --upgrade pip
& $Py -m pip install 'pyusb==1.3.1' 'pycryptodome==3.23.0' 'pycryptodomex==3.23.0' 'pyserial==3.5' 'colorama==0.4.6'
if($LASTEXITCODE -ne 0){ throw 'Python dependency installation failed.' }
Write-Host "mtkclient ready at $InstallDir"
Write-Host "Pinned commit: $PinnedCommit"
Write-Host "UsbDk detected: $usbDk"
Write-Host 'Next: run .\preflight.ps1 (recommended) or .\unlock.ps1.'

