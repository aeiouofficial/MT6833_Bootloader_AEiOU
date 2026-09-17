[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Toolkit.psm1') -Force
$log = Join-Path $PSScriptRoot 'unlock-last.log'

if(Test-Path $log){
    $text = Get-Content $log -Raw
    if(Test-Mt6833Evidence $text){ Write-Host 'MT6833 evidence present in unlock-last.log.' }
    if($text -match 'Device is already unlocked|Successfully wrote seccfg\.'){ Write-Host 'Explicit mtkclient unlock evidence present.' }
}

$fastboot = Get-Command fastboot -ErrorAction SilentlyContinue
if(-not $fastboot){
    Write-Warning 'fastboot is not on PATH. Install Android platform-tools for independent Fastboot verification.'
    exit 0
}
$devices = (& fastboot devices 2>&1) -join "`n"
if([string]::IsNullOrWhiteSpace($devices)){ throw 'No Fastboot device detected. Boot the phone with Power + Volume- and retry.' }
Write-Host $devices
$result = (& fastboot getvar unlocked 2>&1) -join "`n"
Write-Host $result
if($result -match '(?im)unlocked:\s*yes'){ Write-Host 'FASTBOOT VERIFIED: unlocked = yes'; exit 0 }
if($result -match '(?im)unlocked:\s*no'){ throw 'Fastboot reports unlocked = no.' }
Write-Warning 'This bootloader did not expose the Fastboot unlocked variable. Keep the mtkclient evidence and verify via bootloader UI/ROM flashing prerequisites.'
