$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent;$p=Join-Path $root 'install-all.ps1';if(-not(Test-Path $p)){throw 'install-all.ps1 missing'};$t=Get-Content $p -Raw
foreach($token in 'preflight','unlock','verify','rom','gapps','root','postflight','Resume','WhatIf'){if($t -notmatch [regex]::Escape($token)){throw "orchestrator missing: $token"}}
Write-Host 'INSTALL-ALL TESTS PASSED'

if($t -notmatch 'Unlock Android after Magisk reboot'){throw 'orchestrator must expose the credential-unlock boundary'}
if($t -notmatch 'approve Shell in Magisk Superuser'){throw 'orchestrator must expose the one-time Shell root policy boundary'}
Write-Host 'INSTALL-ALL ROOT-BOUNDARY TESTS PASSED'
